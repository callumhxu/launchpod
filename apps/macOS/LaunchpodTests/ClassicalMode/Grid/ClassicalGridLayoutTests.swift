import CoreGraphics
import XCTest
@testable import Launchpod

/// The slot under a dragged icon.
final class ClassicalGridLayoutTests: XCTestCase {
    func testCellsFillRowMajorFromTheTopLeftWithRemaindersAtRightAndBottom() {
        let grid = ClassicalGridLayout(pageSize: CGSize(width: 1290, height: 788), rows: 5, columns: 7)
        // Top row center y = 788 − 78.5.
        XCTAssertEqual(grid.cellFrame(at: 0), CGRect(x: 0, y: 631, width: 184, height: 157))
        XCTAssertEqual(grid.cellFrame(at: 6), CGRect(x: 1104, y: 631, width: 184, height: 157))
        XCTAssertEqual(grid.cellFrame(at: 7), CGRect(x: 0, y: 474, width: 184, height: 157))
        XCTAssertEqual(grid.cellFrame(at: 34), CGRect(x: 1104, y: 3, width: 184, height: 157))
        XCTAssertEqual(grid.cellFrame(at: 0, rightToLeft: true), CGRect(x: 1106, y: 631, width: 184, height: 157))
    }

    func testSlotUnderTheCentreWithHysteresisAndClamping() {
        let grid = ClassicalGridLayout(pageSize: CGSize(width: 300, height: 200), rows: 2, columns: 3)
        let center = { (index: Int) in CGPoint(x: grid.cellFrame(at: index).midX, y: grid.cellFrame(at: index).midY) }
        XCTAssertEqual(grid.itemIndex(at: center(4), current: 0, usingHysteresis: false, count: 6), 4)
        XCTAssertEqual(grid.itemIndex(at: center(5), current: 0, usingHysteresis: false, count: 3), 2,
                       "Space after the last item means the last slot")
        let justPast = CGPoint(x: 100 + 40, y: 150)
        XCTAssertEqual(grid.itemIndex(at: justPast, current: 0, usingHysteresis: true, count: 6), 0,
                       "The current slot holds until the centre is half a cell beyond it")
        XCTAssertEqual(grid.itemIndex(at: CGPoint(x: 160, y: 150), current: 0, usingHysteresis: true, count: 6), 1)
        XCTAssertEqual(grid.itemIndex(at: center(0), current: 5, usingHysteresis: false, count: 6, rightToLeft: true), 2,
                       "Right-to-left mirrors the columns")
    }

    /// Right to left, the column is `columns − floor(midX / cellWidth) − 1` with the whole-point cell
    /// width, floored at zero. It differs from mirroring about the page width
    /// wherever the truncated cells leave a remainder: here the page is 301 pt wide with 100 pt cells.
    func testRightToLeftColumnCountsWholeCellsFromTheLeftEdge() {
        let grid = ClassicalGridLayout(pageSize: CGSize(width: 301, height: 200), rows: 2, columns: 3)
        XCTAssertEqual(grid.cellSize.width, 100)
        let topRow: CGFloat = 150
        func index(_ x: CGFloat) -> Int {
            grid.itemIndex(at: CGPoint(x: x, y: topRow), current: 0, usingHysteresis: false, count: 6, rightToLeft: true)
        }
        XCTAssertEqual(index(0.5), 2, "3 − floor(0.5 / 100) − 1")
        XCTAssertEqual(index(100.5), 1, "3 − floor(100.5 / 100) − 1")
        XCTAssertEqual(index(200.5), 0, "3 − floor(200.5 / 100) − 1")
        XCTAssertEqual(index(300.5), 0, "3 − 3 − 1 is negative and floors at the first column")
        XCTAssertEqual(grid.itemIndex(at: CGPoint(x: 100.5, y: 50), current: 0, usingHysteresis: false, count: 6,
                                      rightToLeft: true), 4, "The second row adds one row of columns")
    }
}
