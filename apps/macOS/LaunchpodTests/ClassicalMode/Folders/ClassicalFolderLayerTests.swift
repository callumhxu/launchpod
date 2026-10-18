import AppKit
import CoreText
import XCTest
@testable import Launchpod

/// The open folder panel: a backdrop that blurs (radius 30, hard edges) and saturates (1.8) what is
/// behind it, and a title in the system UI font of type 103 at 28 pt.
@MainActor
final class ClassicalFolderLayerTests: XCTestCase {
    func testBackdropBlursAndSaturatesWhatIsBehindThePanel() throws {
        let panel = ClassicalFolderLayer(glassEnabled: false)
        XCTAssertFalse(panel.glassEnabled, "Explicitly disabling glass keeps the Classical panel")
        XCTAssertEqual(NSStringFromClass(type(of: panel.backdropLayer)), "CABackdropLayer")
        let filters = panel.backdropLayer.backgroundFilters
        XCTAssertEqual(CoreAnimationFilterReading.types(filters), ["gaussianBlur", "colorSaturate"])
        let blur = CoreAnimationFilterReading.first("gaussianBlur", in: filters)
        XCTAssertEqual(CoreAnimationFilterReading.number("inputRadius", of: blur), 30)
        XCTAssertEqual(blur?.value(forKey: "inputHardEdges") as? Bool, true)
        let saturate = CoreAnimationFilterReading.first("colorSaturate", in: filters)
        XCTAssertEqual(try XCTUnwrap(CoreAnimationFilterReading.number("inputAmount", of: saturate)), 1.8, accuracy: 1e-6)
        XCTAssertTrue(panel.backdropLayer.superlayer === panel.maskContainerLayer)
        XCTAssertNil(panel.backdropLayer.filters, "The panel itself is not filtered")
    }

    func testEnabledGlassLeavesATransparentGuideBehindTheOpenFolder() {
        let panel = ClassicalFolderLayer(glassEnabled: true)
        XCTAssertTrue(panel.glassEnabled)
        XCTAssertNil(panel.backdropLayer.backgroundColor)
        XCTAssertNil(panel.backdropLayer.backgroundFilters)
        XCTAssertTrue(panel.backdropLayer.superlayer === panel.maskContainerLayer)
    }

    func testTitleIsTheUIFontOfType103At28Points() throws {
        let uiType = try XCTUnwrap(CTFontUIFontType(rawValue: 103))
        let reference = try XCTUnwrap(CTFontCreateUIFontForLanguage(uiType, 28, nil))
        let font = ClassicalFolderLayer.titleFont as CTFont
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, CTFontCopyPostScriptName(reference) as String)
        XCTAssertEqual(CTFontGetSize(font), 28)
        XCTAssertEqual((ClassicalFolderLayer().titleLayer.font as? NSFont)?.fontName, ClassicalFolderLayer.titleFont.fontName)
    }
}
