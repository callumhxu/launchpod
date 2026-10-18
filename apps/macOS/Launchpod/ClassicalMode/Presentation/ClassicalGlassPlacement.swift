import QuartzCore

/// Where a glass view goes to cover a layer as it is on screen, in a root layer's coordinates:
/// centre, size after the ancestors' scale, rotation, scaled corner radius and combined opacity.
@MainActor
struct ClassicalGlassPlacement: Equatable {
    var center: CGPoint
    /// The backing's size after the scale of its ancestors, before rotation.
    var size: CGSize
    /// Counterclockwise, in radians.
    var rotation: CGFloat
    var cornerRadius: CGFloat
    var opacity: Float

    /// The on-screen placement of `backing` within `root`, or nil when it is detached, hidden or
    /// fully transparent. While `backing` or one of its ancestors animates, the presentation values
    /// are used; otherwise the model values, which already include changes not yet committed.
    static func covering(_ backing: CALayer, in root: CALayer) -> ClassicalGlassPlacement? {
        guard isDescendant(backing, of: root) else { return nil }
        let animating = chain(from: backing, to: root).contains { !($0.animationKeys() ?? []).isEmpty }
        guard let layer = animating ? backing.presentation() : backing,
              let top = animating ? root.presentation() : root else { return nil }
        let layers = chain(from: layer, to: top)
        guard !layers.contains(where: \.isHidden) else { return nil }
        let opacity = layers.reduce(Float(1)) { $0 * $1.opacity }
        let bounds = layer.bounds
        guard opacity > ClassicalFolderParameters.glassMinimumOpacity, bounds.width > 0, bounds.height > 0 else {
            return nil
        }
        let origin = layer.convert(CGPoint(x: bounds.minX, y: bounds.minY), to: top)
        let right = layer.convert(CGPoint(x: bounds.maxX, y: bounds.minY), to: top)
        let up = layer.convert(CGPoint(x: bounds.minX, y: bounds.maxY), to: top)
        let size = CGSize(width: hypot(right.x - origin.x, right.y - origin.y),
                          height: hypot(up.x - origin.x, up.y - origin.y))
        guard size.width > 0, size.height > 0 else { return nil }
        var rotation = atan2(right.y - origin.y, right.x - origin.x)
        if abs(rotation) < ClassicalFolderParameters.glassRotationEpsilon { rotation = 0 }
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        return ClassicalGlassPlacement(center: layer.convert(CGPoint(x: bounds.midX, y: bounds.midY), to: top),
                                       size: size, rotation: rotation, cornerRadius: layer.cornerRadius * scale,
                                       opacity: opacity)
    }

    /// The placement of `guide`'s frame without its own transform and opacity, which the drop glow
    /// takes from the guide's animations instead (`ClassicalFolderMaterials`).
    static func unscaledFrame(of guide: CALayer, in root: CALayer) -> ClassicalGlassPlacement? {
        guard let parent = guide.superlayer, isDescendant(parent, of: root) else { return nil }
        let animating = chain(from: parent, to: root).contains { !($0.animationKeys() ?? []).isEmpty }
        guard let layer = animating ? parent.presentation() : parent,
              let top = animating ? root.presentation() : root else { return nil }
        let layers = chain(from: layer, to: top)
        guard !layers.contains(where: \.isHidden), !guide.isHidden else { return nil }
        let size = guide.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let anchor = guide.anchorPoint
        let origin = CGPoint(x: guide.position.x - anchor.x * size.width, y: guide.position.y - anchor.y * size.height)
        let corner = layer.convert(origin, to: top)
        let right = layer.convert(CGPoint(x: origin.x + size.width, y: origin.y), to: top)
        let up = layer.convert(CGPoint(x: origin.x, y: origin.y + size.height), to: top)
        let mapped = CGSize(width: hypot(right.x - corner.x, right.y - corner.y), height: hypot(up.x - corner.x, up.y - corner.y))
        var rotation = atan2(right.y - corner.y, right.x - corner.x)
        if abs(rotation) < ClassicalFolderParameters.glassRotationEpsilon { rotation = 0 }
        let scale = min(mapped.width / size.width, mapped.height / size.height)
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        return ClassicalGlassPlacement(center: layer.convert(center, to: top), size: mapped, rotation: rotation,
                                       cornerRadius: guide.cornerRadius * scale,
                                       opacity: layers.reduce(Float(1)) { $0 * $1.opacity })
    }

