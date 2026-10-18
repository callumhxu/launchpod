import QuartzCore
import XCTest
@testable import Launchpod

/// Where a glass view goes to cover a layer as it is drawn on screen.
@MainActor
final class ClassicalGlassPlacementTests: XCTestCase {
    private func withoutActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    /// A 76-point backing with corner radius 15 and opacity 0.8, centred in a parent at (150, 250) that
    /// is turned 2° and scaled 1.2 with opacity 0.5.
    func testPlacementCoversTheBackingAsDrawn() throws {
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let parent = CALayer()
        let backing = CALayer()
        withoutActions {
            parent.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
            parent.position = CGPoint(x: 150, y: 250)
            parent.opacity = 0.5
            parent.transform = CATransform3DConcat(CATransform3DMakeScale(1.2, 1.2, 1),
                                                   CATransform3DMakeRotation(2 * .pi / 180, 0, 0, 1))
            backing.bounds = CGRect(x: 0, y: 0, width: 76, height: 76)
            backing.position = CGPoint(x: 100, y: 100)
            backing.cornerRadius = 15
            backing.opacity = 0.8
            root.addSublayer(parent)
            parent.addSublayer(backing)
        }

        let placement = try XCTUnwrap(ClassicalGlassPlacement.covering(backing, in: root))

        XCTAssertEqual(placement.center.x, 150, accuracy: 1e-6)
        XCTAssertEqual(placement.center.y, 250, accuracy: 1e-6)
        XCTAssertEqual(placement.size.width, 91.2, accuracy: 1e-6)
        XCTAssertEqual(placement.size.height, 91.2, accuracy: 1e-6)
        XCTAssertEqual(placement.rotation, 2 * .pi / 180, accuracy: 1e-9, "Counterclockwise, like the layer")
        XCTAssertEqual(placement.cornerRadius, 18, accuracy: 1e-6)
        XCTAssertEqual(placement.opacity, 0.4, accuracy: 1e-6)

        // An offset from the parent's centre turns and scales with it.
        withoutActions { backing.position = CGPoint(x: 150, y: 100) }
        let offset = try XCTUnwrap(ClassicalGlassPlacement.covering(backing, in: root))
        let angle = 2 * CGFloat.pi / 180
        XCTAssertEqual(offset.center.x, 150 + 50 * 1.2 * cos(angle), accuracy: 1e-6)
        XCTAssertEqual(offset.center.y, 250 + 50 * 1.2 * sin(angle), accuracy: 1e-6)
    }

    func testPlacementIsNilForADetachedHiddenOrTransparentBackingAndIgnoresNegligibleRotation() throws {
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let parent = CALayer()
        let backing = CALayer()
        withoutActions {
            parent.frame = root.bounds
            backing.frame = CGRect(x: 10, y: 10, width: 60, height: 60)
        }
        XCTAssertNil(ClassicalGlassPlacement.covering(backing, in: root), "Not in the root's tree")
        withoutActions {
            root.addSublayer(parent)
            parent.addSublayer(backing)
        }
        XCTAssertNotNil(ClassicalGlassPlacement.covering(backing, in: root))
        withoutActions { parent.isHidden = true }
        XCTAssertNil(ClassicalGlassPlacement.covering(backing, in: root), "A hidden ancestor hides the glass")
        withoutActions {
            parent.isHidden = false
            parent.opacity = 0
        }
        XCTAssertNil(ClassicalGlassPlacement.covering(backing, in: root), "No ghost of a faded-out cell")
        withoutActions {
            parent.opacity = 1
            parent.transform = CATransform3DMakeRotation(0.00001, 0, 0, 1)
        }
        XCTAssertEqual(ClassicalGlassPlacement.covering(backing, in: root)?.rotation, 0)
    }

