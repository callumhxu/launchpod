import AppKit
import QuartzCore
import XCTest
@testable import Launchpod

@available(macOS 26.0, *)
@MainActor
final class ClassicalFolderGlassStageTests: XCTestCase {
    /// Every native glass view under `view`, in subview order.
    private func glassViews(in view: NSView) -> [NSGlassEffectView] {
        view.subviews.flatMap { subview -> [NSGlassEffectView] in
            (subview as? NSGlassEffectView).map { [$0] } ?? glassViews(in: subview)
        }
    }

    private func containsContainer(_ view: NSView) -> Bool {
        view.subviews.contains { $0 is NSGlassEffectContainerView || containsContainer($0) }
    }

    /// A stage over `fixture`'s layers in a key panel. The fixture's cells take the Liquid Glass
    /// option from the current defaults.
    private func stage(over fixture: ClassicalFolderTestBoard,
                       searchBackground: @escaping @MainActor () -> CALayer? = { nil })
        -> (stage: ClassicalFolderGlassStage, root: CALayer, window: NSWindow) {
        let frame = CGRect(origin: .zero, size: ClassicalFolderTestBoard.geometry.screenSize)
        let root = CALayer()
        root.frame = frame
        let stage = ClassicalFolderGlassStage(frame: frame, rootLayer: root, contentLayer: fixture.background,
                                              springboard: fixture.board, searchBackground: searchBackground)
        let window = NativeAppTestSupport.makeKeyPanel(size: frame.size, contentView: stage)
        CATransaction.flush()
        stage.synchronize()
        return (stage, root, window)
    }

    private func withoutActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    // MARK: Glass views

    func testStageOwnsHiddenClearGlassForTheOpenFolderAndSearchField() throws {
        let frame = CGRect(x: 0, y: 0, width: 480, height: 320)
        let root = CALayer()
        root.frame = frame
        let content = CALayer()
        content.frame = frame
        root.addSublayer(content)
        let stage = ClassicalFolderGlassStage(frame: frame, rootLayer: root, contentLayer: content,
                                              springboard: ClassicalSpringboard())

        XCTAssertFalse(containsContainer(stage), "A glass container would ignore each glass view's opacity")
        let glasses = glassViews(in: stage)
        XCTAssertEqual(glasses.count, 2, "The open panel's glass and the search field's glass")
        for glass in glasses {
            XCTAssertNotNil(glass.contentView, "AppKit embeds content inside the native glass effect")
            XCTAssertTrue(glass.isHidden, "Nothing is covered until a folder opens or the field uses glass")
        }
        let open = try XCTUnwrap(glasses.first)
        XCTAssertEqual(open.style, .clear, "The open panel uses clear glass")
        let search = try XCTUnwrap(glasses.last)
        if search.responds(to: NSSelectorFromString("_variant")) {
            XCTAssertEqual(search.value(forKey: "_variant") as? Int, 3,
                           "The search field uses the glass variant matching the dock's glass")
        } else {
            XCTAssertEqual(search.style, .clear, "Without the private variant the field keeps clear glass")
        }
    }

