import AppKit
import QuartzCore

/// A closed folder on a root page: a translucent backdrop in place of an application icon, a 3 × 3
/// grid of the icons on the folder's first page over it, and the folder title below. Selection,
/// pressing, jitter and magnification behave as on application cells; the icon layer stays empty.
@MainActor
final class ClassicalFolderItemLayer: ClassicalItemLayer {
    let backdropLayer: CALayer
    /// Clips thumbnails past the ninth.
    let miniGridLayer = CALayer()
    private(set) var thumbnailLayers: [CALayer] = []
    private(set) var folder: ClassicalPageFolder
    let geometry: ClassicalFolderGeometry.Cell
    let rightToLeft: Bool
    let glassEnabled: Bool

    init(folder: ClassicalPageFolder, layout: ClassicalItemLayout, scale: CGFloat, rightToLeft: Bool,
         glassEnabled: Bool = false) {
        self.folder = folder
        geometry = ClassicalFolderGeometry.Cell(iconFrame: layout.iconFrame)
        self.rightToLeft = rightToLeft
        backdropLayer = CALayer()
        self.glassEnabled = glassEnabled
        super.init(title: folder.title, layout: layout, scale: scale)
        let parameters = ClassicalFolderParameters.self
        backdropLayer.frame = geometry.backdropFrame
        if !self.glassEnabled {
            backdropLayer.backgroundColor = CGColor(gray: parameters.itemBackdropGray, alpha: parameters.itemBackdropAlpha)
        }
        backdropLayer.cornerRadius = geometry.cornerRadius
        backdropLayer.cornerCurve = .continuous
        miniGridLayer.frame = geometry.miniGridFrame
        miniGridLayer.masksToBounds = true
        jitterLayer.insertSublayer(backdropLayer, below: iconLayer)
        jitterLayer.addSublayer(miniGridLayer)
        makeThumbnails()
    }

    override init(layer: Any) {
        let source = layer as? ClassicalFolderItemLayer
        folder = source?.folder ?? ClassicalPageFolder(id: .init(), title: "", pages: [])
        geometry = source?.geometry ?? ClassicalFolderGeometry.Cell(iconFrame: .zero)
        rightToLeft = source?.rightToLeft ?? false
        glassEnabled = source?.glassEnabled ?? false
        backdropLayer = CALayer()
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { nil }

    /// The applications whose icons the thumbnail grid shows: all of the folder's first page.
    var thumbnailRecords: [AppRecord] { folder.pages.first ?? [] }

    /// The icon size thumbnails request, from the cell's icon side.
    var thumbnailIconSize: AppIconSize? {
        let side = ClassicalFolderGeometry.Cell.miniIconSide(iconSide: layout.iconFrame.height)
        return try? AppIconSize(pointSize: CGSize(width: side, height: side), backingScale: scale)
    }

    func hasThumbnail(at index: Int) -> Bool {
        thumbnailLayers.indices.contains(index) && thumbnailLayers[index].contents != nil
    }

    func setThumbnail(_ image: CGImage, at index: Int) {
        guard thumbnailLayers.indices.contains(index) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thumbnailLayers[index].contents = image
        CATransaction.commit()
    }

    /// Hide a thumbnail until the icon image minimizing into it has finished.
    func setThumbnailVisible(_ visible: Bool, at index: Int) {
        guard thumbnailLayers.indices.contains(index) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thumbnailLayers[index].opacity = visible ? ClassicalAnimationParameters.Folder.visibleOpacity
                                                 : ClassicalAnimationParameters.Folder.hiddenOpacity
        CATransaction.commit()
    }

    /// The thumbnail fades in after its full-size icon has minimized into place.
    func revealThumbnail(at index: Int, completion: @escaping @MainActor () -> Void) {
        guard thumbnailLayers.indices.contains(index) else { return completion() }
        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        thumbnailLayers[index].opacity = ClassicalAnimationParameters.Folder.visibleOpacity
        CATransaction.commit()
    }

    /// Thumbnail `index`'s frame in `layer`'s coordinates.
    func thumbnailFrame(at index: Int, in layer: CALayer) -> CGRect {
        layer.convert(geometry.thumbnailFrame(at: index, rightToLeft: rightToLeft), from: miniGridLayer)
    }

    /// Scrolls enough rows to expose an empty thumbnail slot when the first folder page fills the
    /// 3 × 3 preview: past the rows beyond the preview, and one row further when the last row is full.
    func scrollToAvailableSpace() {
        let columns = ClassicalFolderParameters.miniGridColumns
        let capacity = columns * ClassicalFolderParameters.miniGridRows
        let count = thumbnailRecords.count
        guard count >= capacity else { return }
        let additionalRows = (count - capacity + columns - 1) / columns
        let rows = additionalRows + (count.isMultiple(of: columns) ? 1 : 0)
        miniGridLayer.bounds.origin.y = -CGFloat(rows) * geometry.miniCellSize.height
    }

    func scrollToTop() {
        miniGridLayer.bounds.origin.y = 0
    }

    /// Shows `folder`'s title and first page, keeping the icons of applications still shown.
    func setFolder(_ folder: ClassicalPageFolder) {
        let icons = Dictionary(zip(thumbnailRecords.map(\.id), thumbnailLayers.map(\.contents)),
                               uniquingKeysWith: { first, _ in first })
        self.folder = folder
        setTitle(folder.title)
        makeThumbnails()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, record) in thumbnailRecords.enumerated() {
            if let icon = icons[record.id] ?? nil, CFGetTypeID(icon as CFTypeRef) == CGImage.typeID {
                setThumbnail(icon as! CGImage, at: index)
            }
        }
        CATransaction.commit()
    }

    /// The pressed look darkens the thumbnail grid and, in the classic appearance, its backing.
    override func setDarkened(_ darkened: Bool) {
        guard darkened != isDarkened else { return }
        super.setDarkened(darkened)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in glassEnabled ? [miniGridLayer] : [backdropLayer, miniGridLayer] {
            layer.filters = darkened ? ClassicalPressedIcon.filter().map { [$0] } : nil
        }
        CATransaction.commit()
    }

    private func makeThumbnails() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thumbnailLayers.forEach { $0.removeFromSuperlayer() }
        thumbnailLayers = thumbnailRecords.indices.map { index in
            let thumbnail = CALayer()
            thumbnail.frame = geometry.thumbnailFrame(at: index, rightToLeft: rightToLeft)
            thumbnail.contentsGravity = .resizeAspect
            thumbnail.contentsScale = scale
            miniGridLayer.addSublayer(thumbnail)
            return thumbnail
        }
        CATransaction.commit()
    }
}
