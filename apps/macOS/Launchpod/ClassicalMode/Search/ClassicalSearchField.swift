import AppKit
import QuartzCore

/// Geometry of the Classical search field:
/// a 250 × 25 pt field whose loupe and placeholder sit centred while it is idle and move to the
/// leading edge once typing starts.
nonisolated struct ClassicalSearchFieldLayout: Equatable {
    static let loupeSide: CGFloat = 12
    static let closeSide: CGFloat = 14
    static let placeholderY: CGFloat = 4

    let bounds: CGRect
    let placeholderSize: CGSize
    let rightToLeft: Bool

    /// `round(midY − 6 − 1 + 2) − 1`.
    var loupeY: CGFloat { (bounds.midY - 6 - 1 + 2).rounded(.toNearestOrAwayFromZero) - 1 }
    var closeY: CGFloat { (bounds.midY - 7 - 1 + 2).rounded(.toNearestOrAwayFromZero) - 1 }

    func placeholderFrame(active: Bool) -> CGRect {
        let x: CGFloat
        if active {
            x = rightToLeft ? loupeFrame(active: true).minX - (placeholderSize.width + 8) : 7 + Self.loupeSide + 8
        } else {
            x = bounds.midX - placeholderSize.width / 2 + (rightToLeft ? -12 : 12)
        }
        return CGRect(x: x, y: Self.placeholderY, width: placeholderSize.width, height: placeholderSize.height)
    }

    func loupeFrame(active: Bool) -> CGRect {
        let x: CGFloat
        if active {
            x = rightToLeft ? bounds.width - 19 : 7
        } else {
            let placeholder = placeholderFrame(active: false)
            x = rightToLeft ? placeholder.maxX + 8 : placeholder.minX - 20
        }
        return CGRect(x: x, y: loupeY, width: Self.loupeSide, height: Self.loupeSide)
    }

    var closeFrame: CGRect {
        CGRect(x: rightToLeft ? 6 : bounds.width - 14 - 6, y: closeY, width: Self.closeSide, height: Self.closeSide)
    }

    /// The editable text: from the active placeholder's leading edge to the clear button.
    var editorFrame: CGRect {
        let placeholder = placeholderFrame(active: true)
        let close = closeFrame
        return rightToLeft
            ? CGRect(x: close.maxX + 4, y: 0, width: placeholder.maxX - close.maxX - 4, height: bounds.height)
            : CGRect(x: placeholder.minX, y: 0, width: close.minX - 4 - placeholder.minX, height: bounds.height)
    }
}

/// The search field: its look is drawn in layers inside the zooming content
/// layer — the Dock's stretchable background, loupe and clear images when the system still ships
/// them, a placeholder in SF Light 16 at white 0.36 — while typing goes to a borderless
/// `NSTextField` laid over it. During the launcher's zoom the typed text is shown by a text layer.
@MainActor
final class ClassicalSearchField {
    static let fontSize: CGFloat = 16
    static let placeholderAlpha: CGFloat = 0.36
    static let closeOpacity: Float = 0.3
    /// With the Liquid Glass option the background is system glass drawn behind the field (the
    /// glass stage follows `backgroundLayer`): a capsule, whose corner radius is this share of the
    /// height, with the placeholder and loupe in white at `glassContentAlpha`.
    static let glassCornerRadiusFraction: CGFloat = 0.5
    static let glassContentAlpha: CGFloat = 0.7
    /// `CTFontCreateUIFontForLanguage(103, 16)`: SF Light.
    static var font: NSFont {
        CTFontCreateUIFontForLanguage(CTFontUIFontType(rawValue: 103) ?? .system, fontSize, nil) as NSFont? ?? .systemFont(ofSize: fontSize, weight: .light)
    }

    let layer = CALayer()
    let backgroundLayer = CALayer()
    let loupeLayer = CALayer()
    let placeholderLayer = CATextLayer()
    let closeLayer = CALayer()
    /// Stands in for the text field while the content layer is scaled.
    let textLayer = CATextLayer()
    let textField = ClassicalSearchTextField(frame: .zero)
    private(set) var isActive = false
    /// Tab or a click puts the caret in the field; arrow keys then edit instead of navigating.
    private(set) var hasFocus = false
    private(set) var rightToLeft = false
    private var scale: CGFloat = 0
    private var showsTextField = true
    /// Whether the Liquid Glass option drew the field when it was last placed.
    private(set) var usesGlass = false

    init() {
        backgroundLayer.contentsCenter = CGRect(x: 0.5, y: 0, width: 0, height: 1)
        loupeLayer.contentsGravity = .resizeAspect
        closeLayer.contentsGravity = .resizeAspect
        closeLayer.opacity = Self.closeOpacity
        closeLayer.isHidden = true
        for text in [placeholderLayer, textLayer] {
            text.font = Self.font
            text.fontSize = Self.fontSize
            text.alignmentMode = .left
            text.truncationMode = .none
        }
        placeholderLayer.foregroundColor = CGColor(gray: 1, alpha: Self.placeholderAlpha)
        textLayer.foregroundColor = .white
        textLayer.isHidden = true
        [backgroundLayer, placeholderLayer, textLayer, loupeLayer, closeLayer].forEach(layer.addSublayer)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = Self.font
        textField.textColor = .white
        textField.usesSingleLineMode = true
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.isHidden = true
        // Composed text is not reported as a text change, yet it is shown: the placeholder hides.
        textField.onMarkedTextChange = { [weak self] in self?.textDidChange() }
    }

