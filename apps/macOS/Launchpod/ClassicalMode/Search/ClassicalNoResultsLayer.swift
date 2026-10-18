import AppKit
import QuartzCore

/// "No Results" over the page area while a search matches nothing: SF Light 40, gray 0.204
/// composited with plus-lighter, with the title shadow.
@MainActor
final class ClassicalNoResultsLayer: CALayer {
    static let fontSize: CGFloat = 40
    static let gray: CGFloat = 0.20392156862745098

    let textLayer = ClassicalShadowTextLayer()

    override init() {
        super.init()
        // The text blends with what lies behind this layer, not only with the layer itself.
        ClassicalLayerFilters.disableGroupBlending(self)
        textLayer.font = CTFontCreateUIFontForLanguage(CTFontUIFontType(rawValue: 103) ?? .system, Self.fontSize, nil)
        textLayer.fontSize = Self.fontSize
        textLayer.foregroundColor = CGColor(gray: Self.gray, alpha: 1)
        textLayer.compositingFilter = "plusL"
        textLayer.alignmentMode = .center
        textLayer.opacity = ClassicalAnimationParameters.Search.hiddenOpacity
        addSublayer(textLayer)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { nil }

    /// Centred on `page` (pager-layer coordinates), 10 pt larger than the text.
    func layOut(text: String, scale: CGFloat, page: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer.string = text
        textLayer.contentsScale = scale
        let size = textLayer.preferredFrameSize()
        let width = size.width + 10, height = size.height + 10
        frame = CGRect(x: (page.midX - width / 2).rounded(.down), y: (page.midY - height / 2).rounded(.down),
                       width: width, height: height)
        textLayer.frame = bounds
        CATransaction.commit()
    }

    /// Showing fades in with the default implicit action; hiding is immediate.
    func setVisible(_ visible: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!visible)
        textLayer.opacity = visible ? ClassicalAnimationParameters.Search.visibleOpacity
                                    : ClassicalAnimationParameters.Search.hiddenOpacity
        CATransaction.commit()
    }
}
