import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalPagerTests: XCTestCase {
    private let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956), dock: .bottom(extent: 59))

    func testRecordsFillPagesOneScreenWidthApartWithDotsInTheBottomMargin() throws {
        let pager = ClassicalPager()
        pager.show(try records(80), geometry: geometry, scale: 2, rightToLeft: false) { _, _ in throw CancellationError() }
        XCTAssertEqual(pager.pageCount, 3)
        XCTAssertEqual(pager.pages.map(\.itemLayers.count), [35, 35, 10])
        let content = geometry.contentFrame
        XCTAssertEqual(pager.layer.frame, content, "The pager fills the content frame")
        XCTAssertTrue(pager.layer.masksToBounds)
        XCTAssertEqual(pager.stripLayer.frame, CGRect(x: 0, y: geometry.margins.bottom, width: 1470,
                                                      height: content.height - geometry.margins.bottom))
        XCTAssertTrue(pager.stripLayer.masksToBounds, "Pages are clipped at the bottom margin")
        for (index, page) in pager.pages.enumerated() {
            let root = pager.stripLayer.convert(page.layer.frame, to: pager.layer).offsetBy(dx: content.minX, dy: content.minY)
            XCTAssertEqual(root, geometry.pageFrame.offsetBy(dx: CGFloat(index) * 1470, dy: 0))
        }
        let band = ClassicalPageDotsLayout.bandFrame(for: geometry)
        XCTAssertEqual(band, CGRect(x: 0, y: geometry.contentFrame.minY + (geometry.margins.bottom / 2 - 7.5).rounded(.down),
                                    width: 1470, height: 15))
        XCTAssertEqual(pager.dotsLayer.frame, band.offsetBy(dx: 0, dy: -geometry.contentFrame.minY))
        XCTAssertFalse(pager.dotsLayer.isHidden)
        XCTAssertEqual(pager.dotsLayer.dotLayers.map(\.opacity), [1, 0.2, 0.2])
        XCTAssertEqual(pager.dotsLayer.dotLayers.map(\.frame.width), [8, 8, 8])
    }

    func testDotsAreHiddenWithASinglePage() throws {
        let pager = ClassicalPager()
        pager.show(try records(3), geometry: geometry, scale: 1, rightToLeft: false) { _, _ in throw CancellationError() }
        XCTAssertTrue(pager.dotsLayer.isHidden)
        XCTAssertFalse(pager.mouseDown(at: CGPoint(x: 735, y: ClassicalPageDotsLayout.bandFrame(for: geometry).midY), time: 0),
                       "Hidden dots do not take the click")
    }

    func testReleasingOverADotSettlesOnItsPage() throws {
        let pager = ClassicalPager()
        pager.show(try records(80), geometry: geometry, scale: 1, rightToLeft: false) { _, _ in throw CancellationError() }
        let dot = pager.dotsLayer.layout.indicatorFrame(for: 2)
        let point = CGPoint(x: dot.midX, y: ClassicalPageDotsLayout.bandFrame(for: geometry).minY + dot.midY)
        XCTAssertTrue(pager.mouseDown(at: point, time: 0))
        pager.dotsMouseUp(at: point)
        XCTAssertEqual(pager.currentPage, 2)
        XCTAssertEqual(pager.stripLayer.bounds.origin.x, 2 * 1470)
        XCTAssertEqual(pager.dotsLayer.dotLayers.map(\.opacity), [0.2, 0.2, 1])
    }

    /// Frame by frame at 60 Hz: the settle leaves from where the strip is drawn, follows the settle
    /// curve for 0.5 s, and lands exactly on the page.
    func testFastFlickSettlesWithTheDockCurveFrameByFrame() throws {
        let pager = ClassicalPager()
        pager.shiftKeyDown = { false }
        pager.show(try records(80), geometry: geometry, scale: 1, rightToLeft: false) { _, _ in throw CancellationError() }
        XCTAssertFalse(pager.mouseDown(at: CGPoint(x: 700, y: 500), time: 0))
        pager.mouseDragged(to: CGPoint(x: 650, y: 500))
        XCTAssertEqual(pager.stripLayer.bounds.origin.x, 50, "The strip follows the drag without animation")
        XCTAssertTrue(pager.mouseUp(at: CGPoint(x: 650, y: 500), time: 0.1))
        XCTAssertEqual(pager.currentPage, 1)
        let animation = try XCTUnwrap(pager.stripLayer.animation(forKey: ClassicalPager.settleAnimationKey) as? CABasicAnimation)
        XCTAssertEqual(animation.duration, 0.5)
        XCTAssertEqual(animation.fromValue as? CGFloat, 50)
        XCTAssertNil(animation.toValue, "Like the Dock's implicit action, the animation ends at the model value")
        let dockTiming = CAMediaTimingFunction(controlPoints: 0, 0, 0.35841, 1.0019)
        for index in 0..<4 {
            var actual: [Float] = [0, 0]
            var expected: [Float] = [0, 0]
            animation.timingFunction?.getControlPoint(at: index, values: &actual)
            dockTiming.getControlPoint(at: index, values: &expected)
            XCTAssertEqual(actual[0], expected[0], accuracy: 1e-6)
            XCTAssertEqual(actual[1], expected[1], accuracy: 1e-6)
        }
        XCTAssertEqual(pager.stripLayer.bounds.origin.x, 1470, "The model value is the target")

        let frames = (0...30).map { frame -> CGFloat in
            let progress = CGFloat(Self.evaluate(dockTiming, at: Double(frame) / 30))
            return 50 + (1470 - 50) * progress
        }
        XCTAssertEqual(frames.first, 50)
        XCTAssertEqual(frames.last!, 1470, accuracy: 0.001)
        // Ease-out: 8 % of the travel in the first frame, 78 % at the midpoint, the last frame 1 pt short.
        XCTAssertEqual(frames[1], 168.137, accuracy: 0.01)
        XCTAssertEqual(frames[15], 1163.110, accuracy: 0.01)
        XCTAssertEqual(frames[29], 1468.854, accuracy: 0.01)
        XCTAssertEqual(frames, frames.sorted(), "No visible overshoot at 60 Hz")
    }

    func testShiftSlowsThePageSettleOnlyWhenSlowMotionIsAllowed() throws {
        let pager = ClassicalPager()
        pager.shiftKeyDown = { true }
        pager.slowMotionAllowed = { false }
        pager.show(try records(80), geometry: geometry, scale: 1, rightToLeft: false) { _, _ in throw CancellationError() }
        pager.settle(on: 1)
        let ordinary = try XCTUnwrap(pager.stripLayer.animation(forKey: ClassicalPager.settleAnimationKey))
        XCTAssertEqual(ordinary.duration, 0.5)

        pager.slowMotionAllowed = { true }
        pager.settle(on: 2)
        let slow = try XCTUnwrap(pager.stripLayer.animation(forKey: ClassicalPager.settleAnimationKey))
        XCTAssertEqual(slow.duration, 5)

        pager.shiftKeyDown = { false }
        pager.settle(on: 0)
        let unshifted = try XCTUnwrap(pager.stripLayer.animation(forKey: ClassicalPager.settleAnimationKey))
        XCTAssertEqual(unshifted.duration, 0.5)
    }

    func testSlowDragAndEdgeBounceReturnToTheirPage() throws {
        let pager = ClassicalPager()
        pager.shiftKeyDown = { false }
        pager.show(try records(80), geometry: geometry, scale: 1, rightToLeft: false) { _, _ in throw CancellationError() }
        _ = pager.mouseDown(at: CGPoint(x: 700, y: 500), time: 0)
        pager.mouseDragged(to: CGPoint(x: 800, y: 500))
        XCTAssertEqual(pager.stripLayer.bounds.origin.x, -25, "Before the first page the strip moves a quarter as far")
        XCTAssertTrue(pager.mouseUp(at: CGPoint(x: 800, y: 500), time: 0.05))
        XCTAssertEqual(pager.currentPage, 0)
        let bounce = try XCTUnwrap(pager.stripLayer.animation(forKey: ClassicalPager.settleAnimationKey) as? CABasicAnimation)
        XCTAssertEqual(bounce.fromValue as? CGFloat, -25)
        XCTAssertEqual(pager.stripLayer.bounds.origin.x, 0)

        _ = pager.mouseDown(at: CGPoint(x: 700, y: 500), time: 1)
        pager.mouseDragged(to: CGPoint(x: 690, y: 500))
        XCTAssertNotNil(pager.stripLayer.animation(forKey: ClassicalPager.settleAnimationKey),
                        "A drag during the settle moves the model; the running animation follows it")
        XCTAssertEqual(pager.stripLayer.bounds.origin.x, 10, "Travel starts from the model value, as `scrollValue` does")
        pager.mouseDragged(to: CGPoint(x: 100, y: 500))
        XCTAssertTrue(pager.mouseUp(at: CGPoint(x: 100, y: 500), time: 5))
        XCTAssertEqual(pager.currentPage, 0, "A slow drag cancels back to its page")
    }

    func testWheelSettlesAfterTheIdleDelayAndMomentumIsIgnored() async throws {
        let pager = ClassicalPager()
        pager.shiftKeyDown = { false }
        var delays: [TimeInterval] = []
        pager.wheelSettleSleep = { delays.append($0) }
        pager.show(try records(80), geometry: geometry, scale: 1, rightToLeft: false) { _, _ in throw CancellationError() }
        pager.scrollWheel(deltaX: 0, deltaY: -1, phase: [], momentumPhase: [], at: .zero, time: 0)
        XCTAssertEqual(pager.stripLayer.bounds.origin.x, 2)
        pager.scrollWheel(deltaX: 0, deltaY: -30, phase: [], momentumPhase: .changed, at: .zero, time: 0.01)
        XCTAssertEqual(pager.stripLayer.bounds.origin.x, 2, "Momentum events are ignored")
        try await waitUntil { pager.currentPage == 1 }
        XCTAssertEqual(delays, [0.075])
    }

    /// The wheel timer reads Shift independently of the slow-motion preference.
    func testShiftExtendsWheelIdleWhenSlowMotionPreferenceIsOff() async throws {
        let pager = ClassicalPager()
        pager.shiftKeyDown = { true }
        pager.slowMotionAllowed = { false }
        var delays: [TimeInterval] = []
        pager.wheelSettleSleep = { delays.append($0) }
        pager.show(try records(80), geometry: geometry, scale: 1, rightToLeft: false) { _, _ in throw CancellationError() }

        pager.scrollWheel(deltaX: 0, deltaY: -1, phase: [], momentumPhase: [], at: .zero, time: 0)
        try await waitUntil { pager.currentPage == 1 }
        XCTAssertEqual(delays, [0.375])
    }

    func testTrackpadGestureSettlesOnItsEndPhase() throws {
        let pager = ClassicalPager()
        pager.shiftKeyDown = { false }
        pager.wheelSettleSleep = { _ in XCTFail("A gesture never uses the wheel timer") }
        pager.show(try records(80), geometry: geometry, scale: 1, rightToLeft: false) { _, _ in throw CancellationError() }
        pager.scrollWheel(deltaX: -10, deltaY: 0, phase: .began, momentumPhase: [], at: .zero, time: 0)
        pager.scrollWheel(deltaX: -10, deltaY: 0, phase: .changed, momentumPhase: [], at: .zero, time: 0.05)
        XCTAssertEqual(pager.stripLayer.bounds.origin.x, 40)
        XCTAssertEqual(pager.currentPage, 0)
        pager.scrollWheel(deltaX: 0, deltaY: 0, phase: .ended, momentumPhase: [], at: .zero, time: 0.1)
        XCTAssertEqual(pager.currentPage, 1)
    }

    /// A wheel event before any pages exist (content not loaded yet) must not crash when it settles.
    func testWheelSettleBeforeAnyPagesIsHarmless() async throws {
        let pager = ClassicalPager()
        pager.shiftKeyDown = { false }
        var settled = false
        pager.wheelSettleSleep = { _ in settled = true }
        pager.scrollWheel(deltaX: 0, deltaY: -1, phase: [], momentumPhase: [], at: .zero, time: 0)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(settled)
        XCTAssertEqual(pager.currentPage, 0)
        pager.swipe(deltaX: -1)
        pager.jump(to: 3)
    }

    func testSwipeTurnsOnePageAndClampsAtTheEnds() throws {
        let pager = ClassicalPager()
        pager.show(try records(80), geometry: geometry, scale: 1, rightToLeft: false) { _, _ in throw CancellationError() }
        pager.swipe(deltaX: -1)
        XCTAssertEqual(pager.currentPage, 0, "A swipe right (−1) goes back; there is no page before the first")
        pager.swipe(deltaX: 1)
        XCTAssertEqual(pager.currentPage, 1, "A swipe left (+1) goes forward, like navigation type 0")
        pager.swipe(deltaX: 0, deltaY: -1)
        XCTAssertEqual(pager.currentPage, 0, "A swipe down goes back, like navigation type 3")
    }

    func testIconsLoadForTheCurrentPageAndItsNeighboursOnly() async throws {
        let pager = ClassicalPager()
        var requested: Set<String> = []
        let image = try pixel()
        pager.show(try records(140), geometry: geometry, scale: 1, rightToLeft: false) { record, _ in
            requested.insert(record.metadata.displayName)
            return image
        }
        XCTAssertEqual(pager.pages.map(\.loadsIcons), [true, true, false, false])
        try await waitUntil { requested.count == 70 }
        pager.settle(on: 2)
        XCTAssertEqual(pager.pages.map(\.loadsIcons), [true, true, true, true])
    }

    // MARK: Helpers

    /// Solves the cubic Bézier timing function for `time` (x) and returns its progress (y).
    private static func evaluate(_ function: CAMediaTimingFunction, at time: Double) -> Double {
        var c1: [Float] = [0, 0], c2: [Float] = [0, 0]
        function.getControlPoint(at: 1, values: &c1)
        function.getControlPoint(at: 2, values: &c2)
        func bezier(_ t: Double, _ p1: Float, _ p2: Float) -> Double {
            let u = 1 - t
            return 3 * u * u * t * Double(p1) + 3 * u * t * t * Double(p2) + t * t * t
        }
        var low = 0.0, high = 1.0
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if bezier(mid, c1[0], c2[0]) < time { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, c1[1], c2[1])
    }

    /// A mirror layer takes the strip's scroll as a translation on every scroll, and the settle
    /// animates both over the same time, so glass in the mirror moves with its page.
    func testStripMirrorFollowsEveryScrollAndTheSettleAnimation() throws {
        let pager = ClassicalPager()
        pager.show(try records(80), geometry: geometry, scale: 1, rightToLeft: false) { _, _ in throw CancellationError() }
        pager.jump(to: 1)
        let mirror = CALayer()
        pager.stripMirror = mirror
        func mirrored() -> CGFloat { mirror.sublayerTransform.m41 }
        XCTAssertEqual(mirrored(), -1470, "A new mirror starts at the current scroll")

        pager.jump(to: 2)
        XCTAssertEqual(mirrored(), -pager.stripLayer.bounds.origin.x)
        XCTAssertEqual(mirrored(), -2 * 1470)

        pager.settle(on: 0)
        XCTAssertEqual(mirrored(), 0)
        let strip = try XCTUnwrap(pager.stripLayer.animation(forKey: ClassicalPager.settleAnimationKey) as? CABasicAnimation)
        let follower = try XCTUnwrap(mirror.animation(forKey: ClassicalPager.settleAnimationKey) as? CABasicAnimation)
        XCTAssertEqual(follower.keyPath, "sublayerTransform.translation.x")
        XCTAssertEqual((follower.fromValue as? NSNumber)?.doubleValue ?? .nan,
                       -((strip.fromValue as? NSNumber)?.doubleValue ?? .nan))
        XCTAssertEqual(follower.duration, strip.duration)
        XCTAssertEqual(follower.beginTime, strip.beginTime)
        var stripPoints = [Float](repeating: 0, count: 2), followerPoints = [Float](repeating: 0, count: 2)
        for index in 1...2 {
            strip.timingFunction?.getControlPoint(at: index, values: &stripPoints)
            follower.timingFunction?.getControlPoint(at: index, values: &followerPoints)
            XCTAssertEqual(stripPoints, followerPoints, "Control point \(index)")
        }

        pager.cancelInteraction()
        XCTAssertNil(mirror.animation(forKey: ClassicalPager.settleAnimationKey), "Both settles stop together")
        pager.stripMirror = nil
        pager.jump(to: 1)
        XCTAssertEqual(mirrored(), 0, "A released mirror no longer follows")
    }

    private func records(_ count: Int) throws -> [AppRecord] {
        try (0..<count).map { index in
            let name = String(format: "App %03d", index)
            let url = URL(filePath: "/Applications/\(name).app", directoryHint: .isDirectory)
            return AppRecord(
                id: AppIdentity(),
                metadata: try AppMetadata(bundleIdentifier: "com.example.\(UUID().uuidString)", bundleURL: url,
                                          displayName: name, version: nil, buildVersion: nil, contentModificationDate: nil),
                source: try AppSource(kind: .custom, directoryURL: url.deletingLastPathComponent())
            )
        }
    }

    private func pixel() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out.")
    }
}