    /// The field's string, including text an input method is still composing.
    var text: String { textField.stringValue }

    /// The text without any composition in progress, which is what searching uses.
    var committedText: String {
        guard let editor = textField.currentEditor() as? NSTextView, editor.hasMarkedText(),
              let marked = Range(editor.markedRange(), in: editor.string) else { return text }
        var committed = editor.string
        committed.removeSubrange(marked)
        return committed
    }

    var placeholder: String {
        get { placeholderLayer.string as? String ?? "" }
        set { placeholderLayer.string = newValue }
    }

    var layout: ClassicalSearchFieldLayout {
        let text = placeholder
        let size = text.isEmpty ? .zero : (text as NSString).size(withAttributes: [.font: Self.font])
        let lineHeight = (Self.font.ascender - Self.font.descender + Self.font.leading).rounded(.up)
        return ClassicalSearchFieldLayout(bounds: layer.bounds, placeholderSize: CGSize(width: size.width.rounded(.up), height: lineHeight),
                                          rightToLeft: rightToLeft)
    }

    /// Places the field at `frame` (root coordinates, which the content view shares); `usesGlass`
    /// gives it the glass capsule appearance.
    func place(in contentLayer: CALayer, view: NSView, frame: CGRect, scale: CGFloat, rightToLeft: Bool,
               usesGlass: Bool) {
        if scale != self.scale || rightToLeft != self.rightToLeft || usesGlass != self.usesGlass {
            self.rightToLeft = rightToLeft
            self.usesGlass = usesGlass
            loadImages(scale: scale)
        }
        self.scale = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if layer.superlayer !== contentLayer { contentLayer.addSublayer(layer) }
        layer.frame = frame
        backgroundLayer.frame = layer.bounds
        backgroundLayer.cornerRadius = usesGlass ? layer.bounds.height * Self.glassCornerRadiusFraction : 0
        backgroundLayer.cornerCurve = .continuous
        let layout = self.layout
        closeLayer.frame = layout.closeFrame
        [layer, placeholderLayer, textLayer].forEach { $0.contentsScale = scale }
        CATransaction.commit()
        placeLoupeAndPlaceholder(animated: false)
        if textField.superview !== view { view.addSubview(textField) }
        textField.frame = editorFrame(layout).offsetBy(dx: frame.minX, dy: frame.minY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer.alignmentMode = rightToLeft ? .right : .left
        textLayer.frame = CGRect(x: layout.editorFrame.minX, y: ClassicalSearchFieldLayout.placeholderY,
                                 width: layout.editorFrame.width, height: layout.placeholderSize.height)
        CATransaction.commit()
    }

    /// While the content zooms, the typed text is drawn by `textLayer` so it scales with the page.
    func setShowsTextField(_ shows: Bool) {
        showsTextField = shows
        updateTextVisibility()
    }

    /// Starts showing typed text; the loupe and placeholder slide to the leading edge.
    func activate() {
        guard !isActive else { return }
        isActive = true
        updateTextVisibility()
        placeLoupeAndPlaceholder(animated: true)
    }

    /// Clears and returns to the idle, centred look, as when the launcher closes.
    func reset() {
        textField.stringValue = ""
        isActive = false
        hasFocus = false
        textDidChange()
        placeLoupeAndPlaceholder(animated: false)
    }

    func setHasFocus(_ focus: Bool) {
        hasFocus = focus
        if focus { activate() }
        (textField.currentEditor() as? NSTextView)?.insertionPointColor = focus ? .white : .clear
        if !focus, text.isEmpty { deactivate() }
    }

    /// Placeholder and clear button follow the text.
    func textDidChange() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeholderLayer.isHidden = !text.isEmpty
        closeLayer.isHidden = text.isEmpty
        textLayer.string = text
        CATransaction.commit()
        updateTextVisibility()
    }

    /// Opacity 1 while pressed, 0.3 otherwise, without animation.
    func setClearButtonPressed(_ pressed: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        closeLayer.opacity = pressed ? 1 : Self.closeOpacity
        CATransaction.commit()
    }

    /// The clear button's hit area, in the content view's coordinates.
    func closeContains(_ point: CGPoint) -> Bool {
        !closeLayer.isHidden && closeLayer.frame.offsetBy(dx: layer.frame.minX, dy: layer.frame.minY).contains(point)
    }

    func contains(_ point: CGPoint) -> Bool {
        layer.superlayer != nil && layer.frame.contains(point)
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        updateTextVisibility()
        placeLoupeAndPlaceholder(animated: true)
    }

    private func updateTextVisibility() {
        textField.isHidden = !(isActive && showsTextField)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer.isHidden = !(isActive && !showsTextField)
        CATransaction.commit()
    }

