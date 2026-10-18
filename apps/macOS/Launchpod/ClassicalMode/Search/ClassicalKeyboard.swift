import AppKit

/// The Classical launcher's keyboard handling.
///
/// Typing, Space and Delete go to the search field, which starts showing text without taking the
/// caret. Up and Down always move the selection; Left and Right move it too unless the field has
/// the caret (Tab or a click), and Right still navigates while the field is empty. Command-Left
/// and Command-Right turn the page. Return launches the selection, or opens a selected folder with
/// its first application selected. Escape clears an active search, otherwise it closes the launcher.
/// While a folder is shown, the arrows, Return and Escape act inside it and other keys do nothing.
@MainActor
final class ClassicalKeyboard: NSObject, NSTextFieldDelegate {
    let field = ClassicalSearchField()
    let springboard: ClassicalSpringboard
    weak var drag: ClassicalItemDrag?
    var launch: (@MainActor (AppRecord) -> Void)?
    var dismiss: (@MainActor () -> Void)?
    /// The view that holds key focus while the field has none.
    weak var contentView: NSView?

    init(springboard: ClassicalSpringboard) {
        self.springboard = springboard
        super.init()
        field.textField.delegate = self
        field.textField.onMouseDown = { [weak self] in self?.focusField() }
    }

    // MARK: Keys arriving at the content view

    /// Returns false for keys the launcher leaves to the system.
    ///
    /// While an icon is dragged, arrows do nothing. While it is held or dragged, Return does nothing
    /// and every other key except the arrows, Escape and Tab is swallowed: the field loses focus and
    /// stops receiving keys but keeps its text, and no search starts.
    func keyDown(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        let held = drag?.holdsKeys == true
        let dragging = drag?.isDragging == true
        switch event.specialKey {
        case .upArrow?: if !dragging { springboard.navigate(.up, command: command) }; return true
        case .downArrow?: if !dragging { springboard.navigate(.down, command: command) }; return true
        case .leftArrow?: if !dragging { springboard.navigate(.left, command: command) }; return true
        case .rightArrow?: if !dragging { springboard.navigate(.right, command: command) }; return true
        case .carriageReturn?, .enter?, .newline?: if !held { performAction() }; return true
        case .tab?, .backTab?:
            if !springboard.folders.isActive { setFieldFocus(!field.hasFocus) }
            return true
        default: break
        }
        if event.keyCode == 53 { cancel(); return true }
        if held || springboard.folders.isActive {
            endTextInput()
            return true
        }
        // Every other key, ⌘ combinations included, goes to the field.
        if event.modifierFlags.contains(.control), !command { return false }
        guard let characters = event.characters, !characters.isEmpty else { return false }
        typeIntoField(event)
        return true
    }

    /// The standard editing shortcuts, which a menu bar would otherwise deliver to the field editor.
    static let editingShortcuts: [String: Selector] = [
        "a": #selector(NSText.selectAll(_:)), "c": #selector(NSText.copy(_:)), "x": #selector(NSText.cut(_:)),
        "v": #selector(NSText.paste(_:)), "z": Selector(("undo:"))
    ]

