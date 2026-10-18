import AppKit
import XCTest
@testable import Launchpod

/// The pointer-driven drag controller: rest and page-edge timers and the hand-off to the Dock.
@MainActor
final class ClassicalItemDragTests: XCTestCase {
    private let geometry = ClassicalDragTestBoard.geometry

    func testExternalDragExportsThePresentApplicationAsAFileURLAtItsOriginalIconPosition() throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let appURL = try fixture.application("Studio.app", identifier: "com.example.Studio")
        let record = AppRecord(
            metadata: try AppMetadata(bundleIdentifier: "com.example.Studio", bundleURL: appURL,
                                      displayName: "Studio", version: nil, buildVersion: nil,
                                      contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: fixture.root, isOnline: true)
        )
        let view = NSView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        view.wantsLayer = true
        let layer = try XCTUnwrap(view.layer)
        let board = ClassicalSpringboard()
        layer.addSublayer(board.pager.layer)
        board.show([record], geometry: geometry, scale: 1, rightToLeft: false,
                   noResultsText: "No Results") { _, _ in throw CancellationError() }
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        let originalIcon = cell.iconLayer.convert(cell.iconLayer.bounds, to: layer)
        let start = layer.convert(cell.position, from: cell.superlayer)
        let drag = ClassicalItemDrag()
        drag.springboard = board
        XCTAssertTrue(drag.begin(.app(record), cell: cell, at: start, time: 0))
        drag.moved(to: CGPoint(x: start.x + 30, y: start.y + 20), time: 1)

        let item = try XCTUnwrap(drag.makeExternalDraggingItem(for: record, cell: cell, in: view))
        XCTAssertEqual(item.item as? URL, appURL)
        XCTAssertGreaterThan(item.draggingFrame.width, 0)
        XCTAssertGreaterThan(item.draggingFrame.height, 0)
        XCTAssertEqual(item.draggingFrame.midX, originalIcon.midX, accuracy: 1,
                       "AppKit begins at the original press position when handed the mouse-down event")
        XCTAssertEqual(item.draggingFrame.midY, originalIcon.midY, accuracy: 1)

