import Foundation

/// Owns monitoring and scan requests, publishing completed catalog changes on the main actor.
@MainActor
final class ApplicationDiscovery {
    private let directories: [ApplicationScan.Directory]
    private let catalog: ApplicationCatalog
    private let monitor: ApplicationChangeMonitor
    private var pending = Set<UUID>()
    private var task: Task<Void, Never>?
    private var generation = 0
    private var isStarting = false
    private var receive: (@MainActor (ApplicationCatalog.Update) -> Void)?
    private(set) var isRunning = false
    private(set) var monitoringError: (any Error)?

    isolated deinit {
        stop()
    }

    init(
        directories: [ApplicationScan.Directory] = ApplicationScanner.defaultDirectories(),
        scanner: any ApplicationScanning = ApplicationScanner(),
        monitor: ApplicationChangeMonitor? = nil,
        restoredData: AppData? = nil
    ) {
        self.directories = directories
        catalog = ApplicationCatalog(directories: directories, scanner: scanner,
                                     restoredData: restoredData)
        self.monitor = monitor ?? ApplicationChangeMonitor()
    }

    func start(onUpdate: @escaping @MainActor (ApplicationCatalog.Update) -> Void) async throws {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        let request = generation
        receive = onUpdate
        monitoringError = nil
        do {
            let issues = try await monitor.start(directories: directories) { [weak self] ids, rebuild in
                guard let self, self.isRunning else { return }
                var affected = ids
                if rebuild {
                    do { affected.formUnion(try self.monitor.rebuild()) }
                    catch { self.monitoringError = error }
                }
                self.refresh(directoryIDs: affected)
            }
            guard request == generation, !Task.isCancelled else { throw CancellationError() }
            monitoringError = issues.first
        } catch {
            if request == generation {
                isStarting = false
                receive = nil
                monitor.stop()
            }
            throw error
        }
        isStarting = false
        isRunning = true
        refresh()
    }

    func refresh(directoryIDs: Set<UUID>? = nil) {
        guard isRunning else { return }
        pending.formUnion(directoryIDs ?? Set(directories.map(\.id)))
        guard task == nil else { return }
        let request = generation
        task = Task { [weak self, catalog] in
            while !Task.isCancelled {
                guard let ids = self?.takePending(for: request) else { return }
                let update = await catalog.refresh(directoryIDs: ids)
                guard let self, self.isRunning, request == self.generation, !Task.isCancelled else { return }
                do {
                    self.pending.formUnion(try self.monitor.update(scans: update.scans))
                } catch {
                    self.monitoringError = error
                }
                self.receive?(update)
                guard self.isRunning, request == self.generation else { return }
                if self.pending.isEmpty {
                    self.task = nil
                    return
                }
            }
        }
    }

    private func takePending(for request: Int) -> Set<UUID>? {
        guard isRunning, request == generation else { return nil }
        let ids = pending
        pending.removeAll()
        return ids
    }

    func stop() {
        generation += 1
        isRunning = false
        isStarting = false
        task?.cancel()
        task = nil
        pending.removeAll()
        monitor.stop()
        receive = nil
    }
}
