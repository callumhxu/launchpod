import Foundation

/// Owns shared application data and services independently of presentation sessions.
@MainActor
final class AppServices {
    let icons: AppIconRepository
    let launcher: WorkspaceApplicationLauncher
    private(set) var data: AppData?
    private(set) var availableRecords: [AppRecord] = []
    /// Catalog records eligible for launcher presentation; saved records retain all identities.
    var presentationRecords: [AppRecord] {
        LaunchpodAppVisibility.presentationRecords(from: data?.records ?? [])
    }
    private(set) var isRunning = false
    /// Whether this run has applied an observation from the current discovery scan.
    private(set) var hasCurrentScan = false
    /// Publishes installed catalog changes after affected icon requests have been invalidated.
    var onApplicationsChanged: (@MainActor (Set<AppIdentity>) -> Void)?

    private let store: AppDataStore
    private var directories: [ApplicationScan.Directory]
    private let scanner: any ApplicationScanning
    private let onError: @MainActor (any Error) -> Void
    private var discovery: ApplicationDiscovery?
    private var isStarting = false
    private var isStopping = false
    private var generation = 0
    private var updateTask: Task<Void, Never>?
    private var savedData: AppData?
    private var saveError: (any Error)?
    private var scannedDirectoryURLs = Set<URL>()

    init(
        store: AppDataStore,
        icons: AppIconRepository,
        launcher: WorkspaceApplicationLauncher? = nil,
        directories: [ApplicationScan.Directory] = ApplicationScanner.defaultDirectories(),
        scanner: any ApplicationScanning = ApplicationScanner(),
        onError: @escaping @MainActor (any Error) -> Void
    ) {
        self.store = store
        self.icons = icons
        self.launcher = launcher ?? WorkspaceApplicationLauncher()
        self.directories = directories
        self.scanner = scanner
        self.onError = onError
    }

    isolated deinit {
        discovery?.stop()
    }

    /// Loads before scanning. An unreadable store is never replaced with an empty catalog.
    func start() async throws {
        guard !isRunning, !isStarting, !isStopping else { return }
        isStarting = true
        hasCurrentScan = false
        let request = generation
        defer { if request == generation { isStarting = false } }

        if data == nil {
            let restored = try await store.load()
            try Task.checkCancellation()
            guard request == generation else { throw CancellationError() }
            data = try restored ?? AppData()
            savedData = restored
        }
        scannedDirectoryURLs.formUnion(data?.scannedDirectoryURLs ?? [])
        scannedDirectoryURLs.formUnion((data?.records ?? []).map(\.source.directoryURL))
        let discovery = ApplicationDiscovery(
            directories: directories, scanner: scanner, restoredData: data
        )
        self.discovery = discovery
        do {
            try await discovery.start { [weak self] update in
                guard let self, request == self.generation else { return }
                self.receive(update)
            }
            try Task.checkCancellation()
            guard request == generation else { throw CancellationError() }
            isRunning = true
            if let error = discovery.monitoringError { onError(error) }
        } catch {
            discovery.stop()
            if request == generation { self.discovery = nil }
            throw error
        }
    }

    /// Stops new observations and waits for accepted updates to reach storage.
    func stop() async throws {
        guard !isStopping else { return }
        isStopping = true
        defer { isStopping = false }
        generation += 1
        isStarting = false
        isRunning = false
        hasCurrentScan = false
        discovery?.stop()
        discovery = nil
        await updateTask?.value
        updateTask = nil
        if let saveError { throw saveError }
        await icons.invalidateAll()
        availableRecords = []
    }

    /// Rebuilds discovery for the selected app directories while retaining saved app identities.
    func updateDirectories(_ directories: [ApplicationScan.Directory]) async throws {
        guard self.directories.map(\.source) != directories.map(\.source) else { return }
        let shouldRestart = isRunning || isStarting
        if shouldRestart { try await stop() }
        self.directories = directories
        if shouldRestart { try await start() }
    }

