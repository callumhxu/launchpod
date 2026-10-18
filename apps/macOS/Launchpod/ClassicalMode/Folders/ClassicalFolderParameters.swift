import AppKit
import CoreGraphics
import Foundation
import QuartzCore

/// Classical folder constants: the closed folder cell, the open panel and the open and close
/// transitions. Classical mode only.
///
/// The panel transitions use Core Animation's implicit actions and inherit the enclosing transaction's
/// duration and timing; the second phase, slow motion and post-close delay are explicit.
nonisolated enum ClassicalFolderParameters {
    static var newFolderOpenDelay: TimeInterval { ClassicalAnimationParameters.Folder.newFolderOpenDelay }
    // MARK: Closed folder cell

    static let miniGridRows = 3
    static let miniGridColumns = 3
    /// The thumbnail grid's spacing: each thumbnail is its cell less this, offset by half of it.
    static let miniGridSpacing: CGFloat = 4
    /// The thumbnail grid sits inside the backdrop, inset by this share of the backdrop's width.
    static let miniGridInsetFraction: CGFloat = 0.1
    /// Requested thumbnail icon sides are limited to 1…32 pt.
    static let miniIconSideRange: ClosedRange<CGFloat> = 1...32
    // The closed cell's backdrop; a drag's highlight under a target application icon is the same backdrop.
    static let itemBackdropGray: CGFloat = 0.9686
    static let itemBackdropAlpha: CGFloat = 0.5
    /// The backdrop's corner radius is this share of the icon height, rounded.
    static let itemCornerRadiusFraction: CGFloat = 0.15625

    /// How far the backdrop is inset from the icon frame: 5, 7, 10 or 12 pt by icon height.
    static func itemBackdropInset(iconHeight: CGFloat) -> CGFloat {
        if iconHeight <= 60 { return 5 }
        if iconHeight <= 80 { return 7 }
        if iconHeight < 128 { return 10 }
        return 12
    }

    // MARK: Open panel

    static let panelCornerRadius: CGFloat = 36
    /// The blur and saturation applied to what lies behind the panel's backdrop.
    static let panelBlurRadius: CGFloat = 30
    static let panelSaturation: CGFloat = 1.8
    static let panelBackdropGray: CGFloat = 0.9686
    static let panelBackdropAlpha: CGFloat = 0.5
    /// The panel's side margins are the root pages' margins, but at least this.
    static let panelMinimumSideMargin: CGFloat = 90
    /// The backdrop extends this far past the folder grid on the left and right.
    static let panelBackdropOutset: CGFloat = 20
    /// Added to the panel above the backdrop for the title, and below it when the panel has room.
    static let panelTitleBand: CGFloat = 30
    /// Between the top of the folder pages and the top of the backdrop.
    static let panelPageTopGap: CGFloat = 40
    /// The page strip starts this far below the bottom margin.
    static let panelStripBottomInset: CGFloat = 10
    static let pageDotsHeight: CGFloat = 15
    static let titleFontSize: CGFloat = 28
    /// The title editor extends this far past the title on the left and right.
    static let titleEditOutset: CGFloat = 200
    /// From this many rows, a display's camera housing is left out of the panel's vertical centring.
    static let notchRowThreshold = 5

    // MARK: Liquid Glass (optional appearance)

    /// The closed folder's system glass style. The glass is not interactive, has no tint, and
    /// follows the window's appearance.
    @available(macOS 26.0, *)
    static let closedGlassStyle: NSGlassEffectView.Style = .clear
    /// The open panel's system glass style; its corner radius is the panel backdrop's.
    @available(macOS 26.0, *)
    static let panelGlassStyle: NSGlassEffectView.Style = .clear
    /// The Classical search field's glass: AppKit's private glass variant number whose rendering
    /// matches SwiftUI's dock glass, set through the glass view's private `_variant` key; without it
    /// the field keeps the clear style.
    static let searchGlassVariant = 3
    /// With Liquid Glass, a full-screen material in the app bundle lies behind the open panel; it
    /// fades in as the root pages fade out and out as they return.
    static let backgroundMaterialRecipe = "ClassicalFolderBackground"
    /// The glass stage's run-loop observer order: just before Core Animation's commit observer
    /// (order 2 000 000), so glass changes join the same commit as the layers they follow.
    static let glassCommitObserverOrder: CFIndex = 1_999_000
    /// Below this rotation (radians) the glass stays axis-aligned rather than being rotated with the cell.
    static let glassRotationEpsilon: CGFloat = 0.0001
    /// Below this opacity the glass is hidden instead of drawn nearly transparent.
    static let glassMinimumOpacity: Float = 0.001

    // MARK: Transitions

    static var slowMotionDuration: CFTimeInterval { ClassicalAnimationParameters.Folder.slowMotionDuration }

    /// While a folder is open the root pages scale to this and fade out entirely.
    static var backgroundScale: CGFloat { ClassicalAnimationParameters.Folder.backgroundScale }
    static var backgroundOpacity: Float { ClassicalAnimationParameters.Folder.backgroundOpacity }
    /// While the icons are thumbnail-sized during opening and closing they are minified with this
    /// filter, then the default again.
    static let transitionMinificationFilter: CALayerContentsFilter = ClassicalLayerFilters.lanczos
    /// After the panel has grown, the page dots fade in over this.
    static var secondPhaseDuration: CFTimeInterval { ClassicalAnimationParameters.Folder.secondPhaseDuration }
    static var slowSecondPhaseDuration: CFTimeInterval { ClassicalAnimationParameters.Folder.slowSecondPhaseDuration }
    /// After the panel has shrunk back, the root page is laid out again after this delay.
    static var closeSettleDelay: TimeInterval { ClassicalAnimationParameters.Folder.closeSettleDelay }
    /// A press in the panel off the backdrop closes the folder on release unless the pointer moved
    /// this far on either axis at some point.
    static let outsideClickTolerance: CGFloat = 3
}
