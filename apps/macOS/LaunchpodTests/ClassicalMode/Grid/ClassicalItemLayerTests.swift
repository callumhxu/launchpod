import QuartzCore
import XCTest
@testable import Launchpod

final class ClassicalItemLayerTests: XCTestCase {
    @MainActor
    func testSelectedItemGetsTheHighlightBehindItsIcon() {
        let layout = ClassicalItemLayout(cellSize: CGSize(width: 167, height: 143))
        let cell = ClassicalItemLayer(title: "Safari", layout: layout, scale: 2)
        cell.setSelected(true)
        let selection = try? XCTUnwrap(cell.selectionLayer)
        XCTAssertTrue(cell.jitterLayer.sublayers?.first === selection, "Inserted under the icon inside the jitter layer")
        XCTAssertEqual(selection?.compositingFilter as? String, "plusD")
        XCTAssertEqual(selection?.cornerRadius, ClassicalSelection.cornerRadius(iconHeight: layout.iconFrame.height))
        cell.setSelected(false)
        XCTAssertNil(cell.selectionLayer)
        XCTAssertNil(selection?.superlayer)
    }

    /// Pressing multiplies the icon by gray 0.4 through a layer filter; releasing removes it.
    @MainActor
    func testPressedIconIsMultipliedByGray() throws {
        let cell = ClassicalItemLayer(title: "Safari", layout: ClassicalItemLayout(cellSize: CGSize(width: 167, height: 143)), scale: 2)
        cell.setDarkened(true)
        XCTAssertEqual(CoreAnimationFilterReading.types(cell.iconLayer.filters), ["multiplyColor"])
        let filter = CoreAnimationFilterReading.first("multiplyColor", in: cell.iconLayer.filters)
        XCTAssertEqual(filter?.value(forKey: "inputColor") as! CGColor?, CGColor(gray: 0.4, alpha: 1))
        cell.setDarkened(false)
        XCTAssertNil(cell.iconLayer.filters)
    }

    /// The selection's plus-darker compositing reaches what is behind the cell, not only the cell's
    /// own layers.
    @MainActor
    func testJitterLayerDoesNotBlendAsAGroup() {
        let cell = ClassicalItemLayer(title: "Safari", layout: ClassicalItemLayout(cellSize: CGSize(width: 167, height: 143)), scale: 2)
        XCTAssertEqual(cell.jitterLayer.value(forKey: "allowsGroupBlending") as? Bool, false)
    }

    /// The unavailable artwork covers the icon visually but leaves the icon as the hit target.
    @MainActor
    func testNotFoundArtworkDoesNotInterceptIconHitTesting() throws {
        let cell = ClassicalItemLayer(title: "Offline", layout: ClassicalItemLayout(cellSize: CGSize(width: 167, height: 143)), scale: 2)
        cell.setNotFound(true)
        let marker = try XCTUnwrap(cell.notFoundLayer)
        let iconCenter = CGPoint(x: cell.iconLayer.bounds.midX, y: cell.iconLayer.bounds.midY)

        XCTAssertTrue(cell.iconLayer.hitTest(iconCenter) === cell.iconLayer)
        XCTAssertNil(marker.hitTest(iconCenter))

        cell.setNotFound(false)
        XCTAssertNil(cell.notFoundLayer)
        XCTAssertNil(marker.superlayer)
    }

    @MainActor
    func testRestrictedStatusDimsIconAndKeepsASeparateMarkerUntilCleared() throws {
        let cell = ClassicalItemLayer(title: "Limited", layout: ClassicalItemLayout(cellSize: CGSize(width: 167, height: 143)), scale: 2)
        let image = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        cell.setIcon(image)

        XCTAssertFalse(cell.isRestricted)
        XCTAssertNil(cell.restrictedLayer)
        XCTAssertEqual(cell.iconLayer.opacity, 1)

        cell.setRestricted(true)
        let marker = try XCTUnwrap(cell.restrictedLayer)
        XCTAssertTrue(cell.isRestricted)
        XCTAssertNotNil(marker.superlayer)
        XCTAssertFalse(marker === cell.iconLayer)
        XCTAssertEqual(cell.iconLayer.opacity, 0.2, accuracy: 0.001)
        XCTAssertTrue(cell.iconLayer.contents as AnyObject? === image)
        XCTAssertTrue(marker.superlayer === cell.jitterLayer)
        XCTAssertEqual(marker.frame, CGRect(x: cell.iconLayer.frame.maxX, y: cell.iconLayer.frame.minY + 4,
                                            width: 16, height: 16))

        cell.setRestricted(true, rightToLeft: true)
        XCTAssertTrue(cell.restrictedLayer === marker, "Direction changes reposition the existing marker")
        XCTAssertEqual(marker.frame, CGRect(x: cell.iconLayer.frame.minX - 16, y: cell.iconLayer.frame.minY + 4,
                                            width: 16, height: 16))

        cell.setRestricted(false)
        XCTAssertFalse(cell.isRestricted)
        XCTAssertNil(cell.restrictedLayer)
        XCTAssertNil(marker.superlayer)
        XCTAssertEqual(cell.iconLayer.opacity, 1)
        XCTAssertTrue(cell.iconLayer.contents as AnyObject? === image)
    }

    /// Dock's recently added flag is a 9-point circular mark that disappears after opening.
    @MainActor
    func testRecentlyAddedFlagAppearsBesideTitleAndCanClear() throws {
        let cell = ClassicalItemLayer(title: "New App", layout: ClassicalItemLayout(cellSize: CGSize(width: 167, height: 143)), scale: 2)
        XCTAssertNil(cell.flagLayer)
        cell.setRecentlyAdded(true)
        let flag = try XCTUnwrap(cell.flagLayer)
        XCTAssertTrue(flag.superlayer === cell.jitterLayer)
        XCTAssertEqual(flag.bounds.size, CGSize(width: 9, height: 9))
        XCTAssertEqual(flag.cornerRadius, 4.5)
        // The flag's outer square sits beside the complete label, including its 2-point text margins.
        let label = cell.titleFrame.insetBy(dx: -2, dy: -2)
        let outerSide = label.height - 8
        func expectedFrame(outerX: CGFloat) -> CGRect {
            let outer = CGRect(x: outerX, y: label.minY + 5, width: outerSide, height: outerSide)
            return CGRect(x: CGFloat(Int(outer.midX - 4.5)), y: CGFloat(Int(outer.midY - 4.5)),
                          width: 9, height: 9)
        }
        XCTAssertEqual(expectedFrame(outerX: label.maxX), CGRect(x: 116, y: 26, width: 9, height: 9))
        XCTAssertEqual(flag.frame, CGRect(x: 116, y: 26, width: 9, height: 9))

        cell.setRecentlyAdded(true, rightToLeft: true)
        XCTAssertTrue(cell.flagLayer === flag)
        XCTAssertEqual(expectedFrame(outerX: label.minX - outerSide + 1),
                       CGRect(x: 42, y: 26, width: 9, height: 9))
        XCTAssertEqual(flag.frame, CGRect(x: 42, y: 26, width: 9, height: 9))

        cell.setRecentlyAdded(false)
        XCTAssertNil(cell.flagLayer)
        XCTAssertNil(flag.superlayer)
    }
}
