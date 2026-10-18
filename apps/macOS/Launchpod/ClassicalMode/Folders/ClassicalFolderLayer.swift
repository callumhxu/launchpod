import AppKit
import QuartzCore

/// The open folder's panel: a rounded backing guide for native glass or a translucent backdrop,
/// the folder's pages and page dots inside it, and the title above it.
///
/// Everything below the title sits in `maskContainerLayer`, which `maskLayer` clips to the
/// backdrop's shape. Opening starts with the mask and backdrop at the closed cell's backdrop and
/// grows them to the panel; closing reverses that. The panel's own frame never animates.
@MainActor
final class ClassicalFolderLayer: CALayer {
    let maskContainerLayer = CALayer()
    let maskLayer = CALayer()
    /// A plain geometry guide for native glass, or a filtered backdrop for the classic appearance.
    let backdropLayer: CALayer
    let glassEnabled: Bool
    let titleLayer = ClassicalShadowTextLayer()
    /// Where the title editor goes; it has no content of its own.
    let titleEditLayer = CALayer()
    private(set) var geometry: ClassicalFolderGeometry.Panel?

    /// The system UI font of type 103 (SF Light) at the title size.
    static var titleFont: NSFont {
        let size = ClassicalFolderParameters.titleFontSize
        return CTFontCreateUIFontForLanguage(CTFontUIFontType(rawValue: 103) ?? .system, size, nil) as NSFont?
            ?? .systemFont(ofSize: size, weight: .light)
    }

    init(glassEnabled: Bool = false) {
        backdropLayer = glassEnabled ? CALayer() : ClassicalLayerFilters.makeBackdropLayer() ?? CALayer()
        self.glassEnabled = glassEnabled
        super.init()
        let parameters = ClassicalFolderParameters.self
        masksToBounds = false
        maskLayer.backgroundColor = .white
        if !self.glassEnabled {
            backdropLayer.backgroundColor = CGColor(gray: parameters.panelBackdropGray, alpha: parameters.panelBackdropAlpha)
        }
        for layer in [maskLayer, backdropLayer] {
            layer.cornerRadius = parameters.panelCornerRadius
            layer.cornerCurve = .continuous
        }
        if !self.glassEnabled {
            backdropLayer.backgroundFilters = [
                ClassicalLayerFilters.gaussianBlur(radius: parameters.panelBlurRadius, hardEdges: true),
                ClassicalLayerFilters.colorSaturate(amount: parameters.panelSaturation),
            ].compactMap { $0 }
        }
        maskContainerLayer.mask = maskLayer
        maskContainerLayer.addSublayer(backdropLayer)
        titleLayer.font = Self.titleFont
        titleLayer.fontSize = parameters.titleFontSize
        titleLayer.foregroundColor = .white
        titleLayer.alignmentMode = .center
        titleLayer.truncationMode = .middle
        titleLayer.isWrapped = false
        titleEditLayer.isHidden = true
        addSublayer(maskContainerLayer)
        addSublayer(titleLayer)
        addSublayer(titleEditLayer)
    }

    override init(layer: Any) {
        let source = layer as? ClassicalFolderLayer
        glassEnabled = source?.glassEnabled ?? false
        backdropLayer = glassEnabled ? CALayer() : ClassicalLayerFilters.makeBackdropLayer() ?? CALayer()
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { nil }

    /// Places the panel for `geometry` in its final, open state and adds `pagerLayer` inside the mask.
    func layOut(_ geometry: ClassicalFolderGeometry.Panel, title: String, scale: CGFloat, pagerLayer: CALayer) {
        self.geometry = geometry
        withoutActions {
            frame = geometry.frame
            contentsScale = scale
            titleLayer.contentsScale = scale
            maskContainerLayer.frame = bounds
            if pagerLayer.superlayer !== maskContainerLayer { maskContainerLayer.addSublayer(pagerLayer) }
            titleLayer.string = title
        }
        applyOpenState()
    }

    func setTitle(_ title: String) {
        withoutActions {
            titleLayer.string = title
            placeTitle()
        }
    }

    /// The title label's size: the text's width and line height with the label insets and shadow
    /// allowance of an application title, no wider than the folder grid.
    var titleLabelSize: CGSize {
        let font = Self.titleFont
        let text = (titleLayer.string as? String) ?? ""
        let inset = ClassicalItemLayout.titleInset
        let width = (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + 2 * inset
        let line = (font.ascender - font.descender + font.leading).rounded(.up)
        let maximum = geometry?.firstPageFrame.width ?? width
        return CGSize(width: min(width, maximum),
                      height: line + 2 * inset + ClassicalTitleFont.shadowBlur - ClassicalTitleFont.shadowOffset.height)
    }

    /// The title's editing area, in the panel's coordinates.
    var titleEditFrame: CGRect { titleEditLayer.frame }

    /// Sets the open state's frames, corner radius and opacities, animated by the current transaction.
    func applyOpenState() {
        guard let geometry else { return }
        let backdrop = geometry.backdropFrame
        for layer in [maskLayer, backdropLayer] {
            layer.frame = backdrop
            layer.cornerRadius = ClassicalFolderParameters.panelCornerRadius
        }
        placeTitle()
        titleLayer.opacity = ClassicalAnimationParameters.Folder.visibleOpacity
        titleEditLayer.opacity = ClassicalAnimationParameters.Folder.visibleOpacity
    }

    /// The closed state: the mask and backdrop at the closed cell's `itemBackdrop` with its corner
    /// radius, and the title's bottom edge at the top of `cell`, the closed cell's whole frame,
    /// centred on it (both in the panel's coordinates); the title fades out. Animated by the
    /// current transaction.
    func applyClosedState(itemBackdrop: CGRect, cornerRadius: CGFloat, cell: CGRect) {
        for layer in [maskLayer, backdropLayer] {
            layer.frame = itemBackdrop
            layer.cornerRadius = cornerRadius
        }
        for layer in [titleLayer, titleEditLayer] {
            let size = layer.bounds.size
            layer.frame = CGRect(x: cell.midX - size.width / 2, y: cell.maxY, width: size.width, height: size.height)
            layer.opacity = ClassicalAnimationParameters.Folder.hiddenOpacity
        }
    }

    /// Whether `point` (panel coordinates) is on the backdrop as it is shown open.
    func backdropContains(_ point: CGPoint) -> Bool {
        guard let geometry else { return false }
        let radius = ClassicalFolderParameters.panelCornerRadius
        return CGPath(roundedRect: geometry.backdropFrame, cornerWidth: radius, cornerHeight: radius, transform: nil)
            .contains(point)
    }

    private func placeTitle() {
        guard let geometry else { return }
        let size = titleLabelSize
        let inset = ClassicalItemLayout.titleInset
        titleLayer.frame = geometry.titleFrame(labelSize: size).insetBy(dx: inset, dy: inset)
        titleEditLayer.frame = geometry.titleEditFrame(labelSize: size)
    }

    private func withoutActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
