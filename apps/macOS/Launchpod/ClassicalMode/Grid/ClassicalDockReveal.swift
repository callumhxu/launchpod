import Foundation

/// Keeps an auto-hiding Dock revealed while the Classical launcher is shown, and
/// hides the Dock while a folder is open.
///
/// Auto-hide is switched for the presentation and the user's setting restored afterwards, with a
/// marker holding that setting so the next launch can restore it after a crash or forced quit. While a folder is open the Dock only auto-hides, so the pointer at
/// the screen edge can still bring it back.
@MainActor
final class ClassicalDockReveal {
    struct Operations {
        let autoHideEnabled: @MainActor () -> Bool
        let setAutoHideEnabled: @MainActor (Bool) -> Void
    }

    /// Holds the user's auto-hide setting while Launchpod has changed it.
    static let restorePendingKey = "classicalDockAutoHideRestorePending"

    /// The Dock as it was before being revealed, for layout while the reveal is in effect.
    private(set) var revealedMetrics: ClassicalDockMetrics?
    /// Whether an open folder currently hides the Dock.
    private(set) var hidesForFolder = false
    /// The user's auto-hide setting while Launchpod has changed it; nil otherwise.
    private var userAutoHide: Bool?
    private let defaults: UserDefaults
    private let operations: Operations?
    private let metrics: @MainActor () -> ClassicalDockMetrics?

    init(defaults: UserDefaults = .standard, operations: Operations? = nativeOperations(),
         metrics: @escaping @MainActor () -> ClassicalDockMetrics? = { ClassicalDockMetrics.current() }) {
        self.defaults = defaults
        self.operations = operations
        self.metrics = metrics
    }

    isolated deinit {
        restore()
    }

    /// Reveals an auto-hiding Dock; a Dock that does not auto-hide is left untouched.
    func reveal() {
        guard revealedMetrics == nil, let operations, operations.autoHideEnabled(),
              let current = metrics(), current.autoHides else { return }
        remember(true)
        revealedMetrics = current
        operations.setAutoHideEnabled(false)
    }

    /// Lets the Dock auto-hide while a folder is open, so it slides away.
    func hideForFolder() {
        guard !hidesForFolder, let operations else { return }
        hidesForFolder = true
        guard !operations.autoHideEnabled() else { return }
        remember(false)
        operations.setAutoHideEnabled(true)
    }

    /// The folder closed: the Dock returns to the state the presentation keeps it in.
    func endFolderHide() {
        guard hidesForFolder else { return }
        hidesForFolder = false
        guard let userAutoHide else { return }
        if revealedMetrics != nil {
            apply(false)
        } else {
            apply(userAutoHide)
            forget()
        }
    }

    /// Returns the Dock to the user's auto-hide setting unless someone already set it that way.
    func restore() {
        revealedMetrics = nil
        hidesForFolder = false
        guard let userAutoHide else { return }
        apply(userAutoHide)
        forget()
    }

    /// Restores the auto-hide setting left changed by a presentation that ended without cleanup.
    func recoverAfterUnexpectedExit() {
        guard let setting = defaults.object(forKey: Self.restorePendingKey) as? Bool else { return }
        apply(setting)
        defaults.removeObject(forKey: Self.restorePendingKey)
    }

    private func remember(_ setting: Bool) {
        guard userAutoHide == nil else { return }
        userAutoHide = setting
        defaults.set(setting, forKey: Self.restorePendingKey)
    }

    private func forget() {
        userAutoHide = nil
        defaults.removeObject(forKey: Self.restorePendingKey)
    }

    private func apply(_ setting: Bool) {
        if let operations, operations.autoHideEnabled() != setting {
            operations.setAutoHideEnabled(setting)
        }
    }

    /// Test hosts and explicitly isolated app launches never touch the user's Dock.
    nonisolated static func nativeOperations() -> Operations? {
        guard !DockMutationPolicy.isIsolated,
              let functions = CoreDockFunctions.shared else { return nil }
        return Operations(autoHideEnabled: { functions.autoHideEnabled() },
                          setAutoHideEnabled: { functions.setAutoHideEnabled($0) })
    }
}
