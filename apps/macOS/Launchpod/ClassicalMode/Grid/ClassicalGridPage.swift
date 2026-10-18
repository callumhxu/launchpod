import AppKit
import QuartzCore

/// One page of application and folder cells. Cells are placed at once; their icons load on request
/// so only the pages near the visible one fetch rasters.
@MainActor
final class ClassicalGridPage {
    let layer = CALayer()
    var slowMotionAllowed: @MainActor () -> Bool = {
        UserDefaults(suiteName: "com.apple.dock").map(ClassicalAnimationParameters.slowMotionAllowed(in:)) ?? false
    }
    var shiftKeyDown: @MainActor () -> Bool = { NSEvent.modifierFlags.contains(.shift) }
    private(set) var itemLayers: [ClassicalItemLayer] = []
    private(set) var items: [ClassicalPageItem] = []
    /// The applications placed directly on this page; a folder's applications are not included.
    var records: [AppRecord] { items.compactMap(\.record) }
    private var scale: CGFloat = 0
    private var itemLayout: ClassicalItemLayout?
    private var iconSize: AppIconSize?
    private var icon: (@MainActor (AppRecord, AppIconSize) async throws -> CGImage)?
    private var iconTasks: [Task<Void, Never>] = []
    private(set) var loadsIcons = false
    /// Whether folder cells made from now on use the glass appearance; the pager sets it.
    var folderGlassEnabled = false

    isolated deinit {
        cancelIconLoads()
    }

    /// Replaces the page's cells for `geometry` at its first-page frame and loads their icons.
    func show(_ records: [AppRecord], geometry: ClassicalSpringboardGeometry, scale: CGFloat,
              rightToLeft: Bool, icon: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage) {
        show(records.map(ClassicalPageItem.app), grid: geometry.grid, frame: geometry.pageFrame, scale: scale,
             rightToLeft: rightToLeft, icon: icon)
        loadIcons()
    }

    /// Replaces the page's cells with `items` in `frame`; icons wait for `loadIcons()`.
    ///
    /// With `animatesMoves`, cells whose item stays keep their layer and slide to their new
    /// slot with the implicit animation of the current transaction after a removal or a drag move;
    /// other cells appear and disappear at once. Cells past the
    /// grid's capacity are hidden without animation until a drop
    /// moves them to the next page. `detached` stands for its item and is left where it is.
    func show(_ items: [ClassicalPageItem], grid: ClassicalGridLayout, frame: CGRect, scale: CGFloat,
              rightToLeft: Bool, icon: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage,
              cachedIcon: @MainActor (AppRecord, AppIconSize) -> CGImage? = { _, _ in nil }, animatesMoves: Bool = false,
              detached: (id: ClassicalPageItem.ID, cell: ClassicalItemLayer)? = nil) {
        cancelIconLoads()
        let item = ClassicalItemLayout(cellSize: grid.cellSize)
        var reusable: [ClassicalPageItem.ID: (item: ClassicalPageItem, cell: ClassicalItemLayer)] = [:]
        if animatesMoves, self.scale == scale, layer.frame == frame, self.itemLayout == item {
            for (shown, cell) in zip(self.items, itemLayers) where shown.id != detached?.id {
                reusable[shown.id] = (shown, cell)
            }
        }
        self.items = items
        self.icon = icon
        self.scale = scale
        itemLayout = item
        let iconSize = try? AppIconSize(pointSize: item.iconFrame.size, backingScale: scale)
        self.iconSize = iconSize
        withoutActions {
            layer.frame = frame
            let previous = itemLayers
            itemLayers = self.items.enumerated().map { index, shown in
                if let detached, shown.id == detached.id { return detached.cell }
                let slot = grid.cellFrame(at: index, rightToLeft: rightToLeft)
                let hidden = index >= grid.capacity
                if let kept = reusable.removeValue(forKey: shown.id), kept.item == shown {
                    if hidden || kept.cell.isHidden {
                        kept.cell.frame = slot
                    } else {
                        CATransaction.begin()
                        CATransaction.setDisableActions(false)
                        kept.cell.frame = slot
                        CATransaction.commit()
                    }
                    kept.cell.isHidden = hidden
                    if let record = shown.record {
                        kept.cell.setNotFound(Self.isUnavailable(record))
                        kept.cell.setRecentlyAdded(record.isRecentlyAdded == true, rightToLeft: rightToLeft)
                    }
                    return kept.cell
                }
                let cell = Self.makeCell(for: shown, layout: item, scale: scale, rightToLeft: rightToLeft,
                                         iconSize: iconSize, folderGlass: folderGlassEnabled, cachedIcon: cachedIcon)
                cell.frame = slot
                cell.isHidden = hidden
                layer.addSublayer(cell)
                return cell
            }
            let kept = Set(itemLayers.map(ObjectIdentifier.init))
            previous.filter { !kept.contains(ObjectIdentifier($0)) && $0 !== detached?.cell }
                .forEach { $0.removeFromSuperlayer() }
        }
    }

