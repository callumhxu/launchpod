import Foundation

/// Whether Classical folders use the optional glass appearance.
enum ClassicalFolderGlassPreference {
    static let key = "classicalFolderLiquidGlass"
    /// The value while the user has not chosen one.
    static let defaultValue = true

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard #available(macOS 26.0, *) else { return false }
        return defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
