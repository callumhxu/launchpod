import Foundation

enum ApplicationIcon: String, CaseIterable, Sendable {
    case colorTiles
    case colorGrid
    case darkGrid
    case rocket

    var assetName: String {
        ApplicationIconDockContract.assetName(for: rawValue)!
    }

    var name: LocalizedStringResource {
        switch self {
        case .colorTiles: LocalizedStringResource("Color Tiles")
        case .colorGrid: LocalizedStringResource("Color Grid")
        case .darkGrid: LocalizedStringResource("Dark Grid")
        case .rocket: LocalizedStringResource("Rocket")
        }
    }
}
