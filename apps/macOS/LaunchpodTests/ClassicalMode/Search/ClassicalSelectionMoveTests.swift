import XCTest
@testable import Launchpod

final class ClassicalSelectionMoveTests: XCTestCase {
    /// Arrow navigation on a 7-column page of 10 items.
    func testArrowsMoveWithinThePageWithoutWrapping() {
        func move(_ direction: ClassicalNavigation, _ selected: Int?, rightToLeft: Bool = false) -> Int? {
            ClassicalSelectionMove.target(direction, selected: selected, count: 10, columns: 7, rightToLeft: rightToLeft)
        }
        XCTAssertEqual(move(.right, nil), 0)
        XCTAssertEqual(move(.down, nil), 0)
        XCTAssertEqual(move(.left, nil), 9)
        XCTAssertEqual(move(.up, nil), 9)
        XCTAssertEqual(move(.right, 3), 4)
        XCTAssertNil(move(.right, 9), "The last item does not wrap to the next page")
        XCTAssertNil(move(.left, 0))
        XCTAssertEqual(move(.down, 2), 9)
        XCTAssertNil(move(.down, 3), "No item below on the partial last row")
        XCTAssertEqual(move(.up, 8), 1)
        XCTAssertNil(move(.up, 6))
        XCTAssertEqual(move(.left, 3, rightToLeft: true), 4, "Right-to-left mirrors left and right")
        XCTAssertNil(ClassicalSelectionMove.target(.down, selected: nil, count: 0, columns: 7, rightToLeft: false))
    }
}
