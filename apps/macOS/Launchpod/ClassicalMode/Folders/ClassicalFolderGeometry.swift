import CoreGraphics

/// Geometry of a Classical folder: the closed cell's thumbnail grid and the open panel. Core
/// Animation coordinates (origin bottom-left, y up).
enum ClassicalFolderGeometry {
    /// The closed folder cell: a backdrop inset from the icon frame and a 3 × 3 thumbnail grid
    /// inside it. Frames are cell-local, like `ClassicalItemLayout.iconFrame`.
    struct Cell: Equatable, Sendable {
        let iconFrame: CGRect
        let backdropFrame: CGRect
        let cornerRadius: CGFloat
        let miniGridFrame: CGRect
        let miniCellSize: CGSize

        init(iconFrame: CGRect) {
            self.iconFrame = iconFrame
            let inset = ClassicalFolderParameters.itemBackdropInset(iconHeight: iconFrame.height)
            backdropFrame = iconFrame.insetBy(dx: inset, dy: inset)
            cornerRadius = (iconFrame.height * ClassicalFolderParameters.itemCornerRadiusFraction).rounded()
            let gridInset = CGFloat(Int(ClassicalFolderParameters.miniGridInsetFraction * backdropFrame.width))
            miniGridFrame = backdropFrame.insetBy(dx: gridInset, dy: gridInset)
            miniCellSize = CGSize(width: CGFloat(Int(miniGridFrame.width) / ClassicalFolderParameters.miniGridColumns),
                                  height: CGFloat(Int(miniGridFrame.height) / ClassicalFolderParameters.miniGridRows))
        }

        /// Thumbnail `index` in the thumbnail grid's coordinates, row-major from the top-left
        /// (top-right right-to-left). Every index has a frame; those past the ninth fall below the
        /// grid, which clips them.
        func thumbnailFrame(at index: Int, rightToLeft: Bool = false) -> CGRect {
            let columns = ClassicalFolderParameters.miniGridColumns
            let spacing = ClassicalFolderParameters.miniGridSpacing
            let half = CGFloat(Int(spacing / 2))
            let column = CGFloat(index % columns), row = CGFloat(index / columns)
            // Thumbnails are placed in a content layer offset by (−half, +half) inside the grid.
            let contentX = half + miniCellSize.width / 2 + column * miniCellSize.width
            let x = (rightToLeft ? miniGridFrame.width - contentX : contentX) - half
            let y = CGFloat(Int(miniGridFrame.height)) - miniCellSize.height / 2 - half - row * miniCellSize.height + half
            let size = CGSize(width: miniCellSize.width - spacing, height: miniCellSize.height - spacing)
            return CGRect(x: x - size.width / 2, y: y - size.height / 2, width: size.width, height: size.height)
        }

        /// The thumbnail icon side requested for an icon of `iconSide`, limited to 1…32 pt.
        static func miniIconSide(iconSide: CGFloat) -> CGFloat {
            let height = iconSide - 2 * CGFloat(Int(ClassicalFolderParameters.miniGridInsetFraction * iconSide))
            let side = CGFloat(Int(height)) / CGFloat(ClassicalFolderParameters.miniGridRows)
                - ClassicalFolderParameters.miniGridSpacing
            let range = ClassicalFolderParameters.miniIconSideRange
            return min(max(side, range.lowerBound), range.upperBound)
        }
    }

    /// The open panel. `frame` is in the layer that holds the root pager; every other frame is in
    /// the panel's own coordinates, except `firstPageFrame`, which is in the page strip.
    struct Panel: Equatable, Sendable {
        let rows: Int
        let columns: Int
        let rowHeight: CGFloat
        let margins: ClassicalSpringboardGeometry.Margins
        let frame: CGRect

