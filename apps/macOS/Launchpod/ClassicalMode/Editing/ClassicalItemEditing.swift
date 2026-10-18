import AppKit
import QuartzCore

/// Jitter animations. Both are 0.25 s additive keyframe animations that repeat forever,
/// stepped every 0.05 s (`frameInterval`), with a random phase so cells move out of step.
nonisolated enum ClassicalJitter {
    static var duration: CFTimeInterval { ClassicalAnimationParameters.Editing.jitterDuration }
    static var frameInterval: CFTimeInterval { ClassicalAnimationParameters.Editing.jitterFrameInterval }
    /// `±0.03525565085` rad (about 2°).
    static var rotation: Double { ClassicalAnimationParameters.Editing.jitterRotation }
    static let positionKey = "position"
    static let transformKey = "transform"

    /// `ceil((random % 1000 + 1) × 0.2) × 0.05`: a phase between 0.05 s and 10 s.
    static func beginTime(random: UInt32) -> CFTimeInterval {
        let parameters = ClassicalAnimationParameters.Editing.self
        let sample = random % parameters.jitterRandomModulus + parameters.jitterPhaseStartIncrement
        return Double((Float(sample) * parameters.jitterPhaseBucketScale).rounded(.up)) * frameInterval
    }

    /// `floor((random % 1000) / 1000 × 2 × 0.25 − 0.25)`: an offset of −1 or 0 pt.
    static func offset(random: UInt32) -> CGFloat {
        let parameters = ClassicalAnimationParameters.Editing.self
        let modulus = parameters.jitterRandomModulus
        let amplitude = parameters.jitterPositionAmplitude
        let fraction = Double(random % modulus) / Double(modulus)
        return CGFloat(Float(fraction * parameters.jitterPositionSpan * amplitude - amplitude).rounded(.down))
    }

    /// Four random points and a return to the first.
    static func positionAnimation(random: () -> UInt32 = { arc4random() }) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: positionKey)
        configure(animation)
        var points = (0..<4).map { _ in CGPoint(x: offset(random: random()), y: offset(random: random())) }
        points.append(points[0])
        animation.values = points.map { NSValue(point: $0) }
        animation.beginTime = beginTime(random: random())
        return animation
    }

    /// Rotation −a → +a → −a about the cell's centre.
    static func rotationAnimation(random: () -> UInt32 = { arc4random() }) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: transformKey)
        configure(animation)
        animation.valueFunction = CAValueFunction(name: .rotateZ)
        animation.values = [-rotation, rotation, -rotation]
        animation.beginTime = beginTime(random: random())
        return animation
    }

    private static func configure(_ animation: CAKeyframeAnimation) {
        animation.duration = duration
        animation.isAdditive = true
        animation.repeatCount = .greatestFiniteMagnitude
        animation.isRemovedOnCompletion = false
        // The private `frameInterval`: the animation advances in 0.05 s steps.
        let setter = NSSelectorFromString("setFrameInterval:")
        if animation.responds(to: setter) { animation.setValue(frameInterval, forKey: "frameInterval") }
    }
}

/// The delete badge: the Dock's `ecsb_closebox` image at its own size, centred 10 % inside the icon's
/// top-left corner (top-right right-to-left).
nonisolated enum ClassicalCloseBox {
    static let imageName = "ecsb_closebox"
    static let pressedImageName = "ecsb_closebox_pressed"
    static let side: CGFloat = 28

    static func frame(icon: CGRect, size: CGSize = CGSize(width: side, height: side), rightToLeft: Bool) -> CGRect {
        let insetX = CGFloat(Int(icon.width * 0.1))
        let insetY = CGFloat(Int(icon.height * 0.1))
        let centerX = rightToLeft ? icon.maxX - insetX : icon.minX + insetX
        let x = centerX - CGFloat(Int(size.width * 0.5))
        let y = icon.minY + (icon.height - (size.height + insetY)) + CGFloat(Int(size.height * 0.5))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The Dock's image when the system still ships it; otherwise a drawn grey circle with a cross.
    static func image(named name: String, scale: CGFloat) -> CGImage? {
        let suffix = scale > 1 ? "@2x" : ""
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Dock.app/Contents/Resources/\(name)\(suffix).png")
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { return image }
        let pixels = Int(side * scale)
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let circle = CGRect(x: 4, y: 4, width: side - 8, height: side - 8)
        context.setFillColor(CGColor(gray: name == pressedImageName ? 0.35 : 0.5, alpha: 0.95))
        context.fillEllipse(in: circle)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(2)
        context.setLineCap(.round)
        let inset = circle.insetBy(dx: 6, dy: 6)
        context.move(to: CGPoint(x: inset.minX, y: inset.minY)); context.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
        context.move(to: CGPoint(x: inset.minX, y: inset.maxY)); context.addLine(to: CGPoint(x: inset.maxX, y: inset.minY))
        context.strokePath()
        return context.makeImage()
    }
}

extension ClassicalItemLayer {
    func setJittering(_ jittering: Bool) {
        guard jittering != isJittering else { return }
        setJitteringState(jittering)
        if jittering {
            jitterLayer.add(ClassicalJitter.positionAnimation(), forKey: ClassicalJitter.positionKey)
            jitterLayer.add(ClassicalJitter.rotationAnimation(), forKey: ClassicalJitter.transformKey)
        } else {
            jitterLayer.removeAnimation(forKey: ClassicalJitter.positionKey)
            jitterLayer.removeAnimation(forKey: ClassicalJitter.transformKey)
        }
    }

    /// Magnification of a held icon: the transform layer scales about the cell's centre and the
    /// title fades, both with the current transaction's implicit animation.
    func setMagnified(_ magnified: Bool) {
        guard magnified != isMagnified else { return }
        setMagnifiedState(magnified)
        let scale = ClassicalDragParameters.magnifiedScale
        transformLayer.transform = magnified ? CATransform3DMakeScale(scale, scale, 1) : CATransform3DIdentity
        titleLayer.opacity = magnified ? ClassicalDragParameters.magnifiedTitleOpacity : ClassicalAnimationParameters.Drag.visibleOpacity
    }

    /// Shown without animation, only on deletable applications.
    func setCloseboxVisible(_ visible: Bool, rightToLeft: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard visible else {
            closeboxLayer?.removeFromSuperlayer()
            closeboxLayer = nil
            return
        }
        guard closeboxLayer == nil else { return }
        let box = CALayer()
        box.contentsScale = scale
        box.contents = ClassicalCloseBox.image(named: ClassicalCloseBox.imageName, scale: scale)
        box.frame = ClassicalCloseBox.frame(icon: iconLayer.frame, rightToLeft: rightToLeft)
        jitterLayer.addSublayer(box)
        closeboxLayer = box
    }

    /// The delete badge's hit area in `jitterLayer` coordinates.
    func closeboxContains(_ point: CGPoint) -> Bool {
        guard let closeboxLayer else { return false }
        return closeboxLayer.frame.contains(point)
    }

    func setCloseboxPressed(_ pressed: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        closeboxLayer?.contents = ClassicalCloseBox.image(
            named: pressed ? ClassicalCloseBox.pressedImageName : ClassicalCloseBox.imageName, scale: scale)
        CATransaction.commit()
    }
}
