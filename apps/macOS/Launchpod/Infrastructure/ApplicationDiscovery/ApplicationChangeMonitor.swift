import AppKit
import CoreServices

/// File events invalidate observations; they do not establish installation or identity.
@MainActor
final class ApplicationChangeMonitor {
    nonisolated struct Event: Sendable {
        let url: URL
        let flags: FSEventStreamEventFlags
    }

    enum MonitorError: Error {
        case cannotCreateStream
        case cannotStartStream
    }

    private nonisolated final class Callback: Sendable {
        let receive: @Sendable ([Event]) -> Void

        init(receive: @escaping @Sendable ([Event]) -> Void) {
            self.receive = receive
        }
    }

    private var stream: FSEventStreamRef?
    private var paths: [UUID: Set<URL>] = [:]
    private var tokens: [NotificationCenter.ObservationToken] = []
    private var accessedURLs: [URL] = []
    private var receive: (@MainActor (Set<UUID>, Bool) -> Void)?
    private var generation = 0

    isolated deinit {
        stop()
    }

    @discardableResult
    func start(
        directories: [ApplicationScan.Directory],
        onChange: @escaping @MainActor (Set<UUID>, Bool) -> Void
    ) async throws -> [ApplicationScan.Issue] {
        stop()
        let request = generation
        accessedURLs = Set(directories.map { $0.source.directoryURL }).filter {
            $0.startAccessingSecurityScopedResource()
        }
        do {
            let preparation = try await Task.detached(priority: .utility) {
                try Task.checkCancellation()
                var issues: [ApplicationScan.Issue] = []
                let paths = Dictionary(directories.map { directory in
                    let url: URL
                    do {
                        url = try ApplicationScanner.canonicalMonitoringURL(for: directory.source.directoryURL)
                    } catch {
                        url = directory.source.directoryURL
                        issues.append(.init(url: url, error: error))
                    }
                    return (directory.id, Set([url]))
                }, uniquingKeysWith: { $0.union($1) })
                return (paths: paths, issues: issues)
            }.value
            guard request == generation, !Task.isCancelled else { throw CancellationError() }
            paths = preparation.paths
            receive = onChange
            try replaceStream()
            let workspace = NSWorkspace.shared
            let center = workspace.notificationCenter
            tokens = [
                center.addObserver(of: workspace, for: NSWorkspace.DidMountVolumeMessage.self) { [weak self] _ in
                    self?.volumeChanged()
                },
                center.addObserver(of: workspace, for: NSWorkspace.DidUnmountVolumeMessage.self) { [weak self] _ in
                    self?.volumeChanged()
                },
                center.addObserver(of: workspace, for: NSWorkspace.DidRenameVolumeMessage.self) { [weak self] _ in
                    self?.volumeChanged()
                }
            ]
            return preparation.issues
        } catch {
            if request == generation { stop() }
            throw error
        }
    }

    /// Replacing a stream starts at now, so every watched directory needs another scan.
    func update(scans: [ApplicationScan]) throws -> Set<UUID> {
        var changed = Set<UUID>()
        var newPaths = paths
        for scan in scans {
            var urls = Set(scan.monitoredURLs)
            if !scan.isComplete { urls.formUnion(paths[scan.directory.id] ?? []) }
            if urls != paths[scan.directory.id] {
                newPaths[scan.directory.id] = urls
                changed.insert(scan.directory.id)
            }
        }
        guard !changed.isEmpty else { return [] }
        let previous = paths
        paths = newPaths
        do {
            try replaceStream()
        } catch {
            paths = previous
            throw error
        }
        return Set(paths.keys)
    }

    func rebuild() throws -> Set<UUID> {
        try replaceStream()
        return Set(paths.keys)
    }

    func stop() {
        generation += 1
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        tokens.removeAll()
        for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
        accessedURLs.removeAll()
        paths.removeAll()
        receive = nil
    }

    func process(_ events: [Event]) {
        var affected = Set<UUID>()
        var rebuild = false
        let dropped = FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped)
        for event in events {
            if event.flags & dropped != 0 {
                affected.formUnion(paths.keys)
            } else {
                for (id, urls) in paths where urls.contains(where: { Self.overlaps($0, event.url) }) {
                    affected.insert(id)
                }
            }
            if event.flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged
                | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount) != 0 {
                rebuild = true
            }
        }
        if !affected.isEmpty { receive?(affected, rebuild) }
    }

    private func volumeChanged() {
        receive?(Set(paths.keys), true)
    }

    private func replaceStream() throws {
        let urls = Set(paths.values.flatMap { $0 }).map(\.path).sorted()
        guard !urls.isEmpty else { return }
        let current = generation
        let callback = Callback { [weak self] events in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                self.process(events)
            }
        }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<Callback>.fromOpaque(pointer).retain()
                return pointer
            },
            release: { pointer in
                if let pointer { Unmanaged<Callback>.fromOpaque(pointer).release() }
            }, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot
            | kFSEventStreamCreateFlagFileEvents)
        guard let next = FSEventStreamCreate(kCFAllocatorDefault, Self.callback, &context,
            urls as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0, flags)
        else { throw MonitorError.cannotCreateStream }
        FSEventStreamSetDispatchQueue(next, .main)
        guard FSEventStreamStart(next) else {
            FSEventStreamInvalidate(next)
            FSEventStreamRelease(next)
            throw MonitorError.cannotStartStream
        }
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = next
    }

    private nonisolated static let callback: FSEventStreamCallback = { _, context, count, rawPaths, flags, _ in
        guard let context else { return }
        let paths = rawPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        let events = (0..<count).map {
            Event(url: URL(fileURLWithPath: String(cString: paths[$0])), flags: flags[$0])
        }
        Unmanaged<Callback>.fromOpaque(context).takeUnretainedValue().receive(events)
    }

    private nonisolated static func overlaps(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = lhs.pathComponents
        let right = rhs.pathComponents
        return left.starts(with: right) || right.starts(with: left)
    }
}
