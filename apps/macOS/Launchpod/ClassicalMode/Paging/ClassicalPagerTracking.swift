import CoreGraphics
import Foundation

/// Page-selection rules of the Classical pager.
///
/// `scrollValue` is the horizontal offset of the page strip in points; resting on visual page `v`
/// means `v × pageWidth`. Logical pages are mirrored for right-to-left layouts. The type holds no
/// layers or timers, so every rule is testable in isolation.
struct ClassicalPagerTracking: Equatable {
    /// Horizontal travel that turns a press into a drag.
    static var dragActivation: CGFloat { ClassicalAnimationParameters.Paging.dragActivation }
    /// Release speed above which one page turns: the Dock compares `distance / Δns × 10⁷ > 2`,
    /// with nanosecond event timestamps, i.e. 200 pt/s.
    static var flickSpeed: CGFloat { ClassicalAnimationParameters.Paging.flickSpeed }
    /// Share of travel kept beyond the first and last pages.
    static var overscrollFactor: CGFloat { ClassicalAnimationParameters.Paging.overscrollFactor }
    /// Wheel events multiply their dominant axis by 2.
    static var wheelDeltaScale: CGFloat { ClassicalAnimationParameters.Paging.wheelDeltaScale }
    /// Idle time after the last wheel event before the pager settles; five times longer with Shift.
    static var wheelSettleDelay: TimeInterval { ClassicalAnimationParameters.Paging.wheelSettleDelay }
    static var slowWheelSettleDelay: TimeInterval { ClassicalAnimationParameters.Paging.slowWheelSettleDelay }

    var pageCount: Int
    var pageWidth: CGFloat
    var rightToLeft: Bool
    /// The logical page the pager rests on; it changes only when a gesture settles.
    private(set) var currentPage: Int
    private(set) var scrollValue: CGFloat
    /// True between a trackpad gesture's begin and end phases.
    private(set) var isTrackingGesture = false
    /// True while wheel travel waits for the idle settle.
    private(set) var isAccumulatingWheel = false
    private(set) var isDragging = false

    private var startScroll: CGFloat = 0
    private var startLocation: CGPoint = .zero
    private var startTime: TimeInterval = 0
    private var wheelTravel: CGFloat = 0

    init(pageCount: Int, pageWidth: CGFloat, rightToLeft: Bool = false, currentPage: Int = 0) {
        self.pageCount = max(pageCount, 1)
        self.pageWidth = pageWidth
        self.rightToLeft = rightToLeft
        let page = min(max(currentPage, 0), max(pageCount, 1) - 1)
        self.currentPage = page
        scrollValue = 0
        scrollValue = restingScroll(for: page)
    }

    func visualIndex(of page: Int) -> Int {
        rightToLeft ? pageCount - 1 - page : page
    }

    func restingScroll(for page: Int) -> CGFloat {
        CGFloat(visualIndex(of: page)) * pageWidth
    }

    /// Travel beyond either end keeps a quarter of its distance.
    func damped(_ raw: CGFloat) -> CGFloat {
        let last = CGFloat(pageCount - 1) * pageWidth
        if raw < 0 { return raw * Self.overscrollFactor }
        if raw > last { return last + (raw - last) * Self.overscrollFactor }
        return raw
    }

    // MARK: Mouse

    mutating func mouseDown(at location: CGPoint, time: TimeInterval) {
        startScroll = scrollValue
        startLocation = location
        startTime = time
        isDragging = false
    }

    /// Returns true when the strip follows the pointer.
    mutating func mouseDragged(to location: CGPoint) -> Bool {
        if !isDragging, abs(startLocation.x - location.x) >= Self.dragActivation {
            isDragging = true
        }
        guard isDragging else { return false }
        scrollValue = damped(startScroll + (startLocation.x - location.x))
        return true
    }

    /// The page to settle on, or nil when the press never became a drag.
    mutating func mouseUp(at location: CGPoint, time: TimeInterval) -> Int? {
        guard isDragging else { return nil }
        isDragging = false
        let distance = hypot(location.x - startLocation.x, location.y - startLocation.y)
        return settle(speed: speed(distance, since: startTime, at: time))
    }

    // MARK: Trackpad gesture and wheel

    mutating func beginGesture(at location: CGPoint, time: TimeInterval) {
        isTrackingGesture = true
        isAccumulatingWheel = false
        beginTravel(at: location, time: time)
    }

    /// The page to settle on when a trackpad gesture ends: by the speed of the strip's travel.
    mutating func endGesture(at time: TimeInterval) -> Int {
        isTrackingGesture = false
        isAccumulatingWheel = false
        return settle(speed: speed(abs(scrollValue - startScroll), since: startTime, at: time))
    }

    /// Applies a non-momentum wheel delta (already scaled and direction-adjusted); outside a gesture
    /// the caller schedules `settleWheel()` after the idle delay.
    mutating func scroll(by travel: CGFloat, at location: CGPoint, time: TimeInterval) {
        if !isTrackingGesture, !isAccumulatingWheel {
            isAccumulatingWheel = true
            beginTravel(at: location, time: time)
        }
        wheelTravel += travel
        scrollValue = damped(startScroll + wheelTravel)
    }

    /// Abandons wheel or trackpad travel in progress; the caller returns the strip to `currentPage`.
    mutating func cancelTravel() {
        isTrackingGesture = false
        isAccumulatingWheel = false
    }

    /// Wheel travel settles by direction alone, without a distance threshold.
    mutating func settleWheel() -> Int {
        isAccumulatingWheel = false
        return settleOnePage()
    }

    /// The strip's travel for a wheel event: twice the dominant axis, reversed by the
    /// `springboard-reverse-scroll-gesture` preference (on by default).
    static func wheelTravel(deltaX: CGFloat, deltaY: CGFloat, reversed: Bool = true) -> CGFloat {
        let dominant = abs(deltaX) > abs(deltaY) ? deltaX : deltaY
        let travel = dominant * wheelDeltaScale
        return reversed ? -travel : travel
    }

    // MARK: Settling

    /// Records a settled page (a page-dot click or the end of a gesture) and returns its resting scroll.
    @discardableResult
    mutating func select(_ page: Int) -> CGFloat {
        currentPage = min(max(page, 0), pageCount - 1)
        scrollValue = restingScroll(for: currentPage)
        return scrollValue
    }

    private mutating func beginTravel(at location: CGPoint, time: TimeInterval) {
        startScroll = scrollValue
        startLocation = location
        startTime = time
        wheelTravel = 0
    }

    private func speed(_ distance: CGFloat, since start: TimeInterval, at time: TimeInterval) -> CGFloat {
        let elapsed = time - start
        guard elapsed > 0 else { return distance > 0 ? .infinity : 0 }
        return distance / CGFloat(elapsed)
    }

    private func settle(speed: CGFloat) -> Int {
        speed > Self.flickSpeed ? settleOnePage() : currentPage
    }

    /// Past the leading edge: the first visual page. Otherwise one page in the travel direction.
    /// The Dock lets a left-to-right result of −1 wrap to the last page; only exactly zero net travel
    /// reaches that case, and it is clamped to page 0 here.
    private func settleOnePage() -> Int {
        if scrollValue < 0 { return rightToLeft ? pageCount - 1 : 0 }
        let forward = scrollValue > startScroll
        let step = forward != rightToLeft ? 1 : -1
        return min(max(currentPage + step, 0), pageCount - 1)
    }
}
