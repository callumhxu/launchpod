import Foundation

nonisolated enum ApplicationIconDockContract {
    static let defaultsSuiteName = "app.joyx.launchpod.dock-icon"
    static let preferenceKey = "applicationIcon"
    static let changedNotification = Notification.Name("app.joyx.launchpod.applicationIconChanged")
    static let defaultIdentifier = "colorTiles"

    static func assetName(for identifier: String) -> String? {
        switch identifier {
        case "colorTiles": "ApplicationIconColorTiles"
        case "colorGrid": "ApplicationIconColorGrid"
        case "darkGrid": "ApplicationIconDarkGrid"
        case "rocket": "ApplicationIconRocket"
        default: nil
        }
    }
}
