import AppKit
import XCTest
@testable import Launchpod

/// The content view installs a fresh Liquid Glass stage for each presentation, below its other
/// subviews, and removes it completely when the launcher is dismissed.
@MainActor
final class ClassicalContentViewGlassStageTests: XCTestCase {
    func testEachShowPlacesOneStageBelowTheSearchFieldAndDismissalLeavesNothingBehind() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Liquid Glass needs macOS 26") }
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]], folderGlass: true)
        let content = fixture.content
        let window = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: content)
        defer { window.close() }
        let field = fixture.keyboard.field
        field.place(in: fixture.host, view: content, frame: CGRect(x: 100, y: 500, width: 250, height: 25),
                    scale: 1, rightToLeft: false, usesGlass: true)
        weak var lastStage: NSView?

        for show in 0..<3 {
            autoreleasepool {
                let root = CALayer()
                root.frame = content.bounds
                content.installGlassStage(rootLayer: root, contentLayer: fixture.background)
                let stages = content.subviews.filter { $0 is ClassicalFolderGlassStage }
                XCTAssertEqual(stages.count, 1, "Show \(show) has one stage")
                XCTAssertTrue(content.subviews.first === stages.first, "The stage lies below every other subview")
                let fieldIndex = content.subviews.firstIndex { $0 === field.textField }
                XCTAssertNotNil(fieldIndex, "The search text field stays in the content view")
                XCTAssertGreaterThan(fieldIndex ?? 0, 0, "Show \(show): the search text field is above the glass")
                XCTAssertNotNil(fixture.board.pager.stripMirror)
                XCTAssertNotNil(fixture.board.dragOverlay)
                lastStage = stages.first

                content.removeGlassStage()
                XCTAssertFalse(content.subviews.contains { $0 is ClassicalFolderGlassStage })
                XCTAssertNil(fixture.board.pager.stripMirror, "The pager no longer scrolls the removed glass")
                XCTAssertNil(fixture.board.dragOverlay, "Dragged cells no longer go to the removed stage")
                XCTAssertTrue(fixture.board.dragHost === fixture.background)
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNil(lastStage, "Nothing, such as a display link, keeps a dismissed stage alive")
    }

    func testNoStageIsInstalledWithTheOptionOff() throws {
        let fixture = try ClassicalFolderTestBoard([["A"]])
        let root = CALayer()
        root.frame = fixture.content.bounds
        fixture.content.installGlassStage(rootLayer: root, contentLayer: fixture.background)
        XCTAssertTrue(fixture.content.subviews.allSatisfy { NSStringFromClass(type(of: $0)).contains("GlassStage") == false })
        XCTAssertTrue(fixture.background.superlayer === fixture.host, "The pages stay in the content view's layer")
        XCTAssertNil(fixture.board.dragOverlay)
    }
}
