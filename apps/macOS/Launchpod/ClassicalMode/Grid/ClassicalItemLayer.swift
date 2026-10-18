import AppKit
import QuartzCore

/// An application cell: the icon above a single-line, centered title.
///
/// `transformLayer` fills the cell and scales about its centre to magnify a held icon, so the
/// cell's own frame stays its slot. Inside it, `jitterLayer` holds the icon, title, selection and
/// delete badge so they jitter together.
@MainActor
class ClassicalItemLayer: CALayer {
    let transformLayer = CALayer()
    let jitterLayer = CALayer()
    let iconLayer = CALayer()
    let titleLayer = ClassicalShadowTextLayer()
    private(set) var notFoundLayer: CALayer?
    private(set) var restrictedLayer: CALayer?
    private(set) var isRestricted = false
    private(set) var flagLayer: CALayer?
    let scale: CGFloat
    /// The cell's icon and title placement; the icon returns to `layout.iconFrame`.
    let layout: ClassicalItemLayout

    init(title: String, layout: ClassicalItemLayout, scale: CGFloat) {
        self.scale = scale
        self.layout = layout
        super.init()
        contentsScale = scale
        // The selection blends with what lies behind the cell, not only with the cell itself.
        ClassicalLayerFilters.disableGroupBlending(jitterLayer)
        transformLayer.addSublayer(jitterLayer)
        addSublayer(transformLayer)
        layOutTransformLayer(in: CGRect(origin: .zero, size: layout.cellSize))
        iconLayer.frame = layout.iconFrame
        iconLayer.contentsScale = scale
        iconLayer.contentsGravity = .resizeAspect
        let font = ClassicalTitleFont.font
        titleLayer.string = title
        titleLayer.font = font
        titleLayer.fontSize = ClassicalTitleFont.size
        titleLayer.foregroundColor = .white
        titleLayer.alignmentMode = .center
        titleLayer.truncationMode = .middle
        titleLayer.isWrapped = false
        titleLayer.contentsScale = scale
        titleLayer.frame = layout.titleTextFrame(textWidth: Self.titleWidth(title))
        jitterLayer.addSublayer(iconLayer)
        jitterLayer.addSublayer(titleLayer)
    }

    override init(layer: Any) {
        scale = (layer as? ClassicalItemLayer)?.scale ?? 1
        self.layout = (layer as? ClassicalItemLayer)?.layout ?? ClassicalItemLayout(cellSize: .zero)
        super.init(layer: layer)
    }

