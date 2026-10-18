import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalItemEditingTests: XCTestCase {
    func testJitterAnimationsMatchTheDock() throws {
        var randoms: [UInt32] = [0, 999, 400, 600, 10, 510, 499, 500, 0]
        let position = ClassicalJitter.positionAnimation(random: { randoms.removeFirst() })
        XCTAssertEqual(position.keyPath, "position")
        XCTAssertEqual(position.duration, 0.25)
        XCTAssertTrue(position.isAdditive)
        XCTAssertFalse(position.isRemovedOnCompletion)
        XCTAssertEqual(position.repeatCount, .greatestFiniteMagnitude)
        let points = try XCTUnwrap(position.values as? [NSValue]).map(\.pointValue)
        XCTAssertEqual(points, [CGPoint(x: -1, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: -1, y: 0),
                                CGPoint(x: -1, y: 0)], "Offsets are −1 below 0.5 of the random range, the last repeats the first")
        XCTAssertEqual(ClassicalJitter.offset(random: 500), 0)
        XCTAssertEqual(ClassicalJitter.offset(random: 499), -1)
        XCTAssertEqual(position.beginTime, 0.05, accuracy: 1e-9, "ceil((0 + 1) × 0.2) × 0.05")
        XCTAssertEqual(ClassicalJitter.beginTime(random: 999), 10, accuracy: 1e-9)

        let rotation = ClassicalJitter.rotationAnimation(random: { 4 })
        XCTAssertEqual(rotation.keyPath, "transform")
        XCTAssertEqual(rotation.valueFunction?.name, .rotateZ)
        XCTAssertEqual(rotation.values as? [Double], [-0.03525565085, 0.03525565085, -0.03525565085])
        XCTAssertEqual(rotation.duration, 0.25)
        XCTAssertTrue(rotation.isAdditive)
        if rotation.responds(to: NSSelectorFromString("frameInterval")) {
            XCTAssertEqual(rotation.value(forKey: "frameInterval") as? Double, 0.05)
        }
    }

    /// Centred 10 % inside the icon's top-left corner, 28 pt.
    func testCloseboxSitsOnTheIconsTopLeading() {
        let icon = CGRect(x: 35, y: 43, width: 96, height: 96)
        XCTAssertEqual(ClassicalCloseBox.frame(icon: icon, rightToLeft: false), CGRect(x: 30, y: 116, width: 28, height: 28))
        XCTAssertEqual(ClassicalCloseBox.frame(icon: icon, rightToLeft: true), CGRect(x: 108, y: 116, width: 28, height: 28))
    }
}
