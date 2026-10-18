import AppKit
import XCTest
@testable import Launchpod

@MainActor
enum NativeAppTestSupport {
    nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LAUNCHPOD_NATIVE_WINDOW_TESTS"] == "1"
    }

    static func requireNativeWindowTests() throws {
        guard isEnabled else {
            throw XCTSkip("Native window tests require the explicit Launchpod Native Windows scheme.")
        }
    }

    static func waitUntil(
        description: String,
        timeout: Duration = .seconds(4),
        phase: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line,
        state: @MainActor () -> String = { "" },
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                throw NativeConditionTimeout(description: "\(file):\(line) [\(phase)] Timed out waiting for \(description).\n\(state())\n\(captureFailureSnapshot())")
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Captures focus and window state without presenting or activating any window.
    static func captureFailureSnapshot() -> String {
        let application = NSApplication.shared
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        let header = "active=\(application.isActive) frontmost=\(frontmost) key=\(application.keyWindow?.windowNumber ?? -1) main=\(application.mainWindow?.windowNumber ?? -1)"
        let windows = application.windows.map { window in
            "window=\(window.windowNumber) type=\(type(of: window)) visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) level=\(window.level.rawValue) alpha=\(window.alphaValue) frame=\(window.frame) responder=\(window.firstResponder.map { String(describing: type(of: $0)) } ?? "none")"
        }
        return ([header] + windows).joined(separator: "\n")
    }

    static func accessibilityElement(in root: Any, identifier: String) -> (any NSAccessibilityProtocol)? {
        guard let element = root as? any NSAccessibilityProtocol else { return nil }
        if element.accessibilityIdentifier() == identifier { return element }
        for child in element.accessibilityChildren() ?? [] {
            if let match = accessibilityElement(in: child, identifier: identifier) { return match }
        }
        return nil
    }

    /// The running SwiftUI app's delegate after its launch callback initializes the host.
    static func appDelegate() throws -> AppDelegate {
        try requireNativeWindowTests()
        #if DEBUG
        guard let delegate = LaunchpodApp.testHostDelegate else { throw HostError.delegateUnavailable }
        guard delegate.services != nil, delegate.coordinator != nil else { throw HostError.delegateNotLaunched }
        return delegate
        #else
        throw HostError.debugHostRequired
        #endif
    }

    /// Temporarily hides existing host windows; call the returned action after closing test windows.
    static func isolateHostWindows() throws -> @MainActor () -> Void {
        let delegate = try appDelegate()
        let windows = NSApplication.shared.windows
        let visibleWindows = windows.filter(\.isVisible)
        let keyWindow = windows.first(where: \.isKeyWindow)
        let launcherWindow = (delegate.launcherPlaceholder as? NSWindowController)?.window
        // A launcher still preparing (e.g. the startup presentation loading its wallpaper) is not
        // visible yet but would order front and take key focus from the test's own window.
        let restoreLauncher = delegate.launcherPlaceholder?.isVisible == true
            || delegate.coordinator?.session?.presentation.targetIsVisible == true
        if restoreLauncher {
            delegate.toggleLauncher()
            launcherWindow?.orderOut(nil)
        }
        for window in visibleWindows where window !== launcherWindow {
            window.orderOut(nil)
        }
        return {
            for window in visibleWindows where window !== launcherWindow {
                window.orderFrontRegardless()
            }
            if restoreLauncher {
                delegate.showLauncher()
            } else if delegate.launcherPlaceholder?.isVisible == true {
                delegate.toggleLauncher()
            }
            if keyWindow?.isVisible == true { keyWindow?.makeKey() }
        }
    }

    /// A titled panel that takes key focus without activating the test host, like the production
    /// settings panel; a plain `NSWindow` cannot become key while the host app is inactive.
    static func makeKeyPanel(size: NSSize, contentView: NSView) -> NSPanel {
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = contentView
        panel.orderFrontRegardless()
        panel.makeKey()
        return panel
    }

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    /// The app has one settings window, its own panel, reached through the
    /// delegate exactly as the status item and ⌘, reach it.
    static func openSettings() async throws -> NSWindow {
        let delegate = try appDelegate()
        delegate.openSettings()
        try await waitUntil(description: "the host settings window becomes visible", timeout: .seconds(3)) {
            delegate.settingsWindow?.window?.isVisible == true
        }
        guard let window = delegate.settingsWindow?.window else { throw HostError.windowNotPresented }
        return window
    }

    static func capture(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw HostError.bitmapUnavailable }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private enum HostError: Error, CustomStringConvertible {
        case delegateUnavailable, delegateNotLaunched, debugHostRequired, windowNotPresented, bitmapUnavailable

        var description: String {
            switch self {
            case .delegateUnavailable:
                "The running LaunchpodApp has not exposed its SwiftUI-owned delegate."
            case .delegateNotLaunched:
                "The SwiftUI-owned delegate has not initialized its host services and coordinator."
            case .debugHostRequired:
                "Native host tests require a Debug Launchpod build."
            case .windowNotPresented:
                "The running Launchpod app did not present the expected window."
            case .bitmapUnavailable:
                "The native view could not create a bitmap for capture."
            }
        }
    }
}

/// Mutable test state shared with `@MainActor` callbacks, which are `Sendable` and so cannot
/// observe later writes to a captured local `var`.
@MainActor
final class MainActorBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

extension XCTestCase {
    /// Fails, rather than skips, when a native test window cannot take key focus: the behavior under
    /// test would otherwise silently go unverified.
    func requireKeyFocus(_ acquired: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        guard acquired else {
            XCTFail("Test window must take key focus.", file: file, line: line)
            throw KeyFocusUnavailable()
        }
    }
}

private struct KeyFocusUnavailable: Error {}

private struct NativeConditionTimeout: Error, CustomStringConvertible {
    let description: String
}
