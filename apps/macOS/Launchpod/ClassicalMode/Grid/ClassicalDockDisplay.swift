import AppKit

/// Chooses the display for the Classical launcher: it shows on the display the Dock is on and
/// re-lays out when that changes.
enum ClassicalDockDisplay {
    /// A frame whose visible frame reserves the Dock is the Dock's display. Otherwise (auto-hide) the
    /// Dock's reported rectangle, which keeps its position with zero height, locates it.
    /// The Dock's display when a Dock signal identifies one; nil when it cannot be determined.
    @MainActor static func dockScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let frames = screens.map { (frame: $0.frame, visibleFrame: $0.visibleFrame) }
        return index(of: frames, dockRect: reportedDockRect(), dockEdge: ClassicalDockMetrics.current()?.edge)
            .map { screens[$0] }
    }

    static func index(of screens: [(frame: CGRect, visibleFrame: CGRect)], dockRect: CGRect?,
                      dockEdge: ClassicalDockMetrics.Edge?) -> Int? {
        if let reserved = screens.firstIndex(where: { reservesDock($0.frame, $0.visibleFrame) }) {
            return reserved
        }
        guard let dockRect, let first = screens.first else { return nil }
        // Global Dock coordinates are top-left based on the first screen; convert to Cocoa (bottom-left).
        let bottom = first.frame.maxY - dockRect.maxY
        let point: CGPoint
        switch dockEdge ?? .bottom {
        case .bottom: point = CGPoint(x: dockRect.midX, y: bottom + 1)
        case .left: point = CGPoint(x: dockRect.minX + 1, y: bottom + dockRect.height / 2)
        case .right: point = CGPoint(x: dockRect.maxX - 1, y: bottom + dockRect.height / 2)
        }
        return screens.firstIndex { $0.frame.contains(point) }
    }

    static func reservesDock(_ frame: CGRect, _ visibleFrame: CGRect) -> Bool {
        visibleFrame.minY > frame.minY || visibleFrame.minX > frame.minX || visibleFrame.maxX < frame.maxX
    }

    /// The Dock bar's exact hit rectangle while shown. An auto-hidden Dock reports a collapsed
    /// rectangle, so only its first physical edge pixel starts the public dragging session.
    @MainActor static func dragHandoffFrame(on screen: NSScreen) -> CGRect? {
        guard let reported = reportedDockRect(), let primary = NSScreen.screens.first,
              let metrics = ClassicalDockMetrics.current() else { return nil }
        return dragHandoffFrame(screenFrame: screen.frame, desktopTop: primary.frame.maxY,
                                reportedDockRect: reported, edge: metrics.edge,
                                pixel: 1 / screen.backingScaleFactor)
    }

    static func dragHandoffFrame(screenFrame: CGRect, desktopTop: CGFloat, reportedDockRect: CGRect,
                                 edge: ClassicalDockMetrics.Edge, pixel: CGFloat) -> CGRect? {
        var frame = CGRect(x: reportedDockRect.minX,
                           y: desktopTop - reportedDockRect.maxY,
                           width: reportedDockRect.width,
                           height: reportedDockRect.height)
        let pixel = max(pixel, 0)
        if frame.width == 0 || frame.height == 0 {
            switch edge {
            case .bottom:
                guard frame.width > 0, pixel > 0 else { return nil }
                frame.origin.y = screenFrame.minY
                frame.size.height = pixel
            case .left:
                guard frame.height > 0, pixel > 0 else { return nil }
                frame.origin.x = screenFrame.minX
                frame.size.width = pixel
            case .right:
                guard frame.height > 0, pixel > 0 else { return nil }
                frame.origin.x = screenFrame.maxX - pixel
                frame.size.width = pixel
            }
        }
        let hit = frame.intersection(screenFrame)
        return hit.isNull || hit.isEmpty ? nil : hit
    }

    private static func reportedDockRect() -> CGRect? {
        guard let functions = CoreDockFunctions.shared else { return nil }
        var rect = CGRect.zero
        functions.rect(&rect)
        // A hidden Dock collapses its thickness to zero but keeps its extent along the edge.
        return rect.width > 0 || rect.height > 0 ? rect : nil
    }
}

extension NSScreen {
    /// The Core Graphics display number that identifies this screen across screen-list changes.
    var displayNumber: NSNumber? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }
}
