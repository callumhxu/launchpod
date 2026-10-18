import AppKit
import CoreText
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalItemLayoutTests: XCTestCase {
    func testIconAndTitleFitTheMeasuredCellAndLongTitlesStayInsideIt() {
        // Title label 16 + 2·2 + (2 − (−1)) = 23; bottom padding min(ceil(145/8), 20) = 19;
        // icon floor8(145 − 47) = 96;
        // icon x trunc(83.5 − 48) = 35, y 19 + 23.
        let item = ClassicalItemLayout(cellSize: CGSize(width: 167, height: 145), titleLineHeight: 16)
        XCTAssertEqual(item.titleHeight, 23)
        XCTAssertEqual(item.iconFrame, CGRect(x: 35, y: 42, width: 96, height: 96))
        // Label width = text + 4: 64 is even, 83.5 − 32 truncates to 51; 65 is odd, 51 rounds to 51.
        XCTAssertEqual(item.titleFrame(textWidth: 60), CGRect(x: 51, y: 19, width: 64, height: 23))
        XCTAssertEqual(item.titleFrame(textWidth: 61), CGRect(x: 51, y: 19, width: 65, height: 23))
        XCTAssertEqual(item.titleFrame(textWidth: 400), CGRect(x: 6, y: 19, width: 155, height: 23), "Long titles stop 6 pt inside the cell")
        XCTAssertEqual(item.titleTextFrame(textWidth: 60), CGRect(x: 53, y: 21, width: 60, height: 19), "Text sits 2 pt inside the label")
    }

    func testSmallCellsFloorTheIconAt20() {
        XCTAssertEqual(ClassicalItemLayout.iconSide(cellSize: CGSize(width: 60, height: 50), titleHeight: 27), 20)
        XCTAssertEqual(ClassicalItemLayout.iconSide(cellSize: CGSize(width: 90, height: 90), titleHeight: 27), 32)
        XCTAssertEqual(ClassicalItemLayout.iconSide(cellSize: CGSize(width: 400, height: 400), titleHeight: 27), 128)
    }

    func testTitleFontIsThirteenPointMediumWithMonospacedDigitsAndSixteenPointLines() {
        let font = ClassicalTitleFont.font
        XCTAssertEqual(font.pointSize, 13)
        let traits = CTFontCopyTraits(font as CTFont) as NSDictionary
        XCTAssertEqual((traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0, NSFont.Weight.medium.rawValue, accuracy: 0.01)
        let features = (font.fontDescriptor.object(forKey: .featureSettings) as? [[NSFontDescriptor.FeatureKey: Int]]) ?? []
        XCTAssertTrue(features.contains { $0[.typeIdentifier] == kNumberSpacingType && $0[.selectorIdentifier] == kMonospacedNumbersSelector })
        XCTAssertEqual(ClassicalTitleFont.lineHeight, 16, "SF 13 pt: ceil(12.568 + 2.742 + 0)")
    }

    /// The title is the system UI font of type 105 at 13 pt.
    func testTitleFontIsTheUIFontOfType105() throws {
        let uiType = try XCTUnwrap(CTFontUIFontType(rawValue: 105))
        let reference = try XCTUnwrap(CTFontCreateUIFontForLanguage(uiType, 13, nil))
        let font = ClassicalTitleFont.font as CTFont
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, CTFontCopyPostScriptName(reference) as String)
        XCTAssertEqual(CTFontGetSize(font), 13)
    }
}