    /// The strip glass view applies the strip's scroll itself, so the strip placement shifted by that
    /// scroll is where the backing is on screen.
    func testStripPlacementPlusTheMirroredScrollIsTheOnScreenPlacement() throws {
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let strip = CALayer()
        let page = CALayer()
        let backing = CALayer()
        withoutActions {
            strip.frame = CGRect(x: 0, y: 20, width: 400, height: 280)
            strip.bounds.origin.x = 400
            page.frame = CGRect(x: 400, y: 0, width: 400, height: 280)
            page.transform = CATransform3DMakeRotation(0.03, 0, 0, 1)
            backing.frame = CGRect(x: 100, y: 50, width: 64, height: 64)
            backing.cornerRadius = 12
            root.addSublayer(strip)
            strip.addSublayer(page)
            page.addSublayer(backing)
        }

        let onScreen = try XCTUnwrap(ClassicalGlassPlacement.covering(backing, in: root))
        let mirrored = try XCTUnwrap(ClassicalGlassPlacement.onStrip(backing, strip: strip, in: root))

        XCTAssertEqual(mirrored.center.x - strip.bounds.origin.x, onScreen.center.x, accuracy: 1e-6)
        XCTAssertEqual(mirrored.center.y, onScreen.center.y, accuracy: 1e-6)
        XCTAssertEqual(mirrored.size.width, onScreen.size.width, accuracy: 1e-6)
        XCTAssertEqual(mirrored.rotation, onScreen.rotation, accuracy: 1e-9)
        XCTAssertEqual(mirrored.cornerRadius, onScreen.cornerRadius, accuracy: 1e-6)
    }

    /// A drop glow guide takes its frame from its parent's drawing but not its own fade and grow: a
    /// 60-point guide scaled 1.2 with opacity 0.3 in a parent scaled 2 at opacity 0.5 maps to 120
    /// points at opacity 0.5.
    func testUnscaledFrameLeavesOutTheGuidesOwnTransformAndOpacity() throws {
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let parent = CALayer()
        let guide = CALayer()
        withoutActions {
            parent.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
            parent.position = CGPoint(x: 200, y: 200)
            parent.transform = CATransform3DMakeScale(2, 2, 1)
            parent.opacity = 0.5
            guide.bounds = CGRect(x: 0, y: 0, width: 60, height: 60)
            guide.position = CGPoint(x: 60, y: 50)
            guide.cornerRadius = 12
            guide.transform = CATransform3DMakeScale(1.2, 1.2, 1)
            guide.opacity = 0.3
            root.addSublayer(parent)
            parent.addSublayer(guide)
        }

        let placement = try XCTUnwrap(ClassicalGlassPlacement.unscaledFrame(of: guide, in: root))

        XCTAssertEqual(placement.center.x, 220, accuracy: 1e-6)
        XCTAssertEqual(placement.center.y, 200, accuracy: 1e-6)
        XCTAssertEqual(placement.size.width, 120, accuracy: 1e-6)
        XCTAssertEqual(placement.cornerRadius, 24, accuracy: 1e-6)
        XCTAssertEqual(placement.rotation, 0)
        XCTAssertEqual(placement.opacity, 0.5, accuracy: 1e-6)
        withoutActions { guide.removeFromSuperlayer() }
        XCTAssertNil(ClassicalGlassPlacement.unscaledFrame(of: guide, in: root), "A detached guide has no glow")
    }

    func testDescendantMeansInTheRootsLayerTree() {
        let root = CALayer()
        let child = CALayer()
        let grandchild = CALayer()
        root.addSublayer(child)
        child.addSublayer(grandchild)
        XCTAssertTrue(ClassicalGlassPlacement.isDescendant(grandchild, of: root))
        XCTAssertTrue(ClassicalGlassPlacement.isDescendant(root, of: root))
        XCTAssertFalse(ClassicalGlassPlacement.isDescendant(root, of: grandchild))
        XCTAssertFalse(ClassicalGlassPlacement.isDescendant(CALayer(), of: root))
    }
}
