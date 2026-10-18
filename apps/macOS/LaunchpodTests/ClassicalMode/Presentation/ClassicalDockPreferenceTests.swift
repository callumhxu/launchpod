import AppKit
import XCTest
@testable import Launchpod

// Run with parallel testing disabled: these tests own native windows and keyboard focus.
@MainActor
final class ClassicalDockPreferenceTests: XCTestCase {
    func testDefaultLeavesTheDockAboveTheLauncherAndCoveringClearsDockMenuBarAndStatusItems() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        XCTAssertFalse(ClassicalDockPreference.hidesDock(in: defaults))
        defaults.set(true, forKey: ClassicalDockPreference.key)
        XCTAssertTrue(ClassicalDockPreference.hidesDock(in: defaults))

        let beneath = ClassicalDockPreference.windowLevel(hidesDock: false)
        XCTAssertEqual(beneath, 19)
        XCTAssertLessThan(beneath, Int(CGWindowLevelForKey(.dockWindow)))
        let covering = ClassicalDockPreference.windowLevel(hidesDock: true)
        XCTAssertEqual(covering, 27)
        for key: CGWindowLevelKey in [.dockWindow, .mainMenuWindow, .statusWindow] {
            XCTAssertGreaterThan(covering, Int(CGWindowLevelForKey(key)))
        }
        XCTAssertLessThan(covering, Int(CGWindowLevelForKey(.popUpMenuWindow)))
    }

    func testEachPresentationUsesTheCurrentDockPreference() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        let hidesDock = MainActorBox(false)
        let controller = ClassicalWindowController(desktopImage: { _ in image }, hidesDock: { hidesDock.value })
        defer { controller.stop() }
        let window = try XCTUnwrap(controller.window)
        for covering in [false, true, false] {
            hidesDock.value = covering
            var shown = false
            controller.setVisible(true) { shown = $0 }
            try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
            XCTAssertEqual(window.level.rawValue, covering ? 27 : 19)
            var hidden = false
            controller.setVisible(false) { hidden = $0 }
            try await NativeAppTestSupport.waitUntil(description: "dismissal completion reports success", state: { "hidden=\(String(describing: hidden))" }) { hidden }
        }
    }

    private func fixtureImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                                             bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try XCTUnwrap(context.makeImage())
    }
}
