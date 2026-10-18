import CoreGraphics
import XCTest
@testable import Launchpod

/// The closed folder cell's backdrop and thumbnail grid, and the open panel's frames.
final class ClassicalFolderGeometryTests: XCTestCase {
    // MARK: Closed folder cell

    /// A 96 pt icon: backdrop 76 × 76 with corner radius 15, thumbnail grid 62 × 62, cells 20,
    /// thumbnails 16 × 16 centred 1 pt left of and 1 pt above their cells' centres.
    func testNinetySixPointIconExample() {
        let cell = ClassicalFolderGeometry.Cell(iconFrame: CGRect(x: 10, y: 20, width: 96, height: 96))
        XCTAssertEqual(cell.backdropFrame, CGRect(x: 20, y: 30, width: 76, height: 76))
        XCTAssertEqual(cell.cornerRadius, 15)
        XCTAssertEqual(cell.miniGridFrame, CGRect(x: 27, y: 37, width: 62, height: 62))
        XCTAssertEqual(cell.miniCellSize, CGSize(width: 20, height: 20))

        let centres = (0..<9).map { index -> CGPoint in
            let frame = cell.thumbnailFrame(at: index)
            XCTAssertEqual(frame.size, CGSize(width: 16, height: 16), "thumbnail \(index)")
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        // Grid coordinates, origin bottom-left: the first row is the top row.
        XCTAssertEqual(centres, [CGPoint(x: 10, y: 52), CGPoint(x: 30, y: 52), CGPoint(x: 50, y: 52),
                                 CGPoint(x: 10, y: 32), CGPoint(x: 30, y: 32), CGPoint(x: 50, y: 32),
                                 CGPoint(x: 10, y: 12), CGPoint(x: 30, y: 12), CGPoint(x: 50, y: 12)])
    }

    /// Only the first nine thumbnails fit; later ones are laid out outside the grid, which clips them.
    func testThumbnailsPastTheNinthFallOutsideTheGrid() {
        let cell = ClassicalFolderGeometry.Cell(iconFrame: CGRect(x: 0, y: 0, width: 96, height: 96))
        let bounds = CGRect(origin: .zero, size: cell.miniGridFrame.size)
        for index in 0..<9 { XCTAssertTrue(bounds.intersects(cell.thumbnailFrame(at: index)), "thumbnail \(index)") }
        for index in 9..<12 { XCTAssertFalse(bounds.intersects(cell.thumbnailFrame(at: index)), "thumbnail \(index)") }
    }

    func testRightToLeftThumbnailsFillEachRowFromTheRight() {
        let cell = ClassicalFolderGeometry.Cell(iconFrame: CGRect(x: 0, y: 0, width: 96, height: 96))
        for row in 0..<3 {
            let xs = (0..<3).map { cell.thumbnailFrame(at: row * 3 + $0, rightToLeft: true).midX }
            XCTAssertGreaterThan(xs[0], xs[1])
            XCTAssertGreaterThan(xs[1], xs[2])
            XCTAssertEqual(cell.thumbnailFrame(at: row * 3, rightToLeft: true).midY, cell.thumbnailFrame(at: row * 3).midY)
            XCTAssertEqual(cell.thumbnailFrame(at: row * 3, rightToLeft: true).size, CGSize(width: 16, height: 16))
        }
    }

    /// The backdrop inset tiers: height ≤ 60 → 5, ≤ 80 → 7, < 128 → 10, otherwise 12.
    func testBackdropInsetTiersByIconHeight() {
        let expected: [(CGFloat, CGFloat)] = [(40, 5), (60, 5), (61, 7), (80, 7), (81, 10), (127, 10), (128, 12), (256, 12)]
        for (height, inset) in expected {
            let cell = ClassicalFolderGeometry.Cell(iconFrame: CGRect(x: 0, y: 0, width: height, height: height))
            XCTAssertEqual(cell.backdropFrame, CGRect(x: inset, y: inset, width: height - 2 * inset, height: height - 2 * inset),
                           "icon \(height)")
        }
    }

    /// The corner radius is the icon height × 0.15625, rounded half away from zero.
    func testCornerRadiusFollowsTheIconHeight() {
        let expected: [(CGFloat, CGFloat)] = [(96, 15), (80, 13), (128, 20), (64, 10), (100, 16)]
        for (height, radius) in expected {
            XCTAssertEqual(ClassicalFolderGeometry.Cell(iconFrame: CGRect(x: 0, y: 0, width: height, height: height)).cornerRadius,
                           radius, "icon \(height)")
        }
    }

    /// The grid inset and cell sizes truncate: a 128 pt icon has a 104 pt backdrop, inset 10, an
    /// 84 pt grid and 28 pt cells.
    func testGridInsetAndCellsTruncate() {
        let cell = ClassicalFolderGeometry.Cell(iconFrame: CGRect(x: 0, y: 0, width: 128, height: 128))
        XCTAssertEqual(cell.miniGridFrame, CGRect(x: 22, y: 22, width: 84, height: 84))
        XCTAssertEqual(cell.miniCellSize, CGSize(width: 28, height: 28))
        let odd = ClassicalFolderGeometry.Cell(iconFrame: CGRect(x: 0, y: 0, width: 90, height: 90))
        // Backdrop 70, inset trunc(7.0) = 7, grid 56, cells trunc(56 / 3) = 18.
        XCTAssertEqual(odd.miniGridFrame.size, CGSize(width: 56, height: 56))
        XCTAssertEqual(odd.miniCellSize, CGSize(width: 18, height: 18))
    }

    /// The requested thumbnail side: `(trunc(side − 2·trunc(0.1·side)) / 3) − 4`, limited to 1…32.
    func testRequestedThumbnailSide() {
        XCTAssertEqual(ClassicalFolderGeometry.Cell.miniIconSide(iconSide: 96), 22)
        XCTAssertEqual(ClassicalFolderGeometry.Cell.miniIconSide(iconSide: 256), 32)
        XCTAssertEqual(ClassicalFolderGeometry.Cell.miniIconSide(iconSide: 20), 16.0 / 3 - 4, accuracy: 1e-9)
        XCTAssertEqual(ClassicalFolderGeometry.Cell.miniIconSide(iconSide: 10), 1)
    }

    // MARK: Open panel

    /// Rows are `ceil(count / columns)`, at least 1 and at most the root pages' rows.
    func testPanelRowsGrowWithTheFolderUpToTheRootRows() {
        let rows = { ClassicalFolderGeometry.Panel.rows(itemCount: $0, columns: 7, mainRows: 5) }
        XCTAssertEqual([0, 1, 7, 8, 14, 15, 35, 36, 100].map(rows), [1, 1, 1, 2, 2, 3, 5, 5, 5])
        XCTAssertEqual(ClassicalFolderGeometry.Panel.rows(itemCount: 9, columns: 3, mainRows: 2), 2)
    }

    /// Folder capacity follows the rows the panel can show on this root grid. A sixth row cannot
    /// extend beyond a five-row panel, so item 36 must go on another page.
    func testOverflowUsesThePanelGridCapacityAndKeepsItsBorderOnScreen() {
        let screen = CGSize(width: 1470, height: 956)
        let fiveRows = ClassicalSpringboardGeometry(screenSize: screen, dock: .bottom(extent: 59), rows: 5, columns: 7)
        let overflowing = ClassicalFolderGeometry.Panel(springboard: fiveRows, itemCount: 36)
        XCTAssertEqual(overflowing.rows, 5)
        XCTAssertEqual(overflowing.columns, 7)
        XCTAssertEqual(overflowing.grid.capacity, 35)
        XCTAssertGreaterThanOrEqual(overflowing.frame.minY, 0)
        XCTAssertLessThanOrEqual(overflowing.frame.maxY, screen.height)
        XCTAssertLessThanOrEqual(overflowing.backdropFrame.maxY, overflowing.bounds.maxY)

        let fourRows = ClassicalSpringboardGeometry(screenSize: screen, dock: .bottom(extent: 59), rows: 4, columns: 7)
        let smaller = ClassicalFolderGeometry.Panel(springboard: fourRows, itemCount: 29)
        XCTAssertEqual(smaller.rows, 4)
        XCTAssertEqual(smaller.grid.capacity, 28, "The capacity follows the selected root row count")
    }

    func testFiveBySevenFolderWithLeftDockUsesRootMarginsAndRowHeight() {
        let screen = CGSize(width: 1470, height: 956)
        let geometry = ClassicalSpringboardGeometry(screenSize: screen, dock: .left(extent: 80), rows: 5, columns: 7)
        let full = ClassicalFolderGeometry.Panel(springboard: geometry, itemCount: 35)
        let overflow = ClassicalFolderGeometry.Panel(springboard: geometry, itemCount: 36)

        XCTAssertEqual(full.rows, 5)
        XCTAssertEqual(full.columns, 7)
        XCTAssertEqual(full.grid.capacity, 35)
        XCTAssertEqual(full.rowHeight, geometry.grid.cellSize.height)
        XCTAssertEqual(full.margins.top, geometry.margins.top)
        XCTAssertEqual(full.margins.bottom, geometry.margins.bottom)
        let panelHeight = CGFloat(full.rows) * full.rowHeight + full.margins.top + full.margins.bottom
            + ClassicalFolderParameters.panelTitleBand
        let centeredY = geometry.contentFrame.minY
            + CGFloat(Int((geometry.contentFrame.height - panelHeight) / 2))
        let expectedY = centeredY > ClassicalFolderParameters.panelTitleBand
            ? centeredY - ClassicalFolderParameters.panelTitleBand : centeredY
        XCTAssertEqual(full.frame.minY, expectedY)
        XCTAssertEqual(overflow.grid.capacity, 35, "Item 36 belongs on another folder page")
        XCTAssertEqual(overflow.frame.minY, expectedY)
        XCTAssertLessThanOrEqual(overflow.frame.maxY, screen.height)
    }

    private let screen = CGSize(width: 1470, height: 956)

    /// The panel spans the root pager's width; its height is rows × the root row height plus the
    /// root top and bottom margins and a 30 pt title band, centred vertically in the pager with a
    /// further 30 pt below when it fits.
    func testPanelFrameCentresInThePager() {
        let geometry = ClassicalSpringboardGeometry(screenSize: screen, dock: .bottom(extent: 59))
        for (count, rows) in [(3, 1), (9, 2), (40, 5)] {
            let panel = ClassicalFolderGeometry.Panel(springboard: geometry, itemCount: count)
            XCTAssertEqual(panel.rows, rows)
            XCTAssertEqual(panel.columns, geometry.columns)
            let pager = geometry.contentFrame
            let height = CGFloat(rows) * geometry.grid.cellSize.height + geometry.margins.top + geometry.margins.bottom + 30
            let y = pager.minY + ((pager.height - height) / 2).rounded(.towardZero)
            XCTAssertGreaterThan(y, 30)
            XCTAssertEqual(panel.frame, CGRect(x: pager.minX, y: y - 30, width: pager.width, height: height + 30), "\(count) apps")
        }
    }

    /// While an item is dragged, a folder whose applications fill whole rows gets one more row for
    /// it, as long as that is fewer rows than the root pages' less one.
    func testPanelAddsARowForTheDraggedItemWhenItsRowsAreFull() {
        let geometry = ClassicalSpringboardGeometry(screenSize: screen, dock: .bottom(extent: 59))
        XCTAssertEqual(geometry.columns, 7)
        XCTAssertEqual(geometry.rows, 5)
        let expected = [(7, 2), (8, 2), (13, 2), (14, 3), (21, 4), (28, 4), (35, 5)]
        for (count, rows) in expected {
            XCTAssertEqual(ClassicalFolderGeometry.Panel(springboard: geometry, itemCount: count, dragging: true).rows,
                           rows, "\(count) apps while dragging")
        }
        for (count, rows) in [(7, 1), (14, 2), (21, 3)] {
            XCTAssertEqual(ClassicalFolderGeometry.Panel(springboard: geometry, itemCount: count).rows, rows,
                           "\(count) apps without a drag")
        }
    }

    /// A panel of five or more rows also leaves the display's camera housing out of its centring.
    func testFiveRowPanelLeavesTheNotchOut() {
        let notch: CGFloat = 32
        let geometry = ClassicalSpringboardGeometry(screenSize: screen, dock: .bottom(extent: 59), notchHeight: notch)
        let pager = geometry.contentFrame
        func expectedY(rows: Int, notch: CGFloat) -> CGFloat {
            let height = CGFloat(rows) * geometry.grid.cellSize.height + geometry.margins.top + geometry.margins.bottom + 30
            return pager.minY + ((pager.height - height - notch) / 2).rounded(.towardZero) - 30
        }
        XCTAssertEqual(ClassicalFolderGeometry.Panel(springboard: geometry, itemCount: 35).frame.minY, expectedY(rows: 5, notch: notch))
        XCTAssertEqual(ClassicalFolderGeometry.Panel(springboard: geometry, itemCount: 28).frame.minY, expectedY(rows: 4, notch: 0),
                       "Fewer than five rows ignore the notch")
    }

    /// A panel too tall to keep the 30 pt below it takes its centred position without it.
    func testPanelWithoutRoomBelowKeepsItsCentredHeight() {
        let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 500), dock: .hidden, rows: 5)
        let panel = ClassicalFolderGeometry.Panel(springboard: geometry, itemCount: 35)
        let pager = geometry.contentFrame
        let height = 5 * geometry.grid.cellSize.height + geometry.margins.top + geometry.margins.bottom + 30
        let y = pager.minY + ((pager.height - height) / 2).rounded(.towardZero)
        XCTAssertLessThanOrEqual(y, 30, "The fixture must leave no room below")
        XCTAssertEqual(panel.frame, CGRect(x: pager.minX, y: y, width: pager.width, height: height))
    }

    /// Frames inside the panel, from its margins: side margins are at least 90 pt.
    func testPanelInnerFrames() {
        let geometry = ClassicalSpringboardGeometry(screenSize: screen, dock: .bottom(extent: 59))
        let panel = ClassicalFolderGeometry.Panel(springboard: geometry, itemCount: 9)
        let left = max(geometry.margins.left, 90), right = max(geometry.margins.right, 90)
        let top = geometry.margins.top, bottom = geometry.margins.bottom
        XCTAssertEqual(panel.margins.left, left)
        XCTAssertEqual(panel.margins.right, right)
        let w = panel.frame.width, h = panel.frame.height
        XCTAssertEqual(panel.backdropFrame, CGRect(x: left - 20, y: 0, width: w - left - right + 40, height: h - 30 - top))
        let stripBottom = bottom - 10
        XCTAssertEqual(panel.stripFrame, CGRect(x: 0, y: stripBottom, width: w, height: h - 30))
        XCTAssertEqual(panel.firstPageFrame,
                       CGRect(x: left, y: 0, width: w - left - right, height: h - 30 - top - 40 - stripBottom))
        XCTAssertEqual(panel.firstPageFrame.height, CGFloat(panel.rows) * geometry.grid.cellSize.height, accuracy: 0.001,
                       "The folder page holds its rows at the root row height")
        XCTAssertEqual(panel.dotsFrame, CGRect(x: 0, y: max(0, (bottom / 2 - 7.5).rounded(.down)), width: w, height: 15))

        let label = CGSize(width: 101, height: 34)
        let backdrop = panel.backdropFrame.height
        let title = CGRect(x: (left + (w - left - right) / 2 - label.width / 2).rounded(.towardZero),
                           y: (backdrop + (h - backdrop - label.height) / 2).rounded(.towardZero),
                           width: label.width, height: label.height)
        XCTAssertEqual(panel.titleFrame(labelSize: label), title)
        XCTAssertEqual(panel.titleEditFrame(labelSize: label), title.insetBy(dx: -200, dy: 0))
    }
}
