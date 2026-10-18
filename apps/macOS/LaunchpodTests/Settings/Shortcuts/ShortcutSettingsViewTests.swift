import AppKit
import SwiftUI
import XCTest
@testable import Launchpod

@MainActor
final class ShortcutSettingsViewTests: XCTestCase {
    func testClearControlRemovesSavedBindingAndImmediatelyRecordsItsReplacement() async throws {
        try XCTSkipUnless(Bundle(for: AppDelegate.self).bundleURL == Bundle.main.bundleURL
                          && Bundle.main.bundleURL.pathExtension == "app", "Requires the Launchpod application test host and its native accessibility tree.")
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let preference = ShortcutPreference(defaults: defaults)
        preference.selection = try XCTUnwrap(ShortcutPreference.Binding(keyCode: 40, modifiers: .command, characters: "k"))
        var cancellations = 0
        let shortcut = GlobalShortcut(register: { _, _ in { cancellations += 1 } }, action: {})
        shortcut.update(binding: preference.selection)
        let host = NSHostingView(rootView: ShortcutSettingsView(preference: preference, shortcut: shortcut))
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let window = NativeAppTestSupport.makeKeyPanel(size: NSSize(width: 480, height: 260), contentView: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        try requireKeyFocus(window.isKeyWindow)
        host.layoutSubtreeIfNeeded()
        let recorder = try XCTUnwrap(self.recorder(in: host))
        XCTAssertEqual(recorder.focusRingType, .none)
        let clear = try XCTUnwrap(NativeAppTestSupport.accessibilityElement(in: recorder, identifier: "clearLauncherShortcut"))
        let clearView = try XCTUnwrap(clear as? NSView)
        XCTAssertTrue(recorder.bounds.contains(clearView.convert(clearView.bounds, to: recorder)))
        // The press is verified by its effects below rather than by the return value, which
        // `NSButton` can report as false even when it performs its action.
        _ = clear.accessibilityPerformPress()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(preference.selection)
        XCTAssertNil(defaults.object(forKey: ShortcutPreference.preferenceKey))
        XCTAssertNil(shortcut.binding)
        XCTAssertEqual(cancellations, 1)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertTrue(window.firstResponder === recorder)
        XCTAssertTrue(recorder.clearButton.isHidden)
        XCTAssertNil(NativeAppTestSupport.accessibilityElement(in: host, identifier: "clearLauncherShortcut"))

        let replacement = try XCTUnwrap(ShortcutPreference.Binding(keyCode: 40, modifiers: [.command, .shift], characters: "k"))
        let key = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "K", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40
        ))
        XCTAssertTrue(recorder.performKeyEquivalent(with: key))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(preference.selection, replacement)
        XCTAssertEqual(ShortcutPreference(defaults: defaults).selection, replacement)
        XCTAssertEqual(shortcut.binding, replacement)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(recorder.clearButton.isHidden)
    }

    func testOutsideClickAndRemovalRestoreTheUnchangedGlobalShortcut() async throws {
        try XCTSkipUnless(Bundle(for: AppDelegate.self).bundleURL == Bundle.main.bundleURL
                          && Bundle.main.bundleURL.pathExtension == "app", "Requires the Launchpod application test host.")
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let preference = ShortcutPreference(defaults: defaults)
        let original = try XCTUnwrap(ShortcutPreference.Binding(keyCode: 40, modifiers: .command, characters: "k"))
        preference.selection = original
        var registrations: [ShortcutPreference.Binding] = []
        var cancellations = 0
        let shortcut = GlobalShortcut(register: { binding, _ in
            registrations.append(binding)
            return { cancellations += 1 }
        }, action: {})
        shortcut.update(binding: original)
        let host = NSHostingView(rootView: ShortcutSettingsView(preference: preference, shortcut: shortcut))
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let window = NativeAppTestSupport.makeKeyPanel(size: NSSize(width: 480, height: 260), contentView: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let recorder = try XCTUnwrap(self.recorder(in: host))
        recorder.beginRecording()
        try requireKeyFocus(recorder.isRecording)
        XCTAssertNil(shortcut.binding)
        XCTAssertEqual(cancellations, 1)
        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: 10, y: 10),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        NSApplication.shared.sendEvent(click)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(preference.selection, original)
        XCTAssertEqual(ShortcutPreference(defaults: defaults).selection, original)
        XCTAssertEqual(shortcut.binding, original)
        XCTAssertEqual(registrations, [original, original])

        recorder.beginRecording()
        XCTAssertTrue(recorder.isRecording)
        XCTAssertNil(shortcut.binding)
        XCTAssertEqual(cancellations, 2)
        recorder.removeFromSuperview()
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(preference.selection, original)
        XCTAssertEqual(shortcut.binding, original)
        XCTAssertEqual(registrations, [original, original, original])
    }

    private func recorder(in view: NSView) -> ShortcutRecorder.RecorderButton? {
        if let recorder = view as? ShortcutRecorder.RecorderButton { return recorder }
        for child in view.subviews {
            if let recorder = recorder(in: child) { return recorder }
        }
        return nil
    }
}
