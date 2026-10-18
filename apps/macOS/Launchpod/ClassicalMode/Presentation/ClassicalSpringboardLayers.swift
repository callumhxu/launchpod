import QuartzCore

enum ClassicalPresentationParameters {
    static let windowLevel = 19
    /// Above the Dock (20), the menu bar (24) and status items (25).
    static let dockCoveringWindowLevel = 27
    static var hiddenOpacity: Float { ClassicalAnimationParameters.EnterExit.hiddenOpacity }
    static var visibleOpacity: Float { ClassicalAnimationParameters.EnterExit.visibleOpacity }
    static var enterTiming: CAMediaTimingFunction { ClassicalAnimationParameters.EnterExit.enterTiming }
    static var exitTiming: CAMediaTimingFunction { ClassicalAnimationParameters.EnterExit.exitTiming }
    static var contentScale: CGFloat { ClassicalAnimationParameters.EnterExit.contentScale }
    /// A replacement wallpaper fades in over 2 s while the launcher is visible.
    static var desktopCrossfadeDuration: CFTimeInterval { ClassicalAnimationParameters.EnterExit.desktopCrossfadeDuration }
    /// The desktop container's filters, applied in order: a hard-edged blur of radius 30, saturation
    /// 1.8, then each colour channel × 0.55 + 0.05292 on encoded values.
    static let desktopBlurRadius: CGFloat = 30
    static let desktopSaturation: CGFloat = 1.8
    static let desktopColorMatrix: [Float] = [
        0.55, 0, 0, 0, 0.05292,
        0, 0.55, 0, 0, 0.05292,
        0, 0, 0.55, 0, 0.05292,
        0, 0, 0, 1, 0,
    ]

    /// New filters for the desktop container; empty when Core Animation's filter class is unavailable.
    static func desktopFilters() -> [NSObject] {
        [ClassicalLayerFilters.gaussianBlur(radius: desktopBlurRadius, hardEdges: true),
         ClassicalLayerFilters.colorSaturate(amount: desktopSaturation),
         ClassicalLayerFilters.colorMatrix(desktopColorMatrix)].compactMap { $0 }
    }

    static var scaledContentTransform: CATransform3D {
        CATransform3DMakeScale(contentScale, contentScale, 1)
    }
}

/// Owns the Classical desktop and empty content layers, without window or focus management.
@MainActor
final class ClassicalSpringboardLayers {
    let layer = CALayer()
    let desktopContainerLayer = CALayer()
    let contentLayer = CALayer()
    private(set) var desktopLayer: CALayer?

    /// The layer animation target, independent of presentation readiness and keyboard focus.
    private(set) var isVisible = false
    private var isDestroyed = false

    init() {
        withoutActions {
            layer.insertSublayer(desktopContainerLayer, at: 0)
            layer.addSublayer(contentLayer)
            // The wallpaper is filtered once and kept as a raster at the display's scale.
            desktopContainerLayer.filters = ClassicalPresentationParameters.desktopFilters()
            desktopContainerLayer.shouldRasterize = true
        }
    }

    isolated deinit {
        destroy()
    }

    /// Applies caller-resolved geometry without incorporating the content's current scale.
    func layout(rootFrame: CGRect, contentFrame: CGRect) {
        guard !isDestroyed else { return }
        withoutActions {
            layer.frame = rootFrame
            let transform = contentLayer.transform
            contentLayer.transform = CATransform3DIdentity
            contentLayer.frame = contentFrame
            contentLayer.transform = transform
        }
    }

    /// Follows a changed screen size and scale without animating the installed desktop.
    func resizeDesktop(to bounds: CGRect, scale: CGFloat) {
        guard !isDestroyed, let desktopLayer else { return }
        layout(rootFrame: bounds, contentFrame: bounds)
        withoutActions {
            desktopLayer.frame = bounds
            desktopContainerLayer.frame = bounds
            desktopContainerLayer.rasterizationScale = scale
            desktopLayer.contentsScale = scale
        }
    }

    /// Swaps the installed desktop's image in place, without a cross-fade.
    func replaceDesktopImage(_ image: CGImage) {
        guard !isDestroyed else { return }
        withoutActions { desktopLayer?.contents = image }
    }

