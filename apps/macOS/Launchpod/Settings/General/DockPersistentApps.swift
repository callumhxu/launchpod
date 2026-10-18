import Foundation

/// The Dock's `persistent-apps` preference: the tiles the user keeps in the app section of the Dock,
/// in Dock order.
///
/// The key and its tile format are undocumented Dock preferences. Entries are kept exactly as read so
/// that writing the list back preserves every existing tile. Tiles are immutable property-list values,
/// so a list can move between threads.
nonisolated struct DockPersistentApps: @unchecked Sendable {
    static let key = "persistent-apps"

    let tiles: [Any]

    /// Whether any tile names the app by its bundle identifier or points at the app's bundle location.
    func contains(bundleIdentifier: String?, bundleURL: URL) -> Bool {
        let target = Self.normalized(bundleURL)
        return tiles.contains { tile in
            guard let tileData = (tile as? [String: Any])?["tile-data"] as? [String: Any] else { return false }
            if let bundleIdentifier, tileData["bundle-identifier"] as? String == bundleIdentifier {
                return true
            }
            guard let fileData = tileData["file-data"] as? [String: Any],
                  let string = fileData["_CFURLString"] as? String,
                  let url = URL(string: string), url.isFileURL else { return false }
            return Self.normalized(url) == target
        }
    }

    /// The list with a tile for the app bundle appended after the existing tiles.
    ///
    /// The tile carries only the bundle's file URL; the Dock fills in its label, bookmark, and
    /// bundle identifier when it loads the tile.
    func appendingTile(for bundleURL: URL) -> DockPersistentApps {
        let url = URL(fileURLWithPath: bundleURL.path, isDirectory: true)
        let tile: [String: Any] = [
            "tile-data": [
                "file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15]
            ],
            "tile-type": "file-tile"
        ]
        return DockPersistentApps(tiles: tiles + [tile])
    }

    private static func normalized(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
