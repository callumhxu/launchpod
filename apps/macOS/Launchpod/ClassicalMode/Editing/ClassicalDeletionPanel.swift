import AppKit

/// The confirmation shown when a delete badge is clicked.
///
/// An `NSPopover` with a 64 pt icon, one wrapping message and the Cancel and action buttons. There
/// is no title field, so only the message appears. The popover points down from a 20 pt square at
/// the centre of the icon image, and its window sits at level 106. While it is open the
/// background layer swallows clicks elsewhere; Return and Enter choose the action, Escape and ⌘.
/// cancel.
@MainActor
final class ClassicalDeletionPanel: NSObject, NSPopoverDelegate {
    static let iconSide: CGFloat = 64
    static let messageWidth: CGFloat = 304
    static let messageMinimumHeight: CGFloat = 34
    static let anchorSide: CGFloat = 20
    static let windowLevel = 106
    /// The content view frame, which the popover keeps; the message wraps within it.
    static let contentSize = CGSize(width: 400, height: 84)

    static func message(for title: String, locale: Locale) -> String {
        let format = String(localized: LocalizedStringResource("Are you sure you want to delete the application “%@”?",
                                                               locale: locale))
        return String(format: format, title)
    }

    /// The 20 pt square the popover points at: the icon inset by trunc(half its size) − 10 on each axis.
    static func anchor(icon: CGRect) -> CGRect {
        let dx = CGFloat(Int(icon.width * 0.5) - 10), dy = CGFloat(Int(icon.height * 0.5) - 10)
        return icon.insetBy(dx: dx, dy: dy)
    }

    let record: AppRecord
    let popover = NSPopover()
    let messageField: NSTextField
    let cancelButton: NSButton
    let actionButton: NSButton
    /// Called once with true for the action button and false for a cancellation.
    var onFinish: (@MainActor (Bool) -> Void)?
    private var finished = false

    init(record: AppRecord, icon: NSImage, message: String, cancelTitle: String, actionTitle: String) {
        self.record = record
        messageField = NSTextField(wrappingLabelWithString: message)
        cancelButton = NSButton(title: cancelTitle, target: nil, action: nil)
        actionButton = NSButton(title: actionTitle, target: nil, action: nil)
        super.init()
        let view = NSView(frame: CGRect(origin: .zero, size: Self.contentSize))
        let imageView = NSImageView(image: icon)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        messageField.font = .systemFont(ofSize: NSFont.systemFontSize)
        messageField.textColor = .labelColor
        messageField.alignment = .natural
        messageField.isSelectable = false
        messageField.preferredMaxLayoutWidth = Self.messageWidth
        for button in [cancelButton, actionButton] {
            button.bezelStyle = .push
            button.target = self
        }
        cancelButton.action = #selector(cancel)
        actionButton.action = #selector(confirm)
        actionButton.keyEquivalent = "\r"
        for subview in [imageView, cancelButton, messageField, actionButton] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        let minimumHeight = messageField.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.messageMinimumHeight)
        minimumHeight.priority = NSLayoutConstraint.Priority(999)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Self.iconSide),
            imageView.heightAnchor.constraint(equalToConstant: Self.iconSide),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            imageView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            messageField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
            view.trailingAnchor.constraint(equalTo: messageField.trailingAnchor, constant: 12),
            messageField.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            view.bottomAnchor.constraint(equalTo: messageField.bottomAnchor, constant: 40),
            minimumHeight,
            actionButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 10),
            view.trailingAnchor.constraint(equalTo: actionButton.trailingAnchor, constant: 12),
            view.bottomAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: 10),
            view.bottomAnchor.constraint(equalTo: actionButton.bottomAnchor, constant: 10)
        ])
        let controller = NSViewController()
        controller.view = view
        popover.contentViewController = controller
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
    }

    var isShown: Bool { popover.isShown }

    /// `iconFrame` is the icon image in `view`'s coordinates.
    func show(iconFrame: CGRect, in view: NSView) {
        popover.contentSize = Self.contentSize
        popover.show(relativeTo: Self.anchor(icon: iconFrame), of: view, preferredEdge: .minY)
        popover.contentViewController?.view.window?.level = NSWindow.Level(rawValue: Self.windowLevel)
    }

    /// Return and Enter choose the action, Escape and ⌘. cancel, and other keys are consumed while
    /// the panel is open.
    func handleKey(_ event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            confirm()
        } else if event.keyCode == 53
                    || (event.charactersIgnoringModifiers == "." && event.modifierFlags.contains(.command)) {
            cancel()
        }
    }

    @objc func confirm() { finish(true) }
    @objc func cancel() { finish(false) }

    /// The popover closed by itself, as Escape in its own window does.
    func popoverDidClose(_ notification: Notification) { finish(false) }

    private func finish(_ confirmed: Bool) {
        guard !finished else { return }
        finished = true
        if popover.isShown { popover.close() }
        onFinish?(confirmed)
    }
}