    func testNativeGlassTracksClosedPreviewAndOpenedFolder() throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]], folderGlass: true)
        let cell = try fixture.folderCell("Work")
        XCTAssertTrue(cell.glassEnabled)
        let (stage, root, window) = stage(over: fixture)
        defer { window.close() }

        let closed = try XCTUnwrap(glassViews(in: stage).first { !$0.isHidden }, "The closed preview has glass")
        XCTAssertEqual(glassViews(in: stage).filter { !$0.isHidden }.count, 1)
        XCTAssertEqual(closed.style, .clear)
        let closedFrame = cell.backdropLayer.convert(cell.backdropLayer.bounds, to: root)
        let closedOnScreen = closed.convert(closed.bounds, to: stage)
        XCTAssertEqual(closedOnScreen.midX, closedFrame.midX, accuracy: 1)
        XCTAssertEqual(closedOnScreen.midY, closedFrame.midY, accuracy: 1)
        XCTAssertEqual(closedOnScreen.width, closedFrame.width, accuracy: 1)
        XCTAssertEqual(closed.cornerRadius, cell.backdropLayer.cornerRadius, accuracy: 0.01)
        let foreground = try XCTUnwrap(stage.subviews.firstIndex { $0.layer?.sublayers?.contains { $0 === fixture.background } == true })
        let glassHost = try XCTUnwrap(stage.subviews.firstIndex { !glassViews(in: $0).isEmpty })
        XCTAssertLessThan(glassHost, foreground, "Icon content stays above the glass")

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        fixture.waitUntilOpened()
        CATransaction.flush()
        stage.synchronize()
        let panel = try XCTUnwrap(fixture.board.folders.openFolder?.layer)
        let open = try XCTUnwrap(glassViews(in: stage).first { !$0.isHidden && $0 !== closed })
        XCTAssertEqual(open.style, .clear)
        XCTAssertTrue(closed.isHidden, "The closed preview fades out while its folder is open")
        let openFrame = panel.backdropLayer.convert(panel.backdropLayer.bounds, to: root)
        XCTAssertEqual(open.frame.midX, openFrame.midX, accuracy: 1)
        XCTAssertEqual(open.frame.midY, openFrame.midY, accuracy: 1)
        XCTAssertEqual(open.frame.width, openFrame.width, accuracy: 1)
        fixture.board.folders.close(animated: false)
    }

    func testOffLeavesNativeGlassHiddenAndTheClassicBackdropsInPlace() throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let cell = try fixture.folderCell("Work")
        XCTAssertFalse(cell.glassEnabled)
        XCTAssertNotNil(cell.backdropLayer.backgroundColor, "The closed cell keeps its gray backdrop")
        let (stage, _, window) = stage(over: fixture)
        defer { window.close() }

        XCTAssertEqual(glassViews(in: stage).count, 2, "No closed glass view is created")
        XCTAssertTrue(glassViews(in: stage).allSatisfy(\.isHidden))
        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        fixture.waitUntilOpened()
        stage.synchronize()
        let panel = try XCTUnwrap(fixture.board.folders.openFolder?.layer)
        XCTAssertFalse(panel.glassEnabled)
        XCTAssertEqual(NSStringFromClass(type(of: panel.backdropLayer)), "CABackdropLayer")
        XCTAssertTrue(glassViews(in: stage).allSatisfy(\.isHidden), "The panel keeps its Classical backdrop")
        XCTAssertFalse(stage.layer?.allSublayers.contains { NSStringFromClass(type(of: $0)) == "MTMaterialLayer" } ?? true,
                       "No background material lies behind a classic panel")
        fixture.board.folders.close(animated: false)
    }

    // MARK: Tracking

    /// The glass follows the cell's jiggle and page, stays through a press, and fades with the root
    /// pages on the next run-loop pass without an explicit synchronization, so no glass remains
    /// behind once the pages have faded out.
    func testClosedGlassFollowsJigglePressPagingAndTheRootPagesOpacity() throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let fixture = try ClassicalFolderTestBoard([["A", "B", "C", "D", "E", "F"], [.folder("Work", [["G", "H"]])]],
                                                folderGlass: true)
        let (stage, root, window) = stage(over: fixture)
        defer { window.close() }
        let pager = fixture.board.pager
        pager.jump(to: 1)
        let cell = try fixture.folderCell("Work")
        func spin() { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        func closedGlass() throws -> NSGlassEffectView {
            try XCTUnwrap(glassViews(in: stage).first { $0.style == .clear && !$0.isHidden })
        }
        func expectCovering(_ message: String) throws {
            let expected = try XCTUnwrap(ClassicalGlassPlacement.covering(cell.backdropLayer, in: root))
            let glass = try closedGlass()
            let onScreen = glass.convert(CGPoint(x: glass.bounds.midX, y: glass.bounds.midY), to: stage)
            // A view's frame does not include its host layer's scroll translation.
            let scroll = glass.superview?.layer?.sublayerTransform.m41 ?? 0
            XCTAssertEqual(onScreen.x + scroll, expected.center.x, accuracy: 1, message)
            XCTAssertEqual(onScreen.y, expected.center.y, accuracy: 1, message)
            XCTAssertEqual(glass.frameCenterRotation, expected.rotation * 180 / .pi, accuracy: 0.01, message)
        }
        spin()
        try expectCovering("On the second page")
        XCTAssertEqual(pager.stripMirror?.sublayerTransform.m41 ?? .nan, -pager.stripLayer.bounds.origin.x,
                       "The strip glass scrolls with the strip")

        withoutActions { cell.jitterLayer.transform = CATransform3DMakeRotation(2 * .pi / 180, 0, 0, 1) }
        spin()
        try expectCovering("While jiggling")
        XCTAssertEqual(abs(try closedGlass().frameCenterRotation), 2, accuracy: 0.01)

        cell.setDarkened(true)
        spin()
        try expectCovering("While pressed")
        XCTAssertNil(cell.backdropLayer.filters, "Pressing darkens the thumbnails, not the glass backing")
        cell.setDarkened(false)

        withoutActions { pager.layer.opacity = 0.4 }
        spin()
        XCTAssertEqual(try closedGlass().alphaValue, 0.4, accuracy: 0.001)
        withoutActions { pager.layer.opacity = 0 }
        spin()
        XCTAssertTrue(glassViews(in: stage).allSatisfy(\.isHidden), "No glass shows once the pages have faded out")
    }

    func testSearchGlassCoversTheFieldBackgroundAsACapsule() throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let fixture = try ClassicalFolderTestBoard([["A"]])
        let field = CALayer()
        withoutActions {
            field.frame = CGRect(x: 200, y: 500, width: 250, height: 25)
            field.cornerRadius = 12.5
            fixture.background.addSublayer(field)
        }
        final class Shown { var field = true }
        let shown = Shown()
        let (stage, _, window) = stage(over: fixture, searchBackground: { shown.field ? field : nil })
        defer { window.close() }

        let search = try XCTUnwrap(glassViews(in: stage).first { !$0.isHidden })
        XCTAssertEqual(search.frame.midX, 325, accuracy: 1)
        XCTAssertEqual(search.frame.midY, 512.5, accuracy: 1)
        XCTAssertEqual(search.frame.width, 250, accuracy: 1)
        XCTAssertEqual(search.cornerRadius, 12.5, accuracy: 0.01)
        shown.field = false
        stage.synchronize()
        XCTAssertTrue(search.isHidden, "Without a glass field there is no search glass")
    }
}

private extension CALayer {
    /// This layer's sublayers and all of their descendants.
    var allSublayers: [CALayer] {
        (sublayers ?? []).flatMap { [$0] + $0.allSublayers }
    }
}
