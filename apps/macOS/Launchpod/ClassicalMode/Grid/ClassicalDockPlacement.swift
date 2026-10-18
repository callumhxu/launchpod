import AppKit

extension ClassicalSpringboardGeometry.DockPlacement {
    /// The Dock's reserve on `screen`, the Dock's display (`ClassicalDockDisplay`). A shown Dock is
    /// measured from the host's public visible-frame inset on its side (the top inset belongs to the menu bar).
    /// An auto-hidden Dock reserves its revealed thickness. A covered Dock reserves nothing. The shown Dock
    /// uses the host inset so a newer, physically larger Dock is not overlapped by the Classical content.
    /// `revealed` is the Dock as measured before a temporary reveal; while the reveal takes effect the visible
    /// frame may still lack the Dock's inset.
    @MainActor init(screen: NSScreen, hidesDock: Bool, revealed: ClassicalDockMetrics? = nil) {
        self.init(frame: screen.frame, visibleFrame: screen.visibleFrame, hidesDock: hidesDock,
                  dock: revealed ?? ClassicalDockMetrics.current())
    }

    init(frame: CGRect, visibleFrame: CGRect, hidesDock: Bool, dock: ClassicalDockMetrics? = nil) {
        let bottom = visibleFrame.minY - frame.minY
        let left = visibleFrame.minX - frame.minX
        let right = frame.maxX - visibleFrame.maxX
        if hidesDock {
            self = .hidden
        } else if left > 0 {
            self = .left(extent: left)
        } else if right > 0 {
            self = .right(extent: right)
        } else if bottom > 0 {
            self = .bottom(extent: bottom)
        } else if let dock, dock.autoHides {
            switch dock.edge {
            case .bottom: self = .bottom(extent: dock.revealedThickness)
            case .left: self = .left(extent: dock.revealedThickness)
            case .right: self = .right(extent: dock.revealedThickness)
            }
        } else {
            self = .hidden
        }
    }
}