    /// A wallpaper change while shown: a new desktop layer at opacity 0 over the old one fades to 1
    /// in 2 s, then the old layer is removed.
    @discardableResult
    func crossfadeDesktop(to image: CGImage) -> CALayer? {
        guard !isDestroyed, isVisible, let old = desktopLayer else { return nil }
        let next = CALayer()
        withoutActions {
            next.frame = old.frame
            next.contentsScale = old.contentsScale
            next.contents = image
            next.opacity = ClassicalAnimationParameters.EnterExit.hiddenOpacity
            desktopContainerLayer.insertSublayer(next, above: old)
        }
        desktopLayer = next
        CATransaction.flush()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = ClassicalAnimationParameters.EnterExit.hiddenOpacity
        fade.duration = ClassicalPresentationParameters.desktopCrossfadeDuration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self, old] in
            MainActor.assumeIsolated {
                guard let self, !self.isDestroyed else { return }
                self.withoutActions { old.removeFromSuperlayer() }
            }
        }
        next.opacity = ClassicalAnimationParameters.EnterExit.visibleOpacity
        next.add(fade, forKey: "opacity")
        CATransaction.commit()
        return next
    }

    /// Installs a fresh, detached desktop layer showing the unfiltered wallpaper; the desktop
    /// container filters and rasterizes it at the desktop layer's `contentsScale`.
    /// The caller supplies local desktop geometry and owns screen and window selection.
    @discardableResult
    func show(in hostLayer: CALayer, desktopLayer: CALayer, reduceMotion: Bool,
              slowMotionAllowed: Bool = false, shiftKeyDown: Bool = false,
              completion: (@MainActor () -> Void)? = nil) -> Bool {
        guard !isDestroyed, !isVisible else { return false }
        precondition(desktopLayer.superlayer == nil)
        precondition(desktopLayer !== layer && desktopLayer !== desktopContainerLayer && desktopLayer !== contentLayer)
        isVisible = true
        withoutActions {
            self.desktopLayer?.removeFromSuperlayer()
            self.desktopLayer = desktopLayer
            if layer.superlayer == nil { hostLayer.insertSublayer(layer, at: 0) }
            desktopContainerLayer.insertSublayer(desktopLayer, at: 0)
            desktopContainerLayer.frame = CGRect(origin: .zero, size: desktopLayer.frame.size)
            desktopContainerLayer.rasterizationScale = desktopLayer.contentsScale
            layer.opacity = ClassicalPresentationParameters.hiddenOpacity
            if !reduceMotion {
                contentLayer.transform = ClassicalPresentationParameters.scaledContentTransform
            }
        }
        CATransaction.flush()

        let duration = slowMotionAllowed && shiftKeyDown
            ? ClassicalAnimationParameters.EnterExit.slowDuration
            : Double(Float(CATransaction.animationDuration()))
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(ClassicalPresentationParameters.enterTiming)
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isDestroyed else { return }
                completion?()
            }
        }
        layer.opacity = ClassicalPresentationParameters.visibleOpacity
        if !reduceMotion {
            contentLayer.transform = CATransform3DIdentity
        }
        CATransaction.commit()
        return true
    }

    /// Starts fading out; the captured desktop remains attached until transaction completion.
    /// `scaledLayers`, when given (an open folder's panel), scale up instead of the content.
    @discardableResult
    func hide(reduceMotion: Bool, slowMotionAllowed: Bool = false, shiftKeyDown: Bool = false,
              scaledLayers: [CALayer] = [], completion: (@MainActor () -> Void)? = nil) -> Bool {
        guard !isDestroyed, isVisible else { return false }
        isVisible = false
        let exitingDesktop = desktopLayer
        let duration = slowMotionAllowed && shiftKeyDown
            ? ClassicalAnimationParameters.EnterExit.slowDuration
            : Double(Float(CATransaction.animationDuration()))
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(ClassicalPresentationParameters.exitTiming)
        CATransaction.setCompletionBlock { [weak self, exitingDesktop] in
            MainActor.assumeIsolated {
                guard let self, !self.isDestroyed else { return }
                self.cleanupAfterExit(desktopLayer: exitingDesktop, scaledLayers: scaledLayers)
                completion?()
            }
        }
        if !reduceMotion {
            if scaledLayers.isEmpty {
                contentLayer.transform = ClassicalPresentationParameters.scaledContentTransform
            } else {
                scaledLayers.forEach { $0.transform = ClassicalPresentationParameters.scaledContentTransform }
            }
        }
        layer.opacity = ClassicalPresentationParameters.hiddenOpacity
        desktopLayer = nil
        CATransaction.commit()
        return true
    }

    /// Permanently detaches this session's layers and makes deferred callbacks inert.
    func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true
        isVisible = false
        withoutActions {
            layer.removeAllAnimations()
            contentLayer.removeAllAnimations()
            desktopContainerLayer.removeAllAnimations()
            for desktop in desktopContainerLayer.sublayers ?? [] {
                desktop.removeAllAnimations()
                desktop.removeFromSuperlayer()
            }
            desktopLayer = nil
            contentLayer.transform = CATransform3DIdentity
            layer.removeFromSuperlayer()
        }
    }

    private func cleanupAfterExit(desktopLayer: CALayer?, scaledLayers: [CALayer]) {
        guard !isDestroyed else { return }
        withoutActions {
            contentLayer.transform = CATransform3DIdentity
            scaledLayers.forEach { $0.transform = CATransform3DIdentity }
            if !isVisible {
                layer.removeFromSuperlayer()
            }
            desktopLayer?.removeFromSuperlayer()
        }
    }

    private func withoutActions(_ changes: () -> Void) {
        let actionsWereDisabled = CATransaction.disableActions()
        if !actionsWereDisabled {
            CATransaction.setDisableActions(true)
        }
        defer {
            if !actionsWereDisabled {
                CATransaction.setDisableActions(false)
            }
        }
        changes()
    }
}
