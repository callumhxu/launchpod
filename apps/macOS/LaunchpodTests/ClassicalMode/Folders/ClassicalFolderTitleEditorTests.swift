import AppKit
import XCTest
@testable import Launchpod

/// Editing a folder title: every way an edit ends reports its text, and the field goes away.
@MainActor
final class ClassicalFolderTitleEditorTests: XCTestCase {
    private func editing(_ title: String) -> (ClassicalFolderTitleEditor, NSView, () -> [String]) {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let editor = ClassicalFolderTitleEditor()
        var commits: [String] = []
        editor.commit = { commits.append($0) }
        editor.begin(title: title, frame: CGRect(x: 100, y: 400, width: 600, height: 40),
                     font: .systemFont(ofSize: 28), in: view)
        return (editor, view, { commits })
    }

    func testEditStartsWithTheCurrentTitleOverTheTitleArea() {
        let (editor, view, _) = editing("Work")
        XCTAssertTrue(editor.isEditing)
        XCTAssertEqual(editor.textField.stringValue, "Work")
        XCTAssertTrue(editor.textField.superview === view)
        XCTAssertEqual(editor.textField.frame.midY, 420, accuracy: 0.5)
    }

    /// The dark folder header needs a white insertion point when the selection collapses.
    func testFocusedEditorHasWhiteInsertionPoint() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let panel = NativeAppTestSupport.makeKeyPanel(size: view.frame.size, contentView: view)
        defer { panel.close() }
        let editor = ClassicalFolderTitleEditor()
        let sharedEditor = try XCTUnwrap(panel.fieldEditor(true, for: editor.textField) as? NSTextView)
        let originalColor = sharedEditor.insertionPointColor
        editor.begin(title: "Work", frame: CGRect(x: 100, y: 400, width: 600, height: 40),
                     font: .systemFont(ofSize: 28), in: view)

        let fieldEditor = try XCTUnwrap(editor.textField.currentEditor() as? NSTextView)
        XCTAssertTrue(fieldEditor === sharedEditor)
        XCTAssertTrue(panel.firstResponder === fieldEditor)
        fieldEditor.setSelectedRange(NSRange(location: fieldEditor.string.utf16.count, length: 0))
        let color = try XCTUnwrap(fieldEditor.insertionPointColor.usingColorSpace(.deviceRGB))
        XCTAssertEqual(color.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(color.greenComponent, 1, accuracy: 0.01)
        XCTAssertEqual(color.blueComponent, 1, accuracy: 0.01)
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01)
        editor.end()
        XCTAssertTrue(sharedEditor.insertionPointColor.isEqual(originalColor),
                      "The shared field editor must retain its original caret color for other controls")
    }

    func testEndingReportsTheTextOnceAndRemovesTheField() {
        let (editor, _, commits) = editing("Work")
        editor.textField.stringValue = "Projects"
        editor.end()
        XCTAssertEqual(commits(), ["Projects"])
        XCTAssertFalse(editor.isEditing)
        XCTAssertNil(editor.textField.superview)
        editor.end()
        XCTAssertEqual(commits(), ["Projects"], "An ended edit reports nothing more")
    }

    /// Return, Tab and focus loss end editing through the field's end-editing notification.
    func testEndEditingNotificationCommits() {
        let (editor, _, commits) = editing("Work")
        editor.textField.stringValue = "Games"
        editor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: editor.textField))
        XCTAssertEqual(commits(), ["Games"])
    }

    /// Escape also ends the edit with its text; there is no cancel.
    func testEscapeEndsTheEditWithItsText() {
        let (editor, _, commits) = editing("Work")
        editor.textField.stringValue = "Games"
        XCTAssertTrue(editor.control(editor.textField, textView: NSTextView(),
                                     doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(commits(), ["Games"])
        XCTAssertFalse(editor.control(editor.textField, textView: NSTextView(),
                                      doCommandBy: #selector(NSResponder.insertNewline(_:))),
                       "Other commands keep their standard handling")
    }
}
