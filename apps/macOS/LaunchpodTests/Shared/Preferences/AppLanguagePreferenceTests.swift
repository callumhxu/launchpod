import Foundation
import Testing
@testable import Launchpod

@MainActor
struct AppLanguagePreferenceTests {
    @Test(arguments: [
        (["zh-CN"], AppLanguage.simplifiedChinese),
        (["zh-SG"], AppLanguage.simplifiedChinese),
        (["zh-TW"], AppLanguage.traditionalChinese),
        (["zh-HK"], AppLanguage.traditionalChinese),
        (["zh-Hant"], AppLanguage.traditionalChinese),
        (["zh-Hans"], AppLanguage.simplifiedChinese),
        (["zh-Hans-TW"], AppLanguage.simplifiedChinese),
        (["zh-Hant-CN"], AppLanguage.traditionalChinese),
        (["fr-CA"], AppLanguage.french),
        (["de-DE"], AppLanguage.german),
        (["de-AT"], AppLanguage.german),
        (["ja-JP"], AppLanguage.japanese),
        (["ko-KR"], AppLanguage.korean),
        (["es-ES"], AppLanguage.spanish),
        (["es-MX"], AppLanguage.spanish),
        (["en-GB"], AppLanguage.english),
        (["it-IT", "fr-CA", "zh-TW"], AppLanguage.french),
        (["de-DE", "fr-CA", "zh-TW"], AppLanguage.german),
        (["ja-JP", "de-DE"], AppLanguage.japanese),
        (["ar-SA", "ko-KR", "es-MX"], AppLanguage.korean),
        (["es-MX", "ko-KR"], AppLanguage.spanish),
        (["zh-HK", "fr-FR"], AppLanguage.traditionalChinese),
        (["fr-FR", "zh-HK"], AppLanguage.french),
        (["en-US", "fr-FR"], AppLanguage.english),
        (["it-IT", "ar-SA"], AppLanguage.english),
        ([], AppLanguage.english)
    ])
    func freshPreferenceFollowsSystemPriorityAndMatchesRegions(
        preferredLanguages: [String], expected: AppLanguage
    ) throws {
        try withDefaults { defaults in
            let preference = AppLanguagePreference(defaults: defaults, preferredLanguages: { preferredLanguages })

            #expect(preference.selection == .system)
            #expect(preference.resolvedLanguage == expected)
            #expect(preference.locale.identifier == expected.rawValue)
        }
    }

    @Test(arguments: [
        AppLanguage.english, .simplifiedChinese, .traditionalChinese, .french,
        .german, .japanese, .korean, .spanish
    ])
    func explicitChoiceOverridesSystemAndSurvivesRecreation(language: AppLanguage) throws {
        try withDefaults { defaults in
            let preference = AppLanguagePreference(defaults: defaults, preferredLanguages: { ["ar-SA"] })
            preference.selection = language

            #expect(preference.resolvedLanguage == language)
            #expect(preference.locale.identifier == language.rawValue)
            #expect(defaults.string(forKey: AppLanguagePreference.preferenceKey) == language.rawValue)

            let restored = AppLanguagePreference(defaults: defaults, preferredLanguages: { ["fr-CA"] })
            #expect(restored.selection == language)
            #expect(restored.resolvedLanguage == language)
            #expect(restored.locale.identifier == language.rawValue)
        }
    }

    @Test
    func returningToFollowSystemUsesLatestLanguagesAndPersistsTheChoice() throws {
        try withDefaults { defaults in
            var preferredLanguages = ["fr-CA"]
            let preference = AppLanguagePreference(defaults: defaults, preferredLanguages: { preferredLanguages })
            #expect(preference.resolvedLanguage == .french)

            preference.selection = .english
            preferredLanguages = ["zh-HK"]
            preference.refreshSystemLanguages()
            #expect(preference.selection == .english)
            #expect(preference.resolvedLanguage == .english)

            preference.selection = .system
            #expect(preference.resolvedLanguage == .traditionalChinese)
            #expect(preference.locale.identifier == "zh-Hant")

            let restored = AppLanguagePreference(defaults: defaults, preferredLanguages: { ["fr-FR"] })
            #expect(restored.selection == .system)
            #expect(restored.resolvedLanguage == .french)
        }
    }

    @Test
    func followingSystemRespondsToPreferenceRefreshWithoutAnAppSelectionChange() throws {
        try withDefaults { defaults in
            var preferredLanguages = ["fr-CA"]
            let preference = AppLanguagePreference(defaults: defaults, preferredLanguages: { preferredLanguages })

            for (languages, expected) in [
                (["zh-TW"], AppLanguage.traditionalChinese),
                (["zh-CN"], AppLanguage.simplifiedChinese),
                (["de-DE", "en-US"], AppLanguage.german),
                (["ja-JP"], AppLanguage.japanese),
                (["ko-KR"], AppLanguage.korean),
                (["es-MX"], AppLanguage.spanish),
                (["it-IT", "en-US"], AppLanguage.english)
            ] {
                preferredLanguages = languages
                preference.refreshSystemLanguages()

                #expect(preference.selection == .system)
                #expect(preference.resolvedLanguage == expected)
                #expect(preference.locale.identifier == expected.rawValue)
            }
        }
    }

    @Test(arguments: ["", "it", "zh", "French", "\u{8ddf}\u{968f}\u{7cfb}\u{7edf}", "fr-CA"])
    func unsupportedPersistedIdentifiersRecoverToFollowSystem(invalidValue: String) throws {
        try withDefaults { defaults in
            defaults.set(invalidValue, forKey: AppLanguagePreference.preferenceKey)
            let preference = AppLanguagePreference(defaults: defaults, preferredLanguages: { ["zh-TW"] })

            #expect(preference.selection == .system)
            #expect(preference.resolvedLanguage == .traditionalChinese)
            preference.selection = .french

            let restored = AppLanguagePreference(defaults: defaults, preferredLanguages: { ["en-US"] })
            #expect(restored.selection == .french)
            #expect(restored.resolvedLanguage == .french)
        }
    }

    @Test
    func malformedPersistedTypesRecoverWithoutCrashing() throws {
        try withDefaults { defaults in
            for invalidValue: Any in [42, true, ["fr"], ["language": "fr"]] {
                defaults.set(invalidValue, forKey: AppLanguagePreference.preferenceKey)
                let preference = AppLanguagePreference(defaults: defaults, preferredLanguages: { ["fr-CA"] })

                #expect(preference.selection == .system)
                #expect(preference.resolvedLanguage == .french)
            }
        }
    }

    @Test
    func changingAppLanguageLeavesAppleLanguagesAndUnrelatedPreferencesUntouched() throws {
        let globalLanguages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? NSObject
        let standardLanguages = UserDefaults.standard.object(forKey: "AppleLanguages") as? NSObject

        try withDefaults { defaults in
            defaults.set(["ja-JP", "fr-CA"], forKey: "AppleLanguages")
            defaults.set("keep", forKey: "unrelatedPreference")
            let preference = AppLanguagePreference(defaults: defaults, preferredLanguages: { ["fr-CA"] })

            for language in AppLanguage.allCases.reversed() {
                preference.selection = language
                preference.refreshSystemLanguages()

                #expect(defaults.stringArray(forKey: "AppleLanguages") == ["ja-JP", "fr-CA"])
                #expect(defaults.string(forKey: "unrelatedPreference") == "keep")
                #expect(UserDefaults.standard.object(forKey: "AppleLanguages") as? NSObject == standardLanguages)
                #expect(
                    UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? NSObject
                        == globalLanguages
                )
            }
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        try body(defaults)
    }
}
