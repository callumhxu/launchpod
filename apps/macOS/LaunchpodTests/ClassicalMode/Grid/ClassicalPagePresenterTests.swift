import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalPagePresenterTests: XCTestCase {
    func testCanCreateAFolderByDroppingOneApplicationOnAnother() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let a = try ClassicalDragTestBoard.record("A")
        let b = try ClassicalDragTestBoard.record("B")
        let c = try ClassicalDragTestBoard.record("C")
        var committed: ClassicalLayout?
        var content = ClassicalPageContent(records: { [a, b, c] }, icon: { _, _ in throw CancellationError() })
        content.commitFolderDrag = { committed = $0 }
        let presenter = ClassicalPagePresenter(hidesDock: { false }, dockDisplay: { nil })
        presenter.content = content
        defer { presenter.stop() }
        let view = ClassicalContentView(frame: CGRect(origin: .zero, size: screen.frame.size))
        let host = CALayer()
        host.frame = view.bounds
        presenter.present(on: screen, in: host, view: view, revealingDock: false)
        let board = presenter.springboard
        let cells = try XCTUnwrap(board.pager.pages.first?.itemLayers)
        let start = host.convert(cells[0].position, from: cells[0].superlayer)
        let targetFrame = host.convert(cells[1].iconLayer.frame, from: cells[1].jitterLayer)
        let target = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        let drag = ClassicalItemDrag()
        drag.springboard = board

        XCTAssertTrue(drag.begin(board.pages[0][0], cell: cells[0], at: start, time: 0))
        drag.moved(to: target, time: 100)
        drag.ended(at: target)

        let layout = try XCTUnwrap(committed)
        let folder = try XCTUnwrap(layout.folders.first)
        XCTAssertEqual(layout.folders.count, 1)
        XCTAssertEqual(folder.pages, [[b.id, a.id]])
        XCTAssertEqual(layout.pages.first?.compactMap(\.app), [c.id])
    }

    func testConnectionRoutesInputToTheSameSpringboardAndKeyboard() throws {
        let preferences = try TemporaryPreferences()
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let defaults = preferences.defaults
        let presenter = ClassicalPagePresenter(hidesDock: { false },
                                               dockReveal: ClassicalDockReveal(defaults: defaults, operations: nil),
                                               dockDisplay: { nil })
        let view = ClassicalContentView(frame: .zero)
        presenter.connect(view)
        XCTAssertTrue(view.pager === presenter.springboard.pager)
        XCTAssertTrue(view.keyboard === presenter.keyboard)
        XCTAssertTrue(view.springboard === presenter.springboard)
        presenter.stop()
    }

    func testUnknownDockDisplayDoesNotDismissButAChangedKnownDisplayDoes() throws {
        let preferences = try TemporaryPreferences()
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let defaults = preferences.defaults
        let dock = MainActorBox<NSNumber?>(nil)
        let presenter = ClassicalPagePresenter(hidesDock: { false },
                                               dockReveal: ClassicalDockReveal(defaults: defaults, operations: nil),
                                               dockDisplay: { dock.value })
        XCTAssertFalse(presenter.dockLeft(display: 11))
        dock.value = 11
        XCTAssertFalse(presenter.dockLeft(display: 11))
        XCTAssertTrue(presenter.dockLeft(display: 12))
        XCTAssertTrue(presenter.dockLeft(display: nil))
        dock.value = nil
        XCTAssertFalse(presenter.dockLeft(display: 12))
    }
}
