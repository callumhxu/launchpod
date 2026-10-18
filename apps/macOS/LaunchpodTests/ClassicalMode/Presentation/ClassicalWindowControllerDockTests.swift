import AppKit
import XCTest
@testable import Launchpod

// Run with parallel testing disabled: these tests own a native launcher window.
@MainActor
final class ClassicalWindowControllerDockTests: XCTestCase {
    /// Opening a folder lets a shown Dock auto-hide instead of raising the launcher above it; closing
    /// the folder brings the Dock back. The launcher keeps its ordinary level throughout.
    func testFolderLetsTheDockAutoHideAndClosingRestoresIt() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let dock = FakeDock(autoHide: false)
        let (controller, folderID) = try makeController(hidesDock: false, dock: dock)
        defer { controller.stop() }
        let window = try await show(controller)
        let ordinary = ClassicalDockPreference.windowLevel(hidesDock: false)
        XCTAssertEqual(window.level.rawValue, ordinary)
        XCTAssertLessThan(ordinary, Int(CGWindowLevelForKey(.dockWindow)))

        let springboard = try XCTUnwrap((window.contentView as? ClassicalContentView)?.springboard)
        XCTAssertTrue(springboard.openFolder(folderID))
        XCTAssertTrue(springboard.folders.isActive)
        XCTAssertTrue(dock.autoHide, "The Dock slides away while the folder is open")
        XCTAssertEqual(window.level.rawValue, ordinary)

