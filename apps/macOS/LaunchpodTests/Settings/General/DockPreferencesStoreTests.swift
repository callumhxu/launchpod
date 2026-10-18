import Foundation
import XCTest
@testable import Launchpod

@MainActor
final class DockPreferencesStoreTests: XCTestCase {
    func testMissingAndMalformedListsAreUnavailableButEmptyListIsValid() throws {
        let preferences = try TemporaryPreferences()
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let domain = preferences.domain
        let store = DockPreferencesStore(preferencesDomain: domain)
        XCTAssertNil(store.load())
        for malformed in ["not an array", ["tile-data": "not a list"], 42] as [Any] {
            CFPreferencesSetAppValue(DockPersistentApps.key as CFString, malformed as CFPropertyList, domain as CFString)
            XCTAssertTrue(CFPreferencesAppSynchronize(domain as CFString))
            XCTAssertNil(store.load())
        }
        XCTAssertTrue(store.save(DockPersistentApps(tiles: [])))
        XCTAssertEqual(store.load()?.tiles.count, 0)
    }

    func testSaveRoundTripsOrderedUnknownTileDataWithoutChangingOtherPreferences() throws {
        let preferences = try TemporaryPreferences()
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let domain = preferences.domain
        let store = DockPreferencesStore(preferencesDomain: domain)
        CFPreferencesSetAppValue("unrelated" as CFString, "preserved" as CFString, domain as CFString)
        let tiles: [Any] = [
            ["tile-type": "file-tile", "GUID": 123, "tile-data": ["custom": ["a", "b"]]],
            "unknown tile", ["opaque": Data([0, 1, 255])]
        ]
        XCTAssertTrue(store.save(DockPersistentApps(tiles: tiles)))
        let restored = try XCTUnwrap(DockPreferencesStore(preferencesDomain: domain).load())
        XCTAssertEqual(restored.tiles as NSArray, tiles as NSArray)
        XCTAssertEqual(CFPreferencesCopyAppValue("unrelated" as CFString, domain as CFString) as? String, "preserved")
        XCTAssertTrue(store.save(DockPersistentApps(tiles: [tiles[1]])))
        XCTAssertEqual(try XCTUnwrap(store.load()).tiles as NSArray, [tiles[1]] as NSArray)
    }

    func testObservationDeliversChangesOnMainActorAndStopsWhenTokenIsReleased() async throws {
        let preferences = try TemporaryPreferences()
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let store = DockPreferencesStore(preferencesDomain: preferences.domain)
        let defaults = preferences.defaults
        let changes = MainActorBox(0)
        var token: AnyObject? = try XCTUnwrap(store.observeChanges { changes.value += 1 })
        XCTAssertNotNil(token)
        defaults.set([], forKey: DockPersistentApps.key)
        try await NativeAppTestSupport.waitUntil(description: "isolated defaults observation") { changes.value > 0 }
        token = nil
        // Drain any callback already queued before releasing the observer.
        try await Task.sleep(for: .milliseconds(100))
        let countAfterRelease = changes.value
        defaults.set(["second value"], forKey: DockPersistentApps.key)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(changes.value, countAfterRelease)
    }
}
