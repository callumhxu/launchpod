import AppKit

/// A first responder that needs app command shortcuts delivered as ordinary input.
@MainActor
protocol AppCommandShortcutSuppressing: AnyObject {
    var suppressesAppCommandShortcuts: Bool { get }
}

/// Decides when the application may dispatch its own command shortcuts.
///
/// The launcher is a non-activating panel: it takes keyboard focus without
/// activating the application, which keeps the previous app in front. Another
/// application owns the menu bar in this state, and `NSApplication.keyWindow`
/// may be nil. The launcher therefore recognises its command shortcuts from
/// the app's own windows instead of relying on menu bar dispatch.
@MainActor
enum AppShortcutFocus {
    static let launcherWindowIdentifier = NSUserInterfaceItemIdentifier("launcherPlaceholderWindow")
    static let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("settingsWindow")
    static let onboardingWindowIdentifier = NSUserInterfaceItemIdentifier("onboarding")

    /// The app's own panels, which take keyboard focus without activating it.
    private static let shortcutOwningPanels: Set<NSUserInterfaceItemIdentifier> = [
        launcherWindowIdentifier, settingsWindowIdentifier, onboardingWindowIdentifier
    ]

    /// The window receiving key events, including a non-activating panel focused
    /// while the application is inactive and `keyWindow` is nil.
    static func focusedWindow(in application: NSApplication) -> NSWindow? {
        if let keyWindow = application.keyWindow, keyWindow.isKeyWindow { return keyWindow }
        return application.windows.first { $0.isKeyWindow }
    }

    /// The app's own panel currently holding the keyboard, if it is one of
    /// them; nothing else may be touched on its behalf.
    static func focusedOwnPanel(in application: NSApplication) -> NSWindow? {
        guard let window = focusedWindow(in: application), let identifier = window.identifier,
              shortcutOwningPanels.contains(identifier) else { return nil }
        return window
    }

    static func ownsCommandShortcuts(in application: NSApplication) -> Bool {
        guard application.modalWindow == nil else { return false }
        var focusedWindow = application.keyWindow
        if focusedWindow?.isKeyWindow != true { focusedWindow = nil }
        for window in application.windows {
            guard window.attachedSheet == nil else { return false }
            if focusedWindow == nil, window.isKeyWindow { focusedWindow = window }
        }
        return ownsCommandShortcuts(
            focusedWindow: focusedWindow,
            hasModalPresentation: false
        )
    }

    /// A focused window means the keystroke was routed to this application, so a
    /// command may be handled without waiting for activation. Only the app's own
    /// panels claim shortcuts without activation: any other non-activating
    /// panel, such as the hold-to-quit prompt, belongs to a different
    /// interaction. A shortcut being recorded must reach its recorder unchanged.
    static func ownsCommandShortcuts(focusedWindow: NSWindow?, hasModalPresentation: Bool) -> Bool {
        guard let focusedWindow, !hasModalPresentation else { return false }
        if focusedWindow is NSPanel && focusedWindow.styleMask.contains(.nonactivatingPanel) {
            guard let identifier = focusedWindow.identifier,
                  shortcutOwningPanels.contains(identifier) else { return false }
        }
        let responder = focusedWindow.firstResponder as? any AppCommandShortcutSuppressing
        return responder?.suppressesAppCommandShortcuts != true
    }
}
