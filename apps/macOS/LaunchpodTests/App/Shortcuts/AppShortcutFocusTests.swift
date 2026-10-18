import AppKit
import Testing
@testable import Launchpod

@Suite(.serialized)
@MainActor
struct AppShortcutFocusTests {

    @Test func launcherPanelOwnsShortcutsWithoutActivatingTheApp() {
        let panel = makePanel(identifier: AppShortcutFocus.launcherWindowIdentifier)
        defer { panel.close() }

        #expect(AppShortcutFocus.ownsCommandShortcuts(focusedWindow: panel, hasModalPresentation: false))
    }

    @Test func onboardingPanelOwnsShortcutsUnlessAModalPresentationNeedsThem() {
        let panel = makePanel(identifier: AppShortcutFocus.onboardingWindowIdentifier)
        defer { panel.close() }

        #expect(!panel.isVisible)
        #expect(AppShortcutFocus.ownsCommandShortcuts(focusedWindow: panel, hasModalPresentation: false))
        #expect(!AppShortcutFocus.ownsCommandShortcuts(focusedWindow: panel, hasModalPresentation: true))
    }

    @Test func unfocusedOtherPanelsAndModalPresentationsKeepTheirKeys() {
        let prompt = makePanel(identifier: nil)
        let launcher = makePanel(identifier: AppShortcutFocus.launcherWindowIdentifier)
        defer {
            prompt.close()
            launcher.close()
        }

        #expect(!AppShortcutFocus.ownsCommandShortcuts(focusedWindow: prompt, hasModalPresentation: false))
        #expect(!AppShortcutFocus.ownsCommandShortcuts(focusedWindow: nil, hasModalPresentation: false))
        #expect(!AppShortcutFocus.ownsCommandShortcuts(focusedWindow: launcher, hasModalPresentation: true))
    }

    @Test func settingsWindowsOwnShortcutsUnlessAShortcutIsBeingRecorded() async throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let recorder = ShortcutRecorder.RecorderButton()
        let window = makeWindow(recorder: recorder)
        defer { window.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !window.isKeyWindow, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(window.isKeyWindow)
        #expect(AppShortcutFocus.ownsCommandShortcuts(focusedWindow: window, hasModalPresentation: false))

        recorder.beginRecording()
        try #require(recorder.isRecording, "The native test window must become key before recording.")
        #expect(!AppShortcutFocus.ownsCommandShortcuts(focusedWindow: window, hasModalPresentation: false))
        recorder.cancelRecording()
        #expect(AppShortcutFocus.ownsCommandShortcuts(focusedWindow: window, hasModalPresentation: false))
    }

    @Test func focusedWindowIsResolvedFromTheAppsOwnWindows() {
        let application = NSApplication.shared
        let resolved = AppShortcutFocus.focusedWindow(in: application)
        let keyWindow = application.windows.first(where: { $0.isKeyWindow })

        // An inactive application reports no key window of its own, so the
        // resolved window is whichever of its windows still holds key status.
        #expect(resolved === keyWindow)
    }

    private func makePanel(identifier: NSUserInterfaceItemIdentifier?) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.identifier = identifier
        return panel
    }

    private func makeWindow(recorder: ShortcutRecorder.RecorderButton) -> NSWindow {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                             styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.identifier = AppShortcutFocus.settingsWindowIdentifier
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        recorder.frame = NSRect(x: 10, y: 40, width: 280, height: 30)
        content.addSubview(recorder)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
