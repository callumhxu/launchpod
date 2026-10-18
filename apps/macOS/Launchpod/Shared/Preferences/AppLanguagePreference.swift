import Foundation
import Observation

@MainActor
@Observable
final class AppLanguagePreference {
    static let preferenceKey = "appLanguage"

    var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            defaults.set(selection.rawValue, forKey: Self.preferenceKey)
        }
    }

    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]
    private var systemLanguages: [String]

    init(
        defaults: UserDefaults = .standard,
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
        systemLanguages = preferredLanguages()
        selection = defaults.string(forKey: Self.preferenceKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    var resolvedLanguage: AppLanguage {
        guard selection == .system else { return selection }

        // An explicit final preference makes English the fallback for unsupported languages.
        let localizations = Bundle.preferredLocalizations(
            from: AppLanguage.supportedLocalizations,
            forPreferences: systemLanguages + [AppLanguage.english.rawValue]
        )
        return localizations.first.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    var locale: Locale {
        Locale(identifier: resolvedLanguage.rawValue)
    }

    func refreshSystemLanguages() {
        systemLanguages = preferredLanguages()
    }
}
