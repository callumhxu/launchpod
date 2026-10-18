import AppKit
import QuartzCore
import XCTest
@testable import Launchpod

/// A Classical springboard whose root pages hold named placeholder applications and folders, in a
/// content view with the springboard layers nested as in the Classical window (host → background →
/// root pager), for tests that open and close folders. It only builds the fixture, finds cells and
/// converts points; the tests own every expectation.
@MainActor
final class ClassicalFolderTestBoard {
    /// One root slot: an application, or a folder with its title and pages of application names.
    enum Slot: ExpressibleByStringLiteral {
        case app(String)
        case folder(String, [[String]])

        init(stringLiteral value: String) { self = .app(value) }
    }

    /// A 2 × 3 grid, so a root or folder page holds six items.
    static let geometry = ClassicalDragTestBoard.geometry
    let content: ClassicalContentView
    let host: CALayer
    let background = CALayer()
    let board = ClassicalSpringboard()
    let keyboard: ClassicalKeyboard
    private(set) var records: [String: AppRecord] = [:]
    private(set) var folderIDs: [String: ClassicalLayoutFolder.ID] = [:]
    var launched: [String] = []
    var dismissals = 0

    /// `geometry` replaces the 2 × 3 grid when a test needs other root rows or columns;
    /// `folderGlass` is the presentation's Liquid Glass choice, applied before the pages are built.
    init(_ pages: [[Slot]], geometry: ClassicalSpringboardGeometry? = nil, folderGlass: Bool = false) throws {
        let geometry = geometry ?? Self.geometry
        content = ClassicalContentView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        content.wantsLayer = true
        host = try XCTUnwrap(content.layer)
        keyboard = ClassicalKeyboard(springboard: board)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.frame = host.bounds
        host.addSublayer(background)
        background.addSublayer(board.pager.layer)
        CATransaction.commit()
        board.deletability.isDeletable = { _ in false }
        board.folderGlassEnabled = folderGlass
        board.folders.reduceMotion = { false }
        board.folders.sleep = { _ in }
        var items: [[ClassicalPageItem]] = []
        for page in pages {
            items.append(try page.map { slot in
                switch slot {
                case let .app(name):
                    return .app(try self.make(name))
                case let .folder(title, folderPages):
                    let id = ClassicalLayoutFolder.ID()
                    folderIDs[title] = id
                    return .folder(ClassicalPageFolder(id: id, title: title,
                                                       pages: try folderPages.map { try $0.map(self.make) }))
                }
            })
        }
        board.show(pages: items, geometry: geometry, scale: 1, rightToLeft: false,
                   noResultsText: "No Results") { _, _ in throw CancellationError() }
        keyboard.contentView = content
        content.springboard = board
        content.pager = board.pager
        content.keyboard = keyboard
        content.drag.dockHitRegion = { _ in nil }
        keyboard.launch = { [unowned self] in self.launched.append($0.metadata.displayName) }
        keyboard.dismiss = { [unowned self] in self.dismissals += 1 }
        content.launch = { [unowned self] in self.launched.append($0.metadata.displayName) }
        content.dismiss = { [unowned self] in self.dismissals += 1 }
    }

    private func make(_ name: String) throws -> AppRecord {
        let record = try ClassicalDragTestBoard.record(name)
        records[name] = record
        return record
    }

    func record(_ name: String) throws -> AppRecord {
        try XCTUnwrap(records[name], "No application named \(name)")
    }

    func folderID(_ title: String) throws -> ClassicalLayoutFolder.ID {
        try XCTUnwrap(folderIDs[title], "No folder titled \(title)")
    }

    /// The closed cell of the folder `title` on the current root page.
    func folderCell(_ title: String) throws -> ClassicalFolderItemLayer {
        let id = try folderID(title)
        let page = board.pager.pages[board.pager.currentPage]
        let index = try XCTUnwrap(page.items.firstIndex { $0.id == .folder(id) }, "Folder \(title) is not on this page")
        return try XCTUnwrap(page.itemLayers[index] as? ClassicalFolderItemLayer)
    }

    /// The centre of `cell`'s icon (a folder's backdrop area) in the content view's coordinates.
    func iconCenter(of cell: ClassicalItemLayer) -> CGPoint {
        let icon = host.convert(cell.iconLayer.frame, from: cell.jitterLayer)
        return CGPoint(x: icon.midX, y: icon.midY)
    }

    /// The centre of the open folder's backdrop in the content view's coordinates.
    func openBackdropCenter() throws -> CGPoint {
        let folder = try XCTUnwrap(board.folders.openFolder, "No folder is open")
        let backdrop = host.convert(folder.geometry.backdropFrame, from: folder.layer)
        return CGPoint(x: backdrop.midX, y: backdrop.midY)
    }

    /// Opens the folder `title` and runs the main run loop until it has finished opening.
    @discardableResult
    func open(_ title: String, selectingFirstItem: Bool = false) throws -> ClassicalFolder {
        XCTAssertTrue(board.openFolder(try folderID(title), selectingFirstItem: selectingFirstItem))
        Self.waitUntil { !self.board.folders.isOpening }
        return try XCTUnwrap(board.folders.openFolder)
    }

    func waitUntilOpened() {
        Self.waitUntil { !self.board.folders.isOpening }
    }

    func waitUntilClosed() {
        Self.waitUntil { !self.board.folders.isActive }
    }

    func mouse(_ type: NSEvent.EventType, at point: CGPoint, time: TimeInterval) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time, windowNumber: 0,
                                         context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    /// A press and release at `point`, the release `moved` away from the press.
    func click(at point: CGPoint, moved: CGVector = .zero, time: TimeInterval) throws {
        content.mouseDown(with: try mouse(.leftMouseDown, at: point, time: time))
        let end = CGPoint(x: point.x + moved.dx, y: point.y + moved.dy)
        if moved != .zero { content.mouseDragged(with: try mouse(.leftMouseDragged, at: end, time: time + 0.05)) }
        content.mouseUp(with: try mouse(.leftMouseUp, at: end, time: time + 0.1))
    }

    func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                       windowNumber: 0, context: nil, characters: characters,
                                       charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    static func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        ClassicalDragTestBoard.waitUntil(condition, file: file, line: line)
    }
}
