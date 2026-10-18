import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalDockMetricsTests: XCTestCase {
    /// The reserved extent changes at 23, 47, and 127 pt and rounds fractional tile sizes up.
    func testRevealedThicknessFollowsTheDockTierTable() {
        let expected: [(CGFloat, CGFloat)] = [
            (16, 26),
            (23, 33),
            (23.1, 35),
            (39, 50),
            (47, 58),
            (47.1, 63),
            (48, 63),
            (127, 142),
            (127.1, 144),
            (128, 144),
            (400, 144)
        ]
        for (tile, thickness) in expected {
            XCTAssertEqual(ClassicalDockMetrics(tileSize: tile, edge: .bottom, autoHides: true).revealedThickness,
                           thickness, "tile \(tile)")
        }
    }

    func testLiveDockMetricsReportATileSizeInRange() throws {
        let metrics = try XCTUnwrap(ClassicalDockMetrics.current(), "CoreDock functions must resolve in the app process")
        XCTAssertTrue(ClassicalDockMetrics.tileSizeRange.contains(metrics.tileSize))
    }
}
