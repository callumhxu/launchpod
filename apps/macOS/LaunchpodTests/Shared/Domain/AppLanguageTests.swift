import Foundation
import Testing
@testable import Launchpod

struct AppLanguageTests {
    @Test
    func pickerChoicesHaveStableLanguageIndependentIdentifiers() {
        #expect(Set(AppLanguage.allCases.map(\.rawValue)) == [
            "system", "en", "zh-Hans", "zh-Hant", "fr", "de", "ja", "ko", "es"
        ])
    }

    @Test(arguments: [
        (AppLanguage.system, "system"),
        (AppLanguage.english, "en"),
        (AppLanguage.simplifiedChinese, "zh-Hans"),
        (AppLanguage.traditionalChinese, "zh-Hant"),
        (AppLanguage.french, "fr"),
        (AppLanguage.german, "de"),
        (AppLanguage.japanese, "ja"),
        (AppLanguage.korean, "ko"),
        (AppLanguage.spanish, "es")
    ])
    func languageChoicesRoundTripWithoutLocalizedNames(language: AppLanguage, identifier: String) throws {
        let data = Data("\"\(identifier)\"".utf8)

        #expect(language.rawValue == identifier)
        #expect(try JSONEncoder().encode(language) == data)
        #expect(try JSONDecoder().decode(AppLanguage.self, from: data) == language)
    }
}
