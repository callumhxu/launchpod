import AppKit
import XCTest
@testable import Launchpod

// Run with parallel testing disabled: these tests change the native test host's focus.
@MainActor
final class LauncherPlaceholderWindowControllerTests: XCTestCase {
    private var inactiveForegroundProcessIdentifier: pid_t?

    func testShowingFromInactiveStateFocusesReusedPanelWithoutActivatingApp() async throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let application = NSApplication.shared
        let controller = try makeController()
        defer { controller.stop() }
        try await deactivateHost()
        XCTAssertFalse(application.isActive)

        var completions: [Bool] = []
        controller.setVisible(true) { success in
            completions.append(success)
            XCTAssertTrue(controller.window?.isVisible == true)
            XCTAssertTrue(controller.window?.isKeyWindow == true)
            XCTAssertTrue(controller.window?.firstResponder === controller.window?.initialFirstResponder)
        }
        let window = try XCTUnwrap(controller.window)
        try await assertFocused(controller)
        XCTAssertEqual(completions, [true])

        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(NSRunningApplication.current.isActive)
        controller.setVisible(true) { success in XCTAssertTrue(success) }
        XCTAssertTrue(controller.window === window)
        try await assertFocused(controller)

        controller.setVisible(false) { success in XCTAssertTrue(success) }
        try await deactivateHost()
        controller.setVisible(true) { success in XCTAssertTrue(success) }
        XCTAssertTrue(controller.window === window)
        try await assertFocused(controller)
    }

    func testInvokedWindowAllowsLocalHoldToQuitHandling() async throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let application = NSApplication.shared
        let controller = try makeController()
        var prompts = 0
        let time = MainActorBox<TimeInterval>(0)
        let qPressed = MainActorBox(true)
        var quits = 0
        let holdToQuit = HoldToQuitController(
            isEligible: { HoldToQuitController.canHandleShortcut(in: application) },
            now: { time.value }, isKeyPressed: { $0 == 12 ? qPressed.value : true }, showPrompt: { prompts += 1 },
            hidePrompt: {}, quit: { _ in quits += 1 }
        )
        defer {
            holdToQuit.stop()
            controller.stop()
        }
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "q", charactersIgnoringModifiers: "q",
            isARepeat: false, keyCode: 12
        ))
        try await deactivateHost()
        XCTAssertFalse(holdToQuit.process(event))
        XCTAssertEqual(prompts, 0)

        controller.setVisible(true) { success in XCTAssertTrue(success) }
        try await assertFocused(controller)
        XCTAssertTrue(holdToQuit.process(event))
        XCTAssertTrue(holdToQuit.isHolding)
        XCTAssertEqual(prompts, 1)
        time.value = 2
        holdToQuit.checkHoldCompletion()
        XCTAssertFalse(holdToQuit.isHolding)
        XCTAssertEqual(quits, 1)
        qPressed.value = false
        holdToQuit.endDraining()

        holdToQuit.start()
        qPressed.value = true
        XCTAssertTrue(holdToQuit.process(event))
        XCTAssertTrue(holdToQuit.isHolding)
        XCTAssertEqual(prompts, 2)
        controller.setVisible(false) { success in XCTAssertTrue(success) }
        XCTAssertFalse(holdToQuit.isHolding)
        XCTAssertEqual(quits, 1)
    }

    func testVisibilityReusesOneWindowAndStopReleasesIt() throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let controller = try makeController()
        defer { controller.stop() }
        var dismissals = 0
        controller.onDismiss = { dismissals += 1 }
        XCTAssertFalse(controller.isVisible)
        let initialWindow = try XCTUnwrap(controller.window)

        controller.setVisible(true) { _ in }
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window === initialWindow)
        XCTAssertTrue(window.isVisible)
        let panel = try XCTUnwrap(window as? NSPanel)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(controller.isVisible)
        controller.setVisible(true) { _ in }
        XCTAssertTrue(controller.window === window)
        controller.setVisible(false) { success in XCTAssertTrue(success) }
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(dismissals, 0)

        controller.setVisible(true) { _ in }
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(window.isVisible)
        controller.stop()
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(controller.isVisible)
        XCTAssertNil(controller.window)
        XCTAssertEqual(dismissals, 0)
    }

    func testNativeCloseAndEscapeDismissAndAllowReopening() throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let controller = try makeController()
        defer { controller.stop() }
        var dismissals = 0
        controller.onDismiss = { dismissals += 1 }
        controller.setVisible(true) { _ in }
        let window = try XCTUnwrap(controller.window)

        window.performClose(nil)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(dismissals, 1)
        controller.setVisible(true) { _ in }
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(window.isVisible)
        window.cancelOperation(nil)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(dismissals, 2)
        controller.setVisible(true) { _ in }
        XCTAssertTrue(window.isVisible)
    }

    func testNativeKeyTransferDismissesUnlessOwnedInteractionRetainsPresentation() async throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let controller = try makeController()
        let other = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.hidesOnDeactivate = false
        defer { other.close(); controller.stop() }
        var dismissals = 0
        let retaining = MainActorBox(true)
        controller.onDismiss = { dismissals += 1 }
        controller.retainsFocusForOwnedInteraction = { retaining.value }
        try await deactivateHost()
        controller.setVisible(true)
        try await assertFocused(controller)
        other.orderFrontRegardless()
        other.makeKey()
        try await assertKeyWindow(other)
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(dismissals, 0)
        XCTAssertFalse(HoldToQuitController.canHandleShortcut(in: .shared))

        controller.setVisible(true)
        try await assertFocused(controller)
        retaining.value = false
        other.makeKey()
        try await assertKeyWindow(other)
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(dismissals, 1)
    }

    func testStoppedControllerRejectsNewPresentationWithoutReportingSuccess() throws {
        let controller = try makeController()
        controller.stop()
        var completions: [Bool] = []
        controller.setVisible(true) { completions.append($0) }
        XCTAssertEqual(completions, [false])
        XCTAssertFalse(controller.isVisible)
    }

    private func deactivateHost(file: StaticString = #filePath, line: UInt = #line) async throws {
        let application = NSApplication.shared
        // Allow pending host-launch activation events to arrive before requesting deactivation.
        await Task.yield()
        application.deactivate()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        repeat {
            try await Task.sleep(for: .milliseconds(20))
        } while (application.isActive || NSRunningApplication.current.isActive) && ContinuousClock.now < deadline
        XCTAssertFalse(application.isActive, "The host must be inactive before presenting the panel.", file: file, line: line)
        XCTAssertFalse(NSRunningApplication.current.isActive, "The native process must relinquish activation.", file: file, line: line)
        inactiveForegroundProcessIdentifier = try XCTUnwrap(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        XCTAssertNotEqual(inactiveForegroundProcessIdentifier, ProcessInfo.processInfo.processIdentifier, file: file, line: line)
    }

    private func assertFocused(
        _ controller: LauncherPlaceholderWindowController,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let window = try XCTUnwrap(controller.window, file: file, line: line)
        try await assertKeyWindow(window, file: file, line: line)
        XCTAssertFalse(NSRunningApplication.current.isActive, file: file, line: line)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier,
                       inactiveForegroundProcessIdentifier, file: file, line: line)
        XCTAssertTrue(controller.window?.isKeyWindow == true, file: file, line: line)
        XCTAssertNotNil(controller.window?.initialFirstResponder, file: file, line: line)
        XCTAssertTrue(controller.window?.firstResponder === controller.window?.initialFirstResponder, file: file, line: line)
    }

    private func assertKeyWindow(_ window: NSWindow, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !window.isKeyWindow, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(window.isVisible, file: file, line: line)
        XCTAssertTrue(window.isKeyWindow, file: file, line: line)
    }

    private func makeController() throws -> LauncherPlaceholderWindowController {
        _ = NSApplication.shared
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        addTeardownBlock { try preferences.cleanup() }
        let preference = AppLanguagePreference(defaults: defaults, preferredLanguages: { ["en-US"] })
        return LauncherPlaceholderWindowController(languagePreference: preference)
    }
}
