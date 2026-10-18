import Foundation
import Testing
@testable import Launchpod

struct AdvancedSettingsViewTests {
    @Test(arguments: [
        ("en", "Startup", "Launch at Login", "Open Launchpod automatically when you log in."),
        ("zh-Hans", CatalogTestSupport.text("Startup", locale: "zh-Hans"), CatalogTestSupport.text("Launch at Login", locale: "zh-Hans"), CatalogTestSupport.text("Open Launchpod automatically when you log in.", locale: "zh-Hans")),
        ("zh-Hant", CatalogTestSupport.text("Startup", locale: "zh-Hant"), CatalogTestSupport.text("Launch at Login", locale: "zh-Hant"), CatalogTestSupport.text("Open Launchpod automatically when you log in.", locale: "zh-Hant")),
        ("fr", CatalogTestSupport.text("Startup", locale: "fr"), CatalogTestSupport.text("Launch at Login", locale: "fr"), CatalogTestSupport.text("Open Launchpod automatically when you log in.", locale: "fr")),
        ("de", CatalogTestSupport.text("Startup", locale: "de"), CatalogTestSupport.text("Launch at Login", locale: "de"), CatalogTestSupport.text("Open Launchpod automatically when you log in.", locale: "de")),
        ("ja", CatalogTestSupport.text("Startup", locale: "ja"), CatalogTestSupport.text("Launch at Login", locale: "ja"), CatalogTestSupport.text("Open Launchpod automatically when you log in.", locale: "ja")),
        ("ko", CatalogTestSupport.text("Startup", locale: "ko"), CatalogTestSupport.text("Launch at Login", locale: "ko"), CatalogTestSupport.text("Open Launchpod automatically when you log in.", locale: "ko")),
        ("es", CatalogTestSupport.text("Startup", locale: "es"), CatalogTestSupport.text("Launch at Login", locale: "es"), CatalogTestSupport.text("Open Launchpod automatically when you log in.", locale: "es"))
    ])
    func launchAtLoginTextResolvesInEverySupportedLanguage(
        identifier: String, startup: String, label: String, subtitle: String
    ) {
        let locale = Locale(identifier: identifier)

        #expect(localized("Startup", locale: locale) == startup)
        #expect(localized("Launch at Login", locale: locale) == label)
        #expect(localized("Open Launchpod automatically when you log in.", locale: locale) == subtitle)
    }

    private func localized(_ value: String.LocalizationValue, locale: Locale) -> String {
        String(localized: LocalizedStringResource(value, locale: locale))
    }
}
