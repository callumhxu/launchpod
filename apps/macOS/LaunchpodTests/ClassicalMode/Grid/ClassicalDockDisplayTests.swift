import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalDockDisplayTests: XCTestCase {
    // Main 1470×956 at the origin; an external 2560×1440 display to its right.
    private let main = (frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                        visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 923))
    private let external = (frame: CGRect(x: 1470, y: 0, width: 2560, height: 1440),
                            visibleFrame: CGRect(x: 1470, y: 0, width: 2560, height: 1415))

    func testTheDisplayReservingTheDockWins() {
        let externalWithDock = (frame: external.frame, visibleFrame: CGRect(x: 1470, y: 59, width: 2560, height: 1356))
        XCTAssertEqual(ClassicalDockDisplay.index(of: [main, externalWithDock], dockRect: nil, dockEdge: nil), 1)
    }

    func testAnAutoHiddenDockIsLocatedByItsReportedRectangle() {
        // Top-left global coordinates against the first screen (height 956); a hidden bottom Dock keeps
        // its x range with zero height at the screen's bottom edge (y 956).
        let atMainBottom = CGRect(x: 98, y: 956, width: 1273, height: 0)
        XCTAssertEqual(ClassicalDockDisplay.index(of: [main, external], dockRect: atMainBottom, dockEdge: .bottom), 0)
        let atExternalBottom = CGRect(x: 2000, y: 956, width: 1200, height: 0)
        XCTAssertEqual(ClassicalDockDisplay.index(of: [main, external], dockRect: atExternalBottom, dockEdge: .bottom), 1)
        // A hidden side Dock keeps its y range with zero width.
        let leftOfMain = CGRect(x: 0, y: 200, width: 0, height: 500)
        XCTAssertEqual(ClassicalDockDisplay.index(of: [main, external], dockRect: leftOfMain, dockEdge: .left), 0)
        let rightOfExternal = CGRect(x: 4030, y: 200, width: 0, height: 500)
        XCTAssertEqual(ClassicalDockDisplay.index(of: [main, external], dockRect: rightOfExternal, dockEdge: .right), 1)
    }

    func testWithoutAnyDockSignalTheCallerFallsBack() {
        XCTAssertNil(ClassicalDockDisplay.index(of: [main, external], dockRect: nil, dockEdge: nil))
    }

    func testVisibleDockHandoffUsesTheReportedBarRectangle() {
        let reported = CGRect(x: 31, y: 897, width: 1408, height: 59)
        XCTAssertEqual(ClassicalDockDisplay.dragHandoffFrame(screenFrame: main.frame, desktopTop: 956,
                                                             reportedDockRect: reported, edge: .bottom, pixel: 0.5),
                       CGRect(x: 31, y: 0, width: 1408, height: 59))
    }

    func testAutoHiddenDockHandoffUsesOnlyItsPhysicalEdge() {
        XCTAssertEqual(ClassicalDockDisplay.dragHandoffFrame(
            screenFrame: main.frame, desktopTop: 956,
            reportedDockRect: CGRect(x: 98, y: 956, width: 1273, height: 0), edge: .bottom, pixel: 0.5),
            CGRect(x: 98, y: 0, width: 1273, height: 0.5))
        XCTAssertEqual(ClassicalDockDisplay.dragHandoffFrame(
            screenFrame: main.frame, desktopTop: 956,
            reportedDockRect: CGRect(x: 0, y: 200, width: 0, height: 500), edge: .left, pixel: 0.5),
            CGRect(x: 0, y: 256, width: 0.5, height: 500))
        XCTAssertEqual(ClassicalDockDisplay.dragHandoffFrame(
            screenFrame: main.frame, desktopTop: 956,
            reportedDockRect: CGRect(x: 1470, y: 200, width: 0, height: 500), edge: .right, pixel: 0.5),
            CGRect(x: 1469.5, y: 256, width: 0.5, height: 500))
    }
}

@MainActor
final class ClassicalDockDisplayPresentationTests: XCTestCase {
    func testLauncherClosesWhenTheDockMovesToAnotherDisplayAndStaysOtherwise() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let screen = try XCTUnwrap(NSScreen.main)
        let current = try XCTUnwrap(screen.displayNumber)
        let dock = MainActorBox<NSNumber?>(current)
        let image = try pixel()
        let controller = ClassicalWindowController(desktopImage: { _ in image }, dockDisplay: { dock.value })
        defer { controller.stop() }
        var dismissals = 0
        controller.onDismiss = { dismissals += 1 }
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await waitUntil { shown }

        // Same display (e.g. the temporary reveal changing the Dock inset): only a re-layout.
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApplication.shared)
        await Task.yield()
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(dismissals, 0)
        // Unknown Dock display: no evidence to close on.
        dock.value = nil
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApplication.shared)
        await Task.yield()
        XCTAssertTrue(controller.isVisible)

        dock.value = NSNumber(value: current.uint32Value &+ 1)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApplication.shared)
        try await waitUntil { dismissals == 1 }
        XCTAssertFalse(controller.isVisible)
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
