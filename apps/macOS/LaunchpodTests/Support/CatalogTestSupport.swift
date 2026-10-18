import Foundation

/// Reads reviewed source translations independently of the compiled application bundle.
enum CatalogTestSupport {
    static let locales = ["en", "zh-Hans", "zh-Hant", "fr", "de", "ja", "ko", "es"]

    static func text(_ key: String, locale: String) -> String {
        guard let entry = catalog.strings[key] else {
            preconditionFailure("Missing catalog source: \(key)")
        }
        if locale == "en" { return key }
        guard let unit = entry.localizations?[locale]?.stringUnit, unit.state == "translated" else {
            preconditionFailure("Missing reviewed translation: \(locale): \(key)")
        }
        return unit.value
    }

    static func format(_ key: String, locale: String, argument: String) -> String {
        String(format: text(key, locale: locale), locale: Locale(identifier: locale), argument)
    }

    private static let catalog: Catalog = {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Launchpod/Resources/Localizable.xcstrings")
        do {
            return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        } catch {
            preconditionFailure("Cannot load source catalog: \(error)")
        }
    }()

    private struct Catalog: Decodable {
        let strings: [String: Entry]
    }

    private struct Entry: Decodable {
        let localizations: [String: Translation]?
    }

    private struct Translation: Decodable {
        let stringUnit: Unit?
    }

    private struct Unit: Decodable {
        let state: String
        let value: String
    }
}
