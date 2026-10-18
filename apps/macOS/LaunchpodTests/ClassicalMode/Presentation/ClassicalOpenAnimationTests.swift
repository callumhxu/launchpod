import QuartzCore
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalOpenAnimationTests: XCTestCase {
    func testIconCopyGrowsTwiceInPlaceAndFadesOverAQuarterSecond() throws {
        let host = CALayer()
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let cell = CALayer()
        cell.frame = CGRect(x: 100, y: 200, width: 160, height: 140)
        host.addSublayer(cell)
        let icon = CALayer()
        icon.frame = CGRect(x: 32, y: 40, width: 96, height: 96)
        icon.contents = try pixel()
        cell.addSublayer(icon)

        let copy = try XCTUnwrap(ClassicalOpenAnimation.play(icon: icon, in: host,
                                                             slowMotionAllowed: false, shiftKeyDown: false))
        XCTAssertTrue(copy.superlayer === host, "The copy sits above the launcher content")
        XCTAssertEqual(copy.frame.size, CGSize(width: 192, height: 192))
        XCTAssertEqual(copy.position, CGPoint(x: 180, y: 288), "It grows in place around the icon")
        XCTAssertEqual(copy.opacity, 0.1)
        let fade = try XCTUnwrap(copy.animation(forKey: "opacity") as? CABasicAnimation)
        XCTAssertEqual(fade.duration, 0.25)
        XCTAssertEqual(fade.fromValue as? Float, 0.9)
        XCTAssertEqual(fade.timingFunction, CAMediaTimingFunction(name: .easeOut))
        XCTAssertNotNil(copy.animation(forKey: "transform"))
    }

    func testLaunchFeedbackSlowsOnlyWithAllowedShift() throws {
        let host = CALayer()
        let icon = CALayer()
        icon.frame = CGRect(x: 20, y: 30, width: 96, height: 96)
        icon.contents = try pixel()
        host.addSublayer(icon)

        for (allowed, shifted, expectedDuration) in [(false, false, 0.25), (false, true, 0.25),
                                                       (true, false, 0.25), (true, true, 5.0)] {
            let copy = try XCTUnwrap(ClassicalOpenAnimation.play(icon: icon, in: host,
                                                                 slowMotionAllowed: allowed, shiftKeyDown: shifted))
            let fade = try XCTUnwrap(copy.animation(forKey: "opacity"))
            let grow = try XCTUnwrap(copy.animation(forKey: "transform"))
            XCTAssertEqual(fade.duration, expectedDuration)
            XCTAssertEqual(grow.duration, expectedDuration)
            copy.removeFromSuperlayer()
        }
    }

    func testIconWithoutImageHasNoAnimation() {
        let host = CALayer()
        XCTAssertNil(ClassicalOpenAnimation.play(icon: CALayer(), in: host))
        XCTAssertNil(host.sublayers)
    }

    private func pixel() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}

@MainActor
final class ClassicalDesktopCrossfadeTests: XCTestCase {
    /// The new wallpaper fades in over 2 s above the old one.
    func testChangedWallpaperFadesInOverTwoSecondsAndReplacesTheOldLayer() throws {
        let layers = ClassicalSpringboardLayers()
        let host = CALayer()
        let desktop = CALayer()
        desktop.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertTrue(layers.show(in: host, desktopLayer: desktop, reduceMotion: true))
        let next = try XCTUnwrap(layers.crossfadeDesktop(to: try pixel()))
        XCTAssertTrue(layers.desktopLayer === next)
        XCTAssertEqual(next.frame, desktop.frame)
        XCTAssertEqual(next.opacity, 1)
        // Detached layer trees drop committed animations, so the fade itself is checked on screen.
        XCTAssertEqual(ClassicalPresentationParameters.desktopCrossfadeDuration, 2)
        XCTAssertTrue(next.superlayer === desktop.superlayer)
        layers.destroy()
    }

    private func pixel() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}