    /// ⌘A/⌘C/⌘X/⌘V/⌘Z/⇧⌘Z: activates the field when needed and performs the edit there; while a
    /// folder is shown, they edit its title instead.
    func performKeyEquivalent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers == .command || modifiers == [.command, .shift],
              let key = event.charactersIgnoringModifiers.map(AppCommandShortcuts.normalizedKey),
              var action = Self.editingShortcuts[key] else { return false }
        if key == "z", modifiers.contains(.shift) { action = Selector(("redo:")) } else if modifiers.contains(.shift) { return false }
        // While a folder is shown the edits go to its title editor, if it is editing, and never to the search field.
        if springboard.folders.isActive {
            if let editor = springboard.folders.openFolder?.titleEditor.textField.currentEditor() {
                NSApp.sendAction(action, to: editor, from: nil)
            }
            return true
        }
        if drag?.holdsKeys == true {
            endTextInput()
            return true
        }
        activateField()
        guard let editor = field.textField.currentEditor() else { return false }
        NSApp.sendAction(action, to: editor, from: nil)
        return true
    }

    /// A drag is cancelled first, then deleting mode ends, then an open folder closes, then an
    /// active search, then the launcher.
    func cancel() {
        // Only a drag that still follows the pointer is cancelled; a landing icon is left to finish.
        if drag?.isDragging ?? (springboard.drag?.isEnding == false) {
            if let drag { drag.cancel() } else { springboard.cancelDrag() }
        } else if springboard.isDeleting {
            springboard.setDeleting(false)
        } else if springboard.folders.isActive {
            springboard.folders.close()
        } else if springboard.isFiltering || !field.text.isEmpty {
            field.textField.stringValue = ""
            textChanged()
        } else {
            dismiss?()
        }
    }

    func performAction() {
        if springboard.folders.isActive {
            if let record = springboard.selectedRecord { launch?(record) }
        } else if case let .folder(id) = springboard.selectedItemID {
            springboard.openFolder(id, selectingFirstItem: true)
        } else if let record = springboard.selectedRecord {
            launch?(record)
        }
    }

    /// A folder is opening: the field gives up the caret, keeping its text.
    func folderWillOpen() {
        endTextInput()
    }

    /// True while a press that started on the clear button is being tracked.
    private(set) var isTrackingClearButton = false

    /// A click on the field gives it the caret. A press on the clear button brightens it to 1 while
    /// the pointer stays over it and clears on release there (0.3 ↔ 1).
    func mouseDown(at point: CGPoint) -> Bool {
        guard field.contains(point) else { return false }
        if field.closeContains(point) {
            isTrackingClearButton = true
            field.setClearButtonPressed(true)
        } else {
            focusField()
        }
        return true
    }

    func mouseDragged(to point: CGPoint) {
        guard isTrackingClearButton else { return }
        field.setClearButtonPressed(field.closeContains(point))
    }

    func mouseUp(at point: CGPoint) {
        guard isTrackingClearButton else { return }
        isTrackingClearButton = false
        field.setClearButtonPressed(false)
        if field.closeContains(point) {
            field.textField.stringValue = ""
            textChanged()
        }
    }

    /// The model has left search for an item drag; keep the visible editor in the same state.
    func clearSearchForDrag() {
        field.reset()
        if let contentView, contentView.window?.firstResponder !== contentView {
            contentView.window?.makeFirstResponder(contentView)
        }
    }

    /// The launcher closed: the search, selection and caret are gone.
    func reset() {
        drag?.reset()
        field.reset()
        springboard.reset()
        if let contentView, contentView.window?.firstResponder !== contentView {
            contentView.window?.makeFirstResponder(contentView)
        }
    }

    /// True while the search field's editor holds key focus in `window`.
    func ownsFocus(in window: NSWindow) -> Bool {
        guard let editor = field.textField.currentEditor() else { return false }
        return window.firstResponder === editor
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        textChanged()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let event = NSApp.currentEvent
        let command = event?.modifierFlags.contains(.command) == true
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            springboard.navigate(.up, command: false)
        case #selector(NSResponder.moveDown(_:)):
            springboard.navigate(.down, command: false)
        case #selector(NSResponder.moveLeft(_:)):
            guard !field.hasFocus else { return false }
            springboard.navigate(.left, command: false)
        case #selector(NSResponder.moveRight(_:)):
            guard !field.hasFocus || field.text.isEmpty else { return false }
            springboard.navigate(.right, command: false)
        case #selector(NSResponder.moveToLeftEndOfLine(_:)), #selector(NSResponder.moveToBeginningOfLine(_:)),
             #selector(NSResponder.moveToRightEndOfLine(_:)), #selector(NSResponder.moveToEndOfLine(_:)):
            guard command, let keyCode = event?.keyCode, keyCode == 123 || keyCode == 124 else { return false }
            springboard.navigate(keyCode == 123 ? .left : .right, command: true)
        case #selector(NSResponder.insertNewline(_:)):
            performAction()
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            setFieldFocus(!field.hasFocus)
        default:
            return false
        }
        return true
    }

    // MARK: Private

    private func textChanged() {
        field.textDidChange()
        springboard.search(field.committedText)
    }

    private func typeIntoField(_ event: NSEvent) {
        activateField()
        field.textField.currentEditor()?.keyDown(with: event)
    }

    /// The field shows text and receives keys; the caret stays hidden until it has focus.
    private func activateField() {
        field.activate()
        let textField = field.textField
        if textField.currentEditor() == nil {
            textField.window?.makeFirstResponder(textField)
            // A new editing session continues after kept text rather than selecting it.
            let end = NSRange(location: (textField.stringValue as NSString).length, length: 0)
            (textField.currentEditor() as? NSTextView)?.setSelectedRange(end)
        }
        (textField.currentEditor() as? NSTextView)?.insertionPointColor = field.hasFocus ? .white : .clear
    }

    /// The field loses focus and stops receiving keys but keeps its text: its editor hands key
    /// focus back to the content view until typing activates the field again.
    private func endTextInput() {
        setFieldFocus(false)
        if field.textField.currentEditor() != nil, let contentView {
            contentView.window?.makeFirstResponder(contentView)
        }
    }

    private func focusField() {
        setFieldFocus(true)
    }

    private func setFieldFocus(_ focus: Bool) {
        if focus { activateField() }
        field.setHasFocus(focus)
        if !field.isActive, let contentView {
            contentView.window?.makeFirstResponder(contentView)
        }
    }
}
