import CoreGraphics
import Foundation
import QuartzCore

@_silgen_name("LPClassicalAnimationScalar")
nonisolated private func nativeClassicalAnimationScalar(_ parameter: UInt32) -> Double

/// Classical animation values, including the Glass hover approximation, supplied by the native core
/// to presentation owners.
nonisolated enum ClassicalAnimationParameters {
    static func slowMotionAllowed(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: "slow-motion-allowed")
    }

    private enum Scalar: UInt32 {
        case entryScale = 1, desktopCrossfade, hiddenOpacity, visibleOpacity, enterTiming, exitTiming,
             enterExitSlowDuration
        case pageSettleDuration = 10, pageCurveX2, pageCurveY2, pageDragActivation,
             pageFlickSpeed, pageOverscroll, pageWheelScale, pageWheelDelay, pageSlowWheelDelay,
             pageSlowSettleDuration
        case folderSlowDuration = 20, folderBackgroundScale, folderSecondPhase,
             folderCloseDelay, newFolderOpenDelay, folderSlowSecondPhase, folderBackgroundOpacity
        case jitterDuration = 30, jitterFrameInterval, jitterRotation, longPressDelay, slowLongPressDelay,
             jitterRandomModulus, jitterPhaseBucketScale, jitterPhaseStartIncrement,
             jitterPositionSpan, jitterPositionAmplitude
        case dragActivation = 40, dragSpeedScale, dragRestSpeed, dragRestDelay, dragSlowRestDelay,
             dragGroupDelay, dragSlowGroupDelay, dragHighlightScale, dragPulseOpacity,
             dragPulseDuration, dragSlowPulseDuration, dragPulseStartDelay, dragPulseRepeat,
             dragGroupDropStagger, dragFolderDissolveScale, dragFolderReturnOpacity,
             dragEdgeDelay, dragEdgeRepeat, dragSlowEdgeDelay, dragSlowEdgeRepeat,
             dragMoveDuration, dragMagnifiedScale, dragMagnifiedTitleOpacity, dragGroupShrinkSlowDuration
        case openDuration = 70, openStartOpacity, openEndOpacity, openScale, openTiming,
             openSlowDuration
        case removalDuration = 80, removalScale, removalSlowDuration
        case dropGlowScale = 90, dropGlowDuration, dropGlowTiming, folderDissolveOffsetX,
             folderDissolveOffsetY, groupThumbnailPositionX, groupThumbnailPositionY,
             groupThumbnailWidthInset, groupThumbnailShadowX, groupThumbnailShadowY,
             groupThumbnailShadowRadius, groupThumbnailShadowOpacity
        case searchPositionTiming = 110
    }

    private static func value(_ scalar: Scalar) -> Double {
        nativeClassicalAnimationScalar(scalar.rawValue)
    }

    private static func timingName(_ scalar: Scalar) -> CAMediaTimingFunctionName {
        switch Int(value(scalar)) {
        case 1: return .easeIn
        case 2: return .easeOut
        case 3: return .easeInEaseOut
        default: preconditionFailure("Unsupported Classical animation timing")
        }
    }

    nonisolated enum EnterExit {
        static var contentScale: CGFloat { CGFloat(value(.entryScale)) }
        static var desktopCrossfadeDuration: CFTimeInterval { value(.desktopCrossfade) }
        static var hiddenOpacity: Float { Float(value(.hiddenOpacity)) }
        static var visibleOpacity: Float { Float(value(.visibleOpacity)) }
        static var enterTiming: CAMediaTimingFunction { CAMediaTimingFunction(name: timingName(.enterTiming)) }
        static var exitTiming: CAMediaTimingFunction { CAMediaTimingFunction(name: timingName(.exitTiming)) }
        static var slowDuration: CFTimeInterval { value(.enterExitSlowDuration) }
    }

    nonisolated enum Paging {
        static var settleDuration: CFTimeInterval { value(.pageSettleDuration) }
        static var slowSettleDuration: CFTimeInterval { value(.pageSlowSettleDuration) }
        static var settleTiming: CAMediaTimingFunction {
            CAMediaTimingFunction(controlPoints: 0, 0, Float(value(.pageCurveX2)), Float(value(.pageCurveY2)))
        }
        static var dragActivation: CGFloat { CGFloat(value(.pageDragActivation)) }
        static var flickSpeed: CGFloat { CGFloat(value(.pageFlickSpeed)) }
        static var overscrollFactor: CGFloat { CGFloat(value(.pageOverscroll)) }
        static var wheelDeltaScale: CGFloat { CGFloat(value(.pageWheelScale)) }
        static var wheelSettleDelay: TimeInterval { value(.pageWheelDelay) }
        static var slowWheelSettleDelay: TimeInterval { value(.pageSlowWheelDelay) }
    }

    nonisolated enum Folder {
        static var slowMotionDuration: CFTimeInterval { value(.folderSlowDuration) }
        static var backgroundScale: CGFloat { CGFloat(value(.folderBackgroundScale)) }
        static var backgroundOpacity: Float { Float(value(.folderBackgroundOpacity)) }
        static var hiddenOpacity: Float { backgroundOpacity }
        static var visibleOpacity: Float { Float(value(.visibleOpacity)) }
        static var secondPhaseDuration: CFTimeInterval { value(.folderSecondPhase) }
        static var slowSecondPhaseDuration: CFTimeInterval { value(.folderSlowSecondPhase) }
        static var closeSettleDelay: TimeInterval { value(.folderCloseDelay) }
        static var newFolderOpenDelay: TimeInterval { value(.newFolderOpenDelay) }
    }

    nonisolated enum Editing {
        static var jitterDuration: CFTimeInterval { value(.jitterDuration) }
        static var jitterFrameInterval: CFTimeInterval { value(.jitterFrameInterval) }
        static var jitterRotation: Double { value(.jitterRotation) }
        static var jitterRandomModulus: UInt32 { UInt32(value(.jitterRandomModulus)) }
        static var jitterPhaseBucketScale: Float { Float(value(.jitterPhaseBucketScale)) }
        static var jitterPhaseStartIncrement: UInt32 { UInt32(value(.jitterPhaseStartIncrement)) }
        static var jitterPositionSpan: Double { value(.jitterPositionSpan) }
        static var jitterPositionAmplitude: Double { value(.jitterPositionAmplitude) }
        static var longPressDelay: TimeInterval { value(.longPressDelay) }
        static var slowLongPressDelay: TimeInterval { value(.slowLongPressDelay) }
    }

    nonisolated enum Drag {
        static var hiddenOpacity: Float { Float(value(.hiddenOpacity)) }
        static var visibleOpacity: Float { Float(value(.visibleOpacity)) }
        static var activationDistance: CGFloat { CGFloat(value(.dragActivation)) }
        static var speedScale: Double { value(.dragSpeedScale) }
        static var restSpeed: Double { value(.dragRestSpeed) }
        static var restDelay: TimeInterval { value(.dragRestDelay) }
        static var slowRestDelay: TimeInterval { value(.dragSlowRestDelay) }
        static var groupDelay: TimeInterval { value(.dragGroupDelay) }
        static var slowGroupDelay: TimeInterval { value(.dragSlowGroupDelay) }
        static var groupHighlightScale: CGFloat { CGFloat(value(.dragHighlightScale)) }
        static var groupPulseMinimumOpacity: Float { Float(value(.dragPulseOpacity)) }
        static var groupPulseDuration: CFTimeInterval { value(.dragPulseDuration) }
        static var slowGroupPulseDuration: CFTimeInterval { value(.dragSlowPulseDuration) }
        static var groupPulseStartDelay: CFTimeInterval { value(.dragPulseStartDelay) }
        static var groupPulseRepeatCount: Float { Float(value(.dragPulseRepeat)) }
        static var groupDropStagger: TimeInterval { value(.dragGroupDropStagger) }
        static var groupThumbnailWidthInset: CGFloat { CGFloat(value(.groupThumbnailWidthInset)) }
        static var groupThumbnailShadowOffset: CGSize {
            CGSize(width: CGFloat(value(.groupThumbnailShadowX)), height: CGFloat(value(.groupThumbnailShadowY)))
        }
        static var groupThumbnailShadowRadius: CGFloat { CGFloat(value(.groupThumbnailShadowRadius)) }
        static var groupThumbnailShadowOpacity: Float { Float(value(.groupThumbnailShadowOpacity)) }
        static var groupThumbnailPositionOffset: CGPoint {
            CGPoint(x: CGFloat(value(.groupThumbnailPositionX)), y: CGFloat(value(.groupThumbnailPositionY)))
        }
        static var folderDissolveOffset: CGPoint {
            CGPoint(x: CGFloat(value(.folderDissolveOffsetX)), y: CGFloat(value(.folderDissolveOffsetY)))
        }
        static var folderDissolveScale: CGFloat { CGFloat(value(.dragFolderDissolveScale)) }
        static var folderReturnOpacity: Float { Float(value(.dragFolderReturnOpacity)) }
        static var edgeDelay: TimeInterval { value(.dragEdgeDelay) }
        static var edgeRepeat: TimeInterval { value(.dragEdgeRepeat) }
        static var slowEdgeDelay: TimeInterval { value(.dragSlowEdgeDelay) }
        static var slowEdgeRepeat: TimeInterval { value(.dragSlowEdgeRepeat) }
        static var moveDuration: CFTimeInterval { value(.dragMoveDuration) }
        static var magnifiedScale: CGFloat { CGFloat(value(.dragMagnifiedScale)) }
        static var magnifiedTitleOpacity: Float { Float(value(.dragMagnifiedTitleOpacity)) }
        static var groupShrinkSlowDuration: CFTimeInterval { value(.dragGroupShrinkSlowDuration) }
    }

    /// The optional Glass hover uses a Launchpod motion approximation.
    nonisolated enum GlassDropGlow {
        static var hiddenOpacity: Float { Float(value(.hiddenOpacity)) }
        static var visibleOpacity: Float { Float(value(.visibleOpacity)) }
        static var scale: CGFloat { CGFloat(value(.dropGlowScale)) }
        static var duration: CFTimeInterval { value(.dropGlowDuration) }
        static var timing: CAMediaTimingFunctionName { timingName(.dropGlowTiming) }
    }

    nonisolated enum OpenFeedback {
        static var duration: CFTimeInterval { value(.openDuration) }
        static var slowDuration: CFTimeInterval { value(.openSlowDuration) }
        static var startOpacity: Float { Float(value(.openStartOpacity)) }
        static var endOpacity: Float { Float(value(.openEndOpacity)) }
        static var scale: CGFloat { CGFloat(value(.openScale)) }
        static var timing: CAMediaTimingFunction { CAMediaTimingFunction(name: timingName(.openTiming)) }
    }

    nonisolated enum Search {
        static var hiddenOpacity: Float { Float(value(.hiddenOpacity)) }
        static var visibleOpacity: Float { Float(value(.visibleOpacity)) }
        static var positionTiming: CAMediaTimingFunction {
            CAMediaTimingFunction(name: timingName(.searchPositionTiming))
        }
    }

    nonisolated enum Removal {
        static var duration: CFTimeInterval { value(.removalDuration) }
        static var slowDuration: CFTimeInterval { value(.removalSlowDuration) }
        static var scale: CGFloat { CGFloat(value(.removalScale)) }
        static var hiddenOpacity: Float { Float(value(.hiddenOpacity)) }
    }
}
