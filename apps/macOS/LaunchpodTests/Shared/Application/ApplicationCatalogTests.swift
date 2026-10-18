import Foundation
import Testing
@testable import Launchpod

struct ApplicationCatalogTests {
    @Test
    func unchangedRescanEmitsNoRecordChangesAndDuplicateBundleIDsStaySeparate() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        _ = try fixture.application("First.app")
        _ = try fixture.application("Second.app")
        let catalog = ApplicationCatalog(directories: [try directory(fixture.root)], scanner: ApplicationScanner())

        let first = await catalog.refresh()
        let second = await catalog.refresh()

        #expect(first.inserted.count == 2)
        #expect(Set(first.records.map(\.id)).count == 2)
        #expect(second.inserted.isEmpty)
        #expect(second.updated.isEmpty)
        #expect(second.records == first.records)
        #expect(second.affectedAppIDs == Set(first.records.map(\.id)))
    }

    @Test
    func incrementalRescanAffectsOnlyItsAppsEvenWhenMetadataIsUnchanged() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let firstSource = try directory(fixture.directory("First"))
        let secondSource = try directory(fixture.directory("Second"))
        let firstApp = try fixture.application("First.app", in: firstSource.source.directoryURL)
        _ = try fixture.application("Second.app", in: secondSource.source.directoryURL)
        let catalog = ApplicationCatalog(directories: [firstSource, secondSource], scanner: ApplicationScanner())
        let initial = await catalog.refresh()
        let firstRecord = try #require(initial.records.first { $0.metadata.bundleURL == firstApp.standardized })

        let result = await catalog.refresh(directoryIDs: [firstSource.id])

        #expect(result.records == initial.records)
        #expect(result.updated.isEmpty)
        #expect(result.affectedAppIDs == [firstRecord.id])
    }

    @Test
    func overlappingSourcesAndLinksDoNotCreateAdditionalAppCopies() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let app = try fixture.application("Editor.app", in: apps)
        _ = try fixture.alias(to: app, named: "Alias")
        _ = try fixture.symbolicLink(to: app, named: "Link.app")
        let catalog = ApplicationCatalog(
            directories: [try directory(fixture.root), try directory(apps)], scanner: ApplicationScanner()
        )

        let result = await catalog.refresh()

        #expect(result.records.count == 1)
        #expect(result.inserted.count == 1)
        #expect(result.records.first?.metadata.bundleURL == app.standardized)
    }

    @Test
    func actualMoveAcrossSourcesPreservesIdentityAndCustomizationKey() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let firstDirectory = try fixture.directory("First")
        let secondDirectory = try fixture.directory("Second")
        let app = try fixture.application("Editor.app", in: firstDirectory)
        let firstSource = try directory(firstDirectory)
        let secondSource = try directory(secondDirectory)
        let catalog = ApplicationCatalog(directories: [firstSource, secondSource], scanner: ApplicationScanner())
        let initial = await catalog.refresh()
        let record = try #require(initial.records.first)
        let customization = AppCustomization(appID: record.id, isHidden: true, customName: "  My Editor  ")
        let overrides = [record.id: customization]
        let moved = secondDirectory.appendingPathComponent("Moved Editor.app", isDirectory: true)
        try FileManager.default.moveItem(at: app, to: moved)

        let result = await catalog.refresh()
        let updated = try #require(result.records.first)

        #expect(result.records.count == 1)
        #expect(result.inserted.isEmpty)
        #expect(updated.id == record.id)
        #expect(updated.metadata.bundleURL == moved.standardized)
        #expect(updated.source.directoryURL == secondDirectory.standardized)
        #expect(updated.isMissing == false)
        #expect(overrides[updated.id] == customization)
    }

    @Test
    func scanningTheOldSourceFirstPreservesAMovedAppsIdentity() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let firstDirectory = try fixture.directory("First")
        let secondDirectory = try fixture.directory("Second")
        let app = try fixture.application("Editor.app", in: firstDirectory)
        let firstSource = try directory(firstDirectory)
        let secondSource = try directory(secondDirectory)
        let catalog = ApplicationCatalog(directories: [firstSource, secondSource], scanner: ApplicationScanner())
        let initial = await catalog.refresh()
        let record = try #require(initial.records.first)
        let customization = AppCustomization(appID: record.id, isHidden: true, customName: "My Editor")
        let savedCustomizations = [record.id: customization]
        let moved = secondDirectory.appendingPathComponent("Moved Editor.app", isDirectory: true)
        try FileManager.default.moveItem(at: app, to: moved)

        let result = await catalog.refresh(directoryIDs: [firstSource.id])
        let updated = try #require(result.records.first)

        #expect(result.records.count == 1)
        #expect(result.inserted.isEmpty)
        #expect(result.updated.map(\.id) == [record.id])
        #expect(result.availableRecords.map(\.id) == [record.id])
        #expect(result.affectedAppIDs == [record.id])
        #expect(updated.id == record.id)
        #expect(updated.metadata.bundleURL == moved.standardized)
        #expect(updated.source.directoryURL == secondDirectory.standardized)
        #expect(savedCustomizations[updated.id] == customization)
    }

    @Test
    func incrementalDeletionRemovesTheRecordAfterCompleteOnlineScan() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let firstDirectory = try fixture.directory("First")
        let secondDirectory = try fixture.directory("Second")
        let removed = try fixture.application("Removed.app", in: firstDirectory)
        _ = try fixture.application("Kept.app", in: secondDirectory)
        let firstSource = try directory(firstDirectory)
        let secondSource = try directory(secondDirectory)
        let catalog = ApplicationCatalog(directories: [firstSource, secondSource], scanner: ApplicationScanner())
        let before = await catalog.refresh()
        let removedRecord = try #require(before.records.first { $0.metadata.bundleURL == removed.standardized })
        let keptRecord = try #require(before.records.first { $0.id != removedRecord.id })
        try FileManager.default.removeItem(at: removed)

        let result = await catalog.refresh(directoryIDs: [firstSource.id])

        #expect(result.inserted.isEmpty)
        #expect(result.records.count == 1)
        #expect(result.records.allSatisfy { $0.id != removedRecord.id })
        #expect(result.records.first { $0.id == keptRecord.id } == keptRecord)
        #expect(result.availableRecords.map(\.id) == [keptRecord.id])
        #expect(result.updated.isEmpty)
        #expect(result.affectedAppIDs == [removedRecord.id, keptRecord.id])
        #expect(result.scans.first { $0.directory.id == firstSource.id }?.isComplete == true)
        #expect(result.scans.first { $0.directory.id == firstSource.id }?.source.isOnline == true)
    }

    @Test
    func inaccessibleSourceDoesNotMarkItsAppsMissing() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        let apps = try fixture.directory("Apps")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: apps.path)
            fixture.remove()
        }
        _ = try fixture.application("Editor.app", in: apps)
        let catalog = ApplicationCatalog(directories: [try directory(apps)], scanner: ApplicationScanner())
        let before = await catalog.refresh()
        let identity = try #require(before.records.first?.id)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: apps.path)

        let result = await catalog.refresh()

        #expect(result.records.count == 1)
        #expect(result.records.first?.id == identity)
        #expect(result.records.first?.isMissing != true)
        #expect(result.scans.contains { !$0.isComplete && !$0.issues.isEmpty })
    }

    @Test
    func absentSourceIsDifferentFromDeletingAnAppInsideAnOnlineSource() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        _ = try fixture.application("Editor.app", in: apps)
        let catalog = ApplicationCatalog(directories: [try directory(apps)], scanner: ApplicationScanner())
        let before = await catalog.refresh()
        try FileManager.default.removeItem(at: apps)

        let result = await catalog.refresh()

        #expect(result.records.count == 1)
        #expect(result.records.first?.id == before.records.first?.id)
        #expect(result.records.first?.isMissing != true)
        #expect(result.scans.first?.source.isOnline == false)
    }

    @Test
    func sameLocationReinstallWithMatchingBundleIdentifierKeepsIdentity() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let staged = try fixture.directory("Staging")
        let previous = try fixture.application("Editor.app", in: apps)
        let replacement = try fixture.application("Replacement.app", in: staged)
        let catalog = ApplicationCatalog(directories: [try directory(apps)], scanner: ApplicationScanner())
        let initial = await catalog.refresh()
        let previousID = try #require(initial.records.first?.id)
        try FileManager.default.removeItem(at: previous)
        try FileManager.default.moveItem(at: replacement, to: previous)

        let result = await catalog.refresh()

        #expect(result.inserted.isEmpty)
        #expect(result.records.count == 1)
        #expect(result.records.first?.id == previousID)
    }

    @Test
    func renamedSourceKeepsItsDirectoryAndAppIdentities() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        _ = try fixture.application("Editor.app", in: apps)
        let source = try directory(apps)
        let catalog = ApplicationCatalog(directories: [source], scanner: ApplicationScanner())
        let initial = await catalog.refresh()
        let moved = fixture.root.appendingPathComponent("Renamed Apps", isDirectory: true)
        try FileManager.default.moveItem(at: apps, to: moved)

        let result = await catalog.refresh()

        #expect(result.records.count == 1)
        #expect(result.records.first?.id == initial.records.first?.id)
        #expect(result.scans.first?.directory.id == source.id)
        #expect(result.records.first?.source.directoryURL == moved.standardized)
    }

    @Test
    func unavailableFileIdentityStillMatchesAUniqueKnownBundleAtTheSameLocation() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        _ = try fixture.application("Editor.app")
        let catalog = ApplicationCatalog(directories: [try directory(fixture.root)], scanner: MetadataOnlyScanner())

        let first = await catalog.refresh()
        let second = await catalog.refresh()

        #expect(second.records.count == 1)
        #expect(second.records.first?.id == first.records.first?.id)
        #expect(second.inserted.isEmpty)
        #expect(second.updated.isEmpty)
    }

    @Test
    func cachedObservationInAnotherSourceCannotUndoAMove() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let firstDirectory = try fixture.directory("First")
        let secondDirectory = try fixture.directory("Second")
        let app = try fixture.application("Editor.app", in: firstDirectory)
        let firstSource = try directory(firstDirectory)
        let secondSource = try directory(secondDirectory)
        let catalog = ApplicationCatalog(directories: [firstSource, secondSource], scanner: ApplicationScanner())
        let before = await catalog.refresh()
        let moved = secondDirectory.appendingPathComponent("Moved.app", isDirectory: true)
        try FileManager.default.moveItem(at: app, to: moved)

        let after = await catalog.refresh(directoryIDs: [secondSource.id])

        #expect(after.records.count == 1)
        #expect(after.records.first?.id == before.records.first?.id)
        #expect(after.records.first?.metadata.bundleURL == moved.standardized)
        #expect(after.records.first?.source.directoryURL == secondDirectory.standardized)
    }

    @Test
    func actualMoveWinsWhenANewCopyOccupiesThePreviousLocation() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let app = try fixture.application("Original.app")
        let catalog = ApplicationCatalog(directories: [try directory(fixture.root)], scanner: ApplicationScanner())
        let before = await catalog.refresh()
        let originalID = try #require(before.records.first?.id)
        let moved = fixture.root.appendingPathComponent("Renamed.app", isDirectory: true)
        try FileManager.default.moveItem(at: app, to: moved)
        _ = try fixture.application("Original.app")

        let after = await catalog.refresh()

        #expect(after.records.count == 2)
        #expect(after.records.first { $0.metadata.bundleURL == moved.standardized }?.id == originalID)
        #expect(after.records.first { $0.metadata.bundleURL == app.standardized }?.id != originalID)
    }

    @Test
    func aDifferentKnownBundleAtTheSameLocationDoesNotInheritIdentity() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let app = try fixture.application("Editor.app", in: apps, identifier: "com.example.Old")
        let catalog = ApplicationCatalog(directories: [try directory(apps)], scanner: ApplicationScanner())
        let before = await catalog.refresh()
        try FileManager.default.removeItem(at: app)
        _ = try fixture.application("Editor.app", in: apps, identifier: "com.example.Different")

        let after = await catalog.refresh()

        #expect(after.availableRecords.count == 1)
        #expect(after.availableRecords.first?.metadata.bundleIdentifier == "com.example.Different")
        #expect(after.availableRecords.first?.id != before.records.first?.id)
        #expect(after.records.count == 2)
        #expect(after.records.first { $0.id == before.records.first?.id }?.isMissing == nil)
    }

    @Test
    func anInvalidatedBundleIsRetainedButUnavailableUntilRestored() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let app = try fixture.application("Editor.app")
        let catalog = ApplicationCatalog(directories: [try directory(fixture.root)], scanner: ApplicationScanner())
        let before = await catalog.refresh()
        try Data("invalid plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"), options: .atomic)

        let after = await catalog.refresh()

        #expect(after.availableRecords.isEmpty)
        #expect(after.records.count == 1)
        #expect(after.records.first?.id == before.records.first?.id)
        #expect(after.records.first?.isMissing == nil)
    }

    @Test
    func deletionInvalidatesEveryCachedSourceThatObservedTheSameCopy() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let app = try fixture.application("Editor.app", in: apps)
        let inner = try directory(apps)
        let catalog = ApplicationCatalog(
            directories: [try directory(fixture.root), inner], scanner: ApplicationScanner()
        )
        let before = await catalog.refresh()
        try FileManager.default.removeItem(at: app)

        let after = await catalog.refresh(directoryIDs: [inner.id])

        #expect(after.records.isEmpty)
        #expect(after.availableRecords.isEmpty)
        #expect(after.affectedAppIDs == Set(before.records.map(\.id)))
    }

    @Test
    func replacingTheOldLocationChecksOtherSourcesForTheMovedOriginal() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let first = try fixture.directory("First")
        let second = try fixture.directory("Second")
        let firstSource = try directory(first)
        let app = try fixture.application("Editor.app", in: first)
        let catalog = ApplicationCatalog(
            directories: [firstSource, try directory(second)], scanner: ApplicationScanner()
        )
        let before = await catalog.refresh()
        let originalID = try #require(before.records.first?.id)
        let moved = second.appendingPathComponent("Moved.app", isDirectory: true)
        try FileManager.default.moveItem(at: app, to: moved)
        _ = try fixture.application("Editor.app", in: first)

        let after = await catalog.refresh(directoryIDs: [firstSource.id])

        #expect(after.availableRecords.count == 2)
        #expect(after.availableRecords.first { $0.metadata.bundleURL == moved.standardized }?.id == originalID)
        #expect(after.availableRecords.first { $0.metadata.bundleURL == app.standardized }?.id != originalID)
        #expect(after.affectedAppIDs == Set(after.records.map(\.id)))
    }

    @Test
    func unknownBundleAndFileIdentityRemainUnresolvedWithoutAccumulatingRecords() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        _ = try fixture.application("Unknown.app", identifier: nil)
        let catalog = ApplicationCatalog(directories: [try directory(fixture.root)], scanner: MetadataOnlyScanner())
        let before = await catalog.refresh()

        let after = await catalog.refresh()
        let again = await catalog.refresh()

        #expect(after.records.count == 1)
        #expect(again.records.count == 1)
        #expect(after.records.first?.id == before.records.first?.id)
        #expect(after.inserted.isEmpty)
        #expect(after.availableRecords.isEmpty)
        #expect(after.unresolvedApplications.count == 1)
    }

    @Test
    func movingTheSourcesParentPreservesTheAvailableAppAndDirectoryIdentity() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Parent/Apps")
        _ = try fixture.application("Editor.app", in: apps)
        let source = try directory(apps)
        let catalog = ApplicationCatalog(directories: [source], scanner: ApplicationScanner())
        let before = await catalog.refresh()
        let movedParent = fixture.root.appendingPathComponent("Renamed Parent", isDirectory: true)
        try FileManager.default.moveItem(at: apps.deletingLastPathComponent(), to: movedParent)

        let after = await catalog.refresh()

        #expect(after.availableRecords.count == 1)
        #expect(after.availableRecords.first?.id == before.availableRecords.first?.id)
        #expect(after.scans.first?.directory.id == source.id)
        #expect(after.scans.first?.isComplete == true)
        #expect(after.availableRecords.first?.source.directoryURL
            == movedParent.appendingPathComponent("Apps", isDirectory: true).standardized)
    }

    private func directory(_ url: URL) throws -> ApplicationScan.Directory {
        ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: url))
    }
}

