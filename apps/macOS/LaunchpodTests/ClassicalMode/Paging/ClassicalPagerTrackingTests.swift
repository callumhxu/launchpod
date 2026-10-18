import XCTest
@testable import Launchpod

/// Page-selection rules of the Classical pager.
@MainActor
final class ClassicalPagerTrackingTests: XCTestCase {
    private let width: CGFloat = 1470

    func testDragFollowsThePointerOnlyAfterThreePointsOfHorizontalTravel() {
        var tracking = ClassicalPagerTracking(pageCount: 3, pageWidth: width)
        tracking.mouseDown(at: CGPoint(x: 700, y: 400), time: 0)
        XCTAssertFalse(tracking.mouseDragged(to: CGPoint(x: 698, y: 300)), "Vertical travel never drags the strip")
        XCTAssertEqual(tracking.scrollValue, 0)
        XCTAssertTrue(tracking.mouseDragged(to: CGPoint(x: 697, y: 400)))
        XCTAssertEqual(tracking.scrollValue, 3, "Moving left scrolls toward the next page by the same distance")
        XCTAssertTrue(tracking.mouseDragged(to: CGPoint(x: 400, y: 400)))
        XCTAssertEqual(tracking.scrollValue, 300)
    }

    func testSlowDragReturnsToTheCurrentPageWhateverTheDistance() {
        var tracking = ClassicalPagerTracking(pageCount: 3, pageWidth: width)
        tracking.mouseDown(at: CGPoint(x: 1400, y: 400), time: 0)
        _ = tracking.mouseDragged(to: CGPoint(x: 100, y: 400))
        // 1300 pt over 7 s is about 186 pt/s, below the 200 pt/s flick speed.
        XCTAssertEqual(tracking.mouseUp(at: CGPoint(x: 100, y: 400), time: 7), 0)
    }

    func testFastFlickTurnsOnePageInTheDragDirection() {
        var tracking = ClassicalPagerTracking(pageCount: 3, pageWidth: width, currentPage: 1)
        tracking.mouseDown(at: CGPoint(x: 700, y: 400), time: 10)
        _ = tracking.mouseDragged(to: CGPoint(x: 660, y: 400))
        XCTAssertEqual(tracking.mouseUp(at: CGPoint(x: 660, y: 400), time: 10.1), 2, "40 pt in 0.1 s is 400 pt/s")

        tracking.select(1)
        tracking.mouseDown(at: CGPoint(x: 700, y: 400), time: 20)
        _ = tracking.mouseDragged(to: CGPoint(x: 740, y: 400))
        XCTAssertEqual(tracking.mouseUp(at: CGPoint(x: 740, y: 400), time: 20.1), 0)
    }

    func testFlickSpeedUsesTheTwoDimensionalDistanceAndIsStrict() {
        var tracking = ClassicalPagerTracking(pageCount: 3, pageWidth: width)
        tracking.mouseDown(at: CGPoint(x: 700, y: 400), time: 0)
        _ = tracking.mouseDragged(to: CGPoint(x: 685, y: 380))
        // 15 pt across and 20 pt down: 25 pt in 0.125 s is exactly 200 pt/s, which is not above the threshold.
        XCTAssertEqual(tracking.mouseUp(at: CGPoint(x: 685, y: 380), time: 0.125), 0)
        tracking.mouseDown(at: CGPoint(x: 700, y: 400), time: 1)
        _ = tracking.mouseDragged(to: CGPoint(x: 685, y: 380))
        XCTAssertEqual(tracking.mouseUp(at: CGPoint(x: 685, y: 380), time: 1.124), 1)
    }

    func testPressWithoutDragSettlesNothing() {
        var tracking = ClassicalPagerTracking(pageCount: 3, pageWidth: width)
        tracking.mouseDown(at: CGPoint(x: 700, y: 400), time: 0)
        _ = tracking.mouseDragged(to: CGPoint(x: 702, y: 400))
        XCTAssertNil(tracking.mouseUp(at: CGPoint(x: 702, y: 400), time: 0.01))
    }

    func testFlickPastEitherEndStaysOnTheEdgePage() {
        var tracking = ClassicalPagerTracking(pageCount: 2, pageWidth: width, currentPage: 1)
        tracking.mouseDown(at: CGPoint(x: 700, y: 400), time: 0)
        _ = tracking.mouseDragged(to: CGPoint(x: 600, y: 400))
        XCTAssertEqual(tracking.mouseUp(at: CGPoint(x: 600, y: 400), time: 0.1), 1)

        tracking.select(0)
        tracking.mouseDown(at: CGPoint(x: 700, y: 400), time: 1)
        _ = tracking.mouseDragged(to: CGPoint(x: 800, y: 400))
        XCTAssertEqual(tracking.scrollValue, -25, "Beyond the first page a quarter of the travel applies")
        XCTAssertEqual(tracking.mouseUp(at: CGPoint(x: 800, y: 400), time: 1.1), 0)
    }

