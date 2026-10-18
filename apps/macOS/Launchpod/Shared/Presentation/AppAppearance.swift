import AppKit
import Foundation

enum AppAppearance: String, CaseIterable, Sendable {
    case automatic
    case light
    case dark

    static let preferenceKey = "appAppearance"

    var name: LocalizedStringResource {
        switch self {
        case .automatic:
            "Auto"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .automatic:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}
