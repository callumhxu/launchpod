import AppKit
import XCTest
@testable import Launchpod

/// The dragged item's moves through the arrangement, its drop and its cancel, driven through the
/// springboard's drag entry points.
@MainActor
final class ClassicalDraggedItemTests: XCTestCase {
    func testDragMovesTheSlotAndTheDropCommitsTheArrangement() throws {
        let fixture = try ClassicalDragTestBoard([["A", "B", "C"], ["D"]])
        let board = fixture.board
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0) }
        let page = try XCTUnwrap(board.pager.pages.first)
        let cells = page.itemLayers
        XCTAssertTrue(board.beginDrag(of: board.pages[0][0], cell: cells[0]))
        XCTAssertTrue(cells[0].superlayer === fixture.host, "The dragged cell leaves its page for the drag layer")
        XCTAssertTrue(cells[0].isMagnified)

        XCTAssertEqual(board.drag?.moveToSlot(center: fixture.center(page: 0, slot: 2)), true)
        XCTAssertEqual(fixture.names, [["B", "C", "A"], ["D"]])
        XCTAssertTrue(page.itemLayers[0] === cells[1] && page.itemLayers[1] === cells[2], "Other cells keep their layers")
        XCTAssertEqual(cells[1].frame, ClassicalDragTestBoard.geometry.grid.cellFrame(at: 0), "B slides into A's old slot")
        XCTAssertEqual(board.drag?.moveToSlot(center: fixture.center(page: 0, slot: 2)), false, "The same slot changes nothing")

        board.drag?.drop(center: fixture.center(page: 0, slot: 2))
        ClassicalDragTestBoard.waitUntil { board.drag == nil }
        XCTAssertTrue(cells[0].superlayer === page.layer, "The cell rejoins its page")
        XCTAssertFalse(cells[0].isMagnified)
        XCTAssertEqual(committed.map { fixture.names($0) }, [[["B", "C", "A"], ["D"]]])
    }

    /// A closed folder on a root page is dragged like an application: the whole folder moves, and the
    /// saved arrangement keeps its title and pages.
    func testDraggingAClosedFolderMovesTheWholeFolder() async throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"], ["D"]]), "E"]])
        let board = fixture.board
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClassicalLayoutStore(directoryURL: directory)
        try await store.save(ClassicalLayout(pages: board.pages.map { $0.map(\.layoutItem) }))
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0); model.commit($0) }

        XCTAssertTrue(board.beginDrag(of: board.pages[0][1], cell: try fixture.folderCell("Work")))
        let frame = ClassicalFolderTestBoard.geometry.grid.cellFrame(at: 2)
        var target = fixture.background.convert(CGPoint(x: frame.midX, y: frame.midY), from: board.pager.pages[0].layer)
        target.x += 10 // Past the current slot's half-cell hysteresis boundary.
        XCTAssertEqual(board.drag?.moveToSlot(center: target), true)
        XCTAssertEqual(ClassicalDragTestBoard.names(board.pages), [["A", "E", "Work"]])
        board.drag?.drop(center: target)
        ClassicalDragTestBoard.waitUntil { !committed.isEmpty }
        XCTAssertEqual(committed.count, 1)

        await model.flush()
        let saved = try await store.load()
        let slots = try XCTUnwrap(saved?.pages.first)
        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(slots[0].app, try fixture.record("A").id)
        XCTAssertEqual(slots[1].app, try fixture.record("E").id)
        let folder = try XCTUnwrap(slots[2].folder)
        XCTAssertEqual(folder.id, try fixture.folderID("Work"))
        XCTAssertEqual(folder.title, "Work")
        XCTAssertEqual(folder.pages, [[try fixture.record("B").id, try fixture.record("C").id], [try fixture.record("D").id]])
    }

    func testDroppingIntoLaterFolderPageMinimizesTowardLastFirstPageThumbnail() throws {
        let firstPage = (1...9).map { "App \($0)" }
        let fixture = try ClassicalFolderTestBoard([["Dragged", .folder("Work", [firstPage, ["Later"]])]])
        let board = fixture.board
        let dragged = try fixture.record("Dragged")
        let target = try XCTUnwrap(board.pages.first?.last)
        let draggedCell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        let targetCell = try fixture.folderCell("Work")
        var committed: [ClassicalLayout] = []
        board.folderDragDidChange = { committed.append($0) }
        let icon = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        draggedCell.iconLayer.contents = icon
        CATransaction.commit()
        XCTAssertTrue(board.beginDrag(of: .app(dragged), cell: draggedCell))
        board.groupVisuals.hover(target: targetCell, dragged: draggedCell, slow: false)
        XCTAssertEqual(targetCell.miniGridLayer.bounds.origin.y, -targetCell.geometry.miniCellSize.height,
                       "Hover exposes the available thumbnail row before release")

        board.drag?.drop(center: fixture.iconCenter(of: targetCell), groupTarget: target)

        let folder = try fixture.folderCell("Work")
        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(committed[0].folder(try fixture.folderID("Work"))?.pages.last?.last, dragged.id)
        XCTAssertEqual(folder.thumbnailRecords.map(\.metadata.displayName), firstPage)
        XCTAssertEqual(folder.thumbnailLayers.count, firstPage.count)
        XCTAssertEqual(folder.miniGridLayer.bounds.origin.y, -folder.geometry.miniCellSize.height,
                       "The hovered preview remains scrolled while the proxy flies toward its thumbnail")
        XCTAssertTrue(folder.thumbnailLayers.dropLast().allSatisfy { $0.opacity == 1 })
        XCTAssertEqual(folder.thumbnailLayers.last?.opacity, 0,
                       "The proxy targets the mini grid's last first-page layer while minimizing")
        let proxies = { (folder.sublayers ?? []).filter { ($0.contents as AnyObject?) === icon } }
        XCTAssertEqual(proxies().count, 1, "The dragged image has a temporary minimizing layer in the folder cell")

        ClassicalFolderTestBoard.waitUntil { folder.thumbnailLayers.last?.opacity == 1 && proxies().isEmpty }
        XCTAssertEqual(folder.miniGridLayer.bounds.origin.y, -folder.geometry.miniCellSize.height,
                       "The thumbnail grid scrolls to the available row after the proxy finishes")
        XCTAssertEqual(folder.thumbnailLayers.last?.opacity, 1)
        XCTAssertTrue(proxies().isEmpty, "The proxy leaves the layer tree after the thumbnail is revealed")
    }

    func testReorderingInsideAnOpenFolderCommitsOnlyThatFoldersMemberOrder() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B", "C"]]), "D"]])
        let folder = try fixture.open("Work")
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        let a = try fixture.record("A")
        let c = try fixture.record("C")
        let cell = try XCTUnwrap(folder.cell(for: a.id))
        XCTAssertTrue(fixture.board.beginDrag(of: .app(a), cell: cell))

        XCTAssertEqual(fixture.board.drag?.moveToSlot(center: fixture.iconCenter(of: try XCTUnwrap(folder.cell(for: c.id)))), true)
        XCTAssertEqual(folder.content.pages.map { $0.map(\.metadata.displayName) }, [["B", "C", "A"]])
        fixture.board.drag?.drop(center: fixture.iconCenter(of: cell))

        ClassicalFolderTestBoard.waitUntil { fixture.board.drag == nil && committed.count == 1 }
        XCTAssertEqual(committed[0].folder(try fixture.folderID("Work"))?.pages,
                       [[try fixture.record("B").id, c.id, a.id]])
        XCTAssertEqual(committed[0].pages.first?.last?.app, try fixture.record("D").id)
    }

    func testDraggingAcrossFolderPagesLeavesRootPageUnchanged() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B", "C", "D", "E", "F"], ["G"]]), "H"]])
        let folder = try fixture.open("Work")
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        let a = try fixture.record("A")
        let cell = try XCTUnwrap(folder.cell(for: a.id))
        XCTAssertTrue(fixture.board.beginDrag(of: .app(a), cell: cell))

        XCTAssertEqual(fixture.board.drag?.changePage(direction: 1), true)
        XCTAssertEqual(folder.pager.currentPage, 1)
        XCTAssertEqual(fixture.board.pager.currentPage, 0)
        XCTAssertEqual(folder.content.pages.map { $0.map(\.metadata.displayName) },
                       [["B", "C", "D", "E", "F"], ["G", "A"]])
        fixture.board.drag?.drop(center: fixture.iconCenter(of: cell))

        ClassicalFolderTestBoard.waitUntil { fixture.board.drag == nil && committed.count == 1 }
        let firstPage = try ["B", "C", "D", "E", "F"].map { try fixture.record($0).id }
        XCTAssertEqual(committed[0].folder(try fixture.folderID("Work"))?.pages,
                       [firstPage, [try fixture.record("G").id, a.id]])
        XCTAssertEqual(committed[0].pages.first?.last?.app, try fixture.record("H").id)
    }

    func testDraggingOutOfAnExistingFolderKeepsItsRemainingMember() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        let folder = try fixture.open("Work")
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        let a = try fixture.record("A")
        let cell = try XCTUnwrap(folder.cell(for: a.id))
        XCTAssertTrue(fixture.board.beginDrag(of: .app(a), cell: cell))

        try leaveFolder(fixture)
        XCTAssertNil(fixture.board.folders.openFolder)
        fixture.board.drag?.drop(center: .zero)

        ClassicalFolderTestBoard.waitUntil { fixture.board.drag == nil && committed.count == 1 }
        XCTAssertEqual(committed[0].folder(try fixture.folderID("Work"))?.pages,
                       [[try fixture.record("B").id]], "An existing folder is allowed to keep one app")
        XCTAssertEqual(committed[0].pages.first?.compactMap(\.app),
                       [try fixture.record("C").id, a.id])
    }

    func testDraggingOutOfANewlyCreatedTwoAppFolderDissolvesIt() throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B", "C"]])
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        let a = try fixture.record("A")
        let b = try fixture.record("B")
        let cell = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(fixture.board.beginDrag(of: .app(a), cell: cell))
        fixture.board.drag?.enterGroup(target: .app(b))
        XCTAssertNotNil(fixture.board.folders.openFolder)

        try leaveFolder(fixture)
        fixture.waitUntilClosed()
        fixture.board.drag?.drop(center: .zero)

        ClassicalFolderTestBoard.waitUntil { fixture.board.drag == nil && committed.count == 1 }
        let saved = try XCTUnwrap(committed.first)
        XCTAssertTrue(saved.folders.isEmpty)
        XCTAssertEqual(saved.pages.first?.compactMap(\.app), [b.id, try fixture.record("C").id, a.id])
    }

    func testDragOutAfterEmptiedFolderPageDropsTheEmptyPage() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A"], ["B", "C"]]), "D"]])
        let folder = try fixture.open("Work")
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        let a = try fixture.record("A")
        let cell = try XCTUnwrap(folder.cell(for: a.id))
        XCTAssertTrue(fixture.board.beginDrag(of: .app(a), cell: cell))
        XCTAssertEqual(fixture.board.drag?.changePage(direction: 1), true)
        XCTAssertTrue(folder.content.pages.first?.isEmpty == true, "The source page empties while dragging")

        try leaveFolder(fixture)
        fixture.board.drag?.drop(center: .zero)

        ClassicalFolderTestBoard.waitUntil { fixture.board.drag == nil && committed.count == 1 }
        XCTAssertEqual(committed[0].folder(try fixture.folderID("Work"))?.pages,
                       [[try fixture.record("B").id, try fixture.record("C").id]])
        XCTAssertEqual(committed[0].pages.first?.compactMap(\.app),
                       [try fixture.record("D").id, a.id])
    }

    func testCancellingDragOutAfterEmptiedFolderPageRestoresOriginalPages() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A"], ["B", "C"]]), "D"]])
        let folder = try fixture.open("Work")
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        let a = try fixture.record("A")
        let cell = try XCTUnwrap(folder.cell(for: a.id))
        XCTAssertTrue(fixture.board.beginDrag(of: .app(a), cell: cell))
        XCTAssertEqual(fixture.board.drag?.changePage(direction: 1), true)
        try leaveFolder(fixture)

        fixture.board.cancelDrag(animated: false)

        ClassicalFolderTestBoard.waitUntil { fixture.board.drag == nil }
        XCTAssertTrue(committed.isEmpty)
        let restored = try XCTUnwrap(fixture.board.pages.first?.first?.folder)
        XCTAssertEqual(restored.pages.map { $0.map(\.metadata.displayName) }, [["A"], ["B", "C"]])
        XCTAssertEqual(fixture.board.pages.first?.last?.record?.id, try fixture.record("D").id)
    }

    func testChangingPageAppendsToTheNeighbourAndCreatesAPagePastTheLast() throws {
        let fixture = try ClassicalDragTestBoard([["A", "B", "C"], ["D"]])
        let board = fixture.board
        let cells = try XCTUnwrap(board.pager.pages.first?.itemLayers)
        XCTAssertTrue(board.beginDrag(of: board.pages[0][1], cell: cells[1]))
        XCTAssertNil(board.drag?.edge(center: CGPoint(x: ClassicalDragTestBoard.geometry.pageFrame.midX, y: ClassicalDragTestBoard.geometry.pageFrame.midY)))
        XCTAssertEqual(board.drag?.edge(center: CGPoint(x: ClassicalDragTestBoard.geometry.pageFrame.minX - 1, y: 300)), -1)
        XCTAssertEqual(board.drag?.edge(center: CGPoint(x: ClassicalDragTestBoard.geometry.pageFrame.maxX + 1, y: 300)), 1)
        XCTAssertEqual(board.drag?.changePage(direction: -1), false, "No page before the first")
        XCTAssertEqual(board.drag?.changePage(direction: 1), true)
        XCTAssertEqual(fixture.names, [["A", "C"], ["D", "B"]])
        XCTAssertEqual(board.pager.currentPage, 1)
        XCTAssertEqual(board.drag?.changePage(direction: 1), true, "Past the last page a new page opens")
        XCTAssertEqual(fixture.names, [["A", "C"], ["D"], ["B"]])
        XCTAssertEqual(board.drag?.changePage(direction: 1), false, "An item alone on its page opens no further page")
        board.cancelDrag(animated: false)
        XCTAssertEqual(fixture.names, [["A", "B", "C"], ["D"]], "Cancelling restores the arrangement")
        XCTAssertEqual(board.pager.currentPage, 0)
        XCTAssertTrue(cells[1].superlayer === board.pager.pages[0].layer)
    }

    /// A full page takes the dragged item past its capacity; the drop pushes the last item on.
    func testDropOnAFullPagePushesTheLastItemToTheNextPage() throws {
        let fixture = try ClassicalDragTestBoard([["A", "B", "C", "D", "E", "F"], ["G"]])
        let board = fixture.board
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0) }
        let cells = try XCTUnwrap(board.pager.pages.last?.itemLayers)
        XCTAssertTrue(board.beginDrag(of: board.pages[1][0], cell: cells[0]))
        XCTAssertEqual(board.drag?.changePage(direction: -1), true)
        XCTAssertEqual(fixture.names, [["A", "B", "C", "D", "E", "F", "G"], []], "The emptied page stays while dragging")
        XCTAssertTrue(board.pager.pages[0].itemLayers.count == 7 && board.pager.pages[0].itemLayers[6] === cells[0])
        board.drag?.drop(center: fixture.center(page: 0, slot: 0))
        ClassicalDragTestBoard.waitUntil { board.drag == nil }
        XCTAssertEqual(fixture.names, [["G", "A", "B", "C", "D", "E"], ["F"]])
        XCTAssertEqual(committed.count, 1)
    }

    func testDraggingASearchResultClearsSearchAndCommitsTheSameAppToANewSlot() throws {
        let fixture = try ClassicalDragTestBoard([["Calendar", "Safari", "Notes"]])
        let board = fixture.board
        let original = board.pages
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0) }
        board.search("saf")
        let result = try XCTUnwrap(board.pager.pages.first?.records.first)
        let resultCell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)

        XCTAssertTrue(board.beginDrag(of: .app(result), cell: resultCell))
        XCTAssertFalse(board.isFiltering, "Dragging a search result returns to the full arrangement")
        XCTAssertEqual(board.drag?.item.id, .app(result.id))
        XCTAssertTrue(board.drag?.cell === resultCell, "The grabbed icon remains attached to the drag")
        XCTAssertTrue(resultCell.superlayer === fixture.host)
        XCTAssertEqual(board.pager.pages.first?.items.map(\.id), original[0].map(\.id))

        var destination = fixture.center(page: 0, slot: 2)
        destination.x += 10 // Past the current slot's half-cell hysteresis boundary.
        XCTAssertEqual(board.drag?.moveToSlot(center: destination), true)
        board.drag?.drop(center: destination)
        ClassicalDragTestBoard.waitUntil { board.drag == nil }
        XCTAssertEqual(fixture.names, [["Calendar", "Notes", "Safari"]])
        XCTAssertEqual(committed.map { fixture.names($0) }, [[["Calendar", "Notes", "Safari"]]])
    }

    // MARK: Drop and cancel transactions

    /// The drop index is clamped to capacity − 1, so the item dropped below a full page's last row
    /// keeps a slot on that page and the previous last item overflows instead of the dropped one.
    func testDropBelowAFullPageKeepsTheItemOnItsLastSlotAndPushesThePreviousLastItemOn() throws {
        let fixture = try ClassicalDragTestBoard([["A", "B", "C", "D", "E", "F"], ["G"]])
        let board = fixture.board
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0) }
        let dragged = try XCTUnwrap(board.pager.pages.last?.itemLayers.first)
        XCTAssertTrue(board.beginDrag(of: board.pages[1][0], cell: dragged))
        XCTAssertEqual(board.drag?.changePage(direction: -1), true)
        let lastColumn = ClassicalDragTestBoard.geometry.grid.cellFrame(at: 5)
        let belowTheGrid = fixture.host.convert(CGPoint(x: lastColumn.midX, y: -10), from: board.pager.pages[0].layer)
        board.drag?.follow(to: belowTheGrid)

        board.drag?.drop(center: belowTheGrid)

        XCTAssertEqual(fixture.names, [["A", "B", "C", "D", "E", "G"], ["F"]])
        ClassicalDragTestBoard.waitUntil { board.drag == nil }
        XCTAssertEqual(committed.map { fixture.names($0) }, [[["A", "B", "C", "D", "E", "G"], ["F"]]])
    }

    /// Empty pages are removed right after the drag ends, before any drop animation finishes.
    func testAPageEmptiedByTheDragIsRemovedWhenTheItemIsDropped() throws {
        let fixture = try ClassicalDragTestBoard([["A", "B"], ["C"]])
        let board = fixture.board
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0) }
        let dragged = try XCTUnwrap(board.pager.pages.last?.itemLayers.first)
        XCTAssertTrue(board.beginDrag(of: board.pages[1][0], cell: dragged))
        XCTAssertEqual(board.drag?.changePage(direction: -1), true)
        XCTAssertEqual(fixture.names, [["A", "B", "C"], []])

        board.drag?.drop(center: fixture.center(page: 0, slot: 2))

        XCTAssertEqual(fixture.names, [["A", "B", "C"]], "The empty page goes at drop time")
        XCTAssertEqual(board.pager.pageCount, 1)
        ClassicalDragTestBoard.waitUntil { board.drag == nil }
        XCTAssertEqual(committed.map { fixture.names($0) }, [[["A", "B", "C"]]])
    }

    /// Removing empty pages keeps the current page number and only clamps it to the last
    /// remaining page, so removing an empty page before the current one brings the following page
    /// into view.
    func testRemovingAnEmptyPageBeforeTheCurrentOneKeepsTheCurrentPageNumber() throws {
        let fixture = try ClassicalDragTestBoard([["A"], ["B", "C"], ["D"]])
        let board = fixture.board
        let dragged = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(board.beginDrag(of: board.pages[0][0], cell: dragged))
        XCTAssertEqual(board.drag?.changePage(direction: 1), true)
        XCTAssertEqual(fixture.names, [[], ["B", "C", "A"], ["D"]])
        XCTAssertEqual(board.pager.currentPage, 1)

        board.drag?.drop(center: fixture.center(page: 1, slot: 2))

        XCTAssertEqual(fixture.names, [["B", "C", "A"], ["D"]])
        XCTAssertEqual(board.pager.currentPage, 1, "The page number stays, so the former next page shows")
        ClassicalDragTestBoard.waitUntil { board.drag == nil }
        XCTAssertEqual(board.pager.currentPage, 1)
    }

    func testRemovingAnEmptyPageClampsTheCurrentPageToTheLastRemainingPage() throws {
        let fixture = try ClassicalDragTestBoard([["A"], ["B"]])
        let board = fixture.board
        let dragged = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(board.beginDrag(of: board.pages[0][0], cell: dragged))
        XCTAssertEqual(board.drag?.changePage(direction: 1), true)
        XCTAssertEqual(board.pager.currentPage, 1)

        board.drag?.drop(center: fixture.center(page: 1, slot: 1))

        XCTAssertEqual(fixture.names, [["B", "A"]])
        XCTAssertEqual(board.pager.pageCount, 1)
        XCTAssertEqual(board.pager.currentPage, 0, "Past the last page the number clamps to it")
        ClassicalDragTestBoard.waitUntil { board.drag == nil }
        XCTAssertEqual(board.pager.currentPage, 0)
    }

    /// Phase 1 of the drop undarkens the icon with actions disabled, un-magnifies it and re-lays out
    /// the other cells with the implicit animation, and leaves the dragged layer where it was
    /// dropped. Only its completion puts the icon back in its page, keeping its frame, and then
    /// slides it into the slot.
    func testDropSettlesTheOtherCellsBeforeTheIconRejoinsItsPageAndSlidesHome() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let view = NSView(frame: CGRect(origin: .zero, size: ClassicalDragTestBoard.geometry.screenSize))
        view.wantsLayer = true
        let window = NativeAppTestSupport.makeKeyPanel(size: view.frame.size, contentView: view)
        defer { window.close() }
        let fixture = try ClassicalDragTestBoard([["A", "B", "C", "D", "E", "F"], ["G"]], host: try XCTUnwrap(view.layer))
        let board = fixture.board
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0) }
        let dragged = try XCTUnwrap(board.pager.pages.last?.itemLayers.first)
        dragged.setDarkened(true) // The pressed look carried into the drag.
        XCTAssertTrue(board.beginDrag(of: board.pages[1][0], cell: dragged))
        XCTAssertEqual(board.drag?.changePage(direction: -1), true)
        let firstSlot = fixture.center(page: 0, slot: 0)
        let dropped = CGPoint(x: firstSlot.x + 12, y: firstSlot.y - 9)
        board.drag?.follow(to: dropped)
        let others = Array(board.pager.pages[0].itemLayers.prefix(6))
        XCTAssertFalse(others.contains { $0 === dragged })
        removeAnimations(from: others + [dragged])

        board.drag?.drop(center: dropped)

        XCTAssertFalse(dragged.isDarkened, "Undarkened at mouse-up")
        XCTAssertNil(dragged.iconLayer.animation(forKey: "filters"), "Undarkening is not animated")
        XCTAssertFalse(dragged.isMagnified)
        XCTAssertTrue(dragged.superlayer === fixture.host, "The icon stays above the pages during the re-layout")
        XCTAssertEqual(dragged.position, dropped, "The re-layout transaction does not move the dragged icon")
        XCTAssertNil(dragged.animation(forKey: "position"))
        XCTAssertNotNil(others[0].animation(forKey: "position"), "A slides to slot 1 with the implicit animation")

        ClassicalDragTestBoard.waitUntil { dragged.superlayer === board.pager.pages[0].layer }
        let slot = ClassicalDragTestBoard.geometry.grid.cellFrame(at: 0)
        XCTAssertEqual(dragged.position, CGPoint(x: slot.midX, y: slot.midY))
        XCTAssertNotNil(dragged.animation(forKey: "position"),
                        "Once back in its page the icon slides from where it was dropped into its slot")
        ClassicalDragTestBoard.waitUntil { board.drag == nil }
        XCTAssertEqual(committed.map { fixture.names($0) }, [[["G", "A", "B", "C", "D", "E"], ["F"]]])
    }

    /// In deleting mode the drop completes like any other and the landed icon jitters again only
    /// after it is home. The other cells keep jittering throughout, which must not hold back the
    /// end of the drop.
    func testDropInDeletingModeLandsAndThenTheIconJittersAgain() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let view = NSView(frame: CGRect(origin: .zero, size: ClassicalDragTestBoard.geometry.screenSize))
        view.wantsLayer = true
        let window = NativeAppTestSupport.makeKeyPanel(size: view.frame.size, contentView: view)
        defer { window.close() }
        let fixture = try ClassicalDragTestBoard([["A", "B", "C"]], host: try XCTUnwrap(view.layer))
        let board = fixture.board
        board.setDeleting(true)
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0) }
        let dragged = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(board.beginDrag(of: board.pages[0][0], cell: dragged))
        XCTAssertFalse(dragged.isJittering)
        var destination = fixture.center(page: 0, slot: 2)
        destination.x += 10 // Past the current slot's half-cell hysteresis boundary.
        board.drag?.follow(to: destination)
        XCTAssertEqual(board.drag?.moveToSlot(center: destination), true)
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        board.drag?.drop(center: destination)

        XCTAssertFalse(dragged.isJittering, "Jitter returns only after the icon is home")
        ClassicalDragTestBoard.waitUntil { board.drag == nil }
        XCTAssertTrue(dragged.superlayer === board.pager.pages[0].layer)
        XCTAssertTrue(dragged.isJittering)
        XCTAssertTrue(board.pager.pages[0].itemLayers.allSatisfy(\.isJittering))
        XCTAssertEqual(committed.map { fixture.names($0) }, [[["B", "C", "A"]]])
    }

    /// A drop that never changed the slot or page is a cancel with slide-back and no data-source
    /// update: nothing is committed, the arrangement and page stay, and the icon slides home at
    /// once, without a re-layout phase for the other cells.
    func testDropWithoutAnyMoveSlidesTheIconHomeWithoutCommitting() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let view = NSView(frame: CGRect(origin: .zero, size: ClassicalDragTestBoard.geometry.screenSize))
        view.wantsLayer = true
        let window = NativeAppTestSupport.makeKeyPanel(size: view.frame.size, contentView: view)
        defer { window.close() }
        let fixture = try ClassicalDragTestBoard([["A", "B", "C"], ["D"]], host: try XCTUnwrap(view.layer))
        let board = fixture.board
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0) }
        let dragged = try XCTUnwrap(board.pager.pages.first?.itemLayers[1])
        XCTAssertTrue(board.beginDrag(of: board.pages[0][1], cell: dragged))
        let home = fixture.center(page: 0, slot: 1)
        let nearby = CGPoint(x: home.x + 14, y: home.y - 11)
        board.drag?.follow(to: nearby)
        XCTAssertEqual(board.drag?.moveToSlot(center: nearby), false, "The pointer never leaves the slot")
        removeAnimations(from: board.pager.pages.flatMap(\.itemLayers) + [dragged])

        board.drag?.drop(center: nearby)

        XCTAssertNotNil(dragged.animation(forKey: "position"), "The icon slides home with the drop itself")
        XCTAssertFalse(dragged.isMagnified)
        for cell in board.pager.pages.flatMap(\.itemLayers) where cell !== dragged {
            XCTAssertNil(cell.animation(forKey: "position"), "No re-layout of the other cells")
            XCTAssertNil(cell.animation(forKey: "bounds"))
        }
        ClassicalDragTestBoard.waitUntil { board.drag == nil }
        XCTAssertEqual(fixture.names, [["A", "B", "C"], ["D"]])
        XCTAssertEqual(board.pager.currentPage, 0)
        XCTAssertTrue(dragged.superlayer === board.pager.pages[0].layer)
        XCTAssertEqual(dragged.frame, ClassicalDragTestBoard.geometry.grid.cellFrame(at: 1))
        XCTAssertTrue(committed.isEmpty, "An unmoved drop saves nothing")
    }

    /// Cancelling after moves reloads the saved arrangement with actions disabled and turns to the
    /// page holding the item; only the dragged icon animates home. Nothing is saved.
    func testCancelAfterCrossingPagesSnapsOthersBackAndReturnsToTheItemsPageWithoutSaving() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let view = NSView(frame: CGRect(origin: .zero, size: ClassicalDragTestBoard.geometry.screenSize))
        view.wantsLayer = true
        let window = NativeAppTestSupport.makeKeyPanel(size: view.frame.size, contentView: view)
        defer { window.close() }
        let fixture = try ClassicalDragTestBoard([["A", "B", "C"], ["D"]], host: try XCTUnwrap(view.layer))
        let board = fixture.board
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0) }
        let dragged = try XCTUnwrap(board.pager.pages.first?.itemLayers[1])
        XCTAssertTrue(board.beginDrag(of: board.pages[0][1], cell: dragged))
        XCTAssertEqual(board.drag?.changePage(direction: 1), true)
        XCTAssertEqual(board.pager.currentPage, 1)
        var firstSlot = fixture.center(page: 1, slot: 0)
        firstSlot.x -= 10 // Past the current slot's half-cell hysteresis boundary.
        board.drag?.follow(to: firstSlot)
        XCTAssertEqual(board.drag?.moveToSlot(center: firstSlot), true)
        XCTAssertEqual(fixture.names, [["A", "C"], ["B", "D"]])
        removeAnimations(from: board.pager.pages.flatMap(\.itemLayers) + [dragged])

        board.cancelDrag()

        XCTAssertEqual(fixture.names, [["A", "B", "C"], ["D"]])
        XCTAssertEqual(board.pager.currentPage, 0, "The pager returns to the page holding the restored item")
        let others = board.pager.pages.flatMap(\.itemLayers).filter { $0 !== dragged }
        XCTAssertEqual(others.count, 3)
        for cell in others {
            XCTAssertNil(cell.animation(forKey: "position"), "Other cells snap back")
            XCTAssertNil(cell.animation(forKey: "bounds"))
        }
        XCTAssertNotNil(dragged.animation(forKey: "position"), "The dragged icon animates home")
        ClassicalDragTestBoard.waitUntil { board.drag == nil }
        XCTAssertTrue(dragged.superlayer === board.pager.pages[0].layer)
        XCTAssertEqual(dragged.frame, ClassicalDragTestBoard.geometry.grid.cellFrame(at: 1))
        XCTAssertFalse(dragged.isMagnified)
        XCTAssertTrue(committed.isEmpty, "A cancelled drag never reaches storage")
    }

    /// A drag from search results first clears the search and shows the item's page; cancelling
    /// returns to the page holding the item, not to the page shown before searching.
    func testCancellingADragStartedInSearchStaysOnThePageHoldingTheItem() throws {
        let fixture = try ClassicalDragTestBoard([["A", "B", "C", "D", "E", "F"], ["G", "Safari"], ["H"]])
        let board = fixture.board
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0) }
        board.pager.jump(to: 2)
        board.search("saf")
        let result = try XCTUnwrap(board.pager.pages.first?.records.first)
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(board.beginDrag(of: .app(result), cell: cell))
        XCTAssertEqual(board.pager.currentPage, 1)

        board.cancelDrag()

        XCTAssertEqual(board.pager.currentPage, 1)
        ClassicalDragTestBoard.waitUntil { board.drag == nil }
        XCTAssertEqual(board.pager.currentPage, 1)
        XCTAssertFalse(board.isFiltering)
        XCTAssertEqual(fixture.names, [["A", "B", "C", "D", "E", "F"], ["G", "Safari"], ["H"]])
        XCTAssertTrue(cell.superlayer === board.pager.pages[1].layer)
        XCTAssertTrue(committed.isEmpty)
    }

    // MARK: Helpers

    /// Clears animations left by earlier steps and commits the layer tree, so implicit actions
    /// apply to the step under test as they do to layers already on screen.
    private func removeAnimations(from cells: [ClassicalItemLayer]) {
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        for cell in cells {
            cell.removeAllAnimations()
            cell.transformLayer.removeAllAnimations()
            cell.iconLayer.removeAllAnimations()
        }
    }

    // MARK: Folders

    /// A folder opened by hovering only closes again once the dragged icon has been over its
    /// backdrop and then left it.
    func testAHoverOpenedFolderClosesOnlyAfterTheIconHasEnteredIt() throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B", "C"]])
        let a = try fixture.record("A")
        let cell = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(fixture.board.beginDrag(of: .app(a), cell: cell))
        fixture.board.drag?.follow(to: .zero)
        fixture.board.drag?.enterGroup(target: .app(try fixture.record("B")))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)

        XCTAssertEqual(fixture.board.drag?.leaveFolder(), false, "The icon has not entered the folder yet")
        XCTAssertTrue(fixture.board.folders.openFolder === folder)
        try leaveFolder(fixture)
        fixture.waitUntilClosed()
        fixture.board.cancelDrag(animated: false)
    }

    /// Escape after the item left its folder slides the icon back toward the closed folder's cell,
    /// shrinking it to the thumbnail's size and fading it to half opacity, before the drag ends
    /// with the saved arrangement.
    func testEscapeAfterLeavingAFolderSlidesTheIconIntoItsCell() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B", "C"]]), "D"]])
        let folder = try fixture.open("Work")
        let a = try fixture.record("A")
        let cell = try XCTUnwrap(folder.cell(for: a.id))
        XCTAssertTrue(fixture.board.beginDrag(of: .app(a), cell: cell))
        try leaveFolder(fixture)
        fixture.waitUntilClosed()

        fixture.board.cancelDrag(animated: true)

        let folderCell = try fixture.folderCell("Work")
        XCTAssertNotNil(cell.superlayer, "The icon is still on screen while it slides home")
        let home = fixture.host.convert(folderCell.position, from: folderCell.superlayer)
        let position = fixture.host.convert(cell.position, from: cell.superlayer)
        XCTAssertEqual(position.x, home.x, accuracy: 1)
        XCTAssertEqual(position.y, home.y, accuracy: 1)
        XCTAssertEqual(cell.opacity, 0.5)
        let shown = fixture.host.convert(cell.bounds, from: cell)
        let thumbnail = folderCell.thumbnailFrame(at: 0, in: fixture.host)
        XCTAssertEqual(shown.width, thumbnail.width, accuracy: 1, "The icon shrinks to the thumbnail's size")
        ClassicalFolderTestBoard.waitUntil { fixture.board.drag == nil }
        let restored = try XCTUnwrap(fixture.board.pages.first?.first?.folder)
        XCTAssertEqual(restored.pages.map { $0.map(\.metadata.displayName) }, [["A", "B", "C"]])
    }

    /// A drop inside a folder leaves no folder page over capacity: the extra application moves on
    /// to the next folder page.
    func testDropInsideAFolderPushesOverflowToTheNextFolderPage() throws {
        let first = ["A", "B", "C", "D", "E", "F"]
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [first, ["G"]]), "H"]])
        let folder = try fixture.open("Work")
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        let g = try fixture.record("G")
        let cell = try XCTUnwrap(folder.cell(for: g.id))
        XCTAssertTrue(fixture.board.beginDrag(of: .app(g), cell: cell))
        XCTAssertEqual(fixture.board.drag?.changePage(direction: -1), true)
        let capacity = folder.geometry.grid.capacity
        XCTAssertEqual(capacity, 6)

        fixture.board.drag?.drop(center: fixture.iconCenter(of: cell))

        ClassicalFolderTestBoard.waitUntil { fixture.board.drag == nil && committed.count == 1 }
        let saved = try XCTUnwrap(committed.first?.folder(try fixture.folderID("Work")))
        XCTAssertTrue(saved.pages.allSatisfy { $0.count <= capacity }, "\(saved.pages.map(\.count))")
        XCTAssertEqual(Set(saved.identities), Set(try (first + ["G"]).map { try fixture.record($0).id }))
        XCTAssertTrue(folder.content.pages.allSatisfy { $0.count <= capacity })
    }

    /// Pages do not turn inside a folder the hover has just created and nothing has saved yet.
    func testPagesDoNotTurnInsideAFolderCreatedByHover() throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B", "C"]])
        let cell = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(fixture.board.beginDrag(of: .app(try fixture.record("A")), cell: cell))
        fixture.board.drag?.enterGroup(target: .app(try fixture.record("B")))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)

        XCTAssertEqual(fixture.board.drag?.changePage(direction: 1), false)
        XCTAssertEqual(fixture.board.drag?.changePage(direction: -1), false)
        XCTAssertEqual(folder.content.pages.count, 1)
        XCTAssertEqual(folder.pager.currentPage, 0)
        fixture.board.cancelDrag(animated: false)
    }

    /// Moves the dragged item over the open folder's backdrop, where it stays in the folder, then
    /// off it, where it leaves.
    private func leaveFolder(_ fixture: ClassicalFolderTestBoard,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        fixture.board.drag?.follow(to: try fixture.openBackdropCenter())
        XCTAssertEqual(fixture.board.drag?.leaveFolder(), false, "Over the backdrop the item stays in the folder",
                       file: file, line: line)
        fixture.board.drag?.follow(to: .zero)
        XCTAssertEqual(fixture.board.drag?.leaveFolder(), true, "Off the backdrop the item leaves", file: file, line: line)
    }
}
