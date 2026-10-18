import AppKit

/// Borderless full-screen Classical panel: key-capable without becoming main, and reporting
/// alpha and order-out changes made by other owners (such as the held-quit workflow).
final class ClassicalPanel: NSPanel {
    /// A transparent, shadowless, key-capable panel that joins the active Space and full-screen Spaces,
    /// hosting a layer-backed `ClassicalContentView` as its first responder.
    static func makeLauncherPanel() -> ClassicalPanel {
        let panel = ClassicalPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.identifier = AppShortcutFocus.launcherWindowIdentifier
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = NSWindow.Level(rawValue: ClassicalPresentationParameters.windowLevel)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        let content = ClassicalContentView(frame: .zero)
        content.wantsLayer = true
        panel.contentView = content
        panel.initialFirstResponder = content
        return panel
    }

    var launcherContentView: ClassicalContentView {
        // Installed by `makeLauncherPanel()` and never replaced.
        contentView as! ClassicalContentView
    }

    var dismiss: (@MainActor () -> Void)?
    var alphaDidChange: (@MainActor (CGFloat, CGFloat) -> Void)?
    var didOrderOut: (@MainActor () -> Void)?
    override var alphaValue: CGFloat {
        didSet { alphaDidChange?(oldValue, alphaValue) }
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
    /// ⌘ shortcuts never reach the menu bar of a launcher that does not activate the app; the
    /// standard editing ones go to the search field.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if launcherContentView.deletion.keyDown(event) { return true }
        if launcherContentView.keyboard?.performKeyEquivalent(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        didOrderOut?()
    }
}