    /// The title's natural single-line width.
    private static func titleWidth(_ title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: ClassicalTitleFont.font]).width.rounded(.up)
    }

    /// Replaces the title, centred for its width.
    func setTitle(_ title: String) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        titleLayer.string = title
        titleLayer.frame = titleFrame
        positionFlag()
        CATransaction.commit()
    }

    /// Where the title rests: centred below the icon for its width.
    var titleFrame: CGRect {
        layout.titleTextFrame(textWidth: Self.titleWidth((titleLayer.string as? String) ?? ""))
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layOutTransformLayer(in: bounds)
        CATransaction.commit()
    }

    /// Sets bounds and position rather than `frame`, which is undefined under a scale transform.
    private func layOutTransformLayer(in rect: CGRect) {
        transformLayer.bounds = CGRect(origin: .zero, size: rect.size)
        transformLayer.position = CGPoint(x: rect.midX, y: rect.midY)
        jitterLayer.frame = transformLayer.bounds
        positionFlag()
        positionRestrictedLayer()
    }

    /// Shows the recently added dot beside the title while the app awaits its first open.
    func setRecentlyAdded(_ recentlyAdded: Bool, rightToLeft: Bool = false) {
        if !recentlyAdded {
            flagLayer?.removeFromSuperlayer()
            flagLayer = nil
            return
        }
        if flagLayer == nil {
            let dot = CALayer()
            dot.backgroundColor = NSColor(calibratedRed: 0, green: 122.0 / 255.0, blue: 1, alpha: 1).cgColor
            dot.cornerRadius = ClassicalRecentlyAddedFlag.dotSide / 2
            dot.contentsScale = scale
            jitterLayer.addSublayer(dot)
            flagLayer = dot
        }
        flagIsRightToLeft = rightToLeft
        positionFlag()
    }

    private var flagIsRightToLeft = false

    private func positionFlag() {
        guard let flagLayer else { return }
        let labelFrame = titleFrame.insetBy(dx: -ClassicalItemLayout.titleInset,
                                            dy: -ClassicalItemLayout.titleInset)
        flagLayer.frame = ClassicalRecentlyAddedFlag.frame(title: labelFrame,
                                                            rightToLeft: flagIsRightToLeft)
    }

    /// Editing-state visuals (jitter, magnification, delete badge) live in `ClassicalItemEditing.swift`.
    var closeboxLayer: CALayer?
    private(set) var isJittering = false
    private(set) var isMagnified = false

    func setJitteringState(_ jittering: Bool) { isJittering = jittering }
    func setMagnifiedState(_ magnified: Bool) { isMagnified = magnified }

    required init?(coder: NSCoder) { nil }

    /// The keyboard selection highlight, behind the icon and title.
    private(set) var selectionLayer: CALayer?

    var isSelected: Bool { selectionLayer != nil }

    func setSelected(_ selected: Bool) {
        guard selected != isSelected else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard selected else {
            selectionLayer?.removeFromSuperlayer()
            selectionLayer = nil
            return
        }
        let selection = CALayer()
        selection.backgroundColor = ClassicalSelection.color
        selection.compositingFilter = ClassicalSelection.compositingFilter
        selection.frame = ClassicalSelection.frame(icon: iconLayer.frame,
                                                   label: titleLayer.frame.insetBy(dx: -ClassicalItemLayout.titleInset,
                                                                                   dy: -ClassicalItemLayout.titleInset))
        selection.cornerRadius = ClassicalSelection.cornerRadius(iconHeight: iconLayer.frame.height)
        jitterLayer.insertSublayer(selection, at: 0)
        selectionLayer = selection
    }

    /// Pressed look: the icon multiplied by gray 0.4 through a layer filter, which also covers an
    /// icon that arrives while pressed.
    private(set) var isDarkened = false

    func setDarkened(_ darkened: Bool) {
        guard darkened != isDarkened else { return }
        isDarkened = darkened
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.filters = darkened ? ClassicalPressedIcon.filter().map { [$0] } : nil
        CATransaction.commit()
    }

    func setIcon(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.contents = image
        CATransaction.commit()
    }

    /// Shows the system's restricted-app badge beside a dimmed icon.
    func setRestricted(_ restricted: Bool, rightToLeft: Bool = false) {
        guard restricted != isRestricted || (restricted && restrictedIsRightToLeft != rightToLeft) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        isRestricted = restricted
        restrictedIsRightToLeft = rightToLeft
        iconLayer.opacity = restricted ? ClassicalRestrictedArtwork.iconOpacity : 1
        guard restricted else {
            restrictedLayer?.removeFromSuperlayer()
            restrictedLayer = nil
            return
        }
        if restrictedLayer == nil, let image = ClassicalRestrictedArtwork.image(scale: scale) {
            let badge = CALayer()
            ClassicalRestrictedArtwork.applyImageMaterial(to: badge)
            badge.contents = image
            badge.contentsScale = scale
            badge.contentsGravity = .resizeAspect
            jitterLayer.addSublayer(badge)
            restrictedLayer = badge
        }
        positionRestrictedLayer()
    }

    private var restrictedIsRightToLeft = false

    private func positionRestrictedLayer() {
        guard let restrictedLayer else { return }
        let icon = iconLayer.frame
        restrictedLayer.frame = CGRect(x: restrictedIsRightToLeft ? icon.minX - ClassicalRestrictedArtwork.side : icon.maxX,
                                       y: icon.minY + ClassicalRestrictedArtwork.topOffset,
                                       width: ClassicalRestrictedArtwork.side,
                                       height: ClassicalRestrictedArtwork.side)
    }

    /// Keeps the unavailable marker separate from the app icon, so reconnecting only removes the marker.
    func setNotFound(_ notFound: Bool) {
        guard notFound != (notFoundLayer != nil) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard notFound else {
            notFoundLayer?.removeFromSuperlayer()
            notFoundLayer = nil
            return
        }
        let marker = CALayer()
        marker.frame = iconLayer.bounds
        if marker.responds(to: NSSelectorFromString("setAllowsHitTesting:")) {
            marker.setValue(false, forKey: "allowsHitTesting")
        }
        marker.contentsScale = scale
        marker.contentsGravity = .resizeAspect
        if let image = ClassicalNotFoundArtwork.image(scale: scale) {
            marker.contents = image
        } else {
            let question = CATextLayer()
            question.string = "?"
            question.fontSize = iconLayer.bounds.height * 0.82
            question.alignmentMode = .center
            question.foregroundColor = NSColor.white.cgColor
            question.contentsScale = scale
            question.frame = marker.bounds
            marker.addSublayer(question)
        }
        iconLayer.addSublayer(marker)
        notFoundLayer = marker
    }
}

/// Position of the 9 pt flag dot within its title-height container.
private enum ClassicalRecentlyAddedFlag {
    static let dotSide: CGFloat = 9

    static func frame(title: CGRect, rightToLeft: Bool) -> CGRect {
        let outerSide = title.height - 8
        let outer = CGRect(x: rightToLeft ? title.minX - outerSide + 1 : title.maxX,
                           y: title.minY + 5, width: outerSide, height: outerSide)
        return CGRect(x: (outer.midX - dotSide / 2).rounded(.towardZero),
                      y: (outer.midY - dotSide / 2).rounded(.towardZero),
                      width: dotSide, height: dotSide)
    }
}

@MainActor
private enum ClassicalNotFoundArtwork {
    private static var cached: [Int: CGImage] = [:]

    static func image(scale: CGFloat) -> CGImage? {
        let resolution = scale > 1 ? 2 : 1
        if let image = cached[resolution] { return image }
        let suffix = resolution == 2 ? "@2x" : ""
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Dock.app/Contents/Resources/ecsb_notFound\(suffix).png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        cached[resolution] = image
        return image
    }
}

@MainActor
private enum ClassicalRestrictedArtwork {
    static let side: CGFloat = 16
    static let topOffset: CGFloat = 4
    static let iconOpacity: Float = 0.2
    private static var cached: [Int: CGImage] = [:]

    static func applyImageMaterial(to layer: CALayer) {
        let selector = NSSelectorFromString("setImageMaterialControl:appearance:")
        guard layer.responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Int, AnyObject?) -> Void
        let setter = unsafeBitCast(layer.method(for: selector), to: Setter.self)
        setter(layer, selector, 1, nil)
    }

    static func image(scale: CGFloat) -> CGImage? {
        let resolution = scale > 1 ? 2 : 1
        if let image = cached[resolution] { return image }
        let suffix = resolution == 2 ? "@2x" : ""
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Dock.app/Contents/Resources/hourglass\(suffix).png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        cached[resolution] = image
        return image
    }
}
