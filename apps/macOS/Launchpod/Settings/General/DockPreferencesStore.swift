import AppKit

/// Reads and writes the Dock's persistent apps and restarts the Dock so it loads a changed list.
///
/// `load`, `save`, and `restartDock` wait on cfprefsd or send an Apple Event, so callers run them
/// off the main actor.
protocol DockPersistentAppsStore: Sendable {
    /// The current list, or nil when the Dock's preferences cannot be read.
    nonisolated func load() -> DockPersistentApps?
    /// Writes the list; false when the Dock's preferences cannot be written.
    nonisolated func save(_ apps: DockPersistentApps) -> Bool
    /// Asks the running Dock to quit; the system relaunches it with the saved list. Calls `whenQuit`
    /// on the main actor once that Dock process has terminated, while the returned token is retained.
    /// Returns nil when no Dock is running or the request cannot be sent.
    nonisolated func restartDock(whenQuit: @escaping @MainActor @Sendable () -> Void) -> (any Sendable & AnyObject)?
    /// Calls `onChange` on the main actor whenever the stored list changes, including when the Dock
    /// writes it, until the returned token is released.
    func observeChanges(_ onChange: @escaping @MainActor @Sendable () -> Void) -> AnyObject?
}

/// The `com.apple.dock` preferences domain, accessed through CFPreferences.
///
/// Reading needs the sandbox's read-only shared-preference exception for `com.apple.dock`; writing
/// needs the read-write exception, and quitting the Dock needs an Apple Events exception for it.
/// Without them, `save` returns false and `restartDock` returns nil.
nonisolated struct DockPreferencesStore: DockPersistentAppsStore {
    static let domain = "com.apple.dock"
    private static let dockBundleIdentifier = "com.apple.dock"
    private let preferencesDomain: String

    init(preferencesDomain: String = Self.domain) {
        self.preferencesDomain = preferencesDomain
    }

    func load() -> DockPersistentApps? {
        let domain = preferencesDomain as CFString
        CFPreferencesAppSynchronize(domain)
        guard let value = CFPreferencesCopyAppValue(DockPersistentApps.key as CFString, domain) else { return nil }
        guard let tiles = value as? [Any] else { return nil }
        return DockPersistentApps(tiles: tiles)
    }

    func save(_ apps: DockPersistentApps) -> Bool {
        let domain = preferencesDomain as CFString
        CFPreferencesSetAppValue(DockPersistentApps.key as CFString, apps.tiles as CFArray, domain)
        return CFPreferencesAppSynchronize(domain)
    }

    func restartDock(whenQuit: @escaping @MainActor @Sendable () -> Void) -> (any Sendable & AnyObject)? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleIdentifier)
            .first else { return nil }
        let observer = ProcessTerminationObserver(application: dock, onTerminate: whenQuit)
        guard dock.terminate() else { return nil }
        return observer
    }

    func observeChanges(_ onChange: @escaping @MainActor @Sendable () -> Void) -> AnyObject? {
        UserDefaults(suiteName: preferencesDomain).map {
            DefaultsKeyObserver(defaults: $0, key: DockPersistentApps.key, onChange: onChange)
        }
    }
}

/// Key-value observes one defaults key. Defaults deliver changes written by other processes this way,
/// on an arbitrary thread; `onChange` runs on the main actor.
private nonisolated final class DefaultsKeyObserver: NSObject, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let onChange: @MainActor @Sendable () -> Void

    init(defaults: UserDefaults, key: String, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.defaults = defaults
        self.key = key
        self.onChange = onChange
        super.init()
        defaults.addObserver(self, forKeyPath: key, options: [], context: nil)
    }

    deinit {
        defaults.removeObserver(self, forKeyPath: key)
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?,
        change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        let onChange = onChange
        Task { @MainActor in onChange() }
    }
}

/// Observes one running application until it terminates. Keeps the application alive for as long as
/// the observation is registered, because key-value observation does not retain the observed object.
private nonisolated final class ProcessTerminationObserver: @unchecked Sendable {
    private let application: NSRunningApplication
    private var observation: NSKeyValueObservation?

    init(application: NSRunningApplication, onTerminate: @escaping @MainActor @Sendable () -> Void) {
        self.application = application
        observation = application.observe(\.isTerminated, options: [.initial, .new]) { application, _ in
            guard application.isTerminated else { return }
            Task { @MainActor in onTerminate() }
        }
    }

    deinit {
        observation?.invalidate()
    }
}
