import CoreGraphics
import Darwin

/// The Dock's configuration as the Dock reports it, including while it auto-hides.
///
/// An auto-hidden Dock reserves no visible-frame inset and reports a zero-height rectangle, so its
/// revealed thickness has to be derived from its tile size the way the Dock derives it.
struct ClassicalDockMetrics: Equatable, Sendable {
    enum Edge: Equatable, Sendable {
        case bottom, left, right
    }

    /// Dock icon size in points (16…128).
    let tileSize: CGFloat
    let edge: Edge
    let autoHides: Bool

    static let tileSizeRange: ClosedRange<CGFloat> = 16...128
    /// The Classical Dock reserve when the host Dock is auto-hidden.
    var revealedThickness: CGFloat {
        let tile = min(max(tileSize, Self.tileSizeRange.lowerBound), Self.tileSizeRange.upperBound)
        let inset: CGFloat
        let bottom: CGFloat
        let topBase: CGFloat
        if tile > 127 {
            (inset, bottom, topBase) = (3, 10, 6)
        } else if tile > 47 {
            (inset, bottom, topBase) = (2, 10, 5)
        } else if tile > 23 {
            (inset, bottom, topBase) = (1, 7, 4)
        } else {
            (inset, bottom, topBase) = (1, 7, 3)
        }
        let top = topBase - 2 * inset
        let barTile = tile + 2 * inset
        return (barTile + top + bottom).rounded(.up)
    }
}

extension ClassicalDockMetrics {
    /// Reads the Dock through the CoreDock functions exported by HIServices. These are not public API;
    /// nil when any of them is unavailable.
    static func current() -> ClassicalDockMetrics? {
        guard let functions = CoreDockFunctions.shared else { return nil }
        var orientation: Int32 = 0
        var pinning: Int32 = 0
        functions.orientationAndPinning(&orientation, &pinning)
        let edge: Edge
        switch orientation {
        case 3: edge = .left
        case 4: edge = .right
        default: edge = .bottom
        }
        let normalized = CGFloat(functions.tileSize())
        guard normalized.isFinite else { return nil }
        let span = tileSizeRange.upperBound - tileSizeRange.lowerBound
        return ClassicalDockMetrics(tileSize: (tileSizeRange.lowerBound + normalized * span).rounded(),
                                    edge: edge, autoHides: functions.autoHideEnabled())
    }
}

nonisolated struct CoreDockFunctions: @unchecked Sendable {
    typealias TileSize = @convention(c) () -> Float
    typealias OrientationAndPinning = @convention(c) (UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Void
    typealias AutoHideEnabled = @convention(c) () -> Bool
    typealias SetAutoHideEnabled = @convention(c) (Bool) -> Void
    typealias GetRect = @convention(c) (UnsafeMutablePointer<CGRect>) -> Void

    let tileSize: TileSize
    let orientationAndPinning: OrientationAndPinning
    let autoHideEnabled: AutoHideEnabled
    /// Persists the user's `com.apple.dock` `autohide` preference, not only the running state.
    let setAutoHideEnabled: SetAutoHideEnabled
    /// The Dock's rectangle in global top-left coordinates; zero height while auto-hidden.
    let rect: GetRect

    static let shared: CoreDockFunctions? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let tile = dlsym(handle, "CoreDockGetTileSize"),
              let orientation = dlsym(handle, "CoreDockGetOrientationAndPinning"),
              let autoHide = dlsym(handle, "CoreDockGetAutoHideEnabled"),
              let setAutoHide = dlsym(handle, "CoreDockSetAutoHideEnabled"),
              let rect = dlsym(handle, "CoreDockGetRect") else { return nil }
        return CoreDockFunctions(tileSize: unsafeBitCast(tile, to: TileSize.self),
                                 orientationAndPinning: unsafeBitCast(orientation, to: OrientationAndPinning.self),
                                 autoHideEnabled: unsafeBitCast(autoHide, to: AutoHideEnabled.self),
                                 setAutoHideEnabled: unsafeBitCast(setAutoHide, to: SetAutoHideEnabled.self),
                                 rect: unsafeBitCast(rect, to: GetRect.self))
    }()
}
