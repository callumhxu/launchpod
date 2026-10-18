import Foundation

/// A Dock list held in memory, used instead of the user's Dock whenever the app runs under tests.
///
/// It starts empty, so the app is not in the Dock. `save` replaces the list and `restartDock` reports
/// the quit right away; nothing outside the process is read, observed, written, or restarted.
nonisolated final class InMemoryDockPersistentAppsStore: DockPersistentAppsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var apps = DockPersistentApps(tiles: [])

    func load() -> DockPersistentApps? {
        lock.withLock { apps }
    }

    func save(_ apps: DockPersistentApps) -> Bool {
        lock.withLock { self.apps = apps }
        return true
    }

    func restartDock(whenQuit: @escaping @MainActor @Sendable () -> Void) -> (any Sendable & AnyObject)? {
        Task { @MainActor in whenQuit() }
        return self
    }

    func observeChanges(_ onChange: @escaping @MainActor @Sendable () -> Void) -> AnyObject? {
        nil
    }

    /// The store for this process: in memory inside a test host or when launched with
    /// `-inMemoryDockStore YES`; otherwise the user's Dock.
    static func forCurrentProcess() -> any DockPersistentAppsStore {
        DockMutationPolicy.isIsolated ? InMemoryDockPersistentAppsStore() : DockPreferencesStore()
    }
}