    private func receive(_ update: ApplicationCatalog.Update) {
        let previous = updateTask
        let store = self.store
        let icons = self.icons
        updateTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let existing = Dictionary(uniqueKeysWithValues: (self.data?.records ?? []).map { ($0.id, $0) })
            let insertedIDs = Set(update.inserted.map(\.id))
            let updatedIDs = Set(update.updated.map(\.id))
            let availableIDs = Set(update.availableRecords.map(\.id))
            let completeDirectoryURLs = Set(update.scans.compactMap { scan in
                scan.isComplete && scan.source.isOnline == true ? scan.source.directoryURL : nil
            })
            let eligibleDirectoryURLs = self.scannedDirectoryURLs.intersection(completeDirectoryURLs)
            let knownBundleIDs = Set(existing.values.compactMap {
                $0.metadata.knownBundleIdentifier?.lowercased()
            })
            let records = update.records.map { record -> AppRecord in
                var record = record
                if let status = existing[record.id]?.isRecentlyAdded {
                    record.isRecentlyAdded = status
                }
                if availableIDs.contains(record.id), eligibleDirectoryURLs.contains(record.source.directoryURL),
                   record.metadata.isStoreApp == true {
                    if insertedIDs.contains(record.id),
                       let bundleID = record.metadata.knownBundleIdentifier?.lowercased(),
                       !knownBundleIDs.contains(bundleID) {
                        record.isRecentlyAdded = true
                    } else if updatedIDs.contains(record.id), let previous = existing[record.id] {
                        let old = previous.metadata
                        let current = record.metadata
                        let versionChanged = old.version != nil && current.version != nil
                            && old.version != current.version
                        let buildChanged = old.buildVersion != nil && current.buildVersion != nil
                            && old.buildVersion != current.buildVersion
                        if old.isStoreApp == false || versionChanged || buildChanged {
                            record.isRecentlyAdded = true
                        }
                    }
                }
                return record
            }
            let scannedDirectoryURLs = self.scannedDirectoryURLs.union(completeDirectoryURLs)
            let snapshot: AppData
            do {
                snapshot = try AppData(records: records, customizations: self.data?.customizations ?? [],
                                       scannedDirectoryURLs: scannedDirectoryURLs)
            } catch {
                self.onError(error)
                return
            }
            self.scannedDirectoryURLs = scannedDirectoryURLs
            // File events can change an icon without changing the bundle's metadata.
            for id in update.affectedAppIDs {
                await icons.invalidate(id)
            }
            // Mode layouts saved while handling the published change refer to these identities, so
            // they reach storage first. A failed save is reported and the change is still published.
            if snapshot == self.savedData {
                self.saveError = nil
            } else {
                do {
                    try await store.save(snapshot)
                    self.savedData = snapshot
                    self.saveError = nil
                } catch {
                    self.saveError = error
                    if !self.isStopping { self.onError(error) }
                }
            }
            self.data = snapshot
            if !self.isStopping { self.hasCurrentScan = true }
            let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            self.availableRecords = update.availableRecords.compactMap { byID[$0.id] }
            if !self.isStopping { self.onApplicationsChanged?(update.affectedAppIDs) }
        }
    }

    /// Clears recently added status for the opened app and copies with its known bundle ID.
    func markOpened(_ id: AppIdentity) {
        let previous = updateTask
        let store = self.store
        updateTask = Task { [weak self] in
            await previous?.value
            guard let self, let data = self.data,
                  let opened = data.records.first(where: { $0.id == id }) else { return }
            let bundleID = opened.metadata.knownBundleIdentifier
            let affected = Set(data.records.compactMap { record -> AppIdentity? in
                guard record.isRecentlyAdded == true else { return nil }
                if record.id == id { return id }
                guard let bundleID, let otherID = record.metadata.knownBundleIdentifier,
                      bundleID.caseInsensitiveCompare(otherID) == .orderedSame else { return nil }
                return record.id
            })
            guard !affected.isEmpty else { return }
            let records = data.records.map { record -> AppRecord in
                var record = record
                if affected.contains(record.id) { record.isRecentlyAdded = false }
                return record
            }
            do {
                let snapshot = try AppData(records: records, customizations: data.customizations,
                                           scannedDirectoryURLs: data.scannedDirectoryURLs)
                self.data = snapshot
                self.availableRecords = self.availableRecords.map { record in
                    var record = record
                    if affected.contains(record.id) { record.isRecentlyAdded = false }
                    return record
                }
                if !self.isStopping { self.onApplicationsChanged?(affected) }
                try await store.save(snapshot)
                self.savedData = snapshot
                self.saveError = nil
            } catch {
                self.saveError = error
                if !self.isStopping { self.onError(error) }
            }
        }
    }
}