    func testOverscrollKeepsAQuarterOfTheTravelBeyondTheLastPage() {
        var tracking = ClassicalPagerTracking(pageCount: 2, pageWidth: width, currentPage: 1)
        tracking.mouseDown(at: CGPoint(x: 700, y: 400), time: 0)
        _ = tracking.mouseDragged(to: CGPoint(x: 300, y: 400))
        XCTAssertEqual(tracking.scrollValue, width + 100)
        XCTAssertEqual(tracking.damped(-40), -10)
        XCTAssertEqual(tracking.damped(width / 2), width / 2)
    }

    func testRightToLeftMirrorsPagesAndDirections() {
        var tracking = ClassicalPagerTracking(pageCount: 3, pageWidth: width, rightToLeft: true)
        XCTAssertEqual(tracking.scrollValue, 2 * width, "The first page is the rightmost")
        XCTAssertEqual(tracking.restingScroll(for: 2), 0)
        tracking.mouseDown(at: CGPoint(x: 700, y: 400), time: 0)
        _ = tracking.mouseDragged(to: CGPoint(x: 760, y: 400))
        XCTAssertEqual(tracking.mouseUp(at: CGPoint(x: 760, y: 400), time: 0.1), 1, "Dragging right advances")
    }

    func testTrackpadGestureSettlesByTheStripsSpeed() {
        var tracking = ClassicalPagerTracking(pageCount: 3, pageWidth: width)
        tracking.beginGesture(at: .zero, time: 0)
        tracking.scroll(by: 30, at: .zero, time: 0.05)
        tracking.scroll(by: 30, at: .zero, time: 0.1)
        XCTAssertEqual(tracking.scrollValue, 60)
        XCTAssertFalse(tracking.isAccumulatingWheel, "Gesture travel waits for the gesture's end, not a timer")
        XCTAssertEqual(tracking.endGesture(at: 0.2), 1, "60 pt in 0.2 s is 300 pt/s")

        tracking.select(1)
        tracking.beginGesture(at: .zero, time: 1)
        tracking.scroll(by: 600, at: .zero, time: 2)
        XCTAssertEqual(tracking.endGesture(at: 5), 1, "600 pt over 4 s is slow: the page stays")
    }

    func testWheelSettlesByDirectionAloneAndResetsItsTravelEachTime() {
        var tracking = ClassicalPagerTracking(pageCount: 3, pageWidth: width)
        tracking.scroll(by: 2, at: .zero, time: 0)
        XCTAssertTrue(tracking.isAccumulatingWheel)
        XCTAssertEqual(tracking.settleWheel(), 1, "Any forward travel turns a page")
        tracking.select(1)
        tracking.scroll(by: -2, at: .zero, time: 1)
        tracking.scroll(by: -2, at: .zero, time: 1.01)
        XCTAssertEqual(tracking.scrollValue, width - 4)
        XCTAssertEqual(tracking.settleWheel(), 0)
        tracking.select(0)
        tracking.scroll(by: -10, at: .zero, time: 2)
        XCTAssertEqual(tracking.scrollValue, -2.5)
        XCTAssertEqual(tracking.settleWheel(), 0, "Past the leading edge the first page is kept")
    }

    func testWheelTravelDoublesTheDominantAxisAndIsReversedByDefault() {
        XCTAssertEqual(ClassicalPagerTracking.wheelTravel(deltaX: 0, deltaY: 3), -6)
        XCTAssertEqual(ClassicalPagerTracking.wheelTravel(deltaX: -4, deltaY: 1), 8)
        XCTAssertEqual(ClassicalPagerTracking.wheelTravel(deltaX: 2, deltaY: 2), -4, "Ties use the vertical axis")
        XCTAssertEqual(ClassicalPagerTracking.wheelTravel(deltaX: 0, deltaY: 3, reversed: false), 6)
    }

    func testSelectionClampsAndResizingKeepsTheCurrentPage() {
        var tracking = ClassicalPagerTracking(pageCount: 3, pageWidth: width, currentPage: 7)
        XCTAssertEqual(tracking.currentPage, 2)
        XCTAssertEqual(tracking.select(-1), 0)
        XCTAssertEqual(tracking.currentPage, 0)
    }
}