    /// The placement of `backing` for the stage's strip glass view: its shape within the strip
    /// (drawn values below the strip), taken to `root` through the strip, with the strip's scroll
    /// added back, because the strip glass view applies the scroll itself. Above the strip the model
    /// values are used unless something other than the settle animates there.
    static func onStrip(_ backing: CALayer, strip: CALayer, in root: CALayer) -> ClassicalGlassPlacement? {
        guard isDescendant(strip, of: root), let local = covering(backing, in: strip) else { return nil }
        let above = chain(from: strip, to: root)
        let animating = above.contains { layer in
            (layer.animationKeys() ?? []).contains { !(layer === strip && $0 == ClassicalPager.settleAnimationKey) }
        }
        guard let stripLayer = animating ? strip.presentation() : strip,
              let top = animating ? root.presentation() : root else { return nil }
        let layers = chain(from: stripLayer, to: top)
        guard !layers.contains(where: \.isHidden) else { return nil }
        let opacity = local.opacity * layers.reduce(Float(1)) { $0 * $1.opacity }
        guard opacity > ClassicalFolderParameters.glassMinimumOpacity else { return nil }
        let scroll = stripLayer.bounds.origin.x
        func mapped(_ point: CGPoint) -> CGPoint {
            let onScreen = stripLayer.convert(point, to: top)
            return CGPoint(x: onScreen.x + scroll, y: onScreen.y)
        }
        let halfWidth = CGPoint(x: cos(local.rotation) * local.size.width / 2, y: sin(local.rotation) * local.size.width / 2)
        let halfHeight = CGPoint(x: -sin(local.rotation) * local.size.height / 2, y: cos(local.rotation) * local.size.height / 2)
        let c = local.center
        let origin = mapped(CGPoint(x: c.x - halfWidth.x - halfHeight.x, y: c.y - halfWidth.y - halfHeight.y))
        let right = mapped(CGPoint(x: c.x + halfWidth.x - halfHeight.x, y: c.y + halfWidth.y - halfHeight.y))
        let up = mapped(CGPoint(x: c.x - halfWidth.x + halfHeight.x, y: c.y - halfWidth.y + halfHeight.y))
        let size = CGSize(width: hypot(right.x - origin.x, right.y - origin.y), height: hypot(up.x - origin.x, up.y - origin.y))
        guard size.width > 0, size.height > 0, local.size.width > 0, local.size.height > 0 else { return nil }
        var rotation = atan2(right.y - origin.y, right.x - origin.x)
        if abs(rotation) < ClassicalFolderParameters.glassRotationEpsilon { rotation = 0 }
        let scale = min(size.width / local.size.width, size.height / local.size.height)
        return ClassicalGlassPlacement(center: mapped(c), size: size, rotation: rotation,
                                       cornerRadius: local.cornerRadius * scale, opacity: opacity)
    }

    static func isDescendant(_ layer: CALayer, of root: CALayer) -> Bool {
        var current: CALayer? = layer
        while let shown = current {
            if shown === root { return true }
            current = shown.superlayer
        }
        return false
    }

    /// `layer` and its ancestors below `root`; presentation copies are matched through their model.
    private static func chain(from layer: CALayer, to root: CALayer) -> [CALayer] {
        var layers: [CALayer] = []
        var current: CALayer? = layer
        while let shown = current, shown.model() !== root.model() {
            layers.append(shown)
            current = shown.superlayer
        }
        return layers
    }
}
