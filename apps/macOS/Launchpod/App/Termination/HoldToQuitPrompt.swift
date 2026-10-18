import AppKit

@MainActor
final class HoldToQuitPrompt {
    private enum Layout {
        static let width: CGFloat = 360
        static let horizontalInset: CGFloat = 16
        static let verticalInset: CGFloat = 16
        static let spacing: CGFloat = 8
        static let titleFontSize: CGFloat = 17
        static let detailFontSize: CGFloat = 15
    }

    private var panel: NSPanel?
    private var progress: NSProgressIndicator?

    func show(locale: Locale) {
        hide()
        let panel = PromptPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: 0),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        // The launcher can own the keyboard while the app is inactive.
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        panel.setAccessibilityIdentifier("holdToQuitPrompt")
        let title = NSTextField(wrappingLabelWithString: String(localized: LocalizedStringResource(
            "Hold ⌘Q for 2 seconds to quit Launchpod",
            locale: locale
        )))
        title.isSelectable = false
        title.font = .boldSystemFont(ofSize: Layout.titleFontSize)
        title.preferredMaxLayoutWidth = Layout.width - 2 * Layout.horizontalInset
        let detail = NSTextField(wrappingLabelWithString: String(localized: LocalizedStringResource(
            "Shortcuts and the menu bar will be unavailable after quitting.",
            locale: locale
        )))
        detail.isSelectable = false
        detail.font = .systemFont(ofSize: Layout.detailFontSize)
        detail.textColor = .secondaryLabelColor
        detail.preferredMaxLayoutWidth = title.preferredMaxLayoutWidth
        // The hold ends by itself, so how much of it is left has to be visible.
        let progress = NSProgressIndicator()
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = 0
        progress.controlSize = .small
        progress.setAccessibilityIdentifier("holdToQuitProgress")
        let stack = NSStackView(views: [title, detail, progress])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Layout.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let content = panel.contentView {
            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Layout.horizontalInset),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Layout.horizontalInset),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: Layout.verticalInset),
                progress.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
            content.layoutSubtreeIfNeeded()
            panel.setContentSize(NSSize(
                width: Layout.width,
                height: stack.fittingSize.height + 2 * Layout.verticalInset
            ))
        }
        panel.center()
        self.panel = panel
        self.progress = progress
        // Order the prompt above the active app even when Launchpod is inactive.
        panel.orderFrontRegardless()
    }

    func update(progress fraction: Double) {
        progress?.doubleValue = min(max(fraction, 0), 1)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        progress = nil
    }

    /// The prompt only reports progress. Taking key status away from the window
    /// the shortcut was pressed in would cancel the hold it is reporting on.
    private final class PromptPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
}
