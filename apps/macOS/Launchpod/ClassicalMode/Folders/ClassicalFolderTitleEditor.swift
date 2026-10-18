import AppKit
import QuartzCore

/// Edits an open folder's title in a borderless text field over the panel's title area, in the
/// title's font and color. Every way an edit ends reports its text: Return, Tab, Escape, focus
/// moving elsewhere, or `end()` when the panel is clicked or the folder closes. There is no cancel;
/// the folder keeps its old title only when the text is empty.
@MainActor
final class ClassicalFolderTitleEditor: NSObject, NSTextFieldDelegate {
    let textField = NSTextField()
    /// Receives the text when an edit ends.
    var commit: (@MainActor (String) -> Void)?
    private weak var view: NSView?
    private weak var fieldEditor: NSTextView?
    private var originalInsertionPointColor: NSColor?
    private(set) var isEditing = false

    override init() {
        super.init()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = .white
        textField.alignment = .center
        textField.usesSingleLineMode = true
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.delegate = self
    }

    /// Shows the field over `frame` (in `view`'s coordinates) with `title` selected and gives it key focus.
    func begin(title: String, frame: CGRect, font: NSFont, in view: NSView) {
        guard !isEditing else { return }
        isEditing = true
        self.view = view
        textField.font = font
        textField.stringValue = title
        let height = (font.ascender - font.descender + font.leading).rounded(.up) + 2
        textField.frame = CGRect(x: frame.minX, y: frame.midY - height / 2, width: frame.width, height: height)
        view.addSubview(textField)
        view.window?.makeFirstResponder(textField)
        textField.currentEditor()?.selectAll(nil)
        if let editor = textField.currentEditor() as? NSTextView {
            fieldEditor = editor
            originalInsertionPointColor = editor.insertionPointColor
            editor.insertionPointColor = NSColor(deviceWhite: 1, alpha: 1)
        }
    }

    /// Ends an edit in progress and reports its text; the view that held key focus before gets it back.
    func end() {
        guard isEditing else { return }
        isEditing = false
        let text = textField.stringValue
        let view = self.view
        // Keep the title reveal and editor removal in the same layer update.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        commit?(text)
        textField.removeFromSuperview()
        CATransaction.commit()
        if let originalInsertionPointColor { fieldEditor?.insertionPointColor = originalInsertionPointColor }
        fieldEditor = nil
        originalInsertionPointColor = nil
        self.view = nil
        if let view, let window = view.window, window.firstResponder !== view { window.makeFirstResponder(view) }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        end()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        end()
        return true
    }
}
