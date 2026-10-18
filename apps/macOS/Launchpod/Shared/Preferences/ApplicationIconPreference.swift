import Foundation
import Observation
import OSLog

nonisolated enum ApplicationIconDefaultsFactory {
    static func make(isIsolated: Bool, fallback: UserDefaults) -> UserDefaults {
        guard !isIsolated else { return fallback }
        guard let defaults = UserDefaults(suiteName: ApplicationIconDockContract.defaultsSuiteName) else {
            preconditionFailure("Could not open the application icon preference domain")
        }
        return defaults
    }
}

@MainActor
@Observable
final class ApplicationIconPreference {
    static let preferenceKey = ApplicationIconDockContract.preferenceKey
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Launchpod",
        category: "ApplicationIcon"
    )

    private(set) var selection: ApplicationIcon

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let applier: any ApplicationIconApplying

    init(
        defaults: UserDefaults = .standard,
        applier: any ApplicationIconApplying
    ) {
        self.defaults = defaults
        self.applier = applier
        selection = defaults.string(forKey: Self.preferenceKey)
            .flatMap(ApplicationIcon.init(rawValue:)) ?? .colorTiles
        if apply(selection) {
            applier.notifyDockTile()
        }
    }

    func select(_ icon: ApplicationIcon) {
        guard apply(icon) else { return }
        if selection != icon {
            selection = icon
            defaults.set(icon.rawValue, forKey: Self.preferenceKey)
        }
        applier.notifyDockTile()
    }

    private func apply(_ icon: ApplicationIcon) -> Bool {
        do {
            try applier.apply(icon)
            return true
        } catch {
            Self.logger.error("Could not apply application icon: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
