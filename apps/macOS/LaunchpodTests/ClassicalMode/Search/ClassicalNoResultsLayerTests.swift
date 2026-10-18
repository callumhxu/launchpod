import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalNoResultsLayerTests: XCTestCase {
    func testRelayoutUpdatesLocalizedTextScaleAndCenterWithoutAnimatingGeometry() {
        let layer = ClassicalNoResultsLayer()
        let parent = CALayer()
        parent.addSublayer(layer)
        let page = CGRect(x: 53, y: 71, width: 801, height: 503)
        layer.layOut(text: "No Results", scale: 1, page: page)
        let originalWidth = layer.frame.width
        layer.layOut(text: "Keine Ergebnisse", scale: 2, page: page)
        XCTAssertEqual(layer.textLayer.string as? String, "Keine Ergebnisse")
        XCTAssertEqual(layer.textLayer.contentsScale, 2)
        XCTAssertGreaterThan(layer.frame.width, originalWidth)
        XCTAssertEqual(layer.frame.midX, page.midX, accuracy: 1)
        XCTAssertEqual(layer.frame.midY, page.midY, accuracy: 1)
        XCTAssertEqual(layer.textLayer.frame, layer.bounds)
        XCTAssertTrue((layer.animationKeys() ?? []).isEmpty)
        XCTAssertTrue((layer.textLayer.animationKeys() ?? []).isEmpty)
    }

    func testHidingResetsTheModelOpacityImmediately() {
        let layer = ClassicalNoResultsLayer()
        XCTAssertEqual(layer.textLayer.opacity, 0)
        layer.setVisible(true)
        XCTAssertEqual(layer.textLayer.opacity, 1)
        layer.setVisible(false)
        XCTAssertEqual(layer.textLayer.opacity, 0)
    }
}
