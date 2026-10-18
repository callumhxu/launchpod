import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalKeyboardTests: XCTestCase {
    private let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956), dock: .bottom(extent: 59))

    func testTypingSearchesArrowsNavigateReturnLaunchesAndEscapeClearsBeforeClosing() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let content = NSView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        content.wantsLayer = true
        let panel = NativeAppTestSupport.makeKeyPanel(size: geometry.screenSize, contentView: content)
        defer { panel.close() }
        let springboard = ClassicalSpringboard()
        springboard.show(try ["Calendar", "Safari", "Stocks"].map(record), geometry: geometry, scale: 1, rightToLeft: false,
                         noResultsText: "No Results") { _, _ in throw CancellationError() }
        let keyboard = ClassicalKeyboard(springboard: springboard)
        keyboard.contentView = content
        keyboard.field.place(in: CALayer(), view: content, frame: geometry.searchFieldFrame, scale: 1, rightToLeft: false,
                             usesGlass: false)
        var launched: [String] = []
        var dismissals = 0
        keyboard.launch = { launched.append($0.metadata.displayName) }
        keyboard.dismiss = { dismissals += 1 }
        panel.makeFirstResponder(content)

        XCTAssertTrue(keyboard.keyDown(try key("s", code: 1)))
        XCTAssertEqual(keyboard.field.text, "s")
        XCTAssertTrue(keyboard.field.isActive)
        XCTAssertFalse(keyboard.field.hasFocus, "Typing shows text without giving the field the caret")
        XCTAssertTrue(keyboard.ownsFocus(in: panel))
        XCTAssertEqual(springboard.pager.pages.first?.records.map(\.metadata.displayName), ["Safari", "Stocks"])
        XCTAssertEqual(springboard.selectedRecord?.metadata.displayName, "Safari")

        let editor = try XCTUnwrap(keyboard.field.textField.currentEditor() as? NSTextView)
        XCTAssertTrue(keyboard.control(keyboard.field.textField, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))))
        XCTAssertEqual(springboard.selectedRecord?.metadata.displayName, "Stocks", "Right moves the selection, not the caret")
        XCTAssertTrue(keyboard.control(keyboard.field.textField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(launched, ["Stocks"])

        XCTAssertTrue(keyboard.control(keyboard.field.textField, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
        XCTAssertTrue(keyboard.field.hasFocus)
        XCTAssertFalse(keyboard.control(keyboard.field.textField, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))),
                       "With the caret, Left edits the text")

        XCTAssertTrue(keyboard.control(keyboard.field.textField, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(keyboard.field.text, "")
        XCTAssertFalse(springboard.isFiltering)
        XCTAssertEqual(dismissals, 0, "The first Escape only clears the search")
        keyboard.cancel()
        XCTAssertEqual(dismissals, 1)

        keyboard.reset()
        XCTAssertFalse(keyboard.field.isActive)
        XCTAssertTrue(panel.firstResponder === content)
    }

    /// While an input method composes text the placeholder is hidden, because the composition is
    /// shown, but only committed text searches; cancelling the composition returns the field to its
    /// empty look without a search.
    func testComposedTextHidesThePlaceholderButOnlyCommittedTextSearches() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let content = NSView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        content.wantsLayer = true
        let panel = NativeAppTestSupport.makeKeyPanel(size: geometry.screenSize, contentView: content)
        defer { panel.close() }
        let springboard = ClassicalSpringboard()
        springboard.show(try ["Calendar", "Safari", "Stocks"].map(record), geometry: geometry, scale: 1, rightToLeft: false,
                         noResultsText: "No Results") { _, _ in throw CancellationError() }
        let keyboard = ClassicalKeyboard(springboard: springboard)
        keyboard.contentView = content
        keyboard.field.place(in: CALayer(), view: content, frame: geometry.searchFieldFrame, scale: 1, rightToLeft: false,
                             usesGlass: false)
        panel.makeFirstResponder(content)
        XCTAssertTrue(keyboard.keyDown(try key("s", code: 1)))
        let editor = try XCTUnwrap(keyboard.field.textField.currentEditor() as? NSTextView)
        XCTAssertTrue(keyboard.control(keyboard.field.textField, textView: editor,
                                       doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(keyboard.field.text, "")
        XCTAssertFalse(keyboard.field.placeholderLayer.isHidden)
        let notFound = NSRange(location: NSNotFound, length: 0)

        editor.setMarkedText("sa", selectedRange: NSRange(location: 2, length: 0), replacementRange: notFound)
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertTrue(keyboard.field.placeholderLayer.isHidden, "The composition is shown instead of the placeholder")
        XCTAssertEqual(keyboard.field.committedText, "")
        XCTAssertFalse(springboard.isFiltering, "Composed text does not search")

        editor.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: notFound)
        editor.unmarkText()
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertFalse(keyboard.field.placeholderLayer.isHidden, "A cancelled composition leaves the empty field")
        XCTAssertTrue(keyboard.field.closeLayer.isHidden)
        XCTAssertFalse(springboard.isFiltering)

        editor.setMarkedText("st", selectedRange: NSRange(location: 2, length: 0), replacementRange: notFound)
        editor.insertText("st", replacementRange: notFound)
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertEqual(keyboard.field.committedText, "st")
        XCTAssertTrue(springboard.isFiltering)
        XCTAssertEqual(springboard.pager.pages.first?.records.map(\.metadata.displayName), ["Stocks"],
                       "Committed text searches")

        keyboard.reset()
        XCTAssertFalse(keyboard.field.isActive)
        XCTAssertFalse(keyboard.field.placeholderLayer.isHidden)
        XCTAssertFalse(springboard.isFiltering)
    }

    /// ⌘A reaches the field editor although no menu bar serves the inactive app; the clear button
    /// brightens while pressed and clears only on release over it.
    func testEditingShortcutsAndTheClearButtonPress() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let content = NSView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        content.wantsLayer = true
        let panel = NativeAppTestSupport.makeKeyPanel(size: geometry.screenSize, contentView: content)
        defer { panel.close() }
        let springboard = ClassicalSpringboard()
        springboard.show(try ["Safari"].map(record), geometry: geometry, scale: 1, rightToLeft: false,
                         noResultsText: "No Results") { _, _ in throw CancellationError() }
        let keyboard = ClassicalKeyboard(springboard: springboard)
        keyboard.contentView = content
        keyboard.field.place(in: CALayer(), view: content, frame: geometry.searchFieldFrame, scale: 1, rightToLeft: false,
                             usesGlass: false)
        panel.makeFirstResponder(content)
        for (character, code) in [("s", UInt16(1)), ("a", 0), ("f", 3)] {
            XCTAssertTrue(keyboard.keyDown(try key(character, code: code)))
        }
        XCTAssertEqual(keyboard.field.text, "saf")
        XCTAssertTrue(keyboard.performKeyEquivalent(try key("a", code: 0, modifiers: .command)))
        let editor = try XCTUnwrap(keyboard.field.textField.currentEditor())
        XCTAssertEqual(editor.selectedRange, NSRange(location: 0, length: 3))
        XCTAssertFalse(keyboard.performKeyEquivalent(try key("q", code: 12, modifiers: .command)))

        let close = keyboard.field.closeLayer.frame.offsetBy(dx: geometry.searchFieldFrame.minX, dy: geometry.searchFieldFrame.minY)
        let center = CGPoint(x: close.midX, y: close.midY)
        XCTAssertTrue(keyboard.mouseDown(at: center))
        XCTAssertEqual(keyboard.field.closeLayer.opacity, 1)
        keyboard.mouseDragged(to: CGPoint(x: center.x, y: center.y + 60))
        XCTAssertEqual(keyboard.field.closeLayer.opacity, 0.3)
        keyboard.mouseUp(at: CGPoint(x: center.x, y: center.y + 60))
        XCTAssertEqual(keyboard.field.text, "saf", "Releasing away from the button keeps the text")
        XCTAssertTrue(keyboard.mouseDown(at: center))
        keyboard.mouseUp(at: center)
        XCTAssertEqual(keyboard.field.text, "")
        XCTAssertFalse(springboard.isFiltering)
    }

    func testArrowKeysAtTheContentViewSelectAndReturnLaunches() throws {
        let springboard = ClassicalSpringboard()
        springboard.show(try ["Calendar", "Safari"].map(record), geometry: geometry, scale: 1, rightToLeft: false,
                         noResultsText: "No Results") { _, _ in throw CancellationError() }
        let keyboard = ClassicalKeyboard(springboard: springboard)
        var launched: [String] = []
        keyboard.launch = { launched.append($0.metadata.displayName) }
        XCTAssertTrue(keyboard.keyDown(try key(String(UnicodeScalar(NSRightArrowFunctionKey)!), code: 124)))
        XCTAssertTrue(keyboard.keyDown(try key(String(UnicodeScalar(NSRightArrowFunctionKey)!), code: 124)))
        XCTAssertTrue(keyboard.keyDown(try key("\r", code: 36)))
        XCTAssertEqual(launched, ["Safari"])
        XCTAssertFalse(keyboard.keyDown(try key("q", code: 12, modifiers: .control)), "Control shortcuts go to the system")
        XCTAssertTrue(keyboard.keyDown(try key("q", code: 12, modifiers: .command)),
                      "Like `-[ECSBLayer keyDown:]`, other ⌘ combinations go to the search field")
    }

    func testDragSearchResetClearsVisibleTextAndReturnsTheFieldToIdle() throws {
        let springboard = ClassicalSpringboard()
        springboard.show(try ["Calendar", "Safari"].map(record), geometry: geometry, scale: 1,
                         rightToLeft: false, noResultsText: "No Results") { _, _ in throw CancellationError() }
        let keyboard = ClassicalKeyboard(springboard: springboard)
        keyboard.field.activate()
        keyboard.field.textField.stringValue = "saf"
        keyboard.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification,
                                                   object: keyboard.field.textField))
        XCTAssertTrue(springboard.isFiltering)
        XCTAssertEqual(keyboard.field.text, "saf")
        XCTAssertFalse(keyboard.field.closeLayer.isHidden)

        springboard.clearSearch()
        keyboard.clearSearchForDrag()

        XCTAssertFalse(springboard.isFiltering)
        XCTAssertEqual(keyboard.field.text, "")
        XCTAssertFalse(keyboard.field.isActive)
        XCTAssertTrue(keyboard.field.placeholderLayer.isHidden == false)
        XCTAssertTrue(keyboard.field.closeLayer.isHidden)
    }

    // MARK: Keys while an icon is held or dragged

    /// From the press on an icon until release, typing does not reach the search,
    /// Return launches nothing, and Tab still toggles the field's focus. Until the drag begins the
    /// arrows skip that check and the pager only refuses to navigate while dragging, so the arrows
    /// select and ⌘→ turns the page.
    func testKeysWhileAnIconIsPressedNeitherSearchNorLaunchButStillNavigate() throws {
        let scene = try DragScene(self)
        defer { scene.close() }
        scene.content.mouseDown(with: try scene.mouse(.leftMouseDown, at: try scene.iconCenter(0), time: 0))
        XCTAssertNotNil(scene.content.press.pressedItem)

        try scene.expectHeldKeys(navigates: true)
        XCTAssertNotNil(scene.content.press.pressedItem, "The press continues")
        XCTAssertNil(scene.board.drag)
        scene.content.press.cancel()
    }

    /// A press during a search keeps the typed text but takes focus away from the field;
    /// further typing and the editing shortcuts are swallowed.
    func testKeysWhileAResultIsPressedKeepTheSearchTextAndSwallowEdits() throws {
        let scene = try DragScene(self)
        defer { scene.close() }
        scene.content.keyDown(with: try key("a", code: 0))
        scene.content.keyDown(with: try key("\t", code: 48))
        XCTAssertEqual(scene.keyboard.field.text, "a")
        XCTAssertTrue(scene.keyboard.field.hasFocus)
        scene.content.mouseDown(with: try scene.mouse(.leftMouseDown, at: try scene.iconCenter(0), time: 0))
        XCTAssertEqual(scene.content.press.pressedItem?.item.title, "A")

        scene.content.keyDown(with: try key("x", code: 7))
        XCTAssertTrue(scene.keyboard.performKeyEquivalent(try key("a", code: 0, modifiers: .command)),
                      "⌘A is swallowed")
        XCTAssertTrue(scene.keyboard.performKeyEquivalent(try key("v", code: 9, modifiers: .command)),
                      "⌘V is swallowed")

        XCTAssertEqual(scene.keyboard.field.text, "a", "The search text is kept")
        XCTAssertFalse(scene.keyboard.field.hasFocus, "The field loses focus")
        XCTAssertTrue(scene.window.firstResponder === scene.content,
                      "The field stops receiving keys (`setTextFieldActive:NO`, 0x100081630)")
        XCTAssertTrue(scene.board.isFiltering)
        scene.content.press.cancel()
        scene.content.drag.pressEnded()

        scene.content.keyDown(with: try key("b", code: 11))
        XCTAssertEqual(scene.keyboard.field.text, "ab",
                       "The next key reactivates the field and continues after the kept text (0x1000816a0)")
    }

    /// While dragging, typing and Return are held back and the arrows and ⌘→ no longer navigate;
    /// Escape cancels the drag with slide-back, restoring the arrangement without saving.
    func testKeysWhileDraggingAreHeldBackAndEscapeCancelsTheDrag() throws {
        let scene = try DragScene(self)
        defer { scene.close() }
        let original = scene.names
        var committed: [ClassicalLayout] = []
        scene.board.layoutDidChange = { committed.append($0) }
        try scene.startDrag(to: 2)
        XCTAssertEqual(scene.names[0].prefix(3), ["B", "C", "A"])

        try scene.expectHeldKeys(navigates: false)
        XCTAssertNotNil(scene.board.drag, "Return does not end the drag")
        XCTAssertEqual(scene.names[0].prefix(3), ["B", "C", "A"])

        scene.content.keyDown(with: try key("\u{1b}", code: 53))
        XCTAssertEqual(scene.names, original, "Escape restores the arrangement")
        XCTAssertEqual(scene.dismissals, 0)
        scene.content.mouseUp(with: try scene.mouse(.leftMouseUp, at: try scene.iconCenter(0), time: 200))
        ClassicalDragTestBoard.waitUntil { scene.board.drag == nil }
        XCTAssertEqual(scene.names, original)
        XCTAssertTrue(committed.isEmpty, "A cancelled drag saves nothing")
        XCTAssertTrue(scene.launched.isEmpty)
    }

    /// Once the item is released, `dragging` is false although the icon may still be
    /// landing, so Escape takes its normal course and first leaves deleting mode.
    func testEscapeAfterTheDropIsNotConsumedByTheLandingDrag() throws {
        let scene = try DragScene(self)
        defer { scene.close() }
        var committed: [ClassicalLayout] = []
        scene.board.layoutDidChange = { committed.append($0) }
        scene.board.setDeleting(true)
        let destination = try scene.startDrag(to: 2)
        scene.content.mouseUp(with: try scene.mouse(.leftMouseUp, at: destination, time: 200))

        scene.content.keyDown(with: try key("\u{1b}", code: 53))

        XCTAssertFalse(scene.board.isDeleting, "Escape leaves deleting mode instead of cancelling the drop")
        XCTAssertEqual(scene.dismissals, 0)
        ClassicalDragTestBoard.waitUntil { scene.board.drag == nil }
        XCTAssertEqual(scene.names[0].prefix(3), ["B", "C", "A"], "The drop stands")
        XCTAssertEqual(committed.count, 1)
    }

    // MARK: Folders

    /// Return on a selected folder opens it with its first application selected; Return inside
    /// launches the selection.
    func testReturnOpensASelectedFolderAndLaunchesInside() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        fixture.board.select(item: .folder(try fixture.folderID("Work")))
        fixture.keyboard.performAction()
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        ClassicalFolderTestBoard.waitUntil { folder.selectedRecord != nil }
        XCTAssertEqual(folder.selectedRecord?.metadata.displayName, "B")
        XCTAssertTrue(fixture.launched.isEmpty, "Opening a folder launches nothing")

        fixture.keyboard.performAction()
        XCTAssertEqual(fixture.launched, ["B"])
    }

    /// Escape inside a folder first leaves deleting mode, then closes the folder, and only then
    /// reaches the search or the launcher.
    func testEscapeLeavesDeletingModeBeforeClosingTheFolder() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let folder = try fixture.open("Work")
        fixture.board.setDeleting(true)
        XCTAssertTrue(folder.isDeleting)

        fixture.keyboard.cancel()
        XCTAssertFalse(folder.isDeleting)
        XCTAssertTrue(fixture.board.folders.openFolder === folder, "The first Escape only leaves deleting mode")
        fixture.keyboard.cancel()
        fixture.waitUntilClosed()
        XCTAssertEqual(fixture.dismissals, 0, "Closing the folder does not close Launchpad")
        fixture.keyboard.cancel()
        XCTAssertEqual(fixture.dismissals, 1)
    }

    /// Inside a folder only Command-Up closes it, and the closed folder's cell is then selected on
    /// its root page. Command-Down, -Left and -Right leave the folder open and the root page still.
    func testOnlyCommandUpClosesTheFolderAndSelectsItsCell() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])], ["C"]])
        let folder = try fixture.open("Work", selectingFirstItem: true)
        ClassicalFolderTestBoard.waitUntil { folder.selectedRecord != nil }
        let arrows: [(String, UInt16)] = [(String(UnicodeScalar(NSDownArrowFunctionKey)!), 125),
                                          (String(UnicodeScalar(NSLeftArrowFunctionKey)!), 123),
                                          (String(UnicodeScalar(NSRightArrowFunctionKey)!), 124)]
        for (characters, code) in arrows {
            _ = fixture.keyboard.keyDown(try fixture.key(characters, code: code, modifiers: .command))
            XCTAssertTrue(fixture.board.folders.openFolder === folder, "Key \(code) keeps the folder open")
            XCTAssertEqual(fixture.board.pager.currentPage, 0, "Key \(code) does not turn the root page")
        }

        let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        XCTAssertTrue(fixture.keyboard.keyDown(try fixture.key(up, code: 126, modifiers: .command)))
        fixture.waitUntilClosed()
        XCTAssertEqual(fixture.board.pager.currentPage, 0, "Closing does not also turn the root page")
        XCTAssertEqual(fixture.board.selectedItemID, .folder(try fixture.folderID("Work")),
                       "The closed folder's cell is selected")
    }

    /// Command-Down on a selected folder opens it with its first application selected; nothing launches.
    func testCommandDownOpensASelectedFolderSelectingItsFirstApplication() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        fixture.board.select(item: .folder(try fixture.folderID("Work")))
        let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        XCTAssertTrue(fixture.keyboard.keyDown(try fixture.key(down, code: 125, modifiers: .command)))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        ClassicalFolderTestBoard.waitUntil { folder.selectedRecord != nil }
        XCTAssertEqual(folder.selectedRecord?.metadata.displayName, "B")
        XCTAssertTrue(fixture.launched.isEmpty)
    }

    /// A content view with a real panel, springboard, keyboard and search field for driving presses,
    /// drags and keys together. Seven applications fill two pages of a 2 × 3 grid.
    @MainActor
    private final class DragScene {
        let test: ClassicalKeyboardTests
        let restore: @MainActor () -> Void
        let geometry = ClassicalDragTestBoard.geometry
        let content: ClassicalContentView
        let window: NSPanel
        let board = ClassicalSpringboard()
        let keyboard: ClassicalKeyboard
        let host: CALayer
        var launched: [String] = []
        var dismissals = 0

        init(_ test: ClassicalKeyboardTests) throws {
            self.test = test
            restore = try NativeAppTestSupport.isolateHostWindows()
            content = ClassicalContentView(frame: CGRect(origin: .zero, size: geometry.screenSize))
            content.wantsLayer = true
            window = NativeAppTestSupport.makeKeyPanel(size: geometry.screenSize, contentView: content)
            host = try XCTUnwrap(content.layer)
            board.deletability.isDeletable = { _ in false }
            host.addSublayer(board.pager.layer)
            board.show(try ["A", "B", "C", "D", "E", "F", "G"].map(ClassicalDragTestBoard.record), geometry: geometry,
                       scale: 1, rightToLeft: false, noResultsText: "No Results") { _, _ in throw CancellationError() }
            keyboard = ClassicalKeyboard(springboard: board)
            keyboard.contentView = content
            keyboard.field.place(in: CALayer(), view: content, frame: geometry.searchFieldFrame, scale: 1, rightToLeft: false,
                             usesGlass: false)
            content.springboard = board
            content.pager = board.pager
            content.keyboard = keyboard
            content.drag.dockHitRegion = { _ in nil }
            keyboard.launch = { [unowned self] in self.launched.append($0.metadata.displayName) }
            keyboard.dismiss = { [unowned self] in self.dismissals += 1 }
            content.launch = { [unowned self] in self.launched.append($0.metadata.displayName) }
            window.makeFirstResponder(content)
        }

        func close() {
            content.drag.reset()
            window.close()
            restore()
        }

        var names: [[String]] { ClassicalDragTestBoard.names(board.pages) }

        /// The icon of the application at `index` in the arrangement, in content-layer coordinates.
        func iconCenter(_ index: Int) throws -> CGPoint {
            let cell = try XCTUnwrap(board.cell(for: board.records[index].id))
            let icon = cell.iconLayer.convert(cell.iconLayer.bounds, to: host)
            return CGPoint(x: icon.midX, y: icon.midY)
        }

        func mouse(_ type: NSEvent.EventType, at point: CGPoint, time: TimeInterval) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                                             clickCount: 1, pressure: 1))
        }

        /// Presses the first icon, starts dragging it and moves it slowly to `slot`; returns the
        /// pointer location there.
        @discardableResult
        func startDrag(to slot: Int) throws -> CGPoint {
            let start = try iconCenter(0)
            content.mouseDown(with: try mouse(.leftMouseDown, at: start, time: 0))
            content.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: start.x + 4, y: start.y), time: 10))
            XCTAssertNotNil(board.drag)
            let frame = geometry.grid.cellFrame(at: slot)
            var destination = host.convert(CGPoint(x: frame.midX, y: frame.midY), from: board.pager.pages[0].layer)
            destination.x += 10 // Past the current slot's half-cell hysteresis boundary.
            content.mouseDragged(with: try mouse(.leftMouseDragged, at: destination, time: 100))
            return destination
        }

        /// Typing, arrows, ⌘→ and Return change nothing; Tab toggles the field's focus.
        /// Typing, Return and Tab while an icon is held or dragged; `navigates` says whether the arrows
        /// and ⌘→ still reach the grid.
        func expectHeldKeys(navigates: Bool) throws {
            let page = board.pager.currentPage
            content.keyDown(with: try test.key("s", code: 1))
            XCTAssertEqual(keyboard.field.text, "", "Typing does not reach the search field")
            XCTAssertFalse(board.isFiltering)
            content.keyDown(with: try test.key("\r", code: 36))
            XCTAssertTrue(launched.isEmpty, "Return launches nothing")
            content.keyDown(with: try test.key("\t", code: 48))
            XCTAssertTrue(keyboard.field.hasFocus, "Tab still gives the field focus")
            content.keyDown(with: try test.key("\t", code: 48))
            XCTAssertFalse(keyboard.field.hasFocus)
            if window.firstResponder !== content { window.makeFirstResponder(content) }
            let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
            let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
            content.keyDown(with: try test.key(right, code: 124))
            content.keyDown(with: try test.key(down, code: 125))
            content.keyDown(with: try test.key(right, code: 124, modifiers: .command))
            if navigates {
                XCTAssertNotNil(board.selectedRecord, "Arrows still select")
                XCTAssertEqual(board.pager.currentPage, page + 1, "⌘→ still turns the page")
            } else {
                XCTAssertNil(board.selectedRecord, "Arrows do not select")
                XCTAssertEqual(board.pager.currentPage, page, "⌘→ does not turn the page")
            }
        }
    }

    fileprivate func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                       context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                       isARepeat: false, keyCode: code))
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
}
