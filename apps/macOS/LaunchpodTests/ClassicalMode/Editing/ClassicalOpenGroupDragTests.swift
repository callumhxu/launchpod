import QuartzCore
import XCTest
@testable import Launchpod

/// Grouping a dragged root application with the icon under it: a release groups at once, a hover
/// opens the folder with the item inside, still dragged.
@MainActor
final class ClassicalOpenGroupDragTests: XCTestCase {
    func testDroppingOnAnExistingFolderAddsTheApplicationWithoutCreatingAnotherFolder() throws {
        let existing = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        let existingCell = try XCTUnwrap(existing.board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(existing.board.beginDrag(of: .app(try existing.record("A")), cell: existingCell))
        let existingDrag = try XCTUnwrap(existing.board.drag)
        var saved: ClassicalLayout?
        existing.board.folderDragDidChange = { saved = $0 }

        XCTAssertTrue(ClassicalOpenGroupDrag.drop(
            on: existing.board.pages[0][1], dragged: existingDrag, springboard: existing.board
        ))
        let folder = try XCTUnwrap(saved?.folders.first)
        XCTAssertEqual(Set(folder.identities), Set([
            try existing.record("A").id,
            try existing.record("B").id,
            try existing.record("C").id,
        ]))
        XCTAssertEqual(saved?.folders.count, 1, "Using an existing folder must not create another folder.")
        existing.board.cancelDrag(animated: false)
    }

    /// Dropping on another application keeps the dragged icon visible from the release until it
    /// shrinks into the new folder's thumbnail.
    func testDroppingOnAnApplicationKeepsTheDraggedIconVisibleUntilItShrinks() throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B", "C"]])
        let a = try fixture.record("A")
        let page = try XCTUnwrap(fixture.board.pager.pages.first)
        let cell = page.itemLayers[0]
        let image = try icon()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cell.iconLayer.contents = image
        CATransaction.commit()
        let target = fixture.iconCenter(of: page.itemLayers[1])
        XCTAssertTrue(fixture.board.beginDrag(of: .app(a), cell: cell))
        fixture.board.drag?.follow(to: target)

        fixture.board.drag?.drop(center: target, groupTarget: fixture.board.pages[0][1])

        XCTAssertFalse(Self.visibleLayers(in: fixture.host).filter { ($0.contents as AnyObject?) === image }.isEmpty,
                       "The dragged icon is still shown right after the release")
        ClassicalFolderTestBoard.waitUntil { fixture.board.drag == nil }
    }

