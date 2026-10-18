import XCTest
@testable import Launchpod

/// A folder made by a drop opens by itself 0.75 s after the drop's settle transaction has finished,
/// unless a folder is shown by then; a new drag or the launcher closing cancels that pending open.
@MainActor
final class ClassicalGroupDragSessionTests: XCTestCase {
    func testTheFolderOpensTheDelayAfterTheSettleCompletionRuns() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        let session = fixture.board.groupDragSession
        XCTAssertEqual(ClassicalFolderParameters.newFolderOpenDelay, 0.75)
        let settled = session.openAfterSettling(try fixture.folderID("Work"))

        wait(ClassicalFolderParameters.newFolderOpenDelay + 0.25)
        XCTAssertFalse(fixture.board.folders.isActive, "Nothing opens before the settle transaction completes")

        let start = Date()
        settled()
        XCTAssertFalse(fixture.board.folders.isActive, "The open waits for the delay")
        ClassicalFolderTestBoard.waitUntil { fixture.board.folders.isActive }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), ClassicalFolderParameters.newFolderOpenDelay - 0.01)
        XCTAssertEqual(fixture.board.folders.folder?.content.id, try fixture.folderID("Work"))
    }

    func testNoOpenIsScheduledWhileAFolderIsShownAtTheSettle() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), .folder("Games", [["C", "D"]])]])
        let settled = fixture.board.groupDragSession.openAfterSettling(try fixture.folderID("Work"))
        try fixture.open("Games")

        settled()
        fixture.board.folders.close(animated: false)
        wait(ClassicalFolderParameters.newFolderOpenDelay + 0.25)

        XCTAssertFalse(fixture.board.folders.isActive)
    }

    func testANewDragCancelsThePendingOpen() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        fixture.board.groupDragSession.openAfterSettling(try fixture.folderID("Work"))()

        let cell = try XCTUnwrap(fixture.board.cell(for: fixture.record("C").id))
        XCTAssertTrue(fixture.board.beginDrag(of: .app(try fixture.record("C")), cell: cell))
        wait(ClassicalFolderParameters.newFolderOpenDelay + 0.25)

        XCTAssertFalse(fixture.board.folders.isActive)
        fixture.board.cancelDrag(animated: false)
    }

    /// A settle completion from before the cancellation does nothing when it runs later.
    func testASettleCompletionFromBeforeANewDragDoesNothing() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        let settled = fixture.board.groupDragSession.openAfterSettling(try fixture.folderID("Work"))
        let cell = try XCTUnwrap(fixture.board.cell(for: fixture.record("C").id))
        XCTAssertTrue(fixture.board.beginDrag(of: .app(try fixture.record("C")), cell: cell))
        fixture.board.cancelDrag(animated: false)
        ClassicalFolderTestBoard.waitUntil { fixture.board.drag == nil }

        settled()
        wait(ClassicalFolderParameters.newFolderOpenDelay + 0.25)

        XCTAssertFalse(fixture.board.folders.isActive)
    }

    func testClosingTheLauncherCancelsThePendingOpen() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        fixture.board.groupDragSession.openAfterSettling(try fixture.folderID("Work"))()

        fixture.board.reset()
        wait(ClassicalFolderParameters.newFolderOpenDelay + 0.25)

        XCTAssertFalse(fixture.board.folders.isActive)
    }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
