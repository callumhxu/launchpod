import Foundation
import Testing
@testable import Launchpod

struct ApplicationCatalogSnapshotTests {
    @Test
    func movingIntoAnAlreadyScannedDirectoryNeverPublishesAnIdentityDeletion() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let destination = ApplicationScan.Directory(source: try AppSource(
            kind: .custom, directoryURL: fixture.directory("First Scanned")
        ))
        let origin = ApplicationScan.Directory(source: try AppSource(
            kind: .custom, directoryURL: fixture.directory("Last Scanned")
        ))
        let app = try fixture.application("Editor.app", in: origin.source.directoryURL)
        let moved = destination.source.directoryURL.appendingPathComponent("Moved.app", isDirectory: true)
        let scanner = MovingAfterScanScanner()
        let catalog = ApplicationCatalog(directories: [destination, origin], scanner: scanner)
        let initial = await catalog.refresh()
        let record = try #require(initial.records.first)
        await scanner.move(app, to: moved, afterScanning: destination.id)

        let overlappingMove = await catalog.refresh()

        try #require(await scanner.moveError == nil)
        #expect(overlappingMove.records.map(\.id) == [record.id],
                "An individually complete directory scan cannot confirm absence across a moving batch")
        #expect(overlappingMove.inserted.isEmpty)
        let settled = await catalog.refresh()
        #expect(settled.availableRecords.map(\.id) == [record.id])
        #expect(settled.availableRecords.first?.metadata.bundleURL == moved.standardized)
        #expect(settled.inserted.isEmpty)
    }

    @Test
    func linkedTargetIdentitySurvivesAnEmptyBundleShellDeletionAndRestoration() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let targetDirectory = try fixture.directory("Actual")
        let links = try fixture.directory("Links")
        let app = try fixture.application("Editor.app", in: targetDirectory)
        _ = try fixture.symbolicLink(to: app, named: "Editor Link.app", in: links)
        let source = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: links))
        let catalog = ApplicationCatalog(directories: [source], scanner: ApplicationScanner())
        let initial = await catalog.refresh()
        let record = try #require(initial.records.first)

        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents"))
        let shell = await catalog.refresh()
        #expect(shell.scans.first?.isComplete == false)
        #expect(shell.availableRecords.isEmpty)
        #expect(shell.records.map(\.id) == [record.id])
        #expect(shell.records.first?.isMissing == nil)

        try FileManager.default.removeItem(at: app)
        let absent = await catalog.refresh()
        #expect(absent.records.map(\.id) == [record.id])
        #expect(absent.availableRecords.isEmpty)
        _ = try fixture.application("Editor.app", in: targetDirectory)
        let restored = await catalog.refresh()
        #expect(restored.availableRecords.map(\.id) == [record.id])
        #expect(restored.inserted.isEmpty)
    }

    @Test
    func declaredCategoryAndNonBetaStateAreStableForANewUnchangedBundle() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        _ = try fixture.application("Fresh.app", identifier: "com.example.Fresh.\(UUID().uuidString)", values: [
            "LSApplicationCategoryType": "public.app-category.developer-tools"
        ])
        let source = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: fixture.root))
        let catalog = ApplicationCatalog(directories: [source], scanner: ApplicationScanner())
        let initial = await catalog.refresh()
        let record = try #require(initial.records.first)
        #expect(record.metadata.categoryIdentifier == "public.app-category.developer-tools")
        if dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_kCFURLApplicationIsBetaKey") != nil {
            #expect(record.metadata.isBeta == false)
        } else {
            #expect(record.metadata.isBeta == nil)
        }

        let immediate = await catalog.refresh()
        #expect(immediate.updated.isEmpty)
        #expect(immediate.records == initial.records)
        // The recorded sandbox registration lag was 2.5 seconds; observe once beyond that window.
        try await Task.sleep(for: .seconds(3))
        let registered = await catalog.refresh()
        #expect(registered.updated.isEmpty)
        #expect(registered.records == initial.records)
    }
}

private actor MovingAfterScanScanner: ApplicationScanning {
    private let scanner = ApplicationScanner()
    private var pendingMove: (source: URL, destination: URL, directoryID: UUID)?
    private(set) var moveError: String?

    func move(_ source: URL, to destination: URL, afterScanning directoryID: UUID) {
        pendingMove = (source, destination, directoryID)
    }

    func scan(_ directory: ApplicationScan.Directory) async -> ApplicationScan {
        let result = await scanner.scan(directory)
        if let move = pendingMove, move.directoryID == directory.id {
            pendingMove = nil
            do {
                try FileManager.default.moveItem(at: move.source, to: move.destination)
            } catch {
                moveError = String(describing: error)
            }
        }
        return result
    }

    func isCurrent(_ scan: ApplicationScan) async -> Bool {
        await scanner.isCurrent(scan)
    }

    func isMissing(at url: URL) async -> Bool? {
        await scanner.isMissing(at: url)
    }
}
