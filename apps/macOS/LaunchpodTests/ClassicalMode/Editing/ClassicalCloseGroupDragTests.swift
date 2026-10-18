import QuartzCore
import XCTest
@testable import Launchpod

/// Dragging an application out of an open folder: the item joins the folder's root page, the
/// folder closes with its animation, and only once it has closed does a folder left with too few
/// applications dissolve. A folder created during this presentation dissolves when it held at most
/// two applications with the dragged one; any other folder only when the dragged one was its last.
@MainActor
final class ClassicalCloseGroupDragTests: XCTestCase {
    func testANewFolderLeftWithOneApplicationDissolvesOnceItHasClosed() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        fixture.board.groupDragSession.markNewFolder(try fixture.folderID("Work"))
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        try dragOut("A", from: "Work", fixture)

        XCTAssertTrue(fixture.board.folders.isClosing)
        XCTAssertEqual(rootNames(fixture), ["Work[B]", "C", "A"], "The folder stays while it closes")
        fixture.waitUntilClosed()
        XCTAssertEqual(rootNames(fixture), ["B", "C", "A"], "The remaining application takes the folder's slot")

        fixture.board.drag?.drop(center: .zero)
        ClassicalFolderTestBoard.waitUntil { fixture.board.drag == nil && !committed.isEmpty }
        let saved = try XCTUnwrap(committed.last)
        XCTAssertTrue(saved.folders.isEmpty)
        XCTAssertEqual(saved.pages.first?.compactMap(\.app), try ["B", "C", "A"].map { try fixture.record($0).id })
    }

    func testANewFolderLeftWithTwoApplicationsStays() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B", "C"]]), "D"]])
        fixture.board.groupDragSession.markNewFolder(try fixture.folderID("Work"))
        try dragOut("A", from: "Work", fixture)
        fixture.waitUntilClosed()
        settle()

        XCTAssertEqual(rootNames(fixture), ["Work[B,C]", "D", "A"])
        fixture.board.cancelDrag(animated: false)
    }

    func testAnExistingFolderLeftWithOneApplicationKeepsIt() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        try dragOut("A", from: "Work", fixture)
        fixture.waitUntilClosed()
        settle()

        XCTAssertEqual(rootNames(fixture), ["Work[B]", "C", "A"])
        fixture.board.cancelDrag(animated: false)
    }

    func testAnExistingFolderLeftByItsOnlyApplicationDisappears() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A"]]), "C"]])
        var committed: [ClassicalLayout] = []
        fixture.board.folderDragDidChange = { committed.append($0) }
        try dragOut("A", from: "Work", fixture)
        fixture.waitUntilClosed()

        XCTAssertEqual(rootNames(fixture), ["C", "A"])
        fixture.board.drag?.drop(center: .zero)
        ClassicalFolderTestBoard.waitUntil { fixture.board.drag == nil && !committed.isEmpty }
        XCTAssertTrue(try XCTUnwrap(committed.last).folders.isEmpty)
    }

    /// Icon and delete-badge presses find nothing from when the left folder starts closing until
    /// its dissolve begins; from then on they reach the icons again.
    func testPressesFindNothingUntilTheDissolveBegins() throws {
        let fixture = try ClassicalFolderTestBoard([["C", .folder("Work", [["A", "B"]]), "D"]])
        fixture.board.deletability.isDeletable = { _ in true }
        fixture.board.setDeleting(true)
        fixture.board.groupDragSession.markNewFolder(try fixture.folderID("Work"))
        let c = try XCTUnwrap(fixture.board.cell(for: fixture.record("C").id))
        XCTAssertTrue(fixture.board.item(at: fixture.iconCenter(of: c))?.cell === c, "The icon is found before the drag")
        XCTAssertTrue(fixture.board.closebox(at: try badgeCenter(of: c, fixture))?.cell === c,
                      "The badge is found before the drag")
        try dragOut("A", from: "Work", fixture)
        // The root pages were rebuilt for the item that left; read the cells shown now.
        let shownC = try XCTUnwrap(fixture.board.cell(for: fixture.record("C").id))
        let icon = fixture.iconCenter(of: shownC)
        let badge = try badgeCenter(of: shownC, fixture)

        XCTAssertTrue(fixture.board.folders.isClosing)
        XCTAssertNil(fixture.board.item(at: icon), "While the folder closes")
        XCTAssertNil(fixture.board.closebox(at: badge), "While the folder closes")
        fixture.waitUntilClosed()
        XCTAssertEqual(rootNames(fixture), ["C", "B", "D", "A"], "The dissolve has begun")
        XCTAssertTrue(fixture.board.item(at: icon)?.cell === shownC, "Once the dissolve has begun")
        XCTAssertTrue(fixture.board.closebox(at: badge)?.cell === shownC, "Once the dissolve has begun")
        fixture.board.cancelDrag(animated: false)
    }

    // MARK: Helpers

    /// Opens `folder`, starts dragging `name` from it, and moves the item over the backdrop, where it
    /// stays in the folder, then off it, where it leaves.
    private func dragOut(_ name: String, from folder: String, _ fixture: ClassicalFolderTestBoard,
                         file: StaticString = #filePath, line: UInt = #line) throws {
        let open = try fixture.open(folder)
        let cell = try XCTUnwrap(open.cell(for: fixture.record(name).id), file: file, line: line)
        XCTAssertTrue(fixture.board.beginDrag(of: .app(try fixture.record(name)), cell: cell), file: file, line: line)
        fixture.board.drag?.follow(to: try fixture.openBackdropCenter())
        XCTAssertEqual(fixture.board.drag?.leaveFolder(), false, file: file, line: line)
        fixture.board.drag?.follow(to: .zero)
        XCTAssertEqual(fixture.board.drag?.leaveFolder(), true, file: file, line: line)
    }

    /// The first root page as application names, a folder as `Title[member,…]`.
    private func rootNames(_ fixture: ClassicalFolderTestBoard) -> [String] {
        (fixture.board.pages.first ?? []).map { item in
            if let folder = item.folder {
                return "\(folder.title)[\(folder.records.map(\.metadata.displayName).joined(separator: ","))]"
            }
            return item.record?.metadata.displayName ?? "?"
        }
    }

    private func badgeCenter(of cell: ClassicalItemLayer, _ fixture: ClassicalFolderTestBoard) throws -> CGPoint {
        let box = try XCTUnwrap(cell.closeboxLayer, "The cell shows a delete badge")
        let frame = fixture.host.convert(box.bounds, from: box)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }
}
