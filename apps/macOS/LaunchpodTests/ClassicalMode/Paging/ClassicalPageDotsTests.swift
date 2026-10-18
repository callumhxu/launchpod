import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalPageDotsTests: XCTestCase {
    func testIndicatorsAreFifteenPointsAndTwentyApartCentredAndMirroredRightToLeft() {
        let layout = ClassicalPageDotsLayout(pageCount: 3, width: 1470, rightToLeft: false)
        XCTAssertEqual(layout.indicatorFrame(for: 0), CGRect(x: 707, y: 0, width: 15, height: 15))
        XCTAssertEqual(layout.indicatorFrame(for: 2).minX - layout.indicatorFrame(for: 0).minX, 40)
        XCTAssertEqual(layout.page(at: CGPoint(x: 730, y: 7)), 1)
        XCTAssertNil(layout.page(at: CGPoint(x: 724, y: 7)), "The 5 pt gap belongs to no page")
        let mirrored = ClassicalPageDotsLayout(pageCount: 3, width: 1470, rightToLeft: true)
        XCTAssertEqual(mirrored.indicatorFrame(for: 0), layout.indicatorFrame(for: 2))
    }
}
