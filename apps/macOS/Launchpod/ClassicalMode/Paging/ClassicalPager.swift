import AppKit
import QuartzCore

/// The horizontal page strip with its page dots.
///
/// On the root pages the pager layer fills the content frame and clips, as does the strip above the
/// bottom margin, and pages sit one screen width apart; an open folder lays the same pager out in
/// its panel (`ClassicalPagerLayout`). The strip moves by the tracking's scroll value without
/// animation while dragged. Settling is an implicit transaction: 0.5 s with the
/// `(0, 0, 0.35841, 1.0019)` curve from the drawn position toward the model value, so travel that
/// starts during a settle is followed by the running animation. Shift also slows the wheel timer;
/// the Dock's 5 s settle needs its hidden `slow-motion-allowed` preference. Icons load for the
/// current page and its neighbours.
@MainActor
final class ClassicalPager {
    static var settleDuration: TimeInterval { ClassicalAnimationParameters.Paging.settleDuration }
    static var slowSettleDuration: TimeInterval { ClassicalAnimationParameters.Paging.slowSettleDuration }
    static var settleTiming: CAMediaTimingFunction { ClassicalAnimationParameters.Paging.settleTiming }
    static let settleAnimationKey = "classicalPagerSettle"

    let layer = CALayer()
    let stripLayer = CALayer()
    let dotsLayer = ClassicalPageDotsLayer()
    private(set) var pages: [ClassicalGridPage] = []
    private(set) var tracking = ClassicalPagerTracking(pageCount: 1, pageWidth: 0)
    private var scale: CGFloat = 1
    private var wheelSettle: Task<Void, Never>?
    /// Called before the current page changes.
    var pageWillChange: (@MainActor () -> Void)?
    /// Replaceable in tests: whether Shift is held, which lengthens the wheel settle delay.
    var shiftKeyDown: @MainActor () -> Bool = { NSEvent.modifierFlags.contains(.shift) }
    var slowMotionAllowed: @MainActor () -> Bool = {
        UserDefaults(suiteName: "com.apple.dock").map(ClassicalAnimationParameters.slowMotionAllowed(in:)) ?? false
    }
    /// A layer that scrolls with the strip: its `sublayerTransform` is the strip's scroll as an x
    /// translation, set in the same transaction as the strip and animated by the same settle.
    weak var stripMirror: CALayer? {
        didSet { withoutActions { mirrorScroll() } }
    }
    /// Whether folder cells on the pages use the glass appearance; applies to cells made by later
    /// calls to `show`.
    var folderGlassEnabled = false
    /// Replaceable in tests: the delay before undirected wheel travel settles.
    var wheelSettleSleep: @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }

    init() {
        layer.addSublayer(stripLayer)
        layer.addSublayer(dotsLayer)
    }

    isolated deinit {
        wheelSettle?.cancel()
    }

    var currentPage: Int { tracking.currentPage }
    var pageCount: Int { tracking.pageCount }

    /// Lays `records` out as full pages for `geometry`, keeping the current page when it still exists.
    func show(_ records: [AppRecord], geometry: ClassicalSpringboardGeometry, scale: CGFloat, rightToLeft: Bool,
              icon: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage,
              cachedIcon: @MainActor (AppRecord, AppIconSize) -> CGImage? = { _, _ in nil }, animatesMoves: Bool = false) {
        show(pages: Self.chunk(records.map(ClassicalPageItem.app), capacity: geometry.grid.capacity), geometry: geometry,
             scale: scale, rightToLeft: rightToLeft, icon: icon, cachedIcon: cachedIcon, animatesMoves: animatesMoves)
    }

    /// `items` in consecutive full pages; at least one, possibly empty, page.
    static func chunk<Item>(_ items: [Item], capacity: Int) -> [[Item]] {
        let capacity = max(capacity, 1)
        return stride(from: 0, to: max(items.count, 1), by: capacity).map {
            Array(items[min($0, items.count)..<min($0 + capacity, items.count)])
        }
    }

    /// Lays the root `pages` out for `geometry`; see `show(pages:layout:scale:rightToLeft:icon:cachedIcon:animatesMoves:detached:)`.
    func show(pages contents: [[ClassicalPageItem]], geometry: ClassicalSpringboardGeometry, scale: CGFloat, rightToLeft: Bool,
              icon: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage,
              cachedIcon: @MainActor (AppRecord, AppIconSize) -> CGImage? = { _, _ in nil }, animatesMoves: Bool = false,
              detached: (id: ClassicalPageItem.ID, cell: ClassicalItemLayer)? = nil) {
        show(pages: contents, layout: ClassicalPagerLayout(geometry: geometry), scale: scale, rightToLeft: rightToLeft,
             icon: icon, cachedIcon: cachedIcon, animatesMoves: animatesMoves, detached: detached)
    }

    /// Lays `pages` out in `layout`, keeping the current page when it still exists. With
    /// `animatesMoves`, cells that stay on their page slide to new slots and a running settle
    /// continues; `detached` is a cell held outside the pages, such as the one being dragged, whose
    /// slot stays empty.
    func show(pages contents: [[ClassicalPageItem]], layout: ClassicalPagerLayout, scale: CGFloat, rightToLeft: Bool,
              icon: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage,
              cachedIcon: @MainActor (AppRecord, AppIconSize) -> CGImage? = { _, _ in nil }, animatesMoves: Bool = false,
              detached: (id: ClassicalPageItem.ID, cell: ClassicalItemLayer)? = nil) {
        if animatesMoves {
            wheelSettle?.cancel()
            wheelSettle = nil
        } else {
            cancelInteraction()
        }
        self.scale = scale
        let chunks = contents.isEmpty ? [[]] : contents
        let width = layout.pageWidth
        tracking = ClassicalPagerTracking(pageCount: chunks.count, pageWidth: width, rightToLeft: rightToLeft,
                                          currentPage: tracking.currentPage)
        withoutActions {
            layer.frame = layout.frame
            layer.masksToBounds = layout.clipsToBounds
            stripLayer.frame = layout.stripFrame
            stripLayer.masksToBounds = layout.clipsToBounds
            dotsLayer.frame = layout.dotsFrame
            while pages.count > chunks.count { pages.removeLast().layer.removeFromSuperlayer() }
            while pages.count < chunks.count {
                let page = ClassicalGridPage()
                stripLayer.addSublayer(page.layer)
                pages.append(page)
            }
            for (index, (page, chunk)) in zip(pages, chunks).enumerated() {
                let offset = CGFloat(tracking.visualIndex(of: index)) * width
                page.folderGlassEnabled = folderGlassEnabled
                page.show(chunk, grid: layout.grid, frame: layout.firstPageFrame.offsetBy(dx: offset, dy: 0), scale: scale,
                          rightToLeft: rightToLeft, icon: icon, cachedIcon: cachedIcon,
                          animatesMoves: animatesMoves, detached: detached)
            }
            setScroll(tracking.scrollValue)
        }
        updateDots()
        loadNearbyIcons()
    }

    func cancelIconLoads() {
        pages.forEach { $0.cancelIconLoads() }
    }

    /// Stops a pending wheel settle and any settle animation.
    func cancelInteraction() {
        wheelSettle?.cancel()
        wheelSettle = nil
        stripLayer.removeAnimation(forKey: Self.settleAnimationKey)
        stripMirror?.removeAnimation(forKey: Self.settleAnimationKey)
    }

    // MARK: Cells

    /// The cell showing item `id` on any page.
    func cell(for id: ClassicalPageItem.ID) -> ClassicalItemLayer? {
        for page in pages {
            if let index = page.items.firstIndex(where: { $0.id == id }), page.itemLayers.indices.contains(index) {
                return page.itemLayers[index]
            }
        }
        return nil
    }

    /// The page holding item `id`.
    func pageIndex(of id: ClassicalPageItem.ID) -> Int? {
        pages.firstIndex { $0.items.contains { $0.id == id } }
    }

    /// The item, other than those `excluded`, whose icon is under `point` (coordinates of the root
    /// layer above the pager) on a visible page. Presentation layers track icons during page
    /// settling and entry scaling.
    func item(at point: CGPoint, excluding excluded: Set<ClassicalPageItem.ID> = [])
        -> (item: ClassicalPageItem, cell: ClassicalItemLayer)? {
        // The event point is in the view's layer; its presentation ancestors include entry scaling.
        var host = layer
        while let parent = host.superlayer { host = parent }
        // A detached pager has no content-layer ancestor, so convert the view point into its bounds.
        let hitPoint = host === layer
            ? CGPoint(x: point.x - layer.frame.minX, y: point.y - layer.frame.minY) : point
        let presentedHost = host.presentation()
        let presentedPager = layer.presentation()
        let hitHost: CALayer
        let hitPager: CALayer
        if let presentedHost, let presentedPager {
            hitHost = presentedHost
            hitPager = presentedPager
        } else {
            hitHost = host
            hitPager = layer
        }
        guard hitPager.bounds.contains(hitPager.convert(hitPoint, from: hitHost)) else { return nil }
        for page in pages {
            for (item, cell) in zip(page.items, page.itemLayers) where !excluded.contains(item.id) {
                let icon: CALayer
                let hitLayer: CALayer
                if let presentedHost, let presentedIcon = cell.iconLayer.presentation() {
                    icon = presentedIcon
                    hitLayer = presentedHost
                } else {
                    icon = cell.iconLayer
                    hitLayer = host
                }
                if icon.bounds.contains(icon.convert(hitPoint, from: hitLayer)) { return (item, cell) }
            }
        }
        return nil
    }

    /// The item, other than those `excluded`, whose delete badge is under `point` (coordinates of
    /// the layer holding the pager) on the current page.
    func closebox(at point: CGPoint, excluding excluded: Set<ClassicalPageItem.ID> = [])
        -> (item: ClassicalPageItem, cell: ClassicalItemLayer)? {
        guard pages.indices.contains(currentPage) else { return nil }
        let page = pages[currentPage]
        let local = CGPoint(x: point.x - layer.frame.minX, y: point.y - layer.frame.minY)
        return zip(page.items, page.itemLayers).first { item, cell in
            !excluded.contains(item.id) && item.record != nil
                && cell.closeboxContains(cell.jitterLayer.convert(local, from: layer))
        }
    }

    // MARK: Events (coordinates of the layer holding the pager, which for the root pages is the root
    // layer; event timestamps in seconds)

    /// Returns true when the press is taken by the page dots rather than the strip.
    func mouseDown(at point: CGPoint, time: TimeInterval) -> Bool {
        if !dotsLayer.isHidden, dotsLayer.frame.contains(local(point)) { return true }
        tracking.mouseDown(at: point, time: time)
        return false
    }

    func mouseDragged(to point: CGPoint) {
        guard tracking.mouseDragged(to: point) else { return }
        placeStrip()
    }

    /// Returns true when the release ended a drag.
    func mouseUp(at point: CGPoint, time: TimeInterval) -> Bool {
        guard let page = tracking.mouseUp(at: point, time: time) else { return false }
        settle(on: page)
        return true
    }

    /// A release on the page dots: an indicator under the pointer selects its page.
    func dotsMouseUp(at point: CGPoint) {
        let inDots = dotsLayer.convert(local(point), from: layer)
        guard let page = dotsLayer.layout.page(at: inDots) else { return }
        settle(on: page)
    }

    /// A scroll-wheel or trackpad scroll event. Momentum is ignored.
    func scrollWheel(deltaX: CGFloat, deltaY: CGFloat, phase: NSEvent.Phase, momentumPhase: NSEvent.Phase,
                     at point: CGPoint, time: TimeInterval) {
        guard momentumPhase.isEmpty else { return }
        if phase.contains(.began) {
            wheelSettle?.cancel()
            tracking.beginGesture(at: point, time: time)
        }
        if deltaX != 0 || deltaY != 0 {
            tracking.scroll(by: ClassicalPagerTracking.wheelTravel(deltaX: deltaX, deltaY: deltaY), at: point, time: time)
            placeStrip()
            if !tracking.isTrackingGesture { scheduleWheelSettle() }
        }
        if tracking.isTrackingGesture, phase.contains(.ended) || phase.contains(.cancelled) {
            settle(on: tracking.endGesture(at: time))
        }
    }

    /// Ends wheel or trackpad travel still in progress by returning to the current page, so a pending
    /// wheel settle cannot turn the page while an icon is held.
    func endScrolling() {
        guard tracking.isAccumulatingWheel || tracking.isTrackingGesture else { return }
        tracking.cancelTravel()
        settle(on: tracking.currentPage)
    }

    /// A navigation swipe turns one page:
    /// navigation types 0 and 2 go forward, 1 and 3 back, mirrored right-to-left. `NSEvent` reports a
    /// swipe left or up as +1 and right or down as −1.
    func swipe(deltaX: CGFloat, deltaY: CGFloat = 0) {
        let delta = deltaX != 0 ? deltaX : deltaY
        guard delta != 0 else { return }
        let forward = (delta > 0) != tracking.rightToLeft
        settle(on: tracking.currentPage + (forward ? 1 : -1))
    }

    // MARK: Settling

    /// Moves to `page` without animation, as filtering and clearing a search do.
    func jump(to page: Int) {
        cancelInteraction()
        notifyIfPageChanges(to: page)
        let target = tracking.select(page)
        withoutActions { setScroll(target) }
        updateDots()
        loadNearbyIcons()
    }

    /// Selects `page` (clamped) and animates the strip to it from where it is drawn. Like an implicit
    /// action, the animation has no `toValue`: it ends at whatever the model value is, so a drag that
    /// begins during the settle moves the model and the animation follows it.
    func settle(on page: Int) {
        wheelSettle?.cancel()
        wheelSettle = nil
        let from = presentedScroll()
        notifyIfPageChanges(to: page)
        let target = tracking.select(page)
        stripLayer.removeAnimation(forKey: Self.settleAnimationKey)
        stripMirror?.removeAnimation(forKey: Self.settleAnimationKey)
        withoutActions { setScroll(target) }
        updateDots()
        loadNearbyIcons()
        guard from != target else { return }
        let animation = CABasicAnimation(keyPath: "bounds.origin.x")
        animation.fromValue = from
        animation.duration = slowMotionAllowed() && shiftKeyDown() ? Self.slowSettleDuration : Self.settleDuration
        animation.timingFunction = Self.settleTiming
        let mirrored = CABasicAnimation(keyPath: "sublayerTransform.translation.x")
        mirrored.fromValue = -from
        mirrored.duration = animation.duration
        mirrored.timingFunction = animation.timingFunction
        // One transaction, so both animations start at the same render time.
        CATransaction.begin()
        stripLayer.add(animation, forKey: Self.settleAnimationKey)
        stripMirror?.add(mirrored, forKey: Self.settleAnimationKey)
        CATransaction.commit()
    }

    private func notifyIfPageChanges(to page: Int) {
        let clamped = min(max(page, 0), tracking.pageCount - 1)
        if clamped != tracking.currentPage { pageWillChange?() }
    }

    private func scheduleWheelSettle() {
        wheelSettle?.cancel()
        let delay = shiftKeyDown() ? ClassicalPagerTracking.slowWheelSettleDelay : ClassicalPagerTracking.wheelSettleDelay
        wheelSettle = Task { [weak self, wheelSettleSleep] in
            do { try await wheelSettleSleep(delay) } catch { return }
            guard let self, !Task.isCancelled, tracking.isAccumulatingWheel else { return }
            settle(on: tracking.settleWheel())
        }
    }

    /// A point in the holding layer's coordinates, in the pager layer's coordinates.
    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - layer.frame.minX, y: point.y - layer.frame.minY)
    }

    private func presentedScroll() -> CGFloat {
        guard stripLayer.animation(forKey: Self.settleAnimationKey) != nil,
              let presented = stripLayer.presentation() else { return tracking.scrollValue }
        return presented.bounds.origin.x
    }

    private func placeStrip() {
        withoutActions { setScroll(tracking.scrollValue) }
        loadVisibleIcons()
    }

    private func setScroll(_ scroll: CGFloat) {
        stripLayer.bounds.origin.x = scroll
        mirrorScroll()
    }

    private func mirrorScroll() {
        stripMirror?.sublayerTransform = CATransform3DMakeTranslation(-stripLayer.bounds.origin.x, 0, 0)
    }

    private func updateDots() {
        dotsLayer.update(ClassicalPageDotsLayout(pageCount: tracking.pageCount, width: dotsLayer.bounds.width,
                                                 rightToLeft: tracking.rightToLeft),
                         currentPage: tracking.currentPage, scale: scale)
    }

    private func loadNearbyIcons() {
        guard !pages.isEmpty else { return }
        let current = tracking.currentPage
        for index in max(current - 1, 0)...min(current + 1, pages.count - 1) { pages[index].loadIcons() }
    }

    /// Pages the strip currently overlaps, for travel past the preloaded neighbours.
    private func loadVisibleIcons() {
        guard tracking.pageWidth > 0 else { return }
        let first = Int((tracking.scrollValue / tracking.pageWidth).rounded(.down))
        for visual in [first, first + 1] where (0..<pages.count).contains(visual) {
            pages[tracking.rightToLeft ? pages.count - 1 - visual : visual].loadIcons()
        }
    }

    private func withoutActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
