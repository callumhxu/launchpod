import Foundation
import XCTest
@testable import Launchpod

/// Whether this app is in the Dock, and adding it: the tile is written, the Dock is asked to quit so
/// it reloads the list, and the list is checked again once the Dock has quit.
@MainActor
final class KeepInDockModelTests: XCTestCase {
    /// A Dock list and Dock process under the test's control.
    private nonisolated final class FakeDockStore: DockPersistentAppsStore, @unchecked Sendable {
        enum Restart { case quits, unavailable, neverQuits }

        private let lock = NSLock()
        private var apps: DockPersistentApps?
        private var savedLists: [DockPersistentApps] = []
        private var restarts = 0
        var savesSucceed = true
        var restart = Restart.quits
        /// The Dock rewrites its list while quitting and drops the new tile.
        var dropsNewTileOnQuit = false

        init(apps: DockPersistentApps?) { self.apps = apps }

        var saveCount: Int { lock.withLock { savedLists.count } }
        var restartCount: Int { lock.withLock { restarts } }
        var lastSaved: DockPersistentApps? { lock.withLock { savedLists.last } }

        func load() -> DockPersistentApps? { lock.withLock { apps } }

        func save(_ apps: DockPersistentApps) -> Bool {
            lock.withLock {
                savedLists.append(apps)
                if savesSucceed { self.apps = apps }
                return savesSucceed
            }
        }

        func restartDock(whenQuit: @escaping @MainActor @Sendable () -> Void) -> (any Sendable & AnyObject)? {
            lock.withLock { restarts += 1 }
            switch restart {
            case .unavailable:
                return nil
            case .neverQuits:
                return self
            case .quits:
                if dropsNewTileOnQuit { lock.withLock { apps = DockPersistentApps(tiles: []) } }
                Task { @MainActor in whenQuit() }
                return self
            }
        }

        func observeChanges(_ onChange: @escaping @MainActor @Sendable () -> Void) -> AnyObject? { nil }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, _ message: String = "") async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out. \(message)")
    }

    private func observedModel(_ store: FakeDockStore) async throws -> KeepInDockModel {
        let model = KeepInDockModel(bundle: .main, store: store)
        model.startObserving()
        try await waitUntil({ model.membership != .unknown || store.load() == nil }, "initial read")
        return model
    }

    func testAppOutsideTheDockCanBeAddedAndIsInTheDockAfterTheDockQuits() async throws {
        let store = FakeDockStore(apps: DockPersistentApps(tiles: []))
        let model = try await observedModel(store)
        XCTAssertEqual(model.membership, .notInDock)
        XCTAssertTrue(model.canAdd)

        model.addToDock()

        XCTAssertTrue(model.isAdding)
        XCTAssertFalse(model.canAdd, "No second add while one is in progress")
        try await waitUntil { !model.isAdding }
        XCTAssertEqual(model.membership, .inDock)
        XCTAssertFalse(model.addFailed)
        XCTAssertFalse(model.canAdd)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.restartCount, 1, "The Dock is asked to quit so it loads the new tile")
        XCTAssertTrue(store.lastSaved?.contains(bundleIdentifier: nil, bundleURL: Bundle.main.bundleURL) == true)
    }

    func testAppAlreadyInTheDockIsNotAddedAgain() async throws {
        let identifier = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let tile: [String: Any] = ["tile-data": ["bundle-identifier": identifier]]
        let store = FakeDockStore(apps: DockPersistentApps(tiles: [tile]))
        let model = try await observedModel(store)
        XCTAssertEqual(model.membership, .inDock)
        XCTAssertFalse(model.canAdd)
    }

    func testUnreadableDockListIsUnknownAndCannotBeAdded() async throws {
        let store = FakeDockStore(apps: nil)
        let model = KeepInDockModel(bundle: .main, store: store)
        model.startObserving()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.membership, .unknown)
        XCTAssertFalse(model.canAdd)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testFailedSaveReportsTheFailureWithoutRestartingTheDock() async throws {
        let store = FakeDockStore(apps: DockPersistentApps(tiles: []))
        store.savesSucceed = false
        let model = try await observedModel(store)

        model.addToDock()

        try await waitUntil { !model.isAdding }
        XCTAssertTrue(model.addFailed)
        XCTAssertEqual(store.restartCount, 0)
        try await waitUntil { model.membership == .notInDock }
        XCTAssertTrue(model.canAdd, "The user can try again")
    }

    func testUnavailableDockRestartReportsTheFailure() async throws {
        let store = FakeDockStore(apps: DockPersistentApps(tiles: []))
        store.restart = .unavailable
        let model = try await observedModel(store)

        model.addToDock()

        try await waitUntil { !model.isAdding }
        XCTAssertTrue(model.addFailed)
        XCTAssertEqual(store.saveCount, 1)
    }

    func testTileDroppedWhileTheDockQuitsReportsTheFailure() async throws {
        let store = FakeDockStore(apps: DockPersistentApps(tiles: []))
        store.dropsNewTileOnQuit = true
        let model = try await observedModel(store)

        model.addToDock()

        try await waitUntil { !model.isAdding }
        XCTAssertTrue(model.addFailed)
        XCTAssertEqual(model.membership, .notInDock)
    }

    func testRepeatedAddWhileAddingWritesOneTile() async throws {
        let store = FakeDockStore(apps: DockPersistentApps(tiles: []))
        store.restart = .neverQuits
        let model = try await observedModel(store)

        model.addToDock()
        model.addToDock()
        try await waitUntil { store.restartCount == 1 }
        model.addToDock()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(model.isAdding, "Still waiting for the Dock to quit")
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.restartCount, 1)
        XCTAssertEqual(store.lastSaved?.tiles.count, 1)
    }
}
