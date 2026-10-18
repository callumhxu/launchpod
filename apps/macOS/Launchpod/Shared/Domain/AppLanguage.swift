import Foundation

enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case french = "fr"
    case german = "de"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"

    static let supportedLocalizations = allCases.filter { $0 != .system }.map(\.rawValue)

    var name: LocalizedStringResource {
        switch self {
        case .system:
            "Follow System"
        case .english:
            "English"
        case .simplifiedChinese:
            "Simplified Chinese"
        case .traditionalChinese:
            "Traditional Chinese"
        case .french:
            "French"
        case .german:
            "German"
        case .japanese:
            "Japanese"
        case .korean:
            "Korean"
        case .spanish:
            "Spanish"
        }
    }
}