        /// A panel for a folder of `itemCount` applications over the root pages of `geometry`. Opened
        /// while an item is `dragging`, a folder whose applications fill whole rows gets one more
        /// row for it, while that stays below the root pages' rows less one.
        init(springboard geometry: ClassicalSpringboardGeometry, itemCount: Int, dragging: Bool = false) {
            let parameters = ClassicalFolderParameters.self
            columns = geometry.columns
            var rows = Self.rows(itemCount: itemCount, columns: geometry.columns, mainRows: geometry.rows)
            if dragging, itemCount % max(geometry.columns, 1) == 0, rows < geometry.rows - 1 { rows += 1 }
            self.rows = rows
            margins = .init(left: max(geometry.margins.left, parameters.panelMinimumSideMargin),
                            right: max(geometry.margins.right, parameters.panelMinimumSideMargin),
                            top: geometry.margins.top, bottom: geometry.margins.bottom)
            let pager = geometry.contentFrame
            let notch = rows >= parameters.notchRowThreshold ? geometry.notchHeight : 0
            rowHeight = geometry.grid.cellSize.height
            let height = CGFloat(rows) * rowHeight + margins.bottom + margins.top + parameters.panelTitleBand
            let y = pager.minY + CGFloat(Int((pager.height - height - notch) / 2))
            let band = parameters.panelTitleBand
            frame = y > band
                ? CGRect(x: pager.minX, y: y - band, width: pager.width, height: height + band)
                : CGRect(x: pager.minX, y: y, width: pager.width, height: height)
        }

        /// `ceil(itemCount / columns)`, at least one row and at most the root pages' rows.
        static func rows(itemCount: Int, columns: Int, mainRows: Int) -> Int {
            let columns = max(columns, 1)
            return max(1, min((max(itemCount, 0) + columns - 1) / columns, mainRows))
        }

        var bounds: CGRect { CGRect(origin: .zero, size: frame.size) }

        /// The translucent backdrop: the folder grid's width plus the outset on each side, from the
        /// panel's bottom to the title band.
        var backdropFrame: CGRect {
            let outset = ClassicalFolderParameters.panelBackdropOutset
            return CGRect(x: margins.left - outset, y: 0,
                          width: frame.width - margins.left - margins.right + 2 * outset,
                          height: frame.height - ClassicalFolderParameters.panelTitleBand - margins.top)
        }

        var stripFrame: CGRect {
            CGRect(x: 0, y: stripBottom, width: frame.width, height: frame.height - ClassicalFolderParameters.panelTitleBand)
        }

        var firstPageFrame: CGRect {
            let parameters = ClassicalFolderParameters.self
            return CGRect(x: margins.left, y: 0, width: frame.width - margins.left - margins.right,
                          height: frame.height - parameters.panelTitleBand - margins.top - parameters.panelPageTopGap - stripBottom)
        }

        var dotsFrame: CGRect {
            let height = ClassicalFolderParameters.pageDotsHeight
            return CGRect(x: 0, y: max(0, (margins.bottom / 2 - height / 2).rounded(.down)), width: frame.width, height: height)
        }

        var grid: ClassicalGridLayout {
            ClassicalGridLayout(pageSize: firstPageFrame.size, rows: rows, columns: columns)
        }

        /// The folder pager fills the panel; the panel's mask clips it.
        var pagerLayout: ClassicalPagerLayout {
            ClassicalPagerLayout(frame: bounds, stripFrame: stripFrame, dotsFrame: dotsFrame, firstPageFrame: firstPageFrame,
                                 pageWidth: frame.width, grid: grid, clipsToBounds: false)
        }

        /// The title label of `labelSize`, centred over the grid in the band above the backdrop.
        func titleFrame(labelSize: CGSize) -> CGRect {
            let backdrop = backdropFrame.height
            let x = margins.left + (frame.width - margins.left - margins.right) / 2 - labelSize.width / 2
            let y = backdrop + (frame.height - backdrop - labelSize.height) / 2
            return CGRect(x: CGFloat(Int(x)), y: CGFloat(Int(y)), width: labelSize.width, height: labelSize.height)
        }

        /// Where the title is edited: the title's frame widened on both sides.
        func titleEditFrame(labelSize: CGSize) -> CGRect {
            titleFrame(labelSize: labelSize).insetBy(dx: -ClassicalFolderParameters.titleEditOutset, dy: 0)
        }

        private var stripBottom: CGFloat { margins.bottom - ClassicalFolderParameters.panelStripBottomInset }
    }
}