extension ApplicationCatalogTests {
    @Test
    func persistedIdentityAndCustomizationSurviveARealRescan() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        _ = try fixture.application("Editor.app", in: apps)
        let source = try directory(apps)
        let initial = await ApplicationCatalog(directories: [source], scanner: ApplicationScanner()).refresh()
        let record = try #require(initial.records.first)
        let customization = AppCustomization(appID: record.id, isHidden: true, customName: "My Editor")
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        try await store.save(AppData(records: [record], customizations: [customization]))
        let restored = try #require(try await store.load())
        let catalog = ApplicationCatalog(
            directories: [try directory(apps)], scanner: ApplicationScanner(), restoredData: restored
        )

        let beforeScan = await catalog.refresh(directoryIDs: [])
        #expect(beforeScan.records.map(\.id) == [record.id])
        #expect(beforeScan.records.first?.isMissing == nil)
        #expect(beforeScan.availableRecords.isEmpty)
        let refreshed = await catalog.refresh()
        #expect(refreshed.inserted.isEmpty)
        #expect(refreshed.availableRecords.map(\.id) == [record.id])
        #expect(refreshed.availableRecords.first?.isMissing == false)
        try await store.save(AppData(records: refreshed.records, customizations: restored.customizations))
        #expect(try await store.load()?.customizations == [customization])
    }

    @Test(arguments: [false, true])
    func restorationDoesNotInventIdentityContinuityWithoutBundleAndLocation(moved: Bool) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let app = try fixture.application("Editor.app")
        let source = try directory(fixture.root)
        let metadata = try AppMetadata(
            bundleIdentifier: moved ? "com.example.DiscoveryFixture" : nil,
            bundleURL: moved ? fixture.root.appendingPathComponent("Former.app") : app,
            displayName: "Saved Editor"
        )
        let saved = AppRecord(metadata: metadata, source: source.source, isMissing: false)
        let catalog = ApplicationCatalog(
            directories: [source], scanner: ApplicationScanner(),
            restoredData: try AppData(records: [saved])
        )

        let result = await catalog.refresh()
        #expect(result.records.contains { $0.id == saved.id } == !moved)
        #expect(!result.availableRecords.contains { $0.id == saved.id })
        #expect(result.availableRecords.count == 1)
        #expect(result.availableRecords.first?.metadata.bundleURL == app.standardized)
        #expect(result.inserted.count == 1)
    }

    @Test
    func restoredDeletedAppIsPrunedAfterItsOnlineDirectoryIsScanned() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let source = try directory(fixture.root)
        let saved = AppRecord(
            metadata: try AppMetadata(bundleIdentifier: "com.example.Deleted",
                                      bundleURL: fixture.root.appendingPathComponent("Deleted.app"),
                                      displayName: "Deleted"),
            source: source.source, isMissing: true
        )
        let catalog = ApplicationCatalog(
            directories: [source], scanner: ApplicationScanner(),
            restoredData: try AppData(records: [saved])
        )

        let beforeScan = await catalog.refresh(directoryIDs: [])
        #expect(beforeScan.records.map(\.id) == [saved.id])
        #expect(beforeScan.records.first?.isMissing == nil)
        #expect(beforeScan.availableRecords.isEmpty)

        let result = await catalog.refresh()
        #expect(result.records.isEmpty)
        #expect(result.availableRecords.isEmpty)
        #expect(result.affectedAppIDs.contains(saved.id))
        #expect(result.scans.first?.isComplete == true)
        #expect(result.scans.first?.source.isOnline == true)

        let subsequent = await catalog.refresh()
        #expect(subsequent.records.isEmpty)
        #expect(subsequent.inserted.isEmpty)
    }

    @Test(arguments: [false, true])
    func unobservedRestoredDirectoriesCannotConfirmAnAppMissing(configured: Bool) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let absentDirectory = fixture.root.appendingPathComponent("Detached")
        let source = try directory(absentDirectory)
        let saved = AppRecord(
            metadata: try AppMetadata(bundleIdentifier: "com.example.Absent",
                                      bundleURL: absentDirectory.appendingPathComponent("Absent.app"),
                                      displayName: "Absent"),
            source: source.source, isMissing: true
        )
        let catalog = ApplicationCatalog(
            directories: configured ? [source] : [], scanner: ApplicationScanner(),
            restoredData: try AppData(records: [saved])
        )

        let result = await catalog.refresh()
        #expect(result.records.map(\.id) == [saved.id])
        #expect(result.records.first?.isMissing == nil)
        #expect(result.availableRecords.isEmpty)
        #expect(result.inserted.isEmpty)
    }
}

private actor MetadataOnlyScanner: ApplicationScanning {
    private let scanner = ApplicationScanner()

    func scan(_ directory: ApplicationScan.Directory) async -> ApplicationScan {
        let scan = await scanner.scan(directory)
        let observations = scan.applications.map {
            ApplicationScan.Observation(metadata: $0.metadata, discoveredURL: $0.discoveredURL,
                                        fileIdentity: nil, isAlias: $0.isAlias,
                                        isSymbolicLink: $0.isSymbolicLink)
        }
        var result = ApplicationScan(directory: scan.directory, source: scan.source, applications: observations,
                                     isComplete: scan.isComplete, issues: scan.issues, monitoredURLs: scan.monitoredURLs)
        result.listedDirectoryModificationDates = scan.listedDirectoryModificationDates
        return result
    }

    func isCurrent(_ scan: ApplicationScan) async -> Bool {
        await scanner.isCurrent(scan)
    }

    func isMissing(at url: URL) async -> Bool? {
        await scanner.isMissing(at: url)
    }
}
