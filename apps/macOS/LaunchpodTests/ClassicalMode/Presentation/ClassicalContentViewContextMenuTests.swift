import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalContentViewContextMenuTests: XCTestCase {
    func testRightClickOnBlankCanvasOffersSettingsWithoutDismissingLauncher() throws {
        let fixture = try ClassicalFolderTestBoard([["A"]])
        fixture.content.openSettings = {}
        fixture.content.showsMenuBarItem = { false }
        let point = blankSlot(in: fixture)

        let menu = try XCTUnwrap(fixture.content.menu(for: fixture.mouse(.rightMouseDown, at: point, time: 0)))

        XCTAssertEqual(menu.items.count, 1)
        XCTAssertFalse(menu.items[0].isSeparatorItem)
        XCTAssertTrue(menu.items[0].isEnabled)
        XCTAssertEqual(fixture.dismissals, 0)
    }

    func testSettingsMenuItemCallsWindowOwnerSettingsRoute() throws {
        let fixture = try ClassicalFolderTestBoard([["A"]])
        var settingsRequests = 0
        fixture.content.openSettings = { settingsRequests += 1 }
        fixture.content.showsMenuBarItem = { false }
        let point = blankSlot(in: fixture)
        let menu = try XCTUnwrap(fixture.content.menu(for: fixture.mouse(.rightMouseDown, at: point, time: 0)))
        let item = try XCTUnwrap(menu.items.first)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))

        XCTAssertEqual(settingsRequests, 1)
        XCTAssertEqual(fixture.dismissals, 0)
    }

    func testRightClickOnApplicationIconDoesNotOfferCanvasMenu() throws {
        let fixture = try ClassicalFolderTestBoard([["A"]])
        fixture.content.openSettings = {}
        fixture.content.showsMenuBarItem = { false }
        let cell = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.first)
        let point = fixture.iconCenter(of: cell)

        XCTAssertNil(fixture.content.menu(for: try fixture.mouse(.rightMouseDown, at: point, time: 0)))
    }

    func testRightClickInsideOpenFolderDoesNotOfferRootCanvasMenu() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        fixture.content.openSettings = {}
        fixture.content.showsMenuBarItem = { false }
        try fixture.open("Work")
        let point = try fixture.openBackdropCenter()

        XCTAssertNil(fixture.content.menu(for: try fixture.mouse(.rightMouseDown,
                                                                  at: point, time: 0)))
    }

    func testBlankCanvasMenuTracksMenuBarItemVisibility() throws {
        let fixture = try ClassicalFolderTestBoard([["A"]])
        fixture.content.openSettings = {}
        let showsMenuBarItem = MainActorBox(true)
        fixture.content.showsMenuBarItem = { showsMenuBarItem.value }
        let event = try fixture.mouse(.rightMouseDown, at: blankSlot(in: fixture), time: 0)

        XCTAssertNil(fixture.content.menu(for: event))
        showsMenuBarItem.value = false
        XCTAssertNotNil(fixture.content.menu(for: event))
        showsMenuBarItem.value = true
        XCTAssertNil(fixture.content.menu(for: event))
        XCTAssertEqual(fixture.dismissals, 0)
    }

    private func blankSlot(in fixture: ClassicalFolderTestBoard) -> CGPoint {
        let page = fixture.board.pager.pages[0]
        let frame = ClassicalFolderTestBoard.geometry.grid.cellFrame(at: 4)
        return fixture.host.convert(CGPoint(x: frame.midX, y: frame.midY), from: page.layer)
    }
}
