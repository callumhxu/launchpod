import AppKit
import XCTest
@testable import Launchpod

/// Deleting (jiggle) mode.
@MainActor
final class ClassicalEditingTests: XCTestCase {
    private let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956), dock: .bottom(extent: 59))

    /// Shrink and fade over 0.5 s, then the rest slide over.
    func testRemovedApplicationShrinksAwayAndTheRestSlideOver() async throws {
        let board = try springboard(["Calendar", "Pages", "Safari"], deletable: ["Pages"])
        board.setDeleting(true)
        let page = try XCTUnwrap(board.pager.pages.first)
        let cells = page.itemLayers
        let pagesSlot = cells[1].frame
        board.removeRecord(try XCTUnwrap(board.records.first { $0.metadata.displayName == "Pages" }).id)
        XCTAssertEqual(cells[1].opacity, 0)
        XCTAssertEqual(cells[1].transform.m11, 0.1, accuracy: 1e-9)
        XCTAssertNil(board.item(at: try iconCenter(board, index: 1)).map { _ in () }, "The fading icon takes no clicks")
        board.refreshRecords(board.records)
        XCTAssertEqual(page.records.count, 3, "Catalog updates wait for the animation")
        try await waitUntil { page.records.count == 2 }
        XCTAssertEqual(page.records.map(\.metadata.displayName), ["Calendar", "Safari"])
        XCTAssertTrue(page.itemLayers[0] === cells[0] && page.itemLayers[1] === cells[2], "Remaining cells keep their layers")
        XCTAssertEqual(cells[2].frame, pagesSlot)
        XCTAssertNil(cells[1].superlayer)
        XCTAssertTrue(board.isDeleting, "Deleting mode stays on")
    }

    // MARK: Springboard

    func testDeletingModeJittersEveryCellAndBadgesOnlyDeletableApps() throws {
        let board = try springboard(["Calendar", "Pages", "Safari"], deletable: ["Pages"])
        board.setDeleting(true)
        let cells = try XCTUnwrap(board.pager.pages.first?.itemLayers)
        XCTAssertTrue(cells.allSatisfy(\.isJittering))
        XCTAssertNotNil(cells[0].jitterLayer.animation(forKey: "position"))
        XCTAssertNotNil(cells[0].jitterLayer.animation(forKey: "transform"))
        XCTAssertEqual(cells.map { $0.closeboxLayer != nil }, [false, true, false])
        XCTAssertTrue(cells[1].closeboxLayer?.superlayer === cells[1].jitterLayer, "The badge jitters with the icon")
        board.setDeleting(false)
        XCTAssertTrue(cells.allSatisfy { !$0.isJittering && $0.closeboxLayer == nil })
        XCTAssertNil(cells[0].jitterLayer.animation(forKey: "position"))
    }

    func testOptionShowsDeletingModeOnlyWhileHeld() throws {
        let board = try springboard(["Calendar"], deletable: [])
        board.optionChanged(isDown: true)
        XCTAssertTrue(board.isDeleting)
        board.optionChanged(isDown: false)
        XCTAssertFalse(board.isDeleting)
        board.setDeleting(true)
        board.optionChanged(isDown: true)
        board.optionChanged(isDown: false)
        XCTAssertTrue(board.isDeleting, "Releasing Option leaves the mode only when Option started it")
    }

    func testLongPressTogglesTheModeAndMagnifiesTheHeldIcon() throws {
        let board = try springboard(["Calendar", "Safari"], deletable: [])
        let cells = try XCTUnwrap(board.pager.pages.first?.itemLayers)
        board.longPress(on: cells[1])
        XCTAssertTrue(board.isDeleting)
        XCTAssertTrue(cells[1].isMagnified)
        XCTAssertFalse(cells[1].isJittering, "The held icon stops jittering")
        XCTAssertEqual(cells[1].transformLayer.transform.m11, 1.1, accuracy: 1e-9)
        XCTAssertEqual(cells[1].titleLayer.opacity, 0.9)
        XCTAssertTrue(cells[0].isJittering)
        board.releasePress(on: cells[1])
        XCTAssertFalse(cells[1].isMagnified)
        XCTAssertTrue(cells[1].isJittering)
        board.longPress(on: cells[0])
        XCTAssertFalse(board.isDeleting, "A second long press leaves the mode")
        board.releasePress(on: cells[0])
        board.setDeleting(true)
        board.reset()
        XCTAssertFalse(board.isDeleting, "Closing Launchpad ends the mode")
    }

    // MARK: Press

    func testLongPressFiresAfterTheDelaySuppressesLaunchAndMovementCancelsIt() async throws {
        let board = try springboard(["Calendar", "Safari"], deletable: [])
        let press = ClassicalItemPress()
        press.springboard = board
        press.shiftKeyDown = { false }
        var delays: [TimeInterval] = []
        press.sleep = { delays.append($0) }
        var launched: [String] = []
        press.launch = { launched.append($0.metadata.displayName) }
        let center = try iconCenter(board, index: 1)

        press.beginIcon(at: center)
        try await waitUntil { board.isDeleting }
        XCTAssertEqual(delays, [1])
        XCTAssertTrue(press.end(at: center))
        XCTAssertEqual(launched, [], "The release after a long press does not open the app")

        board.setDeleting(false)
        press.sleep = { _ in try await Task.sleep(for: .seconds(30)) }
        press.beginIcon(at: center)
        press.dragged(to: CGPoint(x: center.x, y: center.y + 3), pagerIsDragging: false)
        XCTAssertTrue(press.end(at: CGPoint(x: center.x, y: center.y + 3)))
        XCTAssertEqual(launched, ["Safari"], "Still over the icon: a click")
        XCTAssertFalse(board.isDeleting)
    }

    func testBadgePressRequestsDeletionOnlyOnReleaseOverIt() throws {
        let board = try springboard(["Pages"], deletable: ["Pages"])
        board.setDeleting(true)
        let press = ClassicalItemPress()
        press.springboard = board
        var requested: [String] = []
        press.requestDeletion = { record, _ in requested.append(record.metadata.displayName) }
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers.first)
        let box = try XCTUnwrap(cell.closeboxLayer)
        let local = CGPoint(x: box.frame.midX, y: box.frame.midY)
        let inPager = cell.convert(local, to: board.pager.layer)
        let badgePoint = CGPoint(x: board.pager.layer.frame.minX + inPager.x, y: board.pager.layer.frame.minY + inPager.y)
        XCTAssertTrue(press.beginBadge(at: badgePoint))
        press.dragged(to: CGPoint(x: badgePoint.x + 80, y: badgePoint.y), pagerIsDragging: false)
        XCTAssertTrue(press.end(at: CGPoint(x: badgePoint.x + 80, y: badgePoint.y)))
        XCTAssertEqual(requested, [])
        XCTAssertTrue(press.beginBadge(at: badgePoint))
        XCTAssertTrue(press.end(at: badgePoint))
        XCTAssertEqual(requested, ["Pages"])
    }

    func testBlankClickAndEscapeLeaveDeletingModeBeforeClosing() throws {
        let board = try springboard(["Calendar"], deletable: [])
        board.pager.shiftKeyDown = { false }
        CALayer().addSublayer(board.pager.layer)
        let content = ClassicalContentView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        content.pager = board.pager
        content.springboard = board
        var dismissals = 0
        content.dismiss = { dismissals += 1 }
        board.setDeleting(true)
        let blank = CGPoint(x: 1300, y: geometry.contentFrame.minY + 200)
        content.mouseDown(with: try mouse(.leftMouseDown, blank, 0))
        content.mouseUp(with: try mouse(.leftMouseUp, blank, 0.1))
        XCTAssertFalse(board.isDeleting)
        XCTAssertEqual(dismissals, 0)

        let keyboard = ClassicalKeyboard(springboard: board)
        keyboard.dismiss = { dismissals += 1 }
        board.setDeleting(true)
        keyboard.cancel()
        XCTAssertFalse(board.isDeleting)
        XCTAssertEqual(dismissals, 0, "Escape ends deleting mode first")
        keyboard.cancel()
        XCTAssertEqual(dismissals, 1)
    }

    // MARK: Helpers

    private func springboard(_ names: [String], deletable: Set<String>) throws -> ClassicalSpringboard {
        let board = ClassicalSpringboard()
        board.deletability.isDeletable = { deletable.contains($0.metadata.displayName) }
        board.show(try names.map(record), geometry: geometry, scale: 1, rightToLeft: false,
                   noResultsText: "No Results") { _, _ in throw CancellationError() }
        return board
    }

    private func iconCenter(_ board: ClassicalSpringboard, index: Int) throws -> CGPoint {
        let cell = try XCTUnwrap(board.pager.pages.first?.itemLayers[index])
        let icon = cell.convert(cell.iconLayer.frame, to: board.pager.layer)
        return CGPoint(x: icon.midX + board.pager.layer.frame.minX, y: icon.midY + board.pager.layer.frame.minY)
    }

    private func mouse(_ type: NSEvent.EventType, _ location: CGPoint, _ time: TimeInterval) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: time, windowNumber: 0,
                                         context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    private func record(_ name: String) throws -> AppRecord {
        let url = URL(filePath: "/Applications/\(name).app", directoryHint: .isDirectory)
        return AppRecord(
            id: AppIdentity(),
            metadata: try AppMetadata(bundleIdentifier: "com.example.\(UUID().uuidString)", bundleURL: url,
                                      displayName: name, version: nil, buildVersion: nil, contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: url.deletingLastPathComponent())
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out.")
    }
}