        drag.cancel(animated: false)
        try FileManager.default.removeItem(at: appURL)
        XCTAssertNil(drag.makeExternalDraggingItem(for: record, cell: cell, in: view),
                     "An unavailable bundle cannot be handed to the Dock")
    }

    func testDockHandoffUsesTheDockReportedBarRectangle() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let window = NativeAppTestSupport.makeKeyPanel(size: view.bounds.size, contentView: view)
        defer { window.close() }
        let screen = try XCTUnwrap(window.screen)
        let frame = screen.frame
        let dock = CGRect(x: frame.midX - 100, y: frame.minY, width: 200, height: 59)
        let inside = CGPoint(x: dock.midX, y: dock.midY)
        let besideDock = CGPoint(x: dock.minX - 1, y: dock.midY)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        func inView(_ point: CGPoint) -> CGPoint {
            view.convert(window.convertPoint(fromScreen: point), from: nil)
        }
        let drag = ClassicalItemDrag()
        drag.dockHitRegion = { _ in dock }
        XCTAssertTrue(drag.shouldHandOffToDock(at: inView(inside), in: view))
        XCTAssertFalse(drag.shouldHandOffToDock(at: inView(besideDock), in: view),
                       "The screen edge beside the Dock is not part of inBarRect")
        XCTAssertFalse(drag.shouldHandOffToDock(at: inView(center), in: view),
                       "A point outside the Dock stays in the launcher")
    }

    func testFastMovesWaitForTheRestDelayAndEdgesTurnPagesOnATimer() async throws {
        let fixture = try ClassicalDragTestBoard([["A", "B", "C"], ["D"]])
        let board = fixture.board
        let drag = ClassicalItemDrag()
        drag.springboard = board
        drag.shiftKeyDown = { false }
        var sleeps: [TimeInterval] = []
        var gates: [CheckedContinuation<Void, Never>] = []
        drag.sleep = { delay in
            sleeps.append(delay)
            await withCheckedContinuation { gates.append($0) }
        }
        let cells = try XCTUnwrap(board.pager.pages.first?.itemLayers)
        let start = CGPoint(x: cells[0].position.x, y: cells[0].position.y)
        XCTAssertTrue(drag.begin(board.pages[0][0], cell: cells[0], at: fixture.host.convert(start, from: cells[0].superlayer), time: 0))
        let target = fixture.center(page: 0, slot: 2)
        drag.moved(to: target, time: 0.01)
        XCTAssertEqual(fixture.names, [["A", "B", "C"], ["D"]], "A fast move waits for the pointer to rest")
        try await waitUntilAsync { sleeps == [0.15] }
        gates.removeFirst().resume()
        try await waitUntilAsync { fixture.names == [["B", "C", "A"], ["D"]] }

        drag.moved(to: CGPoint(x: target.x + 1, y: target.y), time: 1)
        drag.moved(to: CGPoint(x: geometry.pageFrame.maxX + 20, y: target.y), time: 10)
        try await waitUntilAsync { sleeps.last == 0.7 }
        gates.removeFirst().resume()
        try await waitUntilAsync { board.pager.currentPage == 1 }
        XCTAssertEqual(fixture.names, [["B", "C"], ["D", "A"]])
        try await waitUntilAsync { sleeps.last == 0.75 }
        drag.cancel(animated: false)
        XCTAssertEqual(fixture.names, [["A", "B", "C"], ["D"]])
        gates.forEach { $0.resume() }
    }

    /// Drag-state evaluation waits 0.75 s after a fast move with Shift.
    func testShiftExtendsTheFastMoveRestTimer() async throws {
        let fixture = try ClassicalDragTestBoard([["A", "B", "C"]])
        let board = fixture.board
        let drag = ClassicalItemDrag()
        drag.springboard = board
        drag.shiftKeyDown = { true }
        var delays: [TimeInterval] = []
        drag.sleep = { delay in
            delays.append(delay)
            throw CancellationError()
        }
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        let start = fixture.host.convert(cell.position, from: cell.superlayer)
        XCTAssertTrue(drag.begin(board.pages[0][0], cell: cell, at: start, time: 0))
        drag.moved(to: fixture.center(page: 0, slot: 2), time: 0.01)

        try await waitUntilAsync { delays.count == 1 }
        XCTAssertEqual(delays, [0.75])
        XCTAssertEqual(fixture.names, [["A", "B", "C"]])
        drag.cancel(animated: false)
    }

    /// The page-edge timers select 3.5 s then 3.75 s with Shift.
    func testShiftExtendsBothPageEdgeTimers() async throws {
        let fixture = try ClassicalDragTestBoard([["A", "B", "C"], ["D"]])
        let board = fixture.board
        let drag = ClassicalItemDrag()
        drag.springboard = board
        drag.shiftKeyDown = { true }
        var delays: [TimeInterval] = []
        var gates: [CheckedContinuation<Void, Never>] = []
        drag.sleep = { delay in
            delays.append(delay)
            await withCheckedContinuation { gates.append($0) }
        }
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        let start = fixture.host.convert(cell.position, from: cell.superlayer)
        XCTAssertTrue(drag.begin(board.pages[0][0], cell: cell, at: start, time: 0))
        drag.moved(to: CGPoint(x: geometry.pageFrame.maxX + 20, y: start.y), time: 20)

        try await waitUntilAsync { delays.count == 1 }
        XCTAssertEqual(delays, [3.5])
        gates.removeFirst().resume()
        try await waitUntilAsync { board.pager.currentPage == 1 && delays.count == 2 }
        XCTAssertEqual(delays, [3.5, 3.75])
        drag.cancel(animated: false)
        gates.forEach { $0.resume() }
    }

    /// Hovering over another icon waits 1 s, or 5 s with Shift.
    func testHoveringOverAnotherIconUsesTheShiftGroupDelay() async throws {
        for (shifted, expectedDelay) in [(false, 1.0), (true, 5.0)] {
            let fixture = try ClassicalDragTestBoard([["A", "B"]])
            let board = fixture.board
            let cells = try XCTUnwrap(board.pager.pages.first?.itemLayers)
            let drag = ClassicalItemDrag()
            drag.springboard = board
            drag.shiftKeyDown = { shifted }
            var delays: [TimeInterval] = []
            drag.sleep = { delay in
                delays.append(delay)
                throw CancellationError()
            }
            let start = fixture.host.convert(cells[0].position, from: cells[0].superlayer)
            XCTAssertTrue(drag.begin(board.pages[0][0], cell: cells[0], at: start, time: 0))
            let icon = fixture.host.convert(cells[1].iconLayer.frame, from: cells[1].jitterLayer)
            drag.moved(to: CGPoint(x: icon.midX, y: icon.midY), time: 100)

            try await waitUntilAsync { !delays.isEmpty }
            XCTAssertEqual(delays, [expectedDelay])
            XCTAssertTrue(cells[1].isDarkened)
            drag.cancel(animated: false)
        }
    }

    func testResetStopsPendingRestAndPageEdgeTimers() async throws {
        let fixture = try ClassicalDragTestBoard([["A", "B", "C"], ["D"]])
        let board = fixture.board
        let drag = ClassicalItemDrag()
        drag.springboard = board
        let keyboard = ClassicalKeyboard(springboard: board)
        keyboard.drag = drag
        drag.shiftKeyDown = { false }
        var sleeps: [TimeInterval] = []
        var gates: [CheckedContinuation<Void, Never>] = []
        var cancelledSleeps: [Bool] = []
        drag.sleep = { delay in
            sleeps.append(delay)
            await withCheckedContinuation { gates.append($0) }
            cancelledSleeps.append(Task.isCancelled)
        }
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        let start = fixture.host.convert(cell.position, from: cell.superlayer)
        XCTAssertTrue(drag.begin(board.pages[0][0], cell: cell, at: start, time: 0))
        drag.moved(to: fixture.center(page: 0, slot: 2), time: 0.01)
        try await waitUntilAsync { sleeps == [0.15] }
        keyboard.reset()
        gates.removeFirst().resume()
        try await waitUntilAsync { cancelledSleeps.count == 1 }
        XCTAssertEqual(cancelledSleeps, [true], "Closing cancels the pending rest timer")
        XCTAssertNil(board.drag)
        XCTAssertEqual(fixture.names, [["A", "B", "C"], ["D"]])

        let restoredCell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        XCTAssertTrue(drag.begin(board.pages[0][0], cell: restoredCell,
                                 at: fixture.host.convert(restoredCell.position, from: restoredCell.superlayer), time: 1))
        drag.moved(to: CGPoint(x: geometry.pageFrame.maxX + 20, y: start.y), time: 20)
        try await waitUntilAsync { sleeps.last == 0.7 }
        keyboard.reset()
        gates.removeFirst().resume()
        try await waitUntilAsync { cancelledSleeps.count == 2 }
        XCTAssertEqual(cancelledSleeps, [true, true], "Closing cancels the pending page-edge timer")
        XCTAssertNil(board.drag)
        XCTAssertEqual(board.pager.currentPage, 0)
        XCTAssertEqual(fixture.names, [["A", "B", "C"], ["D"]])
    }

    private func waitUntilAsync(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Timed out.")
    }
}
