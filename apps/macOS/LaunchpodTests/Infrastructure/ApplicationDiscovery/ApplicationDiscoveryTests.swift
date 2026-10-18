import Foundation
import CoreServices
import Testing
@testable import Launchpod

@MainActor
struct ApplicationDiscoveryTests {
    @Test
    func firstDiscoveryUpdatePreservesRestoredIdentity() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        _ = try fixture.application("Editor.app")
        let source = try directory(fixture.root)
        let initial = await ApplicationCatalog(directories: [source], scanner: ApplicationScanner()).refresh()
        let saved = try #require(initial.records.first)
        let discovery = ApplicationDiscovery(
            directories: [try directory(fixture.root)], restoredData: try AppData(records: [saved])
        )
        var latest: ApplicationCatalog.Update?
        try await discovery.start { latest = $0 }
        defer { discovery.stop() }
        try await wait("restored identity scan") { latest != nil }

        #expect(latest?.availableRecords.map(\.id) == [saved.id])
        #expect(latest?.inserted.isEmpty == true)
    }

    @Test
    func actualInstallMoveAndDeleteEventsPublishIncrementalMainActorUpdates() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let requested = FileManager.default.temporaryDirectory
            .appendingPathComponent(fixture.root.lastPathComponent, isDirectory: true)
        let discovery = ApplicationDiscovery(directories: [try directory(requested)])
        var updates: [ApplicationCatalog.Update] = []
        var duplicateReceiverCalled = false
        try await discovery.start { update in
            MainActor.preconditionIsolated()
            updates.append(update)
        }
        try await discovery.start { _ in duplicateReceiverCalled = true }
        defer { discovery.stop() }
        try await wait("initial scan") { !updates.isEmpty }

        let app = try fixture.application("Installed.app")
        try await wait("installed application") { updates.last?.availableRecords.contains { $0.metadata.bundleURL == app.standardized } == true }
        let original = try #require(updates.last?.availableRecords.first)
        let moved = fixture.root.appendingPathComponent("Moved.app", isDirectory: true)
        try FileManager.default.moveItem(at: app, to: moved)
        try await wait("moved application") { updates.last?.availableRecords.contains { $0.metadata.bundleURL == moved.standardized } == true }
        #expect(updates.last?.availableRecords.first?.id == original.id)
        let updateCountBeforeDeletion = updates.count
        try FileManager.default.removeItem(at: moved)
        try await wait("deleted application") {
            updates.dropFirst(updateCountBeforeDeletion).contains {
                $0.records.allSatisfy { $0.id != original.id }
                    && $0.affectedAppIDs.contains(original.id)
            }
        }
        let deletionUpdate = try #require(updates.dropFirst(updateCountBeforeDeletion).first {
            $0.records.allSatisfy { $0.id != original.id }
                && $0.affectedAppIDs.contains(original.id)
        })

        #expect(deletionUpdate.availableRecords.isEmpty)
        #expect(deletionUpdate.records.isEmpty)
        #expect(deletionUpdate.scans.first?.isComplete == true)
        #expect(deletionUpdate.scans.first?.source.isOnline == true)
        #expect(!duplicateReceiverCalled)
        discovery.stop()
        discovery.stop()
        #expect(!discovery.isRunning)
        let deliveryCount = updates.count
        discovery.refresh()
        _ = try fixture.application("After Stop.app")
        try await Task.sleep(for: .milliseconds(100))
        #expect(updates.count == deliveryCount)
    }

    @Test
    func externalLinkedTargetIsRediscoveredAfterDeletionAndRestoration() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Actual")
        let links = try fixture.directory("Links")
        let app = try fixture.application("Editor.app", in: apps)
        _ = try fixture.symbolicLink(to: app, named: "Editor Link.app", in: links)
        let discovery = ApplicationDiscovery(directories: [try directory(links)])
        var latest: ApplicationCatalog.Update?
        try await discovery.start { latest = $0 }
        defer { discovery.stop() }
        try await wait("initial external application") { latest?.availableRecords.count == 1 }
        let identity = try #require(latest?.availableRecords.first?.id)

        try FileManager.default.removeItem(at: app)
        try await wait("deleted external application") { latest?.availableRecords.isEmpty == true }
        _ = try fixture.application("Editor.app", in: apps)
        try await wait("restored external application") { latest?.availableRecords.count == 1 }

        #expect(latest?.availableRecords.first?.id == identity)
        #expect(latest?.availableRecords.first?.metadata.bundleURL == app.standardized)
    }

    @Test(arguments: [false, true])
    func initiallyBrokenExternalSymbolicLinkIsDiscoveredWhenItsTargetAppears(missingParents: Bool) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        let external = try ApplicationDiscoveryTestDirectory()
        defer {
            fixture.remove()
            external.remove()
        }
        let parent = missingParents
            ? external.root.appendingPathComponent("Absent/Tools%2F\u{5de5}\u{5177}", isDirectory: true)
            : external.root
        let target = parent.appendingPathComponent("Editor.app", isDirectory: true)
        _ = try fixture.symbolicLink(to: target, named: "Editor Link.app")
        let discovery = ApplicationDiscovery(directories: [try directory(fixture.root)])
        var latest: ApplicationCatalog.Update?
        try await discovery.start { latest = $0 }
        defer { discovery.stop() }
        try await wait("initial broken link scan") { latest != nil }
        #expect(latest?.availableRecords.isEmpty == true)
        #expect(latest?.scans.first?.isComplete == false)

        let installed = try external.application("Editor.app", in: parent)
        try await wait("initially absent external target") {
            latest?.availableRecords.contains { $0.metadata.bundleURL == installed.standardized } == true
        }

        #expect(latest?.availableRecords.count == 1)
        #expect(latest?.scans.first?.isComplete == true)
    }

    @Test
    func anInitiallyBrokenSourceLinkRecoversWhenItsExternalDirectoryAppears() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        let external = try ApplicationDiscoveryTestDirectory()
        defer {
            fixture.remove()
            external.remove()
        }
        let target = external.root.appendingPathComponent("Absent/Applications", isDirectory: true)
        let link = try fixture.symbolicLink(to: target, named: "Linked Applications")
        let discovery = ApplicationDiscovery(directories: [try directory(link)])
        var latest: ApplicationCatalog.Update?
        try await discovery.start { latest = $0 }
        defer { discovery.stop() }
        try await wait("initial broken source link scan") { latest != nil }
        #expect(latest?.scans.first?.source.isOnline == false)

        let app = try external.application("Editor.app", in: target)
        try await wait("initially absent linked directory") {
            latest?.availableRecords.contains { $0.metadata.bundleURL == app.standardized } == true
        }

        #expect(latest?.scans.first?.source.isOnline == true)
        #expect(latest?.scans.first?.isComplete == true)
    }

    @Test
    func addingAnExternalWatchCompletesAnotherObservationOfEverySource() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        let external = try ApplicationDiscoveryTestDirectory()
        defer {
            fixture.remove()
            external.remove()
        }
        let links = try directory(fixture.directory("Links"))
        let other = try directory(fixture.directory("Other"))
        let app = try external.application("Editor.app")
        _ = try fixture.symbolicLink(to: app, named: "Editor Link.app", in: links.source.directoryURL)
        let scanner = CountingApplicationScanner()
        let discovery = ApplicationDiscovery(directories: [links, other], scanner: scanner)
        var updates = 0
        try await discovery.start { _ in updates += 1 }
        defer { discovery.stop() }
        try await wait("observations after adding an external watch") { updates >= 2 }

        #expect(await scanner.completedScans[links.id, default: 0] >= 2)
        #expect(await scanner.completedScans[other.id, default: 0] >= 2)
    }

    @Test
    func rebuildingForOneRootCompletesAnotherObservationOfEverySource() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let first = try directory(fixture.directory("First"))
        let other = try directory(fixture.directory("Other"))
        let scanner = CountingApplicationScanner()
        let monitor = ApplicationChangeMonitor()
        let discovery = ApplicationDiscovery(directories: [first, other], scanner: scanner, monitor: monitor)
        var updates = 0
        try await discovery.start { _ in updates += 1 }
        defer { discovery.stop() }
        try await wait("initial directory observations") { updates >= 1 }
        let previousUpdates = updates
        let previousScans = await scanner.completedScans

        // This tests the rebuild rescan obligation, without simulating daemon event loss.
        monitor.process([.init(url: try fixture.canonicalURL(first.source.directoryURL),
                              flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged))])
        try await wait("observations after rebuilding the stream") { updates > previousUpdates }

        #expect(await scanner.completedScans[first.id, default: 0] > previousScans[first.id, default: 0])
        #expect(await scanner.completedScans[other.id, default: 0] > previousScans[other.id, default: 0])
    }

    @Test
    func scanningManyRealBundlesAllowsMainActorProgress() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        for index in 0..<160 {
            _ = try fixture.application("Application \(index).app", identifier: "com.example.Fixture\(index)")
        }
        let discovery = ApplicationDiscovery(directories: [try directory(fixture.root)])
        var finished = false
        var ticks = 0
        try await discovery.start { update in finished = update.availableRecords.count == 160 }
        defer { discovery.stop() }
        // Freshly created bundles are unknown to Launch Services; its first `isApplication` and
        // `localizedName` lookups register each one (tens of milliseconds per bundle), unlike
        // installed applications. The bound covers that registration, not scanner throughput.
        let deadline = ContinuousClock.now.advanced(by: .seconds(120))
        while !finished, ContinuousClock.now < deadline {
            ticks += 1
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(finished)
        #expect(ticks > 1)
    }

    @Test
    func aChangeDuringTheInitialScanIsRescannedBeforeBecomingIdle() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let source = try directory(fixture.root)
        let scanner = PausingApplicationScanner()
        let monitor = ApplicationChangeMonitor()
        let discovery = ApplicationDiscovery(directories: [source], scanner: scanner, monitor: monitor)
        var latest: ApplicationCatalog.Update?
        try await discovery.start { latest = $0 }
        defer {
            discovery.stop()
            Task { await scanner.resume() }
        }
        try await waitForPause(scanner)
        let installed = try fixture.application("During Scan.app")
        monitor.process([.init(url: try fixture.canonicalURL(installed), flags: 0)])
        await scanner.resume()
        try await wait { latest?.availableRecords.count == 1 }

        #expect(latest?.availableRecords.first?.metadata.bundleURL == installed.standardized)
        #expect(await scanner.scanCount >= 2)
    }

    @Test
    func aStoppedScanCannotPublishOverTheRestartedSession() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let old = try fixture.application("Old.app", identifier: "com.example.Old")
        let scanner = PausingApplicationScanner()
        let discovery = ApplicationDiscovery(directories: [try directory(fixture.root)], scanner: scanner)
        var oldDeliveries = 0
        var latest: ApplicationCatalog.Update?
        try await discovery.start { _ in oldDeliveries += 1 }
        defer {
            discovery.stop()
            Task { await scanner.resume() }
        }
        try await waitForPause(scanner)
        discovery.stop()
        try FileManager.default.removeItem(at: old)
        let current = try fixture.application("Current.app", identifier: "com.example.Current")
        try await discovery.start { latest = $0 }
        try await wait { latest?.availableRecords.contains { $0.metadata.bundleURL == current.standardized } == true }
        await scanner.resume()
        try await Task.sleep(for: .milliseconds(100))

        #expect(oldDeliveries == 0)
        #expect(latest?.availableRecords.map(\.metadata.bundleIdentifier) == ["com.example.Current"])
    }

    @Test
    func anInitiallyAbsentDirectoryCanAppearAndRecoverAfterRemoval() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = fixture.root.appendingPathComponent("Applications", isDirectory: true)
        let discovery = ApplicationDiscovery(directories: [try directory(apps)])
        var latest: ApplicationCatalog.Update?
        try await discovery.start { latest = $0 }
        defer { discovery.stop() }
        try await wait("initial absent directory scan") { latest != nil }
        _ = try fixture.application("First.app", in: apps)
        try await wait("created directory") { latest?.availableRecords.count == 1 }
        try FileManager.default.removeItem(at: apps)
        try await wait("removed directory") { latest?.availableRecords.isEmpty == true }
        _ = try fixture.application("Restored.app", in: apps, identifier: "com.example.Restored")
        try await wait("restored directory") { latest?.availableRecords.first?.metadata.bundleIdentifier == "com.example.Restored" }

        #expect(latest?.availableRecords.count == 1)
        #expect(latest?.scans.first?.source.isOnline == true)
    }

    @Test
    func cancelledStartDoesNotLeaveMonitoringRunning() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let discovery = ApplicationDiscovery(directories: [try directory(fixture.root)])
        var received = false
        let start = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await discovery.start { _ in received = true }
                return false
            } catch is CancellationError {
                return true
            } catch {
                Issue.record(error)
                return false
            }
        }
        defer { discovery.stop() }

        #expect(await start.value)
        #expect(!discovery.isRunning)
        #expect(!received)
    }

    private func waitForPause(_ scanner: PausingApplicationScanner) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await !scanner.isPaused, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(await scanner.isPaused)
    }

    private func directory(_ url: URL) throws -> ApplicationScan.Directory {
        ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: url))
    }

    private func wait(_ phase: String = "discovery update", until condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(6))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Timed out waiting for \(phase).")
    }
}

