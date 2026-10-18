import Foundation
import AppKit
import Testing
@testable import Launchpod

@MainActor
struct AppAppearanceTests {
    @Test
    func appearanceChoicesUseStableIdentifiers() {
        #expect(Set(AppAppearance.allCases.map(\.rawValue)) == ["automatic", "light", "dark"])
    }

    @Test(arguments: [
        (AppAppearance.automatic, "automatic", nil as NSAppearance.Name?),
        (AppAppearance.light, "light", NSAppearance.Name.aqua),
        (AppAppearance.dark, "dark", NSAppearance.Name.darkAqua)
    ])
    func automaticInheritsTheSystemAndExplicitChoicesRequestTheirScheme(
        appearance: AppAppearance, identifier: String, appearanceName: NSAppearance.Name?
    ) {
        #expect(appearance.rawValue == identifier)
        #expect(AppAppearance(rawValue: identifier) == appearance)
        #expect(appearance.nsAppearance?.name == appearanceName)
    }

    @Test(arguments: [
        ("en", "Auto", "Light", "Dark"),
        ("zh-Hans", CatalogTestSupport.text("Auto", locale: "zh-Hans"), CatalogTestSupport.text("Light", locale: "zh-Hans"), CatalogTestSupport.text("Dark", locale: "zh-Hans")),
        ("zh-Hant", CatalogTestSupport.text("Auto", locale: "zh-Hant"), CatalogTestSupport.text("Light", locale: "zh-Hant"), CatalogTestSupport.text("Dark", locale: "zh-Hant")),
        ("fr", CatalogTestSupport.text("Auto", locale: "fr"), CatalogTestSupport.text("Light", locale: "fr"), CatalogTestSupport.text("Dark", locale: "fr")),
        ("de", CatalogTestSupport.text("Auto", locale: "de"), CatalogTestSupport.text("Light", locale: "de"), CatalogTestSupport.text("Dark", locale: "de")),
        ("ja", CatalogTestSupport.text("Auto", locale: "ja"), CatalogTestSupport.text("Light", locale: "ja"), CatalogTestSupport.text("Dark", locale: "ja")),
        ("ko", CatalogTestSupport.text("Auto", locale: "ko"), CatalogTestSupport.text("Light", locale: "ko"), CatalogTestSupport.text("Dark", locale: "ko")),
        ("es", CatalogTestSupport.text("Auto", locale: "es"), CatalogTestSupport.text("Light", locale: "es"), CatalogTestSupport.text("Dark", locale: "es"))
    ])
    func compiledAppearanceNamesResolveInEverySupportedLanguage(
        identifier: String, automatic: String, light: String, dark: String
    ) {
        for (appearance, text) in [
            (AppAppearance.automatic, automatic), (.light, light), (.dark, dark)
        ] {
            var resource = appearance.name
            resource.locale = Locale(identifier: identifier)
            #expect(String(localized: resource) == text)
        }
    }
}
