import AppKit
import XCTest
@testable import Launchpod

/// An open folder: its own pages, keyboard selection, title edits and removals.
@MainActor
final class ClassicalFolderTests: XCTestCase {
    func testOpenFolderInheritsTheClosedCellsGlassChoice() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let original = try fixture.folderCell("Work")
        let cell = ClassicalFolderItemLayer(folder: original.folder, layout: original.layout, scale: original.scale,
                                            rightToLeft: original.rightToLeft, glassEnabled: true)
        let folder = ClassicalFolder(content: original.folder, cell: cell, springboard: ClassicalFolderTestBoard.geometry,
                                     scale: original.scale, rightToLeft: original.rightToLeft,
                                     icon: { _, _ in throw CancellationError() }, cachedIcon: { _, _ in nil })

        XCTAssertTrue(cell.glassEnabled)
        XCTAssertTrue(folder.layer.glassEnabled)
        XCTAssertNil(folder.layer.backdropLayer.backgroundFilters,
                     "The panel geometry is a guide for the native AppKit glass view")
    }

    /// Only an empty title is rejected: any other title, even one of spaces, renames the folder, and
    /// the panel and the closed cell show it.
    func testTitleEditRejectsOnlyAnEmptyTitle() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        var renamed: [String] = []
        fixture.board.folderRenamed = { id, title in
            XCTAssertEqual(id, try? fixture.folderID("Work"))
            renamed.append(title)
            return nil
        }
        let folder = try fixture.open("Work")
        let cell = try fixture.folderCell("Work")

        folder.commitTitle("")
        XCTAssertEqual(folder.layer.titleLayer.string as? String, "Work", "An empty title keeps the old one")
        XCTAssertTrue(renamed.isEmpty)

        folder.commitTitle("Projects")
        XCTAssertEqual(renamed, ["Projects"])
        XCTAssertEqual(folder.layer.titleLayer.string as? String, "Projects")
        XCTAssertEqual(cell.titleLayer.string as? String, "Projects")
        XCTAssertFalse(folder.layer.titleLayer.isHidden)

        folder.commitTitle("Projects")
        XCTAssertEqual(renamed, ["Projects"], "An unchanged title saves nothing")

        folder.commitTitle("  ")
        XCTAssertEqual(renamed, ["Projects", "  "], "A title of spaces is a title")
        XCTAssertEqual(folder.content.title, "  ")
        XCTAssertEqual(cell.titleLayer.string as? String, "  ")
    }

    /// Renaming a built-in folder whose title is localized makes the title the user's own: the saved
    /// folder and the shown folder both stop using the default title, so later drag commits keep the
    /// new title and a language change does not bring the built-in name back.
    func testRenamingABuiltInFolderKeepsTheUsersTitle() async throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Tmp", [["A", "B"]]), "C"]])
        let a = try fixture.record("A"), b = try fixture.record("B"), c = try fixture.record("C")
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString,
                                                                          directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClassicalLayoutStore(directoryURL: directory)
        let builtIn = ClassicalLayoutFolder(id: .defaultOther, title: "Other", pages: [[a.id, b.id]],
                                            usesDefaultTitle: true)
        try await store.save(ClassicalLayout(pages: [[.folder(builtIn), .app(c.id)]]))
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        fixture.board.folderRenamed = { model.renameFolder($0, to: $1) }
        fixture.board.refresh(pages: [[.folder(ClassicalPageFolder(id: .defaultOther, title: "Other", pages: [[a, b]],
                                                                   usesDefaultTitle: true)), .app(c)]])
        XCTAssertTrue(fixture.board.openFolder(.defaultOther))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        XCTAssertEqual(folder.content.title, "Other")

        folder.commitTitle("Tools")

        let saved = try XCTUnwrap(model.layout?.folder(.defaultOther))
        XCTAssertEqual(saved.title, "Tools")
        XCTAssertFalse(saved.usesDefaultTitle)
        let shown = try XCTUnwrap(fixture.board.pages.first?.first?.folder)
        XCTAssertEqual(shown.title, "Tools")
        XCTAssertFalse(shown.usesDefaultTitle)
        guard case let .folder(committed) = try XCTUnwrap(fixture.board.pages.first?.first?.layoutItem) else {
            return XCTFail("The folder's slot must hold a folder")
        }
        XCTAssertEqual(committed.title, "Tools", "A later drag commit saves the user's title")
        XCTAssertFalse(committed.usesDefaultTitle)
        for identifier in ["en", "fr", "ja"] {
            XCTAssertEqual(ClassicalLayoutFolder.displayTitle(for: .defaultOther, title: saved.title,
                                                              usesDefaultTitle: saved.usesDefaultTitle,
                                                              locale: Locale(identifier: identifier)), "Tools")
        }
        fixture.board.folders.close(animated: false)
    }

    /// Opening a folder never starts a title edit by itself; a release on the title does.
    func testTitleEditingStartsOnlyFromTheTitle() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let folder = try fixture.open("Work")
        XCTAssertFalse(folder.titleEditor.isEditing, "A folder does not open in title editing")
        let title = fixture.host.convert(folder.layer.titleLayer.frame, from: folder.layer)
        try fixture.click(at: CGPoint(x: title.midX, y: title.midY), time: 0)
        XCTAssertTrue(folder.titleEditor.isEditing)
        XCTAssertTrue(fixture.board.folders.openFolder === folder, "Clicking the title keeps the folder open")
        folder.endTitleEditing()
        XCTAssertFalse(folder.titleEditor.isEditing)
        XCTAssertEqual(folder.layer.titleLayer.string as? String, "Work", "Ending without a change keeps the title")
    }

    func testTitleEditorUsesTheDisplayedFolderTitleFont() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let folder = try fixture.open("Work")
        folder.beginTitleEditing(in: fixture.content)
        let fieldFont = try XCTUnwrap(folder.titleEditor.textField.font)
        XCTAssertEqual(fieldFont.fontName, ClassicalFolderLayer.titleFont.fontName)
        XCTAssertEqual(fieldFont.pointSize, 28)
        folder.endTitleEditing()
    }

    /// A title click in a key panel accepts typed text, then Return saves it through the layout owner.
    func testClickedTitleAcceptsTypingAndPersistsAfterReturn() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: fixture.content)
        defer { panel.close() }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString,
                                                                          directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClassicalLayoutStore(directoryURL: directory)
        let id = try fixture.folderID("Work")
        let original = ClassicalLayoutFolder(id: id, title: "Work",
                                             pages: [[try fixture.record("A").id, try fixture.record("B").id]])
        try await store.save(ClassicalLayout(pages: [[.folder(original)]]))
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        fixture.board.folderRenamed = { model.renameFolder($0, to: $1) }
        fixture.board.folders.reduceMotion = { true }

        XCTAssertTrue(fixture.board.openFolder(id, selectingFirstItem: false))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        let title = fixture.host.convert(folder.layer.titleLayer.frame, from: folder.layer)
        try fixture.click(at: CGPoint(x: title.midX, y: title.midY), time: 0)
        XCTAssertTrue(folder.titleEditor.isEditing)
        let fieldEditor = try XCTUnwrap(folder.titleEditor.textField.currentEditor() as? NSTextView,
                                        "Clicking the title must focus the editable text field")
        XCTAssertTrue(panel.firstResponder === fieldEditor)
        fieldEditor.insertText("Projects", replacementRange: fieldEditor.selectedRange())
        XCTAssertEqual(folder.titleEditor.textField.stringValue, "Projects")
        fieldEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertFalse(folder.titleEditor.isEditing, "Return ends the title edit")
        XCTAssertEqual(folder.layer.titleLayer.string as? String, "Projects")
        XCTAssertEqual(try fixture.folderCell("Work").titleLayer.string as? String, "Projects")
        fixture.board.folders.close(animated: false)
        XCTAssertTrue(fixture.board.openFolder(id, selectingFirstItem: false))
        XCTAssertEqual(fixture.board.folders.openFolder?.content.title, "Projects",
                       "Reopening from the root page must keep the renamed title")
        await model.flush()
        let reloaded = ClassicalLayoutModel(store: store)
        await reloaded.load()
        XCTAssertEqual(reloaded.layout?.folder(id)?.title, "Projects")
    }

    /// The editable title remains the sole visible title through successive keystrokes. It must
    /// retain the same field editor and key focus until Return restores the static label.
    func testTypingFolderTitleDoesNotRevealStaticTitleOrResetTheEditor() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: fixture.content)
        defer { panel.close() }
        let folder = try fixture.open("Work")
        let title = fixture.host.convert(folder.layer.titleLayer.frame, from: folder.layer)
        try fixture.click(at: CGPoint(x: title.midX, y: title.midY), time: 0)
        let field = folder.titleEditor.textField
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)

        XCTAssertTrue(panel.firstResponder === editor)
        XCTAssertTrue(folder.layer.titleLayer.isHidden, "The static label must not show behind the edit")
        XCTAssertTrue(field.superview === fixture.content)
        for part in ["P", "ro", "jects"] {
            editor.insertText(part, replacementRange: editor.selectedRange())
            XCTAssertTrue(folder.titleEditor.isEditing)
            XCTAssertTrue(field.currentEditor() === editor, "Typing must not replace the field editor")
            XCTAssertTrue(panel.firstResponder === editor, "Typing must retain key focus")
            XCTAssertTrue(folder.layer.titleLayer.isHidden, "Typing must not flash the static title")
            XCTAssertTrue(field.superview === fixture.content)
        }
        XCTAssertEqual(field.stringValue, "Projects")
        XCTAssertEqual(folder.layer.titleLayer.string as? String, "Work", "The static title updates only on commit")

        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertFalse(folder.titleEditor.isEditing)
        XCTAssertNil(field.superview)
        XCTAssertFalse(folder.layer.titleLayer.isHidden)
        XCTAssertEqual(folder.layer.titleLayer.string as? String, "Projects")
    }

    /// The replacement title is ready and visible before the editable view leaves the window.
    func testEndingTitleEditHandsOffToUpdatedStaticTitleBeforeRemovingEditor() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let folder = try fixture.open("Work")
        folder.beginTitleEditing(in: fixture.content)
        let field = folder.titleEditor.textField
        XCTAssertTrue(folder.layer.titleLayer.isHidden)
        XCTAssertTrue(field.superview === fixture.content)
        field.stringValue = "Projects"
        var checkedHandoff = false
        folder.titleEditor.commit = { title in
            folder.commitTitle(title)
            XCTAssertEqual(folder.layer.titleLayer.string as? String, "Projects")
            XCTAssertFalse(folder.layer.titleLayer.isHidden,
                           "The updated static title must be visible before the editor is removed")
            XCTAssertTrue(field.superview === fixture.content)
            checkedHandoff = true
        }

        folder.endTitleEditing()
        XCTAssertTrue(checkedHandoff)
        XCTAssertNil(field.superview)
        XCTAssertFalse(folder.layer.titleLayer.isHidden)
    }

    /// A real title commit publishes the new label while the editor still covers the title area.
    func testRenameCallbackSeesNewVisibleTitleBeforeEditorLeavesWindow() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let folder = try fixture.open("Work")
        let cell = try fixture.folderCell("Work")
        folder.beginTitleEditing(in: fixture.content)
        let field = folder.titleEditor.textField
        XCTAssertTrue(field.superview === fixture.content)
        field.stringValue = "Projects"
        var callbacks: [String] = []
        folder.didRename = { id, title in
            XCTAssertEqual(id, folder.content.id)
            callbacks.append(title)
            XCTAssertEqual(folder.layer.titleLayer.string as? String, "Projects")
            XCTAssertFalse(folder.layer.titleLayer.isHidden,
                           "The old static title must not reappear as the edit ends")
            XCTAssertFalse(folder.layer.titleLayer.needsDisplay(),
                           "The replacement panel title must have a ready backing store before reveal")
            XCTAssertEqual(cell.titleLayer.string as? String, "Projects")
            XCTAssertFalse(cell.titleLayer.needsDisplay(),
                           "The closed cell title must be ready before the folder can close")
            XCTAssertTrue(field.superview === fixture.content,
                          "The replacement title must be ready before the editor leaves")
        }

        folder.endTitleEditing()

        XCTAssertEqual(callbacks, ["Projects"])
        XCTAssertNil(field.superview)
        XCTAssertEqual(folder.layer.titleLayer.string as? String, "Projects")
    }

    /// Both keyboard commit and a click away must publish the replacement title before removing
    /// the focused editor. These paths use actual field-editor input, not a direct field assignment.
    func testReturnPublishesTheNewTitleBeforeRemovingTheFieldEditor() throws {
        try assertTitleHandoff(commitByClick: false)
    }

    func testOutsideClickPublishesTheNewTitleBeforeRemovingTheFieldEditor() throws {
        try assertTitleHandoff(commitByClick: true)
    }

    private func assertTitleHandoff(commitByClick: Bool) throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: fixture.content)
        defer { panel.close() }
        fixture.board.folders.reduceMotion = { true }
        let folder = try fixture.open("Work")
        let title = fixture.host.convert(folder.layer.titleLayer.frame, from: folder.layer)
        try fixture.click(at: CGPoint(x: title.midX, y: title.midY), time: 0)
        let field = folder.titleEditor.textField
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertTrue(panel.firstResponder === editor)
        editor.insertText("Projects", replacementRange: editor.selectedRange())
        XCTAssertEqual(field.stringValue, "Projects")
        XCTAssertEqual(editor.string, "Projects")
        XCTAssertTrue(folder.layer.titleLayer.isHidden)

        var renamed: [String] = []
        folder.didRename = { _, newTitle in
            renamed.append(newTitle)
            XCTAssertTrue(field.superview === fixture.content,
                          "The field must remain over the title until the replacement is published")
            XCTAssertFalse(folder.layer.titleLayer.isHidden)
            XCTAssertEqual(folder.layer.titleLayer.string as? String, "Projects")
            XCTAssertEqual(field.stringValue, "Projects")
            XCTAssertEqual(editor.string, "Projects")
        }
        if commitByClick {
            let outside = CGPoint(x: fixture.content.bounds.maxX - 2, y: fixture.content.bounds.maxY - 2)
            try fixture.click(at: outside, time: 1)
        } else {
            editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        }

        XCTAssertEqual(renamed, ["Projects"])
        XCTAssertFalse(folder.titleEditor.isEditing)
        XCTAssertNil(field.superview)
        XCTAssertEqual(folder.layer.titleLayer.string as? String, "Projects")
    }

    /// The folder turns its own pages; the root page stays where it was.
    func testFolderPagesTurnIndependentlyOfTheRootPages() throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B"], ["C", .folder("Many", [["D", "E", "F", "G", "H", "I"], ["J"]])]])
        fixture.board.pager.settle(on: 1)
        let folder = try fixture.open("Many")
        XCTAssertEqual(folder.pager.pages.count, 2)
        XCTAssertEqual(folder.pager.pages.map { $0.records.map(\.metadata.displayName) },
                       [["D", "E", "F", "G", "H", "I"], ["J"]])
        folder.pager.settle(on: 1)
        XCTAssertEqual(folder.pager.currentPage, 1)
        XCTAssertEqual(fixture.board.pager.currentPage, 1, "The root page does not move")
        XCTAssertFalse(folder.pager.dotsLayer.isHidden, "A folder with several pages shows its own page dots")
    }

    /// Opening a folder with one overfull saved page creates a second internal page. The root
    /// pager stays on its own page, and the folder's dots offer navigation to item 36.
    func testOpeningThirtySixItemFolderShowsThirtyFiveThenOne() throws {
        let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956),
                                                    dock: .bottom(extent: 59), rows: 5, columns: 7)
        let names = (0..<36).map { String(format: "App %02d", $0) }
        let fixture = try ClassicalFolderTestBoard([[.folder("Many", [names])]], geometry: geometry)
        let folder = try fixture.open("Many")

        XCTAssertEqual(folder.content.pages.map(\.count), [35, 1])
        XCTAssertEqual(folder.pager.pages.map { $0.records.map(\.metadata.displayName) },
                       [Array(names.prefix(35)), [names[35]]])
        XCTAssertFalse(folder.pager.dotsLayer.isHidden)
        XCTAssertEqual(folder.pager.currentPage, 0)
        XCTAssertEqual(fixture.board.pager.currentPage, 0)
        XCTAssertEqual(folder.navigate(.right, command: true), .handled)
        XCTAssertEqual(folder.pager.currentPage, 1)
        XCTAssertEqual(folder.pager.pages[1].records.first?.metadata.displayName, names[35])
        XCTAssertEqual(fixture.board.pager.currentPage, 0, "Folder paging leaves root paging alone")
    }

    /// An existing folder page break is user ordering; opening it does not flatten and repack it.
    func testOpeningFolderKeepsAnExistingPageBreak() throws {
        let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956),
                                                    dock: .bottom(extent: 59), rows: 5, columns: 7)
        let names = (0..<36).map { String(format: "App %02d", $0) }
        let fixture = try ClassicalFolderTestBoard([[.folder("Many", [Array(names.prefix(34)),
                                                                     Array(names.dropFirst(34))])]], geometry: geometry)
        let folder = try fixture.open("Many")

        XCTAssertEqual(folder.content.pages.map { $0.map(\.metadata.displayName) },
                       [Array(names.prefix(34)), Array(names.dropFirst(34))])
        XCTAssertEqual(folder.pager.pages.map(\.records).map(\.count), [34, 2])
    }

    /// Arrows move the selection within the folder page. Of the Command-arrows only Command-Up
    /// closes the folder; the others never close it.
    func testArrowsNavigateInsideAndOnlyCommandUpCloses() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B", "C", "D"]]), "E"]])
        let folder = try fixture.open("Work", selectingFirstItem: true)
        ClassicalFolderTestBoard.waitUntil { folder.selectedRecord != nil }
        XCTAssertEqual(folder.navigate(.right, command: false), .handled)
        XCTAssertEqual(folder.selectedRecord?.metadata.displayName, "B")
        XCTAssertEqual(folder.navigate(.left, command: false), .handled)
        XCTAssertEqual(folder.navigate(.down, command: false), .handled)
        XCTAssertEqual(folder.selectedRecord?.metadata.displayName, "D", "Down moves one row in a 3-column folder")
        for direction in [ClassicalNavigation.right, .left, .down] {
            XCTAssertNotEqual(folder.navigate(direction, command: true), .close, "\(direction)")
        }
        XCTAssertEqual(folder.navigate(.up, command: true), .close)
    }

    /// Without a selection, Command-Left and Command-Right turn the folder's pages.
    func testCommandArrowWithoutSelectionTurnsTheFolderPage() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Many", [["A", "B", "C", "D", "E", "F"], ["G"]])]])
        let folder = try fixture.open("Many")
        XCTAssertEqual(folder.navigate(.right, command: true), .handled)
        XCTAssertEqual(folder.pager.currentPage, 1)
        XCTAssertEqual(folder.navigate(.right, command: true), .ignored, "There is no page after the last")
        XCTAssertEqual(folder.navigate(.left, command: true), .handled)
        XCTAssertEqual(folder.pager.currentPage, 0)
        XCTAssertTrue(fixture.board.folders.openFolder === folder)
    }

    /// Closing the folder ends a title edit in progress and keeps its text.
    func testClosingCommitsATitleEditInProgress() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        var renamed: [String] = []
        fixture.board.folderRenamed = { renamed.append($1); return nil }
        let folder = try fixture.open("Work")
        folder.beginTitleEditing(in: fixture.content)
        XCTAssertTrue(folder.titleEditor.isEditing)
        folder.titleEditor.textField.stringValue = "Games"
        fixture.board.folders.close()
        XCTAssertFalse(folder.titleEditor.isEditing)
        XCTAssertEqual(renamed, ["Games"])
        fixture.waitUntilClosed()
        XCTAssertEqual(try fixture.folderCell("Work").titleLayer.string as? String, "Games")
    }

    func testRemovingTheLastApplicationReportsAnEmptyFolder() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A"], ["B"]])]])
        let folder = try fixture.open("Work")
        var reports: [Bool] = []
        XCTAssertTrue(folder.removeRecord(try fixture.record("A").id) { reports.append($0) })
        ClassicalFolderTestBoard.waitUntil { reports.count == 1 }
        XCTAssertEqual(reports, [false])
        XCTAssertEqual(folder.content.pages.map { $0.map(\.metadata.displayName) }, [["B"]],
                       "An emptied folder page goes")
        XCTAssertEqual(try fixture.folderCell("Work").thumbnailRecords.map(\.metadata.displayName), ["B"])
        XCTAssertTrue(folder.removeRecord(try fixture.record("B").id) { reports.append($0) })
        ClassicalFolderTestBoard.waitUntil { reports.count == 2 }
        XCTAssertEqual(reports, [false, true])
        XCTAssertFalse(folder.removeRecord(try fixture.record("B").id) { reports.append($0) },
                       "An application no longer in the folder cannot be removed again")
    }
}
