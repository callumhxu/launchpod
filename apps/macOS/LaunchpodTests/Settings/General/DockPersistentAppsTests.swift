import Foundation
import XCTest
@testable import Launchpod

/// The Dock's persistent-apps list: finding this app by bundle identifier or bundle location, and
/// appending its tile without disturbing the tiles already there.
final class DockPersistentAppsTests: XCTestCase {
    private let bundleURL = URL(fileURLWithPath: "/Applications/Launchpod.app", isDirectory: true)

    private func bundleTile(_ identifier: String) -> [String: Any] {
        ["tile-data": ["bundle-identifier": identifier], "tile-type": "file-tile"]
    }

    private func fileTile(_ urlString: String) -> [String: Any] {
        ["tile-data": ["file-data": ["_CFURLString": urlString, "_CFURLStringType": 15]], "tile-type": "file-tile"]
    }

    func testMembershipByBundleIdentifier() {
        let apps = DockPersistentApps(tiles: [bundleTile("com.apple.Safari"), bundleTile("app.joyx.launchpod")])
        XCTAssertTrue(apps.contains(bundleIdentifier: "app.joyx.launchpod", bundleURL: bundleURL))
        XCTAssertFalse(apps.contains(bundleIdentifier: "app.joyx.other",
                                     bundleURL: URL(fileURLWithPath: "/Applications/Other.app", isDirectory: true)))
    }

    func testMembershipByBundleLocation() {
        let apps = DockPersistentApps(tiles: [fileTile("file:///Applications/Launchpod.app/")])
        XCTAssertTrue(apps.contains(bundleIdentifier: nil, bundleURL: bundleURL))
        XCTAssertTrue(apps.contains(bundleIdentifier: "app.joyx.launchpod",
                                    bundleURL: URL(fileURLWithPath: "/Applications/Launchpod.app")),
                      "A trailing slash does not matter")
        XCTAssertFalse(apps.contains(bundleIdentifier: nil,
                                     bundleURL: URL(fileURLWithPath: "/Applications/Utilities/Launchpod.app")))
    }

    func testMembershipThroughASymbolicLinkToTheBundlesFolder() throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let bundle = try fixture.application("Launchpod.app", in: try fixture.directory("Actual"))
        let link = fixture.root.appendingPathComponent("Linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundle.deletingLastPathComponent())
        let throughLink = link.appendingPathComponent("Launchpod.app", isDirectory: true)
        let apps = DockPersistentApps(tiles: [fileTile(throughLink.absoluteString)])
        XCTAssertTrue(apps.contains(bundleIdentifier: nil, bundleURL: bundle),
                      "A tile reaching the bundle through a symbolic link names the same bundle")
    }

    func testTilesWithoutAnIdentifierOrLocalLocationDoNotMatch() {
        let apps = DockPersistentApps(tiles: [
            "not a tile", ["tile-type": "spacer-tile"], fileTile("https://example.com/Launchpod.app/"),
            ["tile-data": ["file-data": ["_CFURLString": 42]]]
        ])
        XCTAssertFalse(apps.contains(bundleIdentifier: "app.joyx.launchpod", bundleURL: bundleURL))
    }

    func testAppendingATileKeepsEveryExistingEntryInOrder() throws {
        let existing: [Any] = [bundleTile("com.apple.Safari"), ["tile-type": "spacer-tile"], fileTile("file:///Applications/Notes.app/")]
        let apps = DockPersistentApps(tiles: existing)
        XCTAssertFalse(apps.contains(bundleIdentifier: nil, bundleURL: bundleURL))

        let appended = apps.appendingTile(for: bundleURL)

        XCTAssertEqual(appended.tiles.count, 4)
        XCTAssertEqual(NSArray(array: Array(appended.tiles.prefix(3))), NSArray(array: existing),
                       "Existing tiles are written back exactly as read")
        let tile = try XCTUnwrap(appended.tiles.last as? [String: Any])
        XCTAssertEqual(tile["tile-type"] as? String, "file-tile")
        let fileData = try XCTUnwrap((tile["tile-data"] as? [String: Any])?["file-data"] as? [String: Any])
        XCTAssertEqual(fileData["_CFURLString"] as? String, "file:///Applications/Launchpod.app/")
        XCTAssertTrue(appended.contains(bundleIdentifier: nil, bundleURL: bundleURL))
        XCTAssertTrue(PropertyListSerialization.propertyList(appended.tiles, isValidFor: .binary),
                      "The list can be stored in the Dock's preferences")
    }
}
