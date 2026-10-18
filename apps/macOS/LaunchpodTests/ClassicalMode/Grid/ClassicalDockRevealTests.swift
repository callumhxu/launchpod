import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalDockRevealTests: XCTestCase {
    /// A simulated Dock whose auto-hide setting persists like the real one.
    private final class FakeDock {
        var autoHide: Bool
        var writes: [Bool] = []
        init(autoHide: Bool) { self.autoHide = autoHide }
        var operations: ClassicalDockReveal.Operations {
            .init(autoHideEnabled: { self.autoHide }, setAutoHideEnabled: { self.autoHide = $0; self.writes.append($0) })
        }
    }

    private func makeDefaults() throws -> UserDefaults {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        addTeardownBlock { try preferences.cleanup() }
        return defaults
    }

    private let hidden = ClassicalDockMetrics(tileSize: 39, edge: .bottom, autoHides: true)

    func testRevealTurnsAutoHideOffForThePresentationAndRestoreTurnsItBackOn() throws {
        let defaults = try makeDefaults()
        let dock = FakeDock(autoHide: true)
        let reveal = ClassicalDockReveal(defaults: defaults, operations: dock.operations, metrics: { self.hidden })
        reveal.reveal()
        XCTAssertFalse(dock.autoHide)
        XCTAssertEqual(reveal.revealedMetrics, hidden, "Layout keeps the pre-reveal Dock while the inset catches up")
        XCTAssertTrue(defaults.bool(forKey: ClassicalDockReveal.restorePendingKey), "Marked before the setting changes")
        reveal.reveal()
        XCTAssertEqual(dock.writes, [false], "Repeated reveals do not write again")
        reveal.restore()
        reveal.restore()
        XCTAssertTrue(dock.autoHide)
        XCTAssertEqual(dock.writes, [false, true])
        XCTAssertNil(reveal.revealedMetrics)
        XCTAssertNil(defaults.object(forKey: ClassicalDockReveal.restorePendingKey))
    }

    func testADockThatDoesNotAutoHideIsNeverTouched() throws {
        let defaults = try makeDefaults()
        let dock = FakeDock(autoHide: false)
        let reveal = ClassicalDockReveal(defaults: defaults, operations: dock.operations, metrics: {
            .init(tileSize: 39, edge: .bottom, autoHides: false)
        })
        reveal.reveal()
        reveal.restore()
        XCTAssertTrue(dock.writes.isEmpty)
        XCTAssertNil(defaults.object(forKey: ClassicalDockReveal.restorePendingKey))
    }

    func testRestoreDoesNotOverrideAutoHideTurnedBackOnElsewhere() throws {
        let defaults = try makeDefaults()
        let dock = FakeDock(autoHide: true)
        let reveal = ClassicalDockReveal(defaults: defaults, operations: dock.operations, metrics: { self.hidden })
        reveal.reveal()
        dock.autoHide = true
        reveal.restore()
        XCTAssertEqual(dock.writes, [false])
        XCTAssertNil(defaults.object(forKey: ClassicalDockReveal.restorePendingKey))
    }

    func testNextLaunchRestoresAutoHideLeftOffByAnUnexpectedExit() throws {
        let defaults = try makeDefaults()
        let dock = FakeDock(autoHide: true)
        var crashed: ClassicalDockReveal? = ClassicalDockReveal(defaults: defaults, operations: dock.operations, metrics: { self.hidden })
        crashed?.reveal()
        // Simulate a crash: the object vanishes without restoring.
        crashed = nil
        dock.autoHide = false
        defaults.set(true, forKey: ClassicalDockReveal.restorePendingKey)

        let relaunched = ClassicalDockReveal(defaults: defaults, operations: dock.operations, metrics: { nil })
        relaunched.recoverAfterUnexpectedExit()
        XCTAssertTrue(dock.autoHide)
        XCTAssertNil(defaults.object(forKey: ClassicalDockReveal.restorePendingKey))
        let writes = dock.writes.count
        relaunched.recoverAfterUnexpectedExit()
        XCTAssertEqual(dock.writes.count, writes, "Without a marker nothing is written")
    }

    // MARK: Folder hide

    /// While a folder is open the Dock auto-hides; closing the folder returns it to the state the
    /// presentation keeps it in.
    func testFolderHidesAShownDockAndClosingShowsItAgain() throws {
        let defaults = try makeDefaults()
        let dock = FakeDock(autoHide: false)
        let reveal = ClassicalDockReveal(defaults: defaults, operations: dock.operations, metrics: {
            .init(tileSize: 39, edge: .bottom, autoHides: false)
        })
        reveal.reveal()
        XCTAssertTrue(dock.writes.isEmpty)
        reveal.hideForFolder()
        XCTAssertTrue(reveal.hidesForFolder)
        XCTAssertTrue(dock.autoHide)
        XCTAssertEqual(defaults.object(forKey: ClassicalDockReveal.restorePendingKey) as? Bool, false,
                       "The marker holds the user's original setting")
        reveal.hideForFolder()
        XCTAssertEqual(dock.writes, [true], "Repeated folder hides do not write again")
        reveal.endFolderHide()
        XCTAssertFalse(reveal.hidesForFolder)
        XCTAssertFalse(dock.autoHide)
        XCTAssertNil(defaults.object(forKey: ClassicalDockReveal.restorePendingKey))
        reveal.endFolderHide()
        XCTAssertEqual(dock.writes, [true, false])
    }

    /// An auto-hiding Dock revealed for the launcher hides for a folder and is revealed again after it.
    func testFolderOverARevealedDockReturnsToTheRevealAndCloseRestoresTheUserSetting() throws {
        let defaults = try makeDefaults()
        let dock = FakeDock(autoHide: true)
        let reveal = ClassicalDockReveal(defaults: defaults, operations: dock.operations, metrics: { self.hidden })
        reveal.reveal()
        reveal.hideForFolder()
        XCTAssertTrue(dock.autoHide)
        XCTAssertEqual(defaults.object(forKey: ClassicalDockReveal.restorePendingKey) as? Bool, true)
        reveal.endFolderHide()
        XCTAssertFalse(dock.autoHide, "Revealed again for the rest of the presentation")
        XCTAssertEqual(defaults.object(forKey: ClassicalDockReveal.restorePendingKey) as? Bool, true)
        reveal.restore()
        XCTAssertTrue(dock.autoHide)
        XCTAssertEqual(dock.writes, [false, true, false, true])
        XCTAssertNil(defaults.object(forKey: ClassicalDockReveal.restorePendingKey))
    }

    func testClosingTheLauncherWithAFolderOpenRestoresTheUserSetting() throws {
        let defaults = try makeDefaults()
        let dock = FakeDock(autoHide: false)
        let reveal = ClassicalDockReveal(defaults: defaults, operations: dock.operations, metrics: { nil })
        reveal.hideForFolder()
        reveal.restore()
        XCTAssertFalse(reveal.hidesForFolder)
        XCTAssertFalse(dock.autoHide)
        XCTAssertNil(defaults.object(forKey: ClassicalDockReveal.restorePendingKey))
        reveal.endFolderHide()
        XCTAssertEqual(dock.writes, [true, false])
    }

    func testNextLaunchRestoresAShownDockLeftAutoHidingByAFolder() throws {
        let defaults = try makeDefaults()
        let dock = FakeDock(autoHide: false)
        var crashed: ClassicalDockReveal? = ClassicalDockReveal(defaults: defaults, operations: dock.operations, metrics: { nil })
        crashed?.hideForFolder()
        XCTAssertTrue(dock.autoHide)
        // Simulate a crash: the object vanishes without restoring, and the marker survives.
        crashed = nil
        dock.autoHide = true
        defaults.set(false, forKey: ClassicalDockReveal.restorePendingKey)
        ClassicalDockReveal(defaults: defaults, operations: dock.operations, metrics: { nil }).recoverAfterUnexpectedExit()
        XCTAssertFalse(dock.autoHide)
        XCTAssertNil(defaults.object(forKey: ClassicalDockReveal.restorePendingKey))
    }

    func testTestHostsNeverReachTheRealDock() {
        XCTAssertNil(ClassicalDockReveal.nativeOperations())
    }

    func testLauncherRevealsBeforeLayoutAndRestoresWhenHidden() async throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let defaults = try makeDefaults()
        let dock = FakeDock(autoHide: true)
        let reveal = ClassicalDockReveal(defaults: defaults, operations: dock.operations, metrics: { self.hidden })
        let image = try pixel()
        let covers = MainActorBox(false)
        let controller = ClassicalWindowController(desktopImage: { _ in image }, hidesDock: { covers.value }, dockReveal: reveal)
        defer { controller.stop() }
        for coversDock in [false, true] {
            covers.value = coversDock
            var shown = false
            controller.setVisible(true) { shown = $0 }
            try await waitUntil { shown }
            XCTAssertEqual(dock.autoHide, coversDock, coversDock ? "A covered Dock stays hidden" : "Revealed while shown")
            var hidden = false
            controller.setVisible(false) { hidden = $0 }
            try await waitUntil { hidden }
            XCTAssertTrue(dock.autoHide, "Auto-hide returns when the launcher closes")
        }
        XCTAssertEqual(dock.writes, [false, true])
    }

    private func pixel() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Timed out waiting for native presentation state.")
    }
}