        springboard.folders.close()
        XCTAssertTrue(dock.autoHide, "The Dock stays hidden through the closing animation")
        try await NativeAppTestSupport.waitUntil(description: "folder close animation finishes") { !springboard.folders.isActive }
        XCTAssertFalse(dock.autoHide, "The Dock returns when the folder finishes closing")
        XCTAssertEqual(window.level.rawValue, ordinary)
        XCTAssertEqual(dock.writes, [true, false])
    }

    func testDismissalWithAFolderOpenRestoresTheDockBeforeNextPresentation() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let dock = FakeDock(autoHide: false)
        let (controller, folderID) = try makeController(hidesDock: false, dock: dock)
        defer { controller.stop() }
        let window = try await show(controller)
        let springboard = try XCTUnwrap((window.contentView as? ClassicalContentView)?.springboard)
        XCTAssertTrue(springboard.openFolder(folderID))
        XCTAssertTrue(dock.autoHide)

        var hidden = false
        controller.setVisible(false) { hidden = $0 }
        try await NativeAppTestSupport.waitUntil(description: "dismissal completion reports success", state: { "hidden=\(String(describing: hidden))" }) { hidden }
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(dock.autoHide)

        _ = try await show(controller)
        XCTAssertFalse(springboard.folders.isActive)
        XCTAssertFalse(dock.autoHide)
        XCTAssertEqual(window.level.rawValue, ClassicalDockPreference.windowLevel(hidesDock: false))
    }

    /// A folder temporarily yields the screen edge to the Dock even when the launcher covers it.
    func testSavedHideDockChoiceYieldsToDockDuringFolderAndRestoresAfterClose() async throws {
        try await verifySavedHideDockChoice(initialAutoHide: false)
        try await verifySavedHideDockChoice(initialAutoHide: true)
    }

    private func verifySavedHideDockChoice(initialAutoHide: Bool) async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let dock = FakeDock(autoHide: initialAutoHide)
        let (controller, folderID) = try makeController(hidesDock: true, dock: dock)
        defer { controller.stop() }
        let window = try await show(controller)
        let savedLevel = ClassicalDockPreference.windowLevel(hidesDock: true)
        let ordinary = ClassicalDockPreference.windowLevel(hidesDock: false)
        XCTAssertEqual(window.level.rawValue, savedLevel)
        XCTAssertEqual(dock.autoHide, initialAutoHide)

        let springboard = try XCTUnwrap((window.contentView as? ClassicalContentView)?.springboard)
        XCTAssertTrue(springboard.openFolder(folderID))
        XCTAssertEqual(window.level.rawValue, ordinary)
        XCTAssertTrue(dock.autoHide, "The Dock can reveal from the edge while the folder is open")
        springboard.folders.close()
        XCTAssertTrue(dock.autoHide, "Closing keeps the Dock hidden until the animation ends")
        try await NativeAppTestSupport.waitUntil(description: "folder close animation finishes") { !springboard.folders.isActive }
        XCTAssertEqual(window.level.rawValue, savedLevel)
        XCTAssertEqual(dock.autoHide, initialAutoHide)
        XCTAssertEqual(dock.writes, initialAutoHide ? [] : [true, false])

        XCTAssertTrue(springboard.openFolder(folderID))
        XCTAssertEqual(window.level.rawValue, ordinary)
        var hidden = false
        controller.setVisible(false) { hidden = $0 }
        try await NativeAppTestSupport.waitUntil(description: "dismissal completion reports success", state: { "hidden=\(String(describing: hidden))" }) { hidden }
        XCTAssertEqual(dock.autoHide, initialAutoHide)
        XCTAssertEqual(window.level.rawValue, savedLevel)
    }

    func testExternalDragCompletionRestoresTheOrdinaryLevel() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let (controller, folderID) = try makeController(hidesDock: false, dock: FakeDock(autoHide: false))
        defer { controller.stop() }
        let window = try await show(controller)
        let content = try XCTUnwrap(window.contentView as? ClassicalContentView)
        let springboard = try XCTUnwrap(content.springboard)
        XCTAssertTrue(springboard.openFolder(folderID))

        window.level = NSWindow.Level(rawValue: ClassicalDockPreference.windowLevel(hidesDock: true))
        springboard.folders.close(animated: false)
        content.externalDragDidEnd?()

        XCTAssertEqual(window.level.rawValue, ClassicalDockPreference.windowLevel(hidesDock: false),
                       "A level chosen during an external drag must not persist after it ends")
    }

    /// A simulated Dock whose auto-hide setting persists like the real one.
    private final class FakeDock {
        var autoHide: Bool
        var writes: [Bool] = []
        init(autoHide: Bool) { self.autoHide = autoHide }
        var operations: ClassicalDockReveal.Operations {
            .init(autoHideEnabled: { self.autoHide }, setAutoHideEnabled: { self.autoHide = $0; self.writes.append($0) })
        }
    }

    private func makeController(hidesDock: Bool, dock: FakeDock) throws -> (ClassicalWindowController, ClassicalLayoutFolder.ID) {
        let image = try fixtureImage()
        let record = try ClassicalDragTestBoard.record("Folder App")
        let folderID = ClassicalLayoutFolder.ID()
        var content = ClassicalPageContent(records: { [] }, icon: { _, _ in image })
        content.pages = { _ in [[.folder(ClassicalPageFolder(id: folderID, title: "Work", pages: [[record]]))]] }
        let menu = ClassicalMenuBarVisibility(resolveOperations: {
            .init(connectionID: 73, setAlpha: { _, _, _, _ in 0 }, reset: { _ in 0 })
        })
        let controller = ClassicalWindowController(desktopImage: { _ in image },
            menuBarVisibility: menu, hidesDock: { hidesDock },
            dockReveal: ClassicalDockReveal(defaults: try isolatedDefaults(), operations: dock.operations, metrics: { nil }))
        controller.pageContent = content
        let folders = try XCTUnwrap((controller.window?.contentView as? ClassicalContentView)?.springboard?.folders)
        folders.slowMotionAllowed = { false }
        folders.shiftKeyDown = { false }
        return (controller, folderID)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        addTeardownBlock { try preferences.cleanup() }
        return defaults
    }

    private func show(_ controller: ClassicalWindowController) async throws -> NSWindow {
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        return try XCTUnwrap(controller.window)
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
