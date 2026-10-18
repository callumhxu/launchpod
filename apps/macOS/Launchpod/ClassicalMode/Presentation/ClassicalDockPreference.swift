import Foundation

/// Whether the full-screen Classical launcher covers the Dock instead of leaving it on top.
/// Off by default: the Dock stays above the launcher.
enum ClassicalDockPreference {
    static let key = "classicalHidesDock"

    static func hidesDock(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    /// Covering the Dock also covers the menu bar and its status items, which sit above the Dock.
    static func windowLevel(hidesDock: Bool) -> Int {
        hidesDock ? ClassicalPresentationParameters.dockCoveringWindowLevel : ClassicalPresentationParameters.windowLevel
    }
}
