import Foundation
import XCTest
@testable import Launchpod

/// The Dock store used under tests keeps its list in memory and never reaches the user's Dock.
@MainActor
final class InMemoryDockPersistentAppsStoreTests: XCTestCase {
    func testTheUnitTestHostUsesTheInMemoryStore() {
        XCTAssertTrue(InMemoryDockPersistentAppsStore.forCurrentProcess() is InMemoryDockPersistentAppsStore)
    }

    func testStartsEmptyKeepsWhatIsSavedAndReportsTheQuitAtOnce() async throws {
        let store = InMemoryDockPersistentAppsStore()
        XCTAssertEqual(store.load()?.tiles.count, 0, "The app starts outside the Dock")
        let url = URL(fileURLWithPath: "/Applications/Launchpod.app", isDirectory: true)
        XCTAssertTrue(store.save(DockPersistentApps(tiles: []).appendingTile(for: url)))
        XCTAssertTrue(store.load()?.contains(bundleIdentifier: nil, bundleURL: url) == true)
        XCTAssertNil(store.observeChanges {}, "Nothing outside the process is observed")

        var quits = 0
        let token = store.restartDock { quits += 1 }
        XCTAssertNotNil(token)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while quits == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(quits, 1)
    }
}
