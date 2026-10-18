import AppKit
import SwiftUI
import XCTest
@testable import Launchpod

@MainActor
final class ShortcutRecorderTests: XCTestCase {
    func testNativeRecorderFollowsExplicitLocaleWhenTheExistingViewUpdates() async throws {
        try XCTSkipUnless(Bundle(for: AppDelegate.self).bundleURL == Bundle.main.bundleURL
                          && Bundle.main.bundleURL.pathExtension == "app", "Requires the Launchpod application test host and its compiled localization catalog.")
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let preference = AppLanguagePreference(defaults: defaults, preferredLanguages: { ["en-US"] })
        let host = NSHostingView(rootView: RecorderHost(preference: preference))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }

        for (language, record, recording, purpose) in [
            (AppLanguage.simplifiedChinese, CatalogTestSupport.text("Record Shortcut", locale: "zh-Hans"), CatalogTestSupport.text("Press a shortcut…", locale: "zh-Hans"), CatalogTestSupport.text("Show or Hide Launchpod", locale: "zh-Hans")),
            (.traditionalChinese, CatalogTestSupport.text("Record Shortcut", locale: "zh-Hant"), CatalogTestSupport.text("Press a shortcut…", locale: "zh-Hant"), CatalogTestSupport.text("Show or Hide Launchpod", locale: "zh-Hant")),
            (.english, "Record Shortcut", "Press a shortcut…", "Show or Hide Launchpod")
        ] {
            preference.selection = language
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            let button = try XCTUnwrap(recorder(in: host))
            XCTAssertEqual(button.title, record)
            XCTAssertEqual(button.recordingTitle, recording)
            XCTAssertEqual(button.accessibilityLabel(), purpose)
        }
    }

    func testRecordingConsumesCommandEquivalentAndIgnoresKeyRepeat() throws {
        let button = ShortcutRecorder.RecorderButton()
        let window = makeWindow(button: button)
        defer { window.close() }
        var records: [ShortcutPreference.Binding] = []
        var changes: [Bool] = []
        button.onRecord = { records.append($0) }
        button.onRecordingChanged = { changes.append($0) }
        button.beginRecording()
        try requireKeyFocus(button.isRecording)
        button.keyDown(with: try event(window: window, modifiers: []))
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(button.isRecording)
        XCTAssertTrue(button.performKeyEquivalent(with: try event(window: window, repeated: true)))
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(button.isRecording)
        XCTAssertTrue(button.performKeyEquivalent(with: try event(window: window)))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.characters, "k")
        XCTAssertEqual(records.first?.modifiers, .command)
        XCTAssertFalse(button.isRecording)
        XCTAssertEqual(changes, [true, false])
    }

    func testEscapeFocusLossAndRemovalCancelWithoutChangingSelection() throws {
        let button = ShortcutRecorder.RecorderButton()
        let window = makeWindow(button: button)
        defer { window.close() }
        let original = try XCTUnwrap(ShortcutPreference.Binding(keyCode: 40, modifiers: .option, characters: "k"))
        button.selection = original
        var records = 0
        button.onRecord = { _ in records += 1 }
        button.beginRecording()
        try requireKeyFocus(button.isRecording)
        button.keyDown(with: try event(window: window, characters: "\u{1b}", modifiers: [], keyCode: 53))
        XCTAssertFalse(button.isRecording)
        XCTAssertEqual(button.selection, original)
        button.beginRecording()
        XCTAssertTrue(button.isRecording)
        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertFalse(button.isRecording)
        button.beginRecording()
        XCTAssertTrue(button.isRecording)
        ShortcutRecorder.dismantleNSView(button, coordinator: ())
        XCTAssertFalse(button.isRecording)
        button.beginRecording()
        XCTAssertTrue(button.isRecording)
        button.removeFromSuperview()
        XCTAssertFalse(button.isRecording)
        XCTAssertEqual(button.selection, original)
        XCTAssertEqual(records, 0)
    }

    func testClearControlIsVisibleOnlyWithASavedShortcut() throws {
        let button = ShortcutRecorder.RecorderButton()
        button.refreshTitle()
        XCTAssertTrue(button.clearButton.isHidden)
        button.selection = try XCTUnwrap(ShortcutPreference.Binding(keyCode: 40, modifiers: .option, characters: "k"))
        button.refreshTitle()
        XCTAssertFalse(button.clearButton.isHidden)
        XCTAssertTrue(button.clearButton.isEnabled)
        button.selection = nil
        button.refreshTitle()
        XCTAssertTrue(button.clearButton.isHidden)
    }

    func testSelectionChangesReserveClearControlSpaceEvenWhenTheTitleIsUnchanged() throws {
        let button = ShortcutRecorder.RecorderButton()
        button.bezelStyle = .glass
        button.recordTitle = "⌘K"
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        button.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            button.topAnchor.constraint(equalTo: content.topAnchor)
        ])
        button.refreshTitle()
        content.layoutSubtreeIfNeeded()
        let emptySize = button.intrinsicContentSize
        let emptyWidth = button.frame.width
        let binding = try XCTUnwrap(ShortcutPreference.Binding(keyCode: 40, modifiers: .command, characters: "k"))

        button.selection = binding
        button.refreshTitle()
        content.layoutSubtreeIfNeeded()
        let selectedSize = button.intrinsicContentSize
        let selectedWidth = button.frame.width
        XCTAssertEqual(button.title, "⌘K")
        XCTAssertFalse(button.clearButton.isHidden)
        XCTAssertGreaterThan(selectedSize.width, emptySize.width)
        XCTAssertGreaterThan(selectedWidth, emptyWidth)

        button.refreshTitle()
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(button.intrinsicContentSize, selectedSize)
        XCTAssertEqual(button.frame.width, selectedWidth)
        XCTAssertEqual(button.selection, binding)
        XCTAssertFalse(button.isRecording)

        button.selection = nil
        button.refreshTitle()
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(button.title, "⌘K")
        XCTAssertTrue(button.clearButton.isHidden)
        XCTAssertEqual(button.intrinsicContentSize, emptySize)
        XCTAssertEqual(button.frame.width, emptyWidth)

        button.recordTitle = "Record a different shortcut"
        button.refreshTitle()
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(button.title, button.recordTitle)
        XCTAssertGreaterThan(button.intrinsicContentSize.width, emptySize.width)
        XCTAssertGreaterThan(button.frame.width, emptyWidth)
    }

    func testEmbeddedClearStartsRecordingAndAcceptsTheNextShortcut() throws {
        let button = ShortcutRecorder.RecorderButton()
        let window = makeWindow(button: button)
        defer { window.close() }
        try requireKeyFocus(window.isKeyWindow)
        button.selection = try XCTUnwrap(ShortcutPreference.Binding(keyCode: 40, modifiers: .option, characters: "k"))
        button.refreshTitle()
        var clears = 0
        var records: [ShortcutPreference.Binding] = []
        var changes: [Bool] = []
        button.onClear = { clears += 1 }
        button.onRecord = { records.append($0) }
        button.onRecordingChanged = { changes.append($0) }

        button.clearButton.performClick(nil)

        XCTAssertNil(button.selection)
        XCTAssertTrue(button.isRecording)
        XCTAssertTrue(window.firstResponder === button)
        XCTAssertTrue(button.clearButton.isHidden)
        XCTAssertEqual(clears, 1)
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(changes, [true])

        XCTAssertTrue(button.performKeyEquivalent(with: try event(window: window)))

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(button.selection, records.first)
        XCTAssertEqual(records.first?.modifiers, .command)
        XCTAssertFalse(button.isRecording)
        XCTAssertFalse(button.clearButton.isHidden)
        XCTAssertEqual(changes, [true, false])
    }

    func testEmbeddedClearKeepsRecordingAndEscapeLeavesTheSelectionEmpty() throws {
        let button = ShortcutRecorder.RecorderButton()
        let window = makeWindow(button: button)
        defer { window.close() }
        button.selection = try XCTUnwrap(ShortcutPreference.Binding(keyCode: 40, modifiers: .option, characters: "k"))
        var clears = 0
        var records = 0
        var changes: [Bool] = []
        button.onClear = { clears += 1 }
        button.onRecord = { _ in records += 1 }
        button.onRecordingChanged = { changes.append($0) }
        button.beginRecording()
        try requireKeyFocus(button.isRecording)
        XCTAssertFalse(button.clearButton.isHidden)

        button.clearButton.performClick(nil)

        XCTAssertNil(button.selection)
        XCTAssertTrue(button.isRecording)
        XCTAssertTrue(window.firstResponder === button)
        XCTAssertTrue(button.clearButton.isHidden)
        XCTAssertEqual(clears, 1)
        XCTAssertEqual(records, 0)
        XCTAssertEqual(changes, [true])

        button.keyDown(with: try event(window: window, characters: "\u{1b}", modifiers: [], keyCode: 53))

        XCTAssertFalse(button.isRecording)
        XCTAssertNil(button.selection)
        XCTAssertTrue(button.clearButton.isHidden)
        XCTAssertEqual(changes, [true, false])
    }

    func testOutsideClickAfterClearingCancelsAndLeavesTheSelectionEmpty() throws {
        let button = ShortcutRecorder.RecorderButton()
        let window = makeWindow(button: button)
        defer { window.close() }
        try requireKeyFocus(window.isKeyWindow)
        let target = ClickTarget(frame: NSRect(x: 10, y: 0, width: 100, height: 30))
        try XCTUnwrap(window.contentView).addSubview(target)
        button.selection = try XCTUnwrap(ShortcutPreference.Binding(keyCode: 40, modifiers: .option, characters: "k"))
        button.refreshTitle()
        var records = 0
        button.onRecord = { _ in records += 1 }
        button.clearButton.performClick(nil)
        XCTAssertTrue(button.isRecording)
        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: target.convert(NSPoint(x: 10, y: 10), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))

        NSApplication.shared.sendEvent(click)

        XCTAssertFalse(button.isRecording)
        XCTAssertNil(button.selection)
        XCTAssertTrue(button.clearButton.isHidden)
        XCTAssertEqual(records, 0)
        XCTAssertEqual(target.mouseDownCount, 1)
    }

    func testOutsideClickCancelsRecordingAndReachesItsDestination() throws {
        let button = ShortcutRecorder.RecorderButton()
        let window = makeWindow(button: button)
        defer { window.close() }
        let target = ClickTarget(frame: NSRect(x: 10, y: 0, width: 100, height: 30))
        try XCTUnwrap(window.contentView).addSubview(target)
        let original = try XCTUnwrap(ShortcutPreference.Binding(keyCode: 40, modifiers: .option, characters: "k"))
        button.selection = original
        var records = 0
        var changes: [Bool] = []
        button.onRecord = { _ in records += 1 }
        button.onRecordingChanged = { changes.append($0) }
        button.beginRecording()
        try requireKeyFocus(button.isRecording)
        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: target.convert(NSPoint(x: 10, y: 10), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))

        NSApplication.shared.sendEvent(click)

        XCTAssertFalse(button.isRecording)
        XCTAssertEqual(button.selection, original)
        XCTAssertEqual(records, 0)
        XCTAssertEqual(changes, [true, false])
        XCTAssertEqual(target.mouseDownCount, 1)
        NSApplication.shared.sendEvent(click)
        XCTAssertEqual(changes, [true, false])
        XCTAssertEqual(target.mouseDownCount, 2)

        button.beginRecording()
        XCTAssertTrue(button.isRecording)
        ShortcutRecorder.dismantleNSView(button, coordinator: ())
        XCTAssertFalse(button.isRecording)
        XCTAssertEqual(changes, [true, false, true, false])
        NSApplication.shared.sendEvent(click)
        XCTAssertEqual(changes, [true, false, true, false])
        XCTAssertEqual(target.mouseDownCount, 3)
    }

    private final class ClickTarget: NSView {
        var mouseDownCount = 0

        override func mouseDown(with event: NSEvent) {
            mouseDownCount += 1
        }
    }

    private struct RecorderHost: View {
        let preference: AppLanguagePreference

        var body: some View {
            ShortcutRecorder(selection: nil, onRecord: { _ in }, onRecordingChanged: { _ in })
                .environment(\.locale, preference.locale)
        }
    }

    private func recorder(in view: NSView) -> ShortcutRecorder.RecorderButton? {
        if let button = view as? ShortcutRecorder.RecorderButton { return button }
        for child in view.subviews {
            if let button = recorder(in: child) { return button }
        }
        return nil
    }

    /// Mirrors the production settings panel, which takes key focus without activating the app.
    private func makeWindow(button: NSButton) -> NSWindow {
        if let restoreHost = try? NativeAppTestSupport.isolateHostWindows() {
            addTeardownBlock { @MainActor in restoreHost() }
        }
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        button.frame = NSRect(x: 10, y: 40, width: 280, height: 30)
        content.addSubview(button)
        return NativeAppTestSupport.makeKeyPanel(size: content.frame.size, contentView: content)
    }

    private func event(window: NSWindow, characters: String = "k", modifiers: NSEvent.ModifierFlags = .command,
                       keyCode: UInt16 = 40, repeated: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                      timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                      characters: characters, charactersIgnoringModifiers: characters,
                                      isARepeat: repeated, keyCode: keyCode))
    }
}