    private static func makeCell(for item: ClassicalPageItem, layout: ClassicalItemLayout, scale: CGFloat,
                                 rightToLeft: Bool, iconSize: AppIconSize?, folderGlass: Bool,
                                 cachedIcon: @MainActor (AppRecord, AppIconSize) -> CGImage?) -> ClassicalItemLayer {
        switch item {
        case let .app(record):
            let cell = ClassicalItemLayer(title: record.metadata.displayName, layout: layout, scale: scale)
            if let image = iconSize.flatMap({ cachedIcon(record, $0) }) { cell.setIcon(image) }
            cell.setNotFound(isUnavailable(record))
            cell.setRecentlyAdded(record.isRecentlyAdded == true, rightToLeft: rightToLeft)
            return cell
        case let .folder(folder):
            let cell = ClassicalFolderItemLayer(folder: folder, layout: layout, scale: scale, rightToLeft: rightToLeft,
                                                glassEnabled: folderGlass)
            if let size = cell.thumbnailIconSize {
                for (index, record) in cell.thumbnailRecords.enumerated() {
                    if let image = cachedIcon(record, size) { cell.setThumbnail(image, at: index) }
                }
            }
            return cell
        }
    }

    private static func isUnavailable(_ record: AppRecord) -> Bool {
        record.isMissing == true || record.source.isOnline == false
    }

    /// The cell fades out while shrinking to 0.1 over 0.5 s (5 s with allowed Shift slow motion),
    /// then leaves the page without animation.
    static var removalDuration: CFTimeInterval { ClassicalAnimationParameters.Removal.duration }
    static var slowRemovalDuration: CFTimeInterval { ClassicalAnimationParameters.Removal.slowDuration }
    static var removalScale: CGFloat { ClassicalAnimationParameters.Removal.scale }

    func animateRemoval(of cell: ClassicalItemLayer, completion: @escaping @MainActor () -> Void) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(slowMotionAllowed() && shiftKeyDown()
                                           ? Self.slowRemovalDuration : Self.removalDuration)
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                cell.removeFromSuperlayer()
                CATransaction.commit()
                completion()
            }
        }
        cell.opacity = ClassicalAnimationParameters.Removal.hiddenOpacity
        cell.transform = CATransform3DMakeScale(Self.removalScale, Self.removalScale, 1)
        CATransaction.commit()
    }

    /// Starts loading the icons of cells, and of folder thumbnails, that have none; repeated calls do nothing.
    func loadIcons() {
        guard !loadsIcons, let iconSize, let icon else { return }
        loadsIcons = true
        for (cell, item) in zip(itemLayers, items) {
            if let record = item.record, cell.iconLayer.contents == nil {
                iconTasks.append(Task { [weak cell] in
                    guard let image = try? await icon(record, iconSize), !Task.isCancelled else { return }
                    cell?.setIcon(image)
                })
            } else if let folder = cell as? ClassicalFolderItemLayer, let size = folder.thumbnailIconSize {
                for (index, record) in folder.thumbnailRecords.enumerated() where !folder.hasThumbnail(at: index) {
                    iconTasks.append(Task { [weak folder] in
                        guard let image = try? await icon(record, size), !Task.isCancelled else { return }
                        folder?.setThumbnail(image, at: index)
                    })
                }
            }
        }
    }

    func cancelIconLoads() {
        iconTasks.forEach { $0.cancel() }
        iconTasks.removeAll()
        loadsIcons = false
    }

    private func withoutActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}

/// Draws its text with the title shadow in the backing store: shadow offset and blur are
/// device-space values scaled by 0.6 × the backing scale on Retina.
final class ClassicalShadowTextLayer: CATextLayer {
    override func draw(in context: CGContext) {
        let scale = contentsScale > 1 ? contentsScale * 0.6 : contentsScale
        let offset = ClassicalTitleFont.shadowOffset
        context.setShadow(offset: CGSize(width: offset.width * scale, height: offset.height * scale),
                          blur: ClassicalTitleFont.shadowBlur * scale,
                          color: CGColor(gray: 0, alpha: ClassicalTitleFont.shadowAlpha))
        super.draw(in: context)
    }
}

/// The keyboard selection's look.
nonisolated enum ClassicalSelection {
    /// sRGB white 0.9098 composited with plus-darker: it darkens what is behind it by about 9 %.
    static let color = CGColor(srgbRed: 0.9098039215686274, green: 0.9098039215686274, blue: 0.9098039215686274, alpha: 1)
    static let compositingFilter = "plusD"

    /// The union of the icon and title label, widened so narrow titles still get a 7–15 pt margin,
    /// extended 5 pt below and 15 pt above.
    static func frame(icon: CGRect, label: CGRect) -> CGRect {
        let union = icon.union(label)
        let dx: CGFloat
        if label.width <= icon.width {
            dx = 15
        } else if label.width >= icon.width + 15 {
            dx = 7
        } else {
            dx = max(0, 8 - ((label.width - icon.width) / 2).rounded(.down)) + 7
        }
        var frame = union.insetBy(dx: -dx, dy: -5)
        frame.size.height += 10
        return frame
    }

    /// `iconHeight × 0.15625`, rounded with halves toward zero.
    static func cornerRadius(iconHeight: CGFloat) -> CGFloat {
        let radius = iconHeight * 0.15625
        return radius > 0 ? (radius - 0.5).rounded(.up) : (radius + 0.5).rounded(.down)
    }
}

/// The pressed look: the icon's colour channels multiplied by generic gray 0.4, as a layer filter.
enum ClassicalPressedIcon {
    static let gray: CGFloat = 0.4

    /// A new multiply filter for one layer's `filters`; nil when Core Animation's filter class is unavailable.
    static func filter() -> NSObject? {
        ClassicalLayerFilters.multiplyColor(gray: gray)
    }
}
