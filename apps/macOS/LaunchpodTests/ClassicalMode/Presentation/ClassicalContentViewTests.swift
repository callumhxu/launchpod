import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalContentViewTests: XCTestCase {
    func testDraggingAnApplicationFromAnOpenFolderStartsThroughTheContentView() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        let folder = try fixture.open("Work")
        let cell = try XCTUnwrap(folder.cell(for: fixture.record("A").id))
        let icon = cell.iconLayer.convert(cell.iconLayer.bounds, to: fixture.host)
        let start = CGPoint(x: icon.midX, y: icon.midY)
        let moved = CGPoint(x: start.x + ClassicalDragParameters.activationDistance + 1, y: start.y)

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: start, time: 0))
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: moved, time: 1))

        XCTAssertEqual(fixture.board.drag?.item.record?.id, try fixture.record("A").id)
        XCTAssertTrue(fixture.content.drag.isDragging)
        XCTAssertTrue(fixture.board.folders.openFolder === folder)
        fixture.content.drag.cancel(animated: false)
    }

    func testDroppingOnAnotherApplicationIconCreatesAFolderWithTargetFirst() throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B", "C"]])
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        let page = try XCTUnwrap(fixture.board.pager.pages.first)
        let start = fixture.iconCenter(of: page.itemLayers[0])
        let target = fixture.iconCenter(of: page.itemLayers[1])
        let activation = CGPoint(x: start.x + ClassicalDragParameters.activationDistance + 1, y: start.y)

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: start, time: 0))
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: activation, time: 1))
        let hover = try pointerForDraggedCenter(target, fixture: fixture, at: activation)
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: hover, time: 100))
        fixture.content.mouseUp(with: try fixture.mouse(.leftMouseUp, at: hover, time: 100.1))

        ClassicalFolderTestBoard.waitUntil { committed.count == 1 }
        let folder = try XCTUnwrap(committed[0].pages.first?.first?.folder)
        XCTAssertEqual(folder.pages, [[try fixture.record("B").id, try fixture.record("A").id]])
        XCTAssertEqual(committed[0].pages.first?.last?.app, try fixture.record("C").id)
        XCTAssertEqual(committed.count, 1, "The grouping is one committed drag transaction")
    }

    func testDroppingOnAClosedFolderAppendsToItsLastPage() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"], ["D"]]), "E"]])
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        let page = try XCTUnwrap(fixture.board.pager.pages.first)
        let start = fixture.iconCenter(of: page.itemLayers[0])
        let target = fixture.iconCenter(of: try fixture.folderCell("Work"))
        let activation = CGPoint(x: start.x + ClassicalDragParameters.activationDistance + 1, y: start.y)

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: start, time: 0))
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: activation, time: 1))
        let hover = try pointerForDraggedCenter(target, fixture: fixture, at: activation)
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: hover, time: 100))
        fixture.content.mouseUp(with: try fixture.mouse(.leftMouseUp, at: hover, time: 100.1))

        ClassicalFolderTestBoard.waitUntil { committed.count == 1 }
        let closedCell = try fixture.folderCell("Work")
        XCTAssertEqual(closedCell.thumbnailRecords.map(\.metadata.displayName), ["B", "C"],
                       "The thumbnails still show only the folder's first page")
        ClassicalFolderTestBoard.waitUntil { closedCell.thumbnailLayers.allSatisfy { $0.opacity == 1 } }
        let folder = try XCTUnwrap(committed[0].folder(try fixture.folderID("Work")))
        XCTAssertEqual(folder.pages, [[try fixture.record("B").id, try fixture.record("C").id],
                                    [try fixture.record("D").id, try fixture.record("A").id]])
        XCTAssertEqual(committed[0].pages.first?.last?.app, try fixture.record("E").id)
        XCTAssertEqual(committed.count, 1)
    }

    func testHoveringOnAnApplicationIconOpensANewFolderWithoutSavingBeforeDrop() async throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B", "C"]])
        var committed: [ClassicalLayout] = []
        fixture.board.layoutDidChange = { committed.append($0) }
        var delays: [TimeInterval] = []
        var gates: [CheckedContinuation<Void, Never>] = []
        fixture.content.drag.sleep = { delay in
            delays.append(delay)
            await withCheckedContinuation { gates.append($0) }
        }
        let page = try XCTUnwrap(fixture.board.pager.pages.first)
        let start = fixture.iconCenter(of: page.itemLayers[0])
        let target = fixture.iconCenter(of: page.itemLayers[1])
        let activation = CGPoint(x: start.x + ClassicalDragParameters.activationDistance + 1, y: start.y)

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: start, time: 0))
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: activation, time: 1))
        let hover = try pointerForDraggedCenter(target, fixture: fixture, at: activation)
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: hover, time: 100))
        try await waitUntilAsync { delays.contains(1.0) && !gates.isEmpty }
        XCTAssertTrue(committed.isEmpty, "Hovering alone does not write the changed layout")

        gates.removeFirst().resume()
        try await waitUntilAsync { fixture.board.folders.openFolder != nil }
        XCTAssertTrue(fixture.content.drag.isDragging, "The pointer still owns the dragged application")
        XCTAssertTrue(committed.isEmpty)
        fixture.content.drag.cancel(animated: false)
        try await waitUntilAsync { fixture.board.drag == nil && !fixture.board.folders.isActive }
        XCTAssertEqual(fixture.board.pages[0].compactMap(\.record?.id),
                       [try fixture.record("A").id, try fixture.record("B").id, try fixture.record("C").id],
                       "Escape restores the original root order after a hover created a temporary folder")
        let restored = try XCTUnwrap(fixture.board.cell(for: fixture.record("A").id))
        XCTAssertTrue(restored.superlayer === fixture.board.pager.pages[0].layer,
                      "The dragged cell lands back on its original root page")
        XCTAssertEqual(restored.position,
                       CGPoint(x: ClassicalFolderTestBoard.geometry.grid.cellFrame(at: 0).midX,
                               y: ClassicalFolderTestBoard.geometry.grid.cellFrame(at: 0).midY))
        XCTAssertTrue(committed.isEmpty, "The cancelled folder never reaches persistence")
        gates.forEach { $0.resume() }
    }

    func testDroppingAfterHoverOpenedANewFolderCommitsItsMembersOnce() async throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B", "C"]])
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        var gates: [CheckedContinuation<Void, Never>] = []
        fixture.content.drag.sleep = { _ in await withCheckedContinuation { gates.append($0) } }
        let page = try XCTUnwrap(fixture.board.pager.pages.first)
        let start = fixture.iconCenter(of: page.itemLayers[0])
        let target = fixture.iconCenter(of: page.itemLayers[1])
        let activation = CGPoint(x: start.x + ClassicalDragParameters.activationDistance + 1, y: start.y)

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: start, time: 0))
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: activation, time: 1))
        let hover = try pointerForDraggedCenter(target, fixture: fixture, at: activation)
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: hover, time: 100))
        try await waitUntilAsync { !gates.isEmpty }
        XCTAssertTrue(committed.isEmpty)
        gates.removeFirst().resume()
        try await waitUntilAsync { fixture.board.folders.openFolder != nil }

        fixture.content.mouseUp(with: try fixture.mouse(.leftMouseUp, at: hover, time: 101))
        try await waitUntilAsync { fixture.board.drag == nil && committed.count == 1 }
        XCTAssertEqual(committed[0].folders.first?.pages,
                       [[try fixture.record("B").id, try fixture.record("A").id]])
        XCTAssertEqual(committed[0].pages.first?.last?.app, try fixture.record("C").id)
        gates.forEach { $0.resume() }
    }

    /// The release ends the drag state that was last applied: a fast move off the hovered icon
    /// has not been evaluated yet when the button goes up, so the drop still groups with it.
    func testFastMoveOffAGroupTargetBeforeReleaseStillGroupsWithIt() throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B", "C"]])
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        let page = try XCTUnwrap(fixture.board.pager.pages.first)
        let start = fixture.iconCenter(of: page.itemLayers[0])
        let target = fixture.iconCenter(of: page.itemLayers[1])
        let emptyFrame = ClassicalFolderTestBoard.geometry.grid.cellFrame(at: 4)
        let empty = fixture.host.convert(CGPoint(x: emptyFrame.midX, y: emptyFrame.midY), from: page.layer)
        let activation = CGPoint(x: start.x + ClassicalDragParameters.activationDistance + 1, y: start.y)

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: start, time: 0))
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: activation, time: 1))
        let hover = try pointerForDraggedCenter(target, fixture: fixture, at: activation)
        let offTarget = try pointerForDraggedCenter(empty, fixture: fixture, at: activation)
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: hover, time: 100))
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: offTarget, time: 100.01))
        fixture.content.mouseUp(with: try fixture.mouse(.leftMouseUp, at: offTarget, time: 100.02))

        ClassicalFolderTestBoard.waitUntil { committed.count == 1 }
        let folder = try XCTUnwrap(committed.first?.pages.first?.first?.folder)
        XCTAssertEqual(folder.pages, [[try fixture.record("B").id, try fixture.record("A").id]])
    }

    func testFastMoveOffAGroupTargetCancelsItsPendingHoverOpen() async throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B", "C"]])
        var delays: [TimeInterval] = []
        var gates: [CheckedContinuation<Void, Never>] = []
        fixture.content.drag.sleep = { delay in
            delays.append(delay)
            await withCheckedContinuation { gates.append($0) }
        }
        let page = try XCTUnwrap(fixture.board.pager.pages.first)
        let start = fixture.iconCenter(of: page.itemLayers[0])
        let target = fixture.iconCenter(of: page.itemLayers[1])
        let emptyFrame = ClassicalFolderTestBoard.geometry.grid.cellFrame(at: 4)
        let empty = fixture.host.convert(CGPoint(x: emptyFrame.midX, y: emptyFrame.midY), from: page.layer)
        let activation = CGPoint(x: start.x + ClassicalDragParameters.activationDistance + 1, y: start.y)

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: start, time: 0))
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: activation, time: 1))
        let hover = try pointerForDraggedCenter(target, fixture: fixture, at: activation)
        let offTarget = try pointerForDraggedCenter(empty, fixture: fixture, at: activation)
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: hover, time: 100))
        try await waitUntilAsync { delays.contains(1.0) && !gates.isEmpty }
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: offTarget, time: 100.01))
        try await waitUntilAsync { gates.count == 2 }
        // The pointer rests off the icon (0.15 s) before the hover would open it (1 s).
        let hoverOpen = gates.removeFirst()
        gates.removeFirst().resume()
        try await Task.sleep(for: .milliseconds(50))
        hoverOpen.resume()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(fixture.board.folders.openFolder)
        XCTAssertTrue(fixture.board.pages.joined().allSatisfy { $0.folder == nil })
        fixture.content.drag.cancel(animated: false)
        gates.forEach { $0.resume() }
    }

    func testExternalDragSupportsTheDockAndTrash() {
        let operations = ClassicalContentView.externalDragOperations
        XCTAssertTrue(operations.contains(.copy))
        XCTAssertTrue(operations.contains(.link))
        XCTAssertTrue(operations.contains(.delete))
    }

    func testExternalDockDropRestoresTheOriginalArrangementWithoutCommittingAReorder() throws {
        let (content, board, records) = try externalDragFixture()
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0) }
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(content.drag.begin(.app(records[0]), cell: cell, at: cell.position, time: 0))
        XCTAssertEqual(board.drag?.moveToSlot(center: board.pager.pages[0].layer.convert(
            board.pager.pages[0].itemLayers[2].position, to: board.pager.layer.superlayer)), true)

        content.completeExternalDrag(record: records[0], operation: .link)

        XCTAssertNil(board.drag)
        XCTAssertEqual(board.pages[0].compactMap(\.record?.id), records.map(\.id))
        XCTAssertTrue(committed.isEmpty)
    }

    /// A Trash drop only asks, and only for a deletable application. The record stays until the
    /// user confirms.
    func testExternalTrashDropAsksForConfirmationBeforeRemovingADeletableRecord() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let (content, board, records) = try externalDragFixture()
        let window = NativeAppTestSupport.makeKeyPanel(size: content.frame.size, contentView: content)
        defer { window.close() }
        board.deletability.isDeletable = { _ in true }
        var deleted: [AppIdentity] = []
        content.deletion.didRemoveRecord = { deleted.append($0) }
        content.deletion.remove = { _ in }
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(content.drag.begin(.app(records[0]), cell: cell, at: cell.position, time: 0))

        content.completeExternalDrag(record: records[0], operation: .delete)

        XCTAssertNil(board.drag)
        XCTAssertTrue(content.deletion.isPanelShown, "A deletable application is confirmed first")
        XCTAssertEqual(board.records.map(\.id), records.map(\.id))
        XCTAssertTrue(deleted.isEmpty)
        content.deletion.dismiss()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(board.records.map(\.id), records.map(\.id), "Declining keeps the application")
        XCTAssertTrue(deleted.isEmpty)

        let restored = try XCTUnwrap(board.cell(for: records[0].id))
        XCTAssertTrue(content.drag.begin(.app(records[0]), cell: restored, at: restored.position, time: 1))
        content.completeExternalDrag(record: records[0], operation: .delete)
        content.deletion.panel?.confirm()
        try await waitUntilAsync { !board.records.contains { $0.id == records[0].id } }
        XCTAssertEqual(deleted, [records[0].id])
    }

    func testExternalTrashDropOfAnUndeletableRecordNeitherAsksNorRemoves() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let (content, board, records) = try externalDragFixture()
        let window = NativeAppTestSupport.makeKeyPanel(size: content.frame.size, contentView: content)
        defer { window.close() }
        board.deletability.isDeletable = { _ in false }
        var deleted: [AppIdentity] = []
        content.deletion.didRemoveRecord = { deleted.append($0) }
        var removals = 0
        content.deletion.remove = { _ in removals += 1 }
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(content.drag.begin(.app(records[0]), cell: cell, at: cell.position, time: 0))

        content.completeExternalDrag(record: records[0], operation: .delete)

        XCTAssertNil(board.drag)
        XCTAssertFalse(content.deletion.isPanelShown)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(board.records.map(\.id), records.map(\.id))
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertEqual(removals, 0)
    }

    /// The mouse-down location and time are stored, and the first dragged event's speed is measured
    /// against them. A slow first move (4 pt over 10 s) is below 75 pt/s, so the drag state is
    /// evaluated at once instead of waiting for the pointer to rest.
    func testFirstDragSpeedIsMeasuredFromTheMouseDown() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let (content, board, records) = try externalDragFixture()
        let window = NativeAppTestSupport.makeKeyPanel(size: content.frame.size, contentView: content)
        defer { window.close() }
        let host = try XCTUnwrap(content.layer)
        content.drag.shiftKeyDown = { false }
        content.drag.dockHitRegion = { _ in nil }
        var sleeps: [TimeInterval] = []
        content.drag.sleep = { delay in
            sleeps.append(delay)
            throw CancellationError()
        }
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        let icon = cell.iconLayer.convert(cell.iconLayer.bounds, to: host)
        let start = CGPoint(x: icon.midX, y: icon.midY)
        func mouse(_ type: NSEvent.EventType, at point: CGPoint, time: TimeInterval) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                                             clickCount: 1, pressure: 1))
        }

        content.mouseDown(with: try mouse(.leftMouseDown, at: start, time: 0))
        content.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: start.x + 4, y: start.y), time: 10))
        XCTAssertEqual(board.drag?.item.record?.id, records[0].id)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(sleeps, [], "The first sample is slow when measured from the mouse-down")

        content.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: start.x + 104, y: start.y), time: 10.01))
        try await waitUntilAsync { sleeps == [ClassicalDragParameters.restDelay] }
        content.drag.cancel(animated: false)
    }

    func testEscapeThenMouseReleaseAndRapidNewPressCannotCommitCancelledDrag() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956),
                                                    dock: .bottom(extent: 59), rows: 2, columns: 3)
        let content = ClassicalContentView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        content.wantsLayer = true
        let window = NativeAppTestSupport.makeKeyPanel(size: geometry.screenSize, contentView: content)
        defer { window.close() }
        let board = ClassicalSpringboard()
        let records = try ["A", "B", "C"].map(record)
        let host = try XCTUnwrap(content.layer)
        host.addSublayer(board.pager.layer)
        board.show(records, geometry: geometry, scale: 1, rightToLeft: false,
                   noResultsText: "No Results") { _, _ in throw CancellationError() }
        content.springboard = board
        content.pager = board.pager
        let keyboard = ClassicalKeyboard(springboard: board)
        keyboard.drag = content.drag
        keyboard.contentView = content
        content.keyboard = keyboard
        var committed: [ClassicalLayout] = []
        board.layoutDidChange = { committed.append($0) }
        var launched: [AppIdentity] = []
        content.launch = { launched.append($0.id) }
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        let icon = cell.iconLayer.convert(cell.iconLayer.bounds, to: host)
        let start = CGPoint(x: icon.midX, y: icon.midY)
        let slot = geometry.grid.cellFrame(at: 2)
        let destination = host.convert(CGPoint(x: slot.midX, y: slot.midY), from: board.pager.pages[0].layer)
        func mouse(_ type: NSEvent.EventType, at point: CGPoint, time: TimeInterval) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                                             clickCount: 1, pressure: 1))
        }

        content.mouseDown(with: try mouse(.leftMouseDown, at: start, time: 0))
        content.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: start.x + 4, y: start.y), time: 0.1))
        XCTAssertNotNil(board.drag)
        content.mouseDragged(with: try mouse(.leftMouseDragged, at: destination, time: 100))
        XCTAssertEqual(board.pages[0].compactMap(\.record?.id), [records[1].id, records[2].id, records[0].id])

        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                   timestamp: 100.01, windowNumber: window.windowNumber, context: nil,
                                                   characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                   isARepeat: false, keyCode: 53))
        content.keyDown(with: escape)
        XCTAssertTrue(content.drag.isCancelling)
        content.mouseUp(with: try mouse(.leftMouseUp, at: destination, time: 100.02))
        content.mouseDown(with: try mouse(.leftMouseDown, at: start, time: 100.03))
        XCTAssertNil(content.press.pressedItem, "A new press waits for the cancelled icon to settle")
        content.mouseUp(with: try mouse(.leftMouseUp, at: start, time: 100.04))
        try waitUntil { board.drag == nil }
        // Hit testing reads the presentation tree; commit the landing as the run loop does before
        // the next real event, since this test sends the next press in the same turn.
        CATransaction.flush()
        XCTAssertEqual(board.pages[0].compactMap(\.record?.id), records.map(\.id))
        XCTAssertTrue(committed.isEmpty, "The cancelled arrangement must never reach storage")
        XCTAssertTrue(launched.isEmpty)

        let restored = try XCTUnwrap(board.cell(for: records[0].id))
        let restoredIcon = restored.iconLayer.convert(restored.iconLayer.bounds, to: host)
        let restoredCenter = CGPoint(x: restoredIcon.midX, y: restoredIcon.midY)
        content.mouseDown(with: try mouse(.leftMouseDown, at: restoredCenter, time: 101))
        XCTAssertEqual(content.press.pressedItem?.item.record?.id, records[0].id,
                       "A normal press works once the cancelled drag has settled")
        content.press.cancel()
    }

    /// The pager cannot scroll from the press on an icon until release, so the wheel event is
    /// swallowed; a wheel scroll still waiting to settle when the icon is pressed does not turn the
    /// page either.
    func testWheelScrollingDoesNotTurnThePageWhileAnIconIsHeld() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956),
                                                    dock: .bottom(extent: 59), rows: 2, columns: 3)
        let content = ClassicalContentView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        content.wantsLayer = true
        let window = NativeAppTestSupport.makeKeyPanel(size: geometry.screenSize, contentView: content)
        defer { window.close() }
        let board = ClassicalSpringboard()
        board.pager.shiftKeyDown = { false }
        let host = try XCTUnwrap(content.layer)
        host.addSublayer(board.pager.layer)
        board.show(try ["A", "B", "C", "D", "E", "F", "G"].map(record), geometry: geometry, scale: 1,
                   rightToLeft: false, noResultsText: "No Results") { _, _ in throw CancellationError() }
        content.springboard = board
        content.pager = board.pager
        content.launch = { _ in }
        func mouse(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                                             clickCount: 1, pressure: 1))
        }
        func wheel() throws -> NSEvent {
            let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                              wheel1: -1, wheel2: 0, wheel3: 0))
            return try XCTUnwrap(NSEvent(cgEvent: event))
        }
        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        let icon = cell.iconLayer.convert(cell.iconLayer.bounds, to: host)
        let press = CGPoint(x: icon.midX, y: icon.midY)

        content.mouseDown(with: try mouse(.leftMouseDown, at: press))
        content.scrollWheel(with: try wheel())
        settle()
        XCTAssertEqual(board.pager.currentPage, 0, "Scrolling while an icon is held does not turn the page")
        content.mouseUp(with: try mouse(.leftMouseUp, at: press))

        // The pending travel is dropped and the pager stays on its page.
        content.scrollWheel(with: try wheel())
        content.mouseDown(with: try mouse(.leftMouseDown, at: press))
        settle()
        XCTAssertEqual(board.pager.currentPage, 0, "A pending wheel scroll does not turn the page mid-hold")
        content.mouseUp(with: try mouse(.leftMouseUp, at: press))

        content.scrollWheel(with: try wheel())
        settle()
        XCTAssertEqual(board.pager.currentPage, 1, "The same scroll turns the page once nothing is held")
    }

    // MARK: Folders

    /// A release on a closed folder opens it; nothing launches.
    func testClickOnAFolderOpensIt() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        try fixture.click(at: fixture.iconCenter(of: try fixture.folderCell("Work")), time: 0)
        ClassicalFolderTestBoard.waitUntil { fixture.board.folders.openFolder != nil }
        XCTAssertTrue(fixture.launched.isEmpty)
        XCTAssertEqual(fixture.dismissals, 0)
    }

    func testFirstClickAfterFolderClosesOpensBeforeSettling() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        fixture.board.folders.sleep = { _ in try await Task.sleep(for: .seconds(5)) }
        for cycle in 0..<5 {
            _ = try fixture.open("Work")
            fixture.board.folders.close()
            ClassicalFolderTestBoard.waitUntil { !fixture.board.folders.isActive }
            let icon = fixture.iconCenter(of: try fixture.folderCell("Work"))

            try fixture.click(at: icon, time: Double(cycle) * 10)

            XCTAssertNotNil(fixture.board.folders.openFolder,
                            "Cycle \(cycle): the first click after close must reopen it")
            XCTAssertEqual(fixture.dismissals, 0)
            fixture.board.folders.close(animated: false)
        }
    }

    func testFolderClickSurvivesCellReplacementDuringPostCloseRefresh() async throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        let board = fixture.board
        board.deferredRefreshNeeded = { [weak board] in
            guard let board else { return }
            board.refresh(pages: board.pages)
        }
        var settleGate: CheckedContinuation<Void, Error>?
        board.folders.sleep = { _ in
            try await withCheckedThrowingContinuation { settleGate = $0 }
        }
        XCTAssertTrue(board.openFolder(try fixture.folderID("Work"), selectingFirstItem: false))
        try await waitUntilAsync { !board.folders.isOpening }
        board.folders.close()
        try await waitUntilAsync { !board.folders.isActive && settleGate != nil }
        let originalCell = try fixture.folderCell("Work")
        let icon = fixture.iconCenter(of: originalCell)

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: icon, time: 0))
        settleGate?.resume()
        settleGate = nil
        try await waitUntilAsync { (try? fixture.folderCell("Work")) !== originalCell }
        fixture.content.mouseUp(with: try fixture.mouse(.leftMouseUp, at: icon, time: 0.1))

        XCTAssertNotNil(board.folders.openFolder, "The first release opens after the same folder receives a new cell")
        XCTAssertTrue(fixture.launched.isEmpty)
        XCTAssertEqual(fixture.dismissals, 0)
    }

    func testFirstClickInNonKeyClassicalPanelOpensFolder() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        let panel = ClassicalPanel.makeLauncherPanel()
        panel.setFrame(CGRect(origin: .zero, size: ClassicalFolderTestBoard.geometry.screenSize), display: false)
        panel.contentView = fixture.content
        panel.initialFirstResponder = fixture.content
        panel.orderFrontRegardless()
        defer { panel.close() }
        let other = NativeAppTestSupport.makeKeyPanel(size: CGSize(width: 100, height: 100), contentView: NSView())
        defer { other.close() }
        XCTAssertFalse(panel.isKeyWindow)
        let icon = fixture.iconCenter(of: try fixture.folderCell("Work"))
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: icon, modifierFlags: [], timestamp: 0,
                                             windowNumber: panel.windowNumber, context: nil, eventNumber: 1,
                                             clickCount: 1, pressure: 1))
        }

        XCTAssertTrue(fixture.content.acceptsFirstMouse(for: try event(.leftMouseDown)))
        panel.sendEvent(try event(.leftMouseDown))
        panel.sendEvent(try event(.leftMouseUp))

        XCTAssertNotNil(fixture.board.folders.openFolder, "The first native panel click opens the folder")
        XCTAssertTrue(fixture.launched.isEmpty)
        XCTAssertEqual(fixture.dismissals, 0)
    }

    func testClickOnVisibleFolderDuringPageSettleOpensOnFirstTry() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])], ["C"]])
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: ClassicalFolderTestBoard.geometry.screenSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = fixture.content
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        defer { window.orderOut(nil) }
        let cell = try fixture.folderCell("Work")

        fixture.board.pager.settle(on: 1)
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        let strip = fixture.board.pager.stripLayer
        let presentedScroll = try XCTUnwrap(strip.presentation()?.bounds.origin.x)
        let modelCenter = fixture.iconCenter(of: cell)
        let center = CGPoint(x: modelCenter.x + strip.bounds.origin.x - presentedScroll, y: modelCenter.y)
        XCTAssertTrue(fixture.content.bounds.contains(center), "The outgoing folder remains visible during the transition")

        try fixture.click(at: center, time: 0)

        XCTAssertNotNil(fixture.board.folders.openFolder, "One click on the visible folder opens it")
        XCTAssertEqual(fixture.dismissals, 0)
    }

    func testClickOnFolderUnderScaledParentOpensOnFirstTry() throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B", .folder("Work", [["C", "D"]])]])
        let cell = try fixture.folderCell("Work")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fixture.background.setAffineTransform(CGAffineTransform(scaleX: 1.25, y: 1.25))
        CATransaction.commit()
        let center = fixture.iconCenter(of: cell)

        try fixture.click(at: center, time: 0)

        XCTAssertNotNil(fixture.board.folders.openFolder, "A transformed visible folder opens from one click")
        XCTAssertEqual(fixture.dismissals, 0)
    }

    /// Inside the open folder a click on an application launches it, as on the root pages.
    func testClickInsideTheFolderLaunchesTheApplication() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        let folder = try fixture.open("Work")
        let cell = try XCTUnwrap(folder.cell(for: try fixture.record("C").id))
        try fixture.click(at: fixture.iconCenter(of: cell), time: 0)
        XCTAssertEqual(fixture.launched, ["C"])
    }

    /// In the panel but off the backdrop, a click closes the folder on release unless the pointer
    /// moved 3 pt or more. Neither closes the launcher.
    func testClicksOffTheBackdropCloseTheFolder() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        let folder = try fixture.open("Work")
        let panel = folder.layer.frame
        let backdrop = fixture.host.convert(folder.geometry.backdropFrame, from: folder.layer)
        let beside = CGPoint(x: (panel.minX + backdrop.minX) / 2, y: backdrop.midY)
        XCTAssertTrue(panel.contains(beside) && !backdrop.contains(beside), "The fixture needs a point beside the backdrop")

        try fixture.click(at: beside, moved: CGVector(dx: 3, dy: 0), time: 0)
        XCTAssertTrue(fixture.board.folders.openFolder === folder, "A 3 pt movement is not a click")
        // The backdrop's margin beside the folder grid, away from the icons and the rounded corners.
        try fixture.click(at: CGPoint(x: backdrop.minX + 10, y: backdrop.midY), time: 1)
        XCTAssertTrue(fixture.board.folders.openFolder === folder, "A click on the backdrop keeps the folder open")
        try fixture.click(at: beside, moved: CGVector(dx: 2, dy: 2), time: 2)
        fixture.waitUntilClosed()
        XCTAssertEqual(fixture.dismissals, 0)
        XCTAssertEqual(fixture.launched, [])
    }

    /// A press that travels 3 pt or more at any point is not a click, even when it is released
    /// back where it started.
    func testAPressThatMovedAwayAndBackDoesNotCloseTheFolder() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        let folder = try fixture.open("Work")
        let panel = folder.layer.frame
        let backdrop = fixture.host.convert(folder.geometry.backdropFrame, from: folder.layer)
        let beside = CGPoint(x: (panel.minX + backdrop.minX) / 2, y: backdrop.midY)
        XCTAssertTrue(panel.contains(beside) && !backdrop.contains(beside), "The fixture needs a point beside the backdrop")

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: beside, time: 0))
        let away = CGPoint(x: beside.x, y: beside.y + 5)
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: away, time: 0.05))
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: beside, time: 0.1))
        fixture.content.mouseUp(with: try fixture.mouse(.leftMouseUp, at: beside, time: 0.15))

        XCTAssertTrue(fixture.board.folders.openFolder === folder)
    }

    /// Outside the panel but inside the page area, the press does not close the folder; its release
    /// does. Outside the page area the press itself closes it. Neither closes the launcher.
    func testClicksOutsideThePanelCloseInThePageAreaOnReleaseAndElsewhereOnPress() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        try fixture.open("Work")
        let panel = try XCTUnwrap(fixture.board.folders.openFolder).layer.frame
        let pageArea = fixture.host.convert(fixture.board.pager.layer.frame, from: fixture.background)
        let below = CGPoint(x: panel.midX, y: panel.minY - 5)
        XCTAssertTrue(pageArea.contains(below) && !panel.contains(below), "The fixture needs a page-area point below the panel")

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: below, time: 0))
        XCTAssertNotNil(fixture.board.folders.openFolder, "The press in the page area does not close the folder")
        fixture.content.mouseUp(with: try fixture.mouse(.leftMouseUp, at: below, time: 0.1))
        XCTAssertTrue(fixture.board.folders.isClosing || !fixture.board.folders.isActive, "The release closes it")
        fixture.waitUntilClosed()

        try fixture.open("Work")
        let outside = CGPoint(x: pageArea.midX, y: pageArea.minY - 1)
        XCTAssertTrue(fixture.content.bounds.contains(outside) && !pageArea.contains(outside),
                      "The fixture needs a point outside the page area")
        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: outside, time: 1))
        XCTAssertTrue(fixture.board.folders.isClosing || !fixture.board.folders.isActive, "The press closes it")
        fixture.content.mouseUp(with: try fixture.mouse(.leftMouseUp, at: outside, time: 1.1))
        fixture.waitUntilClosed()
        XCTAssertEqual(fixture.dismissals, 0)
        XCTAssertEqual(fixture.launched, [])
    }

    /// While the folder is still opening or already closing, a click on an application in it
    /// launches nothing. The transition runs in a window, where Core Animation animates it.
    func testClicksOnFolderIconsWhileOpeningOrClosingAreIgnored() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        let window = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: fixture.content)
        defer { window.close() }

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        XCTAssertTrue(fixture.board.folders.isOpening)
        let cell = try XCTUnwrap(folder.cell(for: try fixture.record("C").id))
        let icon = fixture.host.convert(cell.layout.iconFrame, from: cell.jitterLayer)
        try fixture.click(at: CGPoint(x: icon.midX, y: icon.midY), time: 0)
        XCTAssertEqual(fixture.launched, [], "A press while the folder opens is ignored")
        fixture.waitUntilOpened()

        fixture.board.folders.close()
        XCTAssertTrue(fixture.board.folders.isClosing)
        try fixture.click(at: CGPoint(x: icon.midX, y: icon.midY), time: 1)
        XCTAssertEqual(fixture.launched, [], "A press while the folder closes is ignored")
        fixture.waitUntilClosed()
        XCTAssertEqual(fixture.dismissals, 0)
    }

    /// The Dock group hit uses the dragged cell's midpoint, which is offset from the mouse-down
    /// point on the icon. Keep that midpoint over the target image during a synthetic mouse move.
    private func pointerForDraggedCenter(_ center: CGPoint, fixture: ClassicalFolderTestBoard,
                                         at pointer: CGPoint) throws -> CGPoint {
        let draggedCenter = try XCTUnwrap(fixture.board.drag?.cell.position)
        return CGPoint(x: center.x - draggedCenter.x + pointer.x,
                       y: center.y - draggedCenter.y + pointer.y)
    }

    private func record(_ name: String) throws -> AppRecord {
        let url = URL(filePath: "/Applications/\(name).app", directoryHint: .isDirectory)
        return AppRecord(
            metadata: try AppMetadata(bundleIdentifier: "com.example.\(name)", bundleURL: url,
                                      displayName: name, version: nil, buildVersion: nil,
                                      contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: url.deletingLastPathComponent())
        )
    }

    private func externalDragFixture() throws -> (ClassicalContentView, ClassicalSpringboard, [AppRecord]) {
        let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956),
                                                    dock: .bottom(extent: 59), rows: 2, columns: 3)
        let content = ClassicalContentView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        content.wantsLayer = true
        let board = ClassicalSpringboard()
        let records = try ["A", "B", "C"].map(record)
        try XCTUnwrap(content.layer).addSublayer(board.pager.layer)
        board.show(records, geometry: geometry, scale: 1, rightToLeft: false,
                   noResultsText: "No Results") { _, _ in throw CancellationError() }
        content.springboard = board
        content.pager = board.pager
        return (content, board, records)
    }

    private func waitUntilAsync(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Timed out.")
    }

    private func waitUntil(_ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition(), "Timed out waiting for the cancelled drag")
    }
}
