import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalItemPressTests: XCTestCase {
    func testApplicationPressSurvivesCellReplacementAndLaunchesOnce() throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B"]])
        let original = try XCTUnwrap(fixture.board.cell(for: fixture.record("A").id))
        let point = fixture.iconCenter(of: original)

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: point, time: 0))
        fixture.board.refresh(pages: fixture.board.pages)
        XCTAssertFalse(fixture.board.cell(for: try fixture.record("A").id) === original)
        fixture.content.mouseUp(with: try fixture.mouse(.leftMouseUp, at: point, time: 0.1))
        fixture.content.mouseUp(with: try fixture.mouse(.leftMouseUp, at: point, time: 0.2))

        XCTAssertEqual(fixture.launched, ["A"], "A replacement does not lose or repeat the click")
        XCTAssertEqual(fixture.dismissals, 0)
    }

    func testReleaseOnDifferentIconAfterReplacementDoesNotLaunchEitherApplication() throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B"]])
        let first = try XCTUnwrap(fixture.board.cell(for: fixture.record("A").id))
        let second = try XCTUnwrap(fixture.board.cell(for: fixture.record("B").id))
        let start = fixture.iconCenter(of: first)
        let end = fixture.iconCenter(of: second)

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: start, time: 0))
        fixture.board.refresh(pages: fixture.board.pages)
        fixture.content.mouseUp(with: try fixture.mouse(.leftMouseUp, at: end, time: 0.1))

        XCTAssertTrue(fixture.launched.isEmpty)
        XCTAssertEqual(fixture.dismissals, 0)
    }

    func testReleaseOnBlankSpaceAfterReplacementDoesNotLaunch() throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B"]])
        let first = try XCTUnwrap(fixture.board.cell(for: fixture.record("A").id))
        let start = fixture.iconCenter(of: first)
        let blankFrame = ClassicalFolderTestBoard.geometry.grid.cellFrame(at: 4)
        let blank = fixture.host.convert(CGPoint(x: blankFrame.midX, y: blankFrame.midY),
                                         from: fixture.board.pager.pages[0].layer)

        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: start, time: 0))
        fixture.board.refresh(pages: fixture.board.pages)
        fixture.content.mouseUp(with: try fixture.mouse(.leftMouseUp, at: blank, time: 0.1))

        XCTAssertTrue(fixture.launched.isEmpty)
        XCTAssertEqual(fixture.dismissals, 0)
    }

    /// A long press takes 5 s with Shift and 1 s without it.
    func testShiftUsesFiveSecondLongPressAndUnshiftedUsesOneSecond() async throws {
        let fixture = try ClassicalFolderTestBoard([["A"]])
        let cell = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.first)
        let point = fixture.iconCenter(of: cell)
        let press = ClassicalItemPress()
        press.springboard = fixture.board
        var delays: [TimeInterval] = []
        press.sleep = { delay in
            delays.append(delay)
            throw CancellationError()
        }

        press.shiftKeyDown = { true }
        press.beginIcon(at: point)
        try await waitUntil { delays.count == 1 }
        XCTAssertEqual(delays, [5])
        XCTAssertTrue(press.end(at: point))

        press.shiftKeyDown = { false }
        press.beginIcon(at: point)
        try await waitUntil { delays.count == 2 }
        XCTAssertEqual(delays, [5, 1])
        XCTAssertTrue(press.end(at: point))
        XCTAssertFalse(fixture.board.isDeleting)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Timed out.")
    }
}
