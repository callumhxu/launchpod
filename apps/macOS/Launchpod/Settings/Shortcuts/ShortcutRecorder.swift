import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let selection: ShortcutPreference.Binding?
    let onRecord: @MainActor (ShortcutPreference.Binding) -> Void
    let onRecordingChanged: @MainActor (Bool) -> Void
    var onClear: @MainActor () -> Void = {}

    @Environment(\.locale) private var locale

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .glass
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        button.setAccessibilityIdentifier("launcherShortcutRecorder")
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.selection = selection
        button.onRecord = onRecord
        button.onRecordingChanged = onRecordingChanged
        button.onClear = onClear
        button.recordTitle = String(localized: LocalizedStringResource("Record Shortcut", locale: locale))
        button.recordingTitle = String(localized: LocalizedStringResource("Press a shortcut…", locale: locale))
        button.setAccessibilityLabel(String(localized: LocalizedStringResource("Show or Hide Launchpod", locale: locale)))
        let clearTitle = String(localized: LocalizedStringResource("Clear Shortcut", locale: locale))
        button.clearButton.setAccessibilityLabel(clearTitle)
        button.clearButton.toolTip = clearTitle
        button.refreshTitle()
    }

    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) {
        button.cancelRecording()
        NotificationCenter.default.removeObserver(button)
        button.onRecord = { _ in }
        button.onRecordingChanged = { _ in }
        button.onClear = {}
    }

    class FocusButton: NSButton {
        override func becomeFirstResponder() -> Bool {
            let focused = super.becomeFirstResponder()
            if focused { highlight(true) }
            return focused
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { highlight(false) }
            return resigned
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            highlight(window?.firstResponder === self)
        }
    }

    final class RecorderButton: FocusButton, AppCommandShortcutSuppressing {
        var selection: ShortcutPreference.Binding?
        var onRecord: @MainActor (ShortcutPreference.Binding) -> Void = { _ in }
        var onRecordingChanged: @MainActor (Bool) -> Void = { _ in }
        var onClear: @MainActor () -> Void = {}
        var recordTitle = ""
        var recordingTitle = ""
        private(set) var isRecording = false
        var suppressesAppCommandShortcuts: Bool { isRecording }
        let clearButton = FocusButton()
        private var mouseMonitor: Any?
        private static let clearButtonSpacing: CGFloat = 8

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            configureClearButton()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configureClearButton()
        }

        isolated deinit {
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        }

        private func configureClearButton() {
            focusRingType = .none
            alignment = .left
            clearButton.isBordered = false
            clearButton.focusRingType = .none
            clearButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
            clearButton.imagePosition = .imageOnly
            clearButton.controlSize = .small
            clearButton.target = self
            clearButton.action = #selector(clearShortcut)
            clearButton.setAccessibilityIdentifier("clearLauncherShortcut")
            clearButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(clearButton)
            NSLayoutConstraint.activate([
                clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.clearButtonSpacing),
                clearButton.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }

        override func accessibilityChildren() -> [Any]? {
            let children = super.accessibilityChildren() ?? []
            return clearButton.isHidden ? children : children + [clearButton]
        }

        override var intrinsicContentSize: NSSize {
            var size = super.intrinsicContentSize
            if selection != nil {
                size.width += clearButton.intrinsicContentSize.width + Self.clearButtonSpacing
            }
            return size
        }

        @objc private func clearShortcut() {
            selection = nil
            onClear()
            refreshTitle()
            beginRecording()
        }

        override var acceptsFirstResponder: Bool { true }

        @objc func beginRecording() {
            guard !isRecording, let window, window.isKeyWindow,
                  window.makeFirstResponder(self) else { return }
            isRecording = true
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                        self.cancelRecording()
                    }
                }
                return event
            }
            refreshTitle()
            onRecordingChanged(true)
        }

        func cancelRecording() {
            guard isRecording else { return }
            isRecording = false
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
            refreshTitle()
            onRecordingChanged(false)
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { cancelRecording() }
            return resigned
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            cancelRecording()
            NotificationCenter.default.removeObserver(self)
            super.viewWillMove(toWindow: newWindow)
            guard let newWindow else { return }
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(windowDidStopRecording),
                                                       name: name, object: newWindow)
            }
        }

        @objc private func windowDidStopRecording(_ notification: Notification) {
            cancelRecording()
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording, window?.firstResponder === self, event.type == .keyDown else {
                return super.performKeyEquivalent(with: event)
            }
            record(event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            record(event)
        }

        override func cancelOperation(_ sender: Any?) {
            if isRecording { cancelRecording() } else { super.cancelOperation(sender) }
        }

        private func record(_ event: NSEvent) {
            guard !event.isARepeat else { return }
            if event.charactersIgnoringModifiers == "\u{1b}" {
                cancelRecording()
                return
            }
            guard let characters = event.charactersIgnoringModifiers,
                  let binding = ShortcutPreference.Binding(keyCode: event.keyCode,
                                                           modifiers: event.modifierFlags,
                                                           characters: characters) else {
                NSSound.beep()
                return
            }
            selection = binding
            onRecord(binding)
            cancelRecording()
        }

        func refreshTitle() {
            let hidesClearButton = selection == nil
            let clearVisibilityChanged = clearButton.isHidden != hidesClearButton
            if clearVisibilityChanged { clearButton.isHidden = hidesClearButton }
            if clearButton.isEnabled != !hidesClearButton { clearButton.isEnabled = !hidesClearButton }
            let nextTitle: String
            if isRecording {
                nextTitle = recordingTitle
            } else if let selection {
                var modifiers = ""
                if selection.modifiers.contains(.control) { modifiers += "⌃" }
                if selection.modifiers.contains(.option) { modifiers += "⌥" }
                if selection.modifiers.contains(.shift) { modifiers += "⇧" }
                if selection.modifiers.contains(.command) { modifiers += "⌘" }
                nextTitle = modifiers + (selection.characters == " " ? "␣" : selection.characters.uppercased())
            } else {
                nextTitle = recordTitle
            }
            guard title != nextTitle || clearVisibilityChanged else { return }
            if title != nextTitle { title = nextTitle }
            invalidateIntrinsicContentSize()
        }
    }
}
