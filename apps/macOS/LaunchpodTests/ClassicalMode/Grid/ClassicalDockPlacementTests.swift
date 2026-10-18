import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalDockPlacementTests: XCTestCase {
    func testAutoHiddenDockReservesItsRevealedThicknessOnItsEdge() {
        typealias Placement = ClassicalSpringboardGeometry.DockPlacement
        let frame = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let noDockInset = CGRect(x: 0, y: 0, width: 1470, height: 923)
        let hidden = ClassicalDockMetrics(tileSize: 39, edge: .bottom, autoHides: true)
        XCTAssertEqual(Placement(frame: frame, visibleFrame: noDockInset, hidesDock: false, dock: hidden), .bottom(extent: 50))
        XCTAssertEqual(Placement(frame: frame, visibleFrame: noDockInset, hidesDock: false,
                                 dock: .init(tileSize: 64, edge: .left, autoHides: true)), .left(extent: 79))
        XCTAssertEqual(Placement(frame: frame, visibleFrame: noDockInset, hidesDock: false,
                                 dock: .init(tileSize: 64, edge: .right, autoHides: true)), .right(extent: 79))
        XCTAssertEqual(Placement(frame: frame, visibleFrame: noDockInset, hidesDock: true, dock: hidden), .hidden,
                       "A covered Dock reserves nothing")
        XCTAssertEqual(Placement(frame: frame, visibleFrame: noDockInset, hidesDock: false,
                                 dock: .init(tileSize: 39, edge: .bottom, autoHides: false)), .hidden,
                       "Without an inset or auto-hide the Dock is on another display")
        XCTAssertEqual(Placement(frame: frame, visibleFrame: CGRect(x: 0, y: 61, width: 1470, height: 862),
                                 hidesDock: false, dock: hidden), .bottom(extent: 61),
                       "A measured inset always wins over the derived thickness")
    }

    /// An auto-hidden Dock contributes the same extent to the root pager as a shown Dock would:
    /// bottom raises its origin, while a side placement increases the margin on that edge.
    func testAutoHiddenDockReserveChangesSpringboardGeometryOnItsEdge() {
        typealias Placement = ClassicalSpringboardGeometry.DockPlacement
        let size = CGSize(width: 1470, height: 956)
        let frame = CGRect(origin: .zero, size: size)
        let visible = CGRect(x: 0, y: 0, width: size.width, height: size.height - 33)
        let cases: [(ClassicalDockMetrics.Edge, Placement, CGRect)] = [
            (.bottom, .bottom(extent: 50), CGRect(x: 0, y: 80, width: 1470, height: 876)),
            (.left, .left(extent: 50), CGRect(x: 0, y: 30, width: 1470, height: 926)),
            (.right, .right(extent: 50), CGRect(x: 0, y: 30, width: 1470, height: 926))
        ]
        for (edge, expectedPlacement, expectedContent) in cases {
            let placement = Placement(frame: frame, visibleFrame: visible, hidesDock: false,
                                      dock: .init(tileSize: 39, edge: edge, autoHides: true))
            XCTAssertEqual(placement, expectedPlacement, "\(edge)")
            let geometry = ClassicalSpringboardGeometry(screenSize: size, dock: placement)
            XCTAssertEqual(geometry.contentFrame, expectedContent, "\(edge)")
            if edge == .left { XCTAssertGreaterThan(geometry.margins.left, geometry.margins.right) }
            if edge == .right { XCTAssertGreaterThan(geometry.margins.right, geometry.margins.left) }
        }
    }
}
