import Foundation
import QuartzCore

/// Timing, distance and magnification of dragging a Classical item.
nonisolated enum ClassicalDragParameters {
    /// Pointer travel on either axis, still over the pressed icon, that turns a press into a drag.
    static var activationDistance: CGFloat { ClassicalAnimationParameters.Drag.activationDistance }

    /// Pointer speed is measured as points per nanosecond scaled by `speedScale`; below `restSpeed`
    /// (75 pt/s when event times are in seconds) the new drag state is evaluated at once.
    static var speedScale: Double { ClassicalAnimationParameters.Drag.speedScale }
    static var restSpeed: Double { ClassicalAnimationParameters.Drag.restSpeed }
    /// Faster moves evaluate the drag state once the pointer rests this long (Shift: `slowRestDelay`).
    static var restDelay: TimeInterval { ClassicalAnimationParameters.Drag.restDelay }
    static var slowRestDelay: TimeInterval { ClassicalAnimationParameters.Drag.slowRestDelay }

    /// A target icon opens its folder after this hover; Shift slows the transition.
    static var groupDelay: TimeInterval { ClassicalAnimationParameters.Drag.groupDelay }
    static var slowGroupDelay: TimeInterval { ClassicalAnimationParameters.Drag.slowGroupDelay }
    static let groupHighlightTintGray: CGFloat = 0.9412
    /// The tint composites with Core Animation's darken blending.
    static let groupHighlightTintFilterName = ClassicalLayerFilters.darkenBlendMode
    static var groupHighlightScale: CGFloat { ClassicalAnimationParameters.Drag.groupHighlightScale }
    static var groupPulseMinimumOpacity: Float { ClassicalAnimationParameters.Drag.groupPulseMinimumOpacity }
    static var groupPulseDuration: CFTimeInterval { ClassicalAnimationParameters.Drag.groupPulseDuration }
    static var slowGroupPulseDuration: CFTimeInterval { ClassicalAnimationParameters.Drag.slowGroupPulseDuration }
    static var groupPulseStartDelay: CFTimeInterval { ClassicalAnimationParameters.Drag.groupPulseStartDelay }
    static var groupPulseRepeatCount: Float { ClassicalAnimationParameters.Drag.groupPulseRepeatCount }
    static var groupDropStagger: TimeInterval { ClassicalAnimationParameters.Drag.groupDropStagger }
    static var groupShrinkSlowDuration: CFTimeInterval { ClassicalAnimationParameters.Drag.groupShrinkSlowDuration }
    static var groupThumbnailWidthInset: CGFloat { ClassicalAnimationParameters.Drag.groupThumbnailWidthInset }
    static var groupThumbnailShadowOffset: CGSize { ClassicalAnimationParameters.Drag.groupThumbnailShadowOffset }
    static var groupThumbnailShadowRadius: CGFloat { ClassicalAnimationParameters.Drag.groupThumbnailShadowRadius }
    static var groupThumbnailShadowOpacity: Float { ClassicalAnimationParameters.Drag.groupThumbnailShadowOpacity }
    static var groupThumbnailPositionOffset: CGPoint { ClassicalAnimationParameters.Drag.groupThumbnailPositionOffset }

    // With the Liquid Glass option, the hover shows an approximate drop glow instead of the
    // highlight above: a material platter the size and corner radius of a folder cell's backdrop,
    // behind the target, that fades in from 0 while growing to `dropGlowScale`, and reverses when
    // the hover ends.
    static var dropGlowScale: CGFloat { ClassicalAnimationParameters.GlassDropGlow.scale }
    static var dropGlowDuration: CFTimeInterval { ClassicalAnimationParameters.GlassDropGlow.duration }
    static var dropGlowTiming: CAMediaTimingFunctionName { ClassicalAnimationParameters.GlassDropGlow.timing }
    /// Material recipes in the app bundle for the light and dark launcher appearance.
    static let dropGlowLightRecipe = "ClassicalDropGlowLight"
    static let dropGlowDarkRecipe = "ClassicalDropGlowDark"

    /// A folder left with too few applications after a drag out dissolves once it has closed: the
    /// remaining application grows from the thumbnail's share of the cell width, starting at the
    /// folder's centre offset by `folderDissolveOffset`, while the folder cell fades out and shrinks
    /// to `folderDissolveScale`. Both use the default implicit animation.
    static var folderDissolveOffset: CGPoint { ClassicalAnimationParameters.Drag.folderDissolveOffset }
    static var folderDissolveScale: CGFloat { ClassicalAnimationParameters.Drag.folderDissolveScale }
    /// Escape after an item left its folder returns the icon into the closed folder cell, shrunk to
    /// the thumbnail's share of the cell width and at this opacity.
    static var folderReturnOpacity: Float { ClassicalAnimationParameters.Drag.folderReturnOpacity }

    /// Past a page edge, the first page turn and each following one (Shift: the slow values).
    static var edgeDelay: TimeInterval { ClassicalAnimationParameters.Drag.edgeDelay }
    static var edgeRepeat: TimeInterval { ClassicalAnimationParameters.Drag.edgeRepeat }
    static var slowEdgeDelay: TimeInterval { ClassicalAnimationParameters.Drag.slowEdgeDelay }
    static var slowEdgeRepeat: TimeInterval { ClassicalAnimationParameters.Drag.slowEdgeRepeat }

    /// Other cells slide to their new slots while the dragged item moves within a page.
    static var moveDuration: CFTimeInterval { ClassicalAnimationParameters.Drag.moveDuration }

    /// A held or dragged icon scales up and its title fades slightly.
    static var magnifiedScale: CGFloat { ClassicalAnimationParameters.Drag.magnifiedScale }
    static var magnifiedTitleOpacity: Float { ClassicalAnimationParameters.Drag.magnifiedTitleOpacity }

    /// The speed for `distance` points travelled in `elapsed` seconds; no elapsed time counts as fast.
    static func speed(distance: CGFloat, elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return .infinity }
        return Double(distance) / (elapsed * 1e9) * speedScale
    }
}