    /// Moves between the idle and active positions with the field's ease-in-ease-out implicit action.
    private func placeLoupeAndPlaceholder(animated: Bool) {
        let layout = self.layout
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationTimingFunction(ClassicalAnimationParameters.Search.positionTiming)
        placeholderLayer.frame = layout.placeholderFrame(active: isActive)
        loupeLayer.frame = layout.loupeFrame(active: isActive)
        CATransaction.commit()
    }

    /// The text baseline matches the placeholder's, whose layer draws from the top of a line box at y 4.
    private func editorFrame(_ layout: ClassicalSearchFieldLayout) -> CGRect {
        let font = Self.font
        let baseline = ClassicalSearchFieldLayout.placeholderY + layout.placeholderSize.height - font.ascender
        let fieldHeight = (font.ascender - font.descender).rounded(.up) + 2
        let editor = layout.editorFrame
        return CGRect(x: editor.minX - 2, y: (baseline + font.descender - 1).rounded(.down), width: editor.width + 4, height: fieldHeight)
    }

    private func loadImages(scale: CGFloat) {
        let resources = "/System/Library/CoreServices/Dock.app/Contents/Resources/"
        func image(_ name: String) -> CGImage? {
            let suffix = scale > 1 ? "@2x" : ""
            let url = URL(fileURLWithPath: resources + name + suffix + ".png")
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        [backgroundLayer, loupeLayer, closeLayer].forEach { $0.contentsScale = scale }
        placeholderLayer.foregroundColor = CGColor(gray: 1, alpha: usesGlass ? Self.glassContentAlpha : Self.placeholderAlpha)
        if usesGlass {
            backgroundLayer.contents = nil
            loupeLayer.contents = Self.symbol("magnifyingglass", size: ClassicalSearchFieldLayout.loupeSide, scale: scale,
                                              alpha: Self.glassContentAlpha)
        } else {
            backgroundLayer.contents = image("ectl_search_background") ?? Self.fallbackBackground(scale: scale)
            loupeLayer.contents = image(rightToLeft ? "ectl_search_loupe_rtl" : "ectl_search_loupe")
                ?? Self.fallbackLoupe(scale: scale)
        }
        closeLayer.contents = image("ectl_search_close") ?? Self.fallbackClose(scale: scale)
        CATransaction.commit()
    }

    /// Drawn equivalents of the Dock images for systems that no longer ship them: a white 0.06
    /// rounded fill with a white 0.2 hairline, a loupe and a clear glyph.
    private static func fallbackBackground(scale: CGFloat) -> CGImage? {
        draw(size: CGSize(width: 11, height: 22), scale: scale) { context, rect in
            let path = CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 5, cornerHeight: 5, transform: nil)
            context.addPath(path)
            context.setFillColor(CGColor(gray: 1, alpha: 0.06))
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.2))
            context.setLineWidth(1)
            context.strokePath()
        }
    }

    private static func fallbackLoupe(scale: CGFloat) -> CGImage? {
        symbol("magnifyingglass", size: 12, scale: scale)
    }

    private static func fallbackClose(scale: CGFloat) -> CGImage? {
        symbol("xmark.circle.fill", size: 14, scale: scale)
    }

    private static func symbol(_ name: String, size: CGFloat, scale: CGFloat, alpha: CGFloat = 0.6) -> CGImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        return draw(size: CGSize(width: size, height: size), scale: scale) { context, rect in
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: rect)
            context.setBlendMode(.sourceIn)
            context.setFillColor(CGColor(gray: 1, alpha: alpha))
            context.fill(rect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static func draw(size: CGSize, scale: CGFloat, _ body: (CGContext, CGRect) -> Void) -> CGImage? {
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        body(context, CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}

/// The editable text; it never draws a focus ring or background. A click reports itself so the
/// field can take the caret, and its field editor reports changes to composed (marked) text.
final class ClassicalSearchTextField: NSTextField {
    var onMouseDown: (@MainActor () -> Void)?
    /// Called when the field editor's composed (marked) text changes.
    var onMarkedTextChange: (@MainActor () -> Void)?

    override class var cellClass: AnyClass? {
        get { ClassicalSearchTextFieldCell.self }
        set {}
    }

    override var acceptsFirstResponder: Bool { !isHidden }
    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

/// The search field's cell, with its own field editor so marked-text changes can be observed.
final class ClassicalSearchTextFieldCell: NSTextFieldCell {
    let editor: ClassicalSearchFieldEditor = {
        let editor = ClassicalSearchFieldEditor()
        editor.isFieldEditor = true
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        editor.field = controlView as? ClassicalSearchTextField
        return editor
    }
}

/// A field editor that reports when an input method sets, commits or cancels composed text.
final class ClassicalSearchFieldEditor: NSTextView {
    /// The search text field this editor edits.
    weak var field: ClassicalSearchTextField?

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        field?.onMarkedTextChange?()
    }

    override func unmarkText() {
        super.unmarkText()
        field?.onMarkedTextChange?()
    }
}
