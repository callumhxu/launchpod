import CoreGraphics

/// Cell geometry of one Classical page.
///
/// Cell sizes are truncated to whole points; any remainder stays at the page's right and bottom.
/// Rows count from the top; coordinates are page-local Core Animation coordinates (y up).
struct ClassicalGridLayout: Equatable, Sendable {
    let pageSize: CGSize
    let rows: Int
    let columns: Int
    let cellSize: CGSize

    init(pageSize: CGSize, rows: Int, columns: Int) {
        self.pageSize = pageSize
        self.rows = max(rows, 1)
        self.columns = max(columns, 1)
        cellSize = CGSize(width: Self.truncatedQuotient(pageSize.width, self.columns),
                          height: Self.truncatedQuotient(pageSize.height, self.rows))
    }

    var capacity: Int { rows * columns }

    /// Row-major position of a page slot, left to right (mirrored for right-to-left layouts).
    func cellFrame(at index: Int, rightToLeft: Bool = false) -> CGRect {
        let column = index % columns
        let row = index / columns
        let centerX = cellSize.width / 2 + CGFloat(column) * cellSize.width
        let x = rightToLeft ? pageSize.width - centerX : centerX
        let y = CGFloat(Int(pageSize.height)) - cellSize.height / 2 - CGFloat(row) * cellSize.height
        return CGRect(x: x - cellSize.width / 2, y: y - cellSize.height / 2,
                      width: cellSize.width, height: cellSize.height)
    }

    /// The slot for a dragged item centred at `center` (page coordinates): the row under the centre,
    /// counted from the top, and the column under it in whole cell widths, counted from the right
    /// in right-to-left layouts. With hysteresis the current slot keeps the item until the centre
    /// leaves it by more than half a cell. The result never passes the last of `count` items.
    func itemIndex(at center: CGPoint, current: Int, usingHysteresis: Bool, count: Int, rightToLeft: Bool = false) -> Int {
        guard cellSize.width > 0, cellSize.height > 0, count > 0 else { return 0 }
        let fromTop = pageSize.height - center.y
        let fromLeft = (center.x / cellSize.width).rounded(.down)
        let column = Int(max(rightToLeft ? CGFloat(columns) - fromLeft - 1 : fromLeft, 0))
        let row = Int(max((fromTop / cellSize.height).rounded(.down), 0))
        var index = row * columns + column
        if usingHysteresis, index != current, current >= 0 {
            let currentColumn = rightToLeft ? columns - current % columns - 1 : current % columns
            let slot = CGRect(x: CGFloat(currentColumn) * cellSize.width, y: CGFloat(current / columns) * cellSize.height,
                              width: cellSize.width, height: cellSize.height)
                .insetBy(dx: -(cellSize.width / 2).rounded(.up), dy: -(cellSize.height / 2).rounded(.up))
            if slot.contains(CGPoint(x: center.x, y: fromTop)) { index = current }
        }
        return min(index, count - 1)
    }

    private static func truncatedQuotient(_ length: CGFloat, _ count: Int) -> CGFloat {
        guard length.isFinite, length > 0 else { return 0 }
        return CGFloat(Int(length) / count)
    }
}
