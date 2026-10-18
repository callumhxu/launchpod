import XCTest
@testable import Launchpod

final class ClassicalSelectionTests: XCTestCase {
    /// 96 pt icon, labels narrower, a little wider, and much wider.
    func testSelectionFrameWrapsIconAndTitle() {
        let icon = CGRect(x: 35, y: 43, width: 96, height: 96)
        let narrow = CGRect(x: 58, y: 20, width: 50, height: 23)
        XCTAssertEqual(ClassicalSelection.frame(icon: icon, label: narrow), CGRect(x: 20, y: 15, width: 126, height: 139))
        let slightlyWider = CGRect(x: 30, y: 20, width: 106, height: 23)
        XCTAssertEqual(ClassicalSelection.frame(icon: icon, label: slightlyWider),
                       CGRect(x: 20, y: 15, width: 126, height: 139), "dx = 8 − 5 + 7 = 10 around the label")
        let wide = CGRect(x: 6, y: 20, width: 154, height: 23)
        XCTAssertEqual(ClassicalSelection.frame(icon: icon, label: wide), CGRect(x: -1, y: 15, width: 168, height: 139))
        XCTAssertEqual(ClassicalSelection.cornerRadius(iconHeight: 96), 15)
        XCTAssertEqual(ClassicalSelection.cornerRadius(iconHeight: 80), 12, "12.5 rounds toward zero")
    }
}
