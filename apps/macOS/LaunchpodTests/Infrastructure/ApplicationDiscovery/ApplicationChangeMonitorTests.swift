import AppKit
import CoreServices
import Testing
@testable import Launchpod

@MainActor
struct ApplicationChangeMonitorTests {
    @Test
    func realFileEventsReportAnApplicationInstallation() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let source = try directory(fixture.root)
        let monitor = ApplicationChangeMonitor()
        var affected = Set<UUID>()
        try await monitor.start(directories: [source]) { ids, _ in affected.formUnion(ids) }
        defer { monitor.stop() }

        _ = try fixture.application("Installed.app")

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !affected.contains(source.id), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(affected == [source.id])
    }

    @Test
    func eventRoutingUsesPathComponentsAndDroppedEventsInvalidateEverySource() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try directory(fixture.directory("Apps"))
        let appsExtra = try directory(fixture.directory("Apps Extra"))
        let monitor = ApplicationChangeMonitor()
        var deliveries: [(Set<UUID>, Bool)] = []
        try await monitor.start(directories: [apps, appsExtra]) { deliveries.append(($0, $1)) }
        defer { monitor.stop() }

        let eventDirectory = try fixture.canonicalURL(apps.source.directoryURL)
        monitor.process([.init(url: eventDirectory.appendingPathComponent("Editor.app"), flags: 0)])
        #expect(deliveries.count == 1)
        #expect(deliveries.last?.0 == [apps.id])
        monitor.process([.init(url: fixture.root, flags: FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped))])
        #expect(deliveries.last?.0 == [apps.id, appsExtra.id])
    }

    @Test
    func rootAndVolumeChangesRequestWatchRebuilding() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let source = try directory(fixture.root)
        let monitor = ApplicationChangeMonitor()
        var rebuilds = 0
        try await monitor.start(directories: [source]) { _, rebuild in if rebuild { rebuilds += 1 } }
        defer { monitor.stop() }

        for flag in [kFSEventStreamEventFlagRootChanged, kFSEventStreamEventFlagMount, kFSEventStreamEventFlagUnmount] {
            monitor.process([.init(url: try fixture.canonicalURL(fixture.root), flags: FSEventStreamEventFlags(flag))])
        }

        #expect(rebuilds == 3)
    }

    @Test
    func observingResolvedLinkTargetsAddsOneRequiredFollowupScan() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let links = try fixture.directory("Links")
        let app = try fixture.application("Editor.app", in: apps)
        _ = try fixture.symbolicLink(to: app, named: "Editor Link.app", in: links)
        let source = try directory(links)
        let scan = await ApplicationScanner().scan(source)
        let monitor = ApplicationChangeMonitor()
        var affected = Set<UUID>()
        try await monitor.start(directories: [source]) { ids, _ in affected.formUnion(ids) }
        defer { monitor.stop() }

        #expect(try monitor.update(scans: [scan]) == [source.id])
        #expect(try monitor.update(scans: [scan]).isEmpty)
        monitor.process([.init(url: try fixture.canonicalURL(app).appendingPathComponent("Contents/Info.plist"), flags: 0)])

        #expect(affected == [source.id])
    }

    @Test
    func replacingTheSharedStreamRequiresFreshObservationsOfEveryWatchedDirectory() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let links = try fixture.directory("Links")
        let other = try directory(fixture.directory("Other"))
        let external = try fixture.directory("External")
        let app = try fixture.application("Editor.app", in: external)
        let link = try fixture.symbolicLink(to: app, named: "Editor Link.app", in: links)
        let source = try directory(links)
        let scanner = ApplicationScanner()
        let linkedScan = await scanner.scan(source)
        let monitor = ApplicationChangeMonitor()
        try await monitor.start(directories: [source, other]) { _, _ in }
        defer { monitor.stop() }

        // Replacing a SinceNow stream discards its old delivery boundary for both directories.
        #expect(try monitor.update(scans: [linkedScan]) == [source.id, other.id])
        #expect(try monitor.update(scans: [linkedScan]).isEmpty)

        try FileManager.default.removeItem(at: link)
        let unlinkedScan = await scanner.scan(source)
        #expect(unlinkedScan.isComplete)
        #expect(try monitor.update(scans: [unlinkedScan]) == [source.id, other.id])
        #expect(try monitor.update(scans: [unlinkedScan]).isEmpty)
    }

    @Test
    func restartingReplacesTheReceiverAndStoppingRejectsFurtherEvents() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let source = try directory(fixture.root)
        let monitor = ApplicationChangeMonitor()
        var first = 0
        var second = 0
        try await monitor.start(directories: [source]) { _, _ in first += 1 }
        try await monitor.start(directories: [source]) { _, _ in second += 1 }
        let eventRoot = try fixture.canonicalURL(fixture.root)
        monitor.process([.init(url: eventRoot, flags: 0)])
        monitor.stop()
        monitor.stop()
        monitor.process([.init(url: eventRoot, flags: 0)])

        #expect(first == 0)
        #expect(second == 1)
    }

    private func directory(_ url: URL) throws -> ApplicationScan.Directory {
        ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: url))
    }
}
