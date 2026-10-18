import QuartzCore

/// Page-dot geometry: 15 × 15 pt indicators 5 pt apart, centred in a 15 pt band halfway down the
/// bottom margin, each drawing an 8 pt dot.
struct ClassicalPageDotsLayout: Equatable {
    static let indicatorSide: CGFloat = 15
    static let spacing: CGFloat = 5
    static let dotSide: CGFloat = 8
    static let currentAlpha: Float = 1
    static let otherAlpha: Float = 0.2

    let pageCount: Int
    let width: CGFloat
    let rightToLeft: Bool

    /// The control band in root-layer coordinates: full width, centred in the bottom margin.
    static func bandFrame(for geometry: ClassicalSpringboardGeometry) -> CGRect {
        let y = geometry.contentFrame.minY + max(0, (geometry.margins.bottom / 2 - indicatorSide / 2).rounded(.down))
        return CGRect(x: 0, y: y, width: geometry.screenSize.width, height: indicatorSide)
    }

    /// The dots are hidden while there is a single page.
    var isHidden: Bool { pageCount < 2 }

    /// The indicator of logical page `page` inside the band; right-to-left layouts mirror the order.
    func indicatorFrame(for page: Int) -> CGRect {
        let group = CGFloat(pageCount) * Self.indicatorSide + CGFloat(max(pageCount - 1, 0)) * Self.spacing
        let slot = rightToLeft ? pageCount - 1 - page : page
        let x = (width / 2 - group / 2).rounded(.down) + CGFloat(slot) * (Self.indicatorSide + Self.spacing)
        return CGRect(x: x, y: 0, width: Self.indicatorSide, height: Self.indicatorSide)
    }

    func page(at point: CGPoint) -> Int? {
        (0..<pageCount).first { indicatorFrame(for: $0).contains(point) }
    }
}

/// The page-dot band. Its whole area consumes clicks; releasing over an indicator selects that page.
@MainActor
final class ClassicalPageDotsLayer: CALayer {
    private(set) var layout = ClassicalPageDotsLayout(pageCount: 1, width: 0, rightToLeft: false)
    private(set) var dotLayers: [CALayer] = []

    override init() {
        super.init()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { nil }

    func update(_ layout: ClassicalPageDotsLayout, currentPage: Int, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if layout != self.layout || dotLayers.count != layout.pageCount {
            self.layout = layout
            dotLayers.forEach { $0.removeFromSuperlayer() }
            dotLayers = (0..<layout.pageCount).map { page in
                let dot = CALayer()
                let inset = (ClassicalPageDotsLayout.indicatorSide - ClassicalPageDotsLayout.dotSide) / 2
                dot.frame = layout.indicatorFrame(for: page).insetBy(dx: inset, dy: inset)
                dot.cornerRadius = ClassicalPageDotsLayout.dotSide / 2
                dot.backgroundColor = .white
                dot.contentsScale = scale
                addSublayer(dot)
                return dot
            }
        }
        isHidden = layout.isHidden
        for (page, dot) in dotLayers.enumerated() {
            dot.opacity = page == currentPage ? ClassicalPageDotsLayout.currentAlpha : ClassicalPageDotsLayout.otherAlpha
        }
    }
}
