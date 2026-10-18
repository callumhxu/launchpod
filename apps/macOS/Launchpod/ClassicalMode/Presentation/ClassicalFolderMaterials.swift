import AppKit
import QuartzCore

/// The Core Material layers the glass stage draws below the glass: the open folder's background
/// material and a drop glow per guide the drag visuals publish. They live in `host`, a view that
/// keeps its place in the stage's layer order, and are removed with it.
@MainActor
final class ClassicalFolderMaterials {
    private struct DropGlow {
        let layer: CALayer
        var recipe: String
        /// Which of the guide's fade and grow animations the material already carries, by key.
        var mirrored: [String: String] = [:]
    }

    private let host: NSView
    /// The open folder's background material, below the drop glows.
    private var folderBackground: CALayer?
    /// Drop glow material per guide.
    private var dropGlows: [ObjectIdentifier: DropGlow] = [:]

    init(host: NSView) {
        self.host = host
    }

    /// Brings both materials up to date with the open folder and the current drop glow guides, whose
    /// frames are taken to `root`, the stage's layer.
    func synchronize(folders: ClassicalFolderPresenter, dropGlowGuides: [CALayer], in root: CALayer) {
        synchronizeFolderBackground(folders)
        synchronizeDropGlows(guides: dropGlowGuides, in: root)
    }

    /// Covers the stage while a folder is open, at the complement of the root pages' opacity, so it
    /// follows their fade in both directions.
    private func synchronizeFolderBackground(_ folders: ClassicalFolderPresenter) {
        let pages = folders.folder?.layer.glassEnabled == true ? folders.backgroundLayer : nil
        var opacity: Float = 0
        if let pages, pages.superlayer != nil {
            let animating = !(pages.animationKeys() ?? []).isEmpty
            opacity = 1 - ((animating ? pages.presentation() : nil) ?? pages).opacity
        }
        if opacity > ClassicalFolderParameters.glassMinimumOpacity, folderBackground == nil,
           let layer = ClassicalLayerFilters.makeMaterialLayer(recipe: ClassicalFolderParameters.backgroundMaterialRecipe,
                                                             in: .main) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            host.layer?.insertSublayer(layer, at: 0)
            CATransaction.commit()
            folderBackground = layer
        }
        guard let background = folderBackground else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.frame = host.bounds
        background.isHidden = opacity <= ClassicalFolderParameters.glassMinimumOpacity
        background.opacity = opacity
        CATransaction.commit()
    }

    private func synchronizeDropGlows(guides: [CALayer], in root: CALayer) {
        let dark = host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let recipe = dark ? ClassicalDragParameters.dropGlowDarkRecipe : ClassicalDragParameters.dropGlowLightRecipe
        var current = Set<ObjectIdentifier>()
        for guide in guides {
            let id = ObjectIdentifier(guide)
            current.insert(id)
            var glow = dropGlows[id]
            if glow == nil, let layer = ClassicalLayerFilters.makeMaterialLayer(recipe: recipe, in: .main) {
                glow = DropGlow(layer: layer, recipe: recipe)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                host.layer?.addSublayer(layer)
                CATransaction.commit()
            }
            guard var glow else { continue }
            if glow.recipe != recipe {
                ClassicalLayerFilters.setMaterialRecipe(recipe, in: .main, on: glow.layer)
                glow.recipe = recipe
            }
            mirrorFadeAndGrow(of: guide, placement: ClassicalGlassPlacement.unscaledFrame(of: guide, in: root), to: &glow)
            dropGlows[id] = glow
        }
        for id in dropGlows.keys where !current.contains(id) {
            dropGlows.removeValue(forKey: id)?.layer.removeFromSuperlayer()
        }
    }

    /// The glow's opacity and scale are the guide's own, and so are their animations: each is copied
    /// once, in the same commit or with the same begin time, so the render server draws both alike.
    /// Only changed values are set: re-setting a material layer's geometry every frame makes it
    /// reconfigure and skip frames.
    private func mirrorFadeAndGrow(of guide: CALayer, placement: ClassicalGlassPlacement?, to glow: inout DropGlow) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let layer = glow.layer
        guard let placement else {
            if !layer.isHidden { layer.isHidden = true }
            return
        }
        let bounds = CGRect(origin: .zero, size: placement.size)
        let transform = CATransform3DConcat(guide.transform, CATransform3DMakeRotation(placement.rotation, 0, 0, 1))
        let opacity = placement.opacity * guide.opacity
        if layer.isHidden { layer.isHidden = false }
        if layer.bounds != bounds { layer.bounds = bounds }
        if layer.position != placement.center { layer.position = placement.center }
        if !CATransform3DEqualToTransform(layer.transform, transform) { layer.transform = transform }
        if layer.cornerRadius != placement.cornerRadius { layer.cornerRadius = placement.cornerRadius }
        if layer.cornerCurve != .continuous { layer.cornerCurve = .continuous }
        if !layer.masksToBounds { layer.masksToBounds = true }
        if layer.opacity != opacity { layer.opacity = opacity }
        for key in ["opacity", "transform"] {
            guard let animation = guide.animation(forKey: key) as? CABasicAnimation else {
                if glow.mirrored.removeValue(forKey: key) != nil { glow.layer.removeAnimation(forKey: key) }
                continue
            }
            let signature = "\(String(describing: animation.fromValue))|\(String(describing: guide.value(forKey: key)))"
            guard glow.mirrored[key] != signature else { continue }
            glow.layer.add(animation, forKey: key)
            glow.mirrored[key] = signature
        }
    }
}
