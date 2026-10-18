import AppKit
import QuartzCore

/// The launch feedback: a copy of the icon above the launcher, starting at 0.9 opacity,
/// grows to twice its size in place and fades to 0.1 over 0.25 s ease-out (5 s with allowed Shift
/// slow motion), then is removed. There is no target frame, so the copy stays centred on
/// the icon.
@MainActor
enum ClassicalOpenAnimation {
    static var duration: CFTimeInterval { ClassicalAnimationParameters.OpenFeedback.duration }
    static var slowDuration: CFTimeInterval { ClassicalAnimationParameters.OpenFeedback.slowDuration }
    static var startOpacity: Float { ClassicalAnimationParameters.OpenFeedback.startOpacity }
    static var endOpacity: Float { ClassicalAnimationParameters.OpenFeedback.endOpacity }
    static var scale: CGFloat { ClassicalAnimationParameters.OpenFeedback.scale }
    static var timing: CAMediaTimingFunction { ClassicalAnimationParameters.OpenFeedback.timing }

    @discardableResult
    static func play(icon: CALayer, in hostLayer: CALayer,
                     slowMotionAllowed: Bool? = nil, shiftKeyDown: Bool? = nil) -> CALayer? {
        guard let contents = icon.contents else { return nil }
        let slowAllowed = slowMotionAllowed ??
            (UserDefaults(suiteName: "com.apple.dock").map(ClassicalAnimationParameters.slowMotionAllowed(in:)) ?? false)
        let shiftDown = shiftKeyDown ?? NSEvent.modifierFlags.contains(.shift)
        let copy = CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        copy.contents = contents
        copy.contentsScale = icon.contentsScale
        copy.contentsGravity = icon.contentsGravity
        copy.frame = icon.convert(icon.bounds, to: hostLayer)
        copy.opacity = startOpacity
        hostLayer.addSublayer(copy)
        CATransaction.commit()

        // Written as explicit animations toward the new model values.
        let timing = Self.timing
        let grow = CABasicAnimation(keyPath: "transform")
        grow.fromValue = CATransform3DIdentity
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = startOpacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak copy] in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            copy?.removeFromSuperlayer()
            CATransaction.commit()
        }
        copy.transform = CATransform3DMakeScale(scale, scale, 1)
        copy.opacity = endOpacity
        for animation in [grow, fade] {
            animation.duration = slowAllowed && shiftDown ? slowDuration : duration
            animation.timingFunction = timing
            copy.add(animation, forKey: animation.keyPath)
        }
        CATransaction.commit()
        return copy
    }
}