private actor CountingApplicationScanner: ApplicationScanning {
    private let scanner = ApplicationScanner()
    private(set) var completedScans: [UUID: Int] = [:]

    func scan(_ directory: ApplicationScan.Directory) async -> ApplicationScan {
        let scan = await scanner.scan(directory)
        completedScans[directory.id, default: 0] += 1
        return scan
    }

    func isCurrent(_ scan: ApplicationScan) async -> Bool {
        await scanner.isCurrent(scan)
    }

    func isMissing(at url: URL) async -> Bool? {
        await scanner.isMissing(at: url)
    }
}

private actor PausingApplicationScanner: ApplicationScanning {
    private let scanner = ApplicationScanner()
    private var continuation: CheckedContinuation<Void, Never>?
    private var shouldPause = true
    private(set) var isPaused = false
    private(set) var scanCount = 0

    func scan(_ directory: ApplicationScan.Directory) async -> ApplicationScan {
        scanCount += 1
        let result = await scanner.scan(directory)
        if shouldPause {
            shouldPause = false
            isPaused = true
            await withCheckedContinuation { continuation = $0 }
            isPaused = false
        }
        return result
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }

    func isCurrent(_ scan: ApplicationScan) async -> Bool {
        await scanner.isCurrent(scan)
    }

    func isMissing(at url: URL) async -> Bool? {
        await scanner.isMissing(at: url)
    }
}