    /// Dropping on an application puts both icons inside the new folder cell at once; the target
    /// minimizes first and the dragged icon 0.1 s later, and once both have finished the thumbnails
    /// show and the temporary icon images are gone.
    func testDroppingOnAnApplicationMinimizesBothIconsInsideTheNewFolderCell() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([["A", "B", "C"]])
        // Core Animation runs implicit animations only for layers shown in a window.
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: fixture.content)
        defer { panel.close() }
        let page = try XCTUnwrap(fixture.board.pager.pages.first)
        let draggedCell = page.itemLayers[0], targetCell = page.itemLayers[1]
        let draggedImage = try icon(red: 0.9), targetImage = try icon(red: 0.1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        draggedCell.iconLayer.contents = draggedImage
        targetCell.iconLayer.contents = targetImage
        CATransaction.commit()
        let target = fixture.iconCenter(of: targetCell)
        XCTAssertTrue(fixture.board.beginDrag(of: .app(try fixture.record("A")), cell: draggedCell))
        fixture.board.drag?.follow(to: target)
        XCTAssertEqual(ClassicalDragParameters.groupDropStagger, 0.1)

        let dropped = Date()
        fixture.board.drag?.drop(center: target, groupTarget: fixture.board.pages[0][1])

        let folderID = try XCTUnwrap(fixture.board.pages.first?.first?.folder?.id)
        let folderCell = try XCTUnwrap(fixture.board.groupDragSession.rootFolderCell(folderID))
        let draggedCopy = try XCTUnwrap(Self.layers(in: folderCell).first { ($0.contents as AnyObject?) === draggedImage },
                                        "The dragged icon is inside the new folder cell")
        let targetCopy = try XCTUnwrap(Self.layers(in: folderCell).first { ($0.contents as AnyObject?) === targetImage },
                                       "The target icon is inside the new folder cell")
        XCTAssertTrue(Self.visibleLayers(in: fixture.host).contains { $0 === draggedCopy }, "The dragged icon stays visible")
        XCTAssertFalse(CATransform3DIsIdentity(targetCopy.transform), "The target starts shrinking at the drop")
        XCTAssertTrue(CATransform3DIsIdentity(draggedCopy.transform), "The dragged icon waits")

        ClassicalFolderTestBoard.waitUntil { !CATransform3DIsIdentity(draggedCopy.transform) }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(dropped), ClassicalDragParameters.groupDropStagger - 0.01)
        XCTAssertTrue(Self.visibleLayers(in: fixture.host).contains { $0 === draggedCopy },
                      "The dragged icon is still shown inside the folder cell while it shrinks")
        XCTAssertFalse(draggedCopy.animationKeys()?.isEmpty ?? true, "The dragged icon animates its shrink")

        ClassicalFolderTestBoard.waitUntil {
            draggedCopy.superlayer == nil && targetCopy.superlayer == nil && fixture.board.drag == nil
        }
        let shownCell = try XCTUnwrap(fixture.board.groupDragSession.rootFolderCell(folderID))
        XCTAssertEqual(shownCell.thumbnailLayers.prefix(2).map(\.opacity), [1, 1], "Both thumbnails show")
        XCTAssertTrue(Self.layers(in: fixture.host).filter { $0 !== draggedCell.iconLayer && $0 !== targetCell.iconLayer }
            .allSatisfy { ($0.contents as AnyObject?) !== draggedImage && ($0.contents as AnyObject?) !== targetImage },
                      "The temporary icon images are gone")
        fixture.board.folders.close(animated: false)
    }

    /// Hovering opens an existing folder with the dragged application added to the folder page on
    /// screen; pages turn inside a saved folder.
    func testHoverOpeningAFolderAddsTheItemToItsCurrentPage() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"], ["D"]])]])
        let cell = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(fixture.board.beginDrag(of: .app(try fixture.record("A")), cell: cell))

        fixture.board.drag?.enterGroup(target: fixture.board.pages[0][1])

        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        XCTAssertEqual(folder.pager.currentPage, 0)
        XCTAssertEqual(folder.content.pages.map { $0.map(\.metadata.displayName) }, [["B", "C", "A"], ["D"]])
        XCTAssertEqual(fixture.board.drag?.changePage(direction: 1), true)
        XCTAssertEqual(folder.content.pages.map { $0.map(\.metadata.displayName) }, [["B", "C"], ["D", "A"]])
        fixture.board.cancelDrag(animated: false)
    }

    func testHoverOpeningAFullFolderMovesTheDraggedItemToItsNextPage() throws {
        let names = (0..<35).map { String(format: "App %02d", $0) }
        let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956),
                                                    dock: .bottom(extent: 59), rows: 5, columns: 7)
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Full", [names])]], geometry: geometry)
        let cell = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(fixture.board.beginDrag(of: .app(try fixture.record("A")), cell: cell))

        fixture.board.drag?.enterGroup(target: fixture.board.pages[0][1])

        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        XCTAssertEqual(folder.content.pages.map(\.count), [35, 1])
        XCTAssertEqual(folder.content.pages[1].first?.metadata.displayName, "A")
        XCTAssertEqual(folder.pager.currentPage, 1)
        XCTAssertEqual(fixture.board.drag?.changePage(direction: -1), true)
        XCTAssertEqual(folder.content.pages[0].last?.metadata.displayName, "A")
        fixture.board.cancelDrag(animated: false)
    }

    /// A folder opened by hovering has room for the dragged item: when its applications fill whole
    /// rows the panel has one more row than the same folder opened by a click.
    func testHoverOpenedPanelAddsARowForTheDraggedItem() throws {
        let geometry = ClassicalSpringboardGeometry(screenSize: ClassicalFolderTestBoard.geometry.screenSize,
                                                    dock: .bottom(extent: 59), rows: 4, columns: 3)
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C", "D"]])]], geometry: geometry)
        XCTAssertEqual(try fixture.open("Work").geometry.rows, 1)
        fixture.board.folders.close(animated: false)

        let cell = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(fixture.board.beginDrag(of: .app(try fixture.record("A")), cell: cell))
        fixture.board.drag?.enterGroup(target: fixture.board.pages[0][1])

        XCTAssertEqual(try XCTUnwrap(fixture.board.folders.openFolder).geometry.rows, 2)
        fixture.board.cancelDrag(animated: false)
    }

    private func icon(red: CGFloat = 0.2) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try XCTUnwrap(context.makeImage())
    }

    /// Every layer under `root` that is drawn: neither it nor an ancestor below `root` is hidden or
    /// fully transparent.
    private static func layers(in root: CALayer) -> [CALayer] {
        (root.sublayers ?? []).flatMap { [$0] + layers(in: $0) }
    }

    private static func visibleLayers(in root: CALayer) -> [CALayer] {
        (root.sublayers ?? []).filter { !$0.isHidden && $0.opacity > 0 }.flatMap { [$0] + visibleLayers(in: $0) }
    }
}
