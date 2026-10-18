import AppKit
import QuartzCore

/// Hover and thumbnail transitions for grouping a dragged Classical application. The springboard
/// owns this collaborator so delayed thumbnail work ends with its presentation.
@MainActor
final class ClassicalGroupDragVisuals {
    struct IconImage {
        let contents: Any?
        let frame: CGRect
    }

    private weak var target: ClassicalItemLayer?
    private weak var dragged: ClassicalItemLayer?
    private var highlights: [CALayer] = []
    /// Deleting-mode visuals the hover paused on the target and dragged cells, restored when it ends.
    private var pausedEditing: [(cell: ClassicalItemLayer, jittering: Bool, closebox: CALayer?)] = []
    private var thumbnails: [CALayer] = []
    private var hiddenThumbnails: [(cell: ClassicalFolderItemLayer, index: Int)] = []
    private var scrolledFolders: [ClassicalFolderItemLayer] = []
    private var staggerTask: Task<Void, Never>?
    /// Drop glow geometry guides, the showing one and any still fading out; the Liquid Glass stage
    /// draws the material where each is on screen.
    private(set) var dropGlowGuides: [CALayer] = []
    private weak var shownDropGlow: CALayer?
    /// With the Liquid Glass option: hovering shows a drop glow instead of darkening and pulsing.
    var showsDropGlow = false
    var slowMotionAllowed: @MainActor () -> Bool = {
        UserDefaults(suiteName: "com.apple.dock").map(ClassicalAnimationParameters.slowMotionAllowed(in:)) ?? false
    }
    var shiftKeyDown: @MainActor () -> Bool = { NSEvent.modifierFlags.contains(.shift) }
    private var animationGeneration = 0

    /// The target darkens (an application's icon; a folder darkens only its image layer, which has
    /// no contents, so its backdrop and thumbnails stay as they are), both titles hide, the dragged
    /// icon returns to its normal size, and in deleting mode both cells stop jittering and lose
    /// their delete badges. The highlight appears at full opacity, scaled to 1.1, and pulses. With the
    /// Liquid Glass option the target neither darkens nor pulses; a drop glow appears behind it.
    func hover(target: ClassicalItemLayer, dragged: ClassicalItemLayer, slow: Bool) {
        endHover()
        self.target = target
        self.dragged = dragged
        // A folder target shows no darkening: only its empty image layer would darken.
        if !showsDropGlow, !(target is ClassicalFolderItemLayer) { target.setDarkened(true) }
        target.titleLayer.opacity = ClassicalAnimationParameters.Drag.hiddenOpacity
        dragged.setMagnified(false)
        dragged.titleLayer.opacity = ClassicalAnimationParameters.Drag.hiddenOpacity
        pauseEditing(of: [target, dragged])
        let folder = target as? ClassicalFolderItemLayer
        if let folder {
            folder.scrollToAvailableSpace()
            scrolledFolders.append(folder)
        }
        if showsDropGlow {
            showDropGlow(behind: target)
            return
        }
        if let folder {
            folder.backdropLayer.transform = CATransform3DMakeScale(ClassicalDragParameters.groupHighlightScale,
                                                                    ClassicalDragParameters.groupHighlightScale, 1)
            pulse(folder.backdropLayer, slow: slow)
            return
        }
        // The highlight is the backdrop a folder cell of the same icon size shows.
        let shape = ClassicalFolderGeometry.Cell(iconFrame: target.iconLayer.frame)
        let frame = shape.backdropFrame
        let backdrop = CALayer()
        backdrop.frame = frame
        backdrop.backgroundColor = CGColor(gray: ClassicalFolderParameters.itemBackdropGray,
                                           alpha: ClassicalFolderParameters.itemBackdropAlpha)
        backdrop.cornerRadius = shape.cornerRadius
        backdrop.cornerCurve = .continuous
        let tint = CALayer()
        tint.frame = frame
        tint.backgroundColor = CGColor(gray: ClassicalDragParameters.groupHighlightTintGray, alpha: 1)
        // Darken blending keeps whatever is already darker than the tint.
        tint.compositingFilter = ClassicalDragParameters.groupHighlightTintFilterName
        tint.cornerRadius = shape.cornerRadius
        tint.cornerCurve = .continuous
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [backdrop, tint] {
            layer.opacity = ClassicalAnimationParameters.Drag.hiddenOpacity
            target.jitterLayer.insertSublayer(layer, below: target.iconLayer)
        }
        CATransaction.commit()
        highlights = [backdrop, tint]
        for layer in highlights {
            layer.opacity = ClassicalAnimationParameters.Drag.visibleOpacity
            layer.transform = CATransform3DMakeScale(ClassicalDragParameters.groupHighlightScale,
                                                     ClassicalDragParameters.groupHighlightScale, 1)
            pulse(layer, slow: slow)
        }
    }

    func endHover(restorePreview: Bool = true) {
        hideDropGlow()
        if !(target is ClassicalFolderItemLayer) { target?.setDarkened(false) }
        target?.titleLayer.opacity = ClassicalAnimationParameters.Drag.visibleOpacity
        dragged?.setMagnified(true)
        dragged?.titleLayer.opacity = ClassicalAnimationParameters.Drag.visibleOpacity
        resumeEditing()
        if let folder = target as? ClassicalFolderItemLayer {
            folder.backdropLayer.removeAnimation(forKey: Self.pulseKey)
            folder.backdropLayer.transform = CATransform3DIdentity
            if restorePreview {
                folder.scrollToTop()
                scrolledFolders.removeAll { $0 === folder }
            }
        }
        for layer in highlights {
            layer.removeAllAnimations()
            layer.opacity = ClassicalAnimationParameters.Drag.hiddenOpacity
            layer.transform = CATransform3DIdentity
            layer.removeFromSuperlayer()
        }
        highlights = []
        target = nil
        dragged = nil
    }

    func clear() {
        animationGeneration += 1
        endHover()
        staggerTask?.cancel()
        staggerTask = nil
        thumbnails.forEach { $0.removeFromSuperlayer() }
        thumbnails = []
        hiddenThumbnails.forEach { $0.cell.setThumbnailVisible(true, at: $0.index) }
        hiddenThumbnails = []
        scrolledFolders.forEach { $0.scrollToTop() }
        scrolledFolders = []
    }

    func image(of cell: ClassicalItemLayer, in host: CALayer) -> IconImage {
        IconImage(contents: cell.iconLayer.contents, frame: cell.iconLayer.convert(cell.iconLayer.bounds, to: host))
    }

    /// Both icon images (frames in `host`) move at once into the folder cell, where they stay on
    /// screen, above the cell's own layers and below later cells on the page; the target minimizes
    /// into a new folder's first thumbnail slot at once and the dragged icon 0.1 seconds later into
    /// its slot. Existing folders target the last thumbnail from their first page.
    func minimize(target: IconImage?, dragged: IconImage, into folder: ClassicalFolderItemLayer,
                  host: CALayer, draggedIndex: Int,
                  onDraggedShrinkComplete: (@MainActor () -> Void)? = nil) {
        endHover(restorePreview: target != nil)
        if target == nil {
            if !scrolledFolders.contains(where: { $0 === folder }) { scrolledFolders.append(folder) }
        }
        // The dragged image goes in last, above the target's.
        let targetLayer = target.map { imageLayer($0, from: host, in: folder) }
        let draggedLayer = imageLayer(dragged, from: host, in: folder)
        if let target, let targetLayer {
            hideThumbnail(0, in: folder)
            animate(targetLayer, image: target, into: folder.thumbnailFrame(at: 0, in: folder),
                    folder: folder, index: 0)
        }
        let destination = folder.thumbnailFrame(at: draggedIndex, in: folder)
        hideThumbnail(draggedIndex, in: folder)
        guard target != nil else {
            animate(draggedLayer, image: dragged, into: destination, folder: folder, index: draggedIndex,
                    onShrinkComplete: onDraggedShrinkComplete)
            return
        }
        staggerTask?.cancel()
        staggerTask = Task { [weak self, weak folder, weak draggedLayer] in
            do { try await Task.sleep(for: .seconds(ClassicalDragParameters.groupDropStagger)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.staggerTask = nil
            guard let folder, let draggedLayer else { return }
            self.animate(draggedLayer, image: dragged, into: destination, folder: folder, index: draggedIndex,
                         onShrinkComplete: onDraggedShrinkComplete)
        }
    }

    /// The target's icon image (frame in `host`) moves into the folder cell and minimizes into its
    /// first thumbnail slot.
    func minimizeTarget(_ image: IconImage, into folder: ClassicalFolderItemLayer, host: CALayer) {
        endHover()
        hideThumbnail(0, in: folder)
        animate(imageLayer(image, from: host, in: folder), image: image, into: folder.thumbnailFrame(at: 0, in: folder),
                folder: folder, index: 0)
    }

    /// A guide the shape of a folder cell's backdrop, behind the target's icon, fading in from 0
    /// while growing to `dropGlowScale`.
    private func showDropGlow(behind target: ClassicalItemLayer) {
        let shape = ClassicalFolderGeometry.Cell(iconFrame: target.iconLayer.frame)
        let guide = CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guide.frame = shape.backdropFrame
        guide.cornerRadius = shape.cornerRadius
        guide.cornerCurve = .continuous
        guide.opacity = ClassicalAnimationParameters.GlassDropGlow.hiddenOpacity
        target.jitterLayer.insertSublayer(guide, at: 0)
        CATransaction.commit()
        dropGlowGuides.append(guide)
        shownDropGlow = guide
        animateDropGlow(guide, shown: true, completion: nil)
    }

    /// The shown glow reverses to opacity 0 at its own size, then leaves the target.
    private func hideDropGlow() {
        guard let guide = shownDropGlow else { return }
        shownDropGlow = nil
        animateDropGlow(guide, shown: false) { [weak self, weak guide] in
            guard let guide else { return }
            guide.removeFromSuperlayer()
            self?.dropGlowGuides.removeAll { $0 === guide }
        }
    }

    /// Explicit animations from where the guide is drawn, because a layer inserted in the same
    /// transaction gets no implicit action.
    private func animateDropGlow(_ guide: CALayer, shown: Bool, completion: (@MainActor () -> Void)?) {
        let scale = ClassicalDragParameters.dropGlowScale
        let drawn = guide.animationKeys()?.isEmpty == false ? guide.presentation() ?? guide : guide
        let targets: [(key: String, from: Any, to: Any)] = [
            ("opacity", drawn.opacity, shown ? ClassicalAnimationParameters.GlassDropGlow.visibleOpacity
                                             : ClassicalAnimationParameters.GlassDropGlow.hiddenOpacity),
            ("transform", NSValue(caTransform3D: drawn.transform),
             NSValue(caTransform3D: shown ? CATransform3DMakeScale(scale, scale, 1) : CATransform3DIdentity)),
        ]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let completion { CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } } }
        for target in targets {
            let animation = CABasicAnimation(keyPath: target.key)
            animation.fromValue = target.from
            animation.duration = ClassicalDragParameters.dropGlowDuration
            animation.timingFunction = CAMediaTimingFunction(name: ClassicalDragParameters.dropGlowTiming)
            guide.setValue(target.to, forKeyPath: target.key)
            guide.add(animation, forKey: target.key)
        }
        CATransaction.commit()
    }

    private func pauseEditing(of cells: [ClassicalItemLayer]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for cell in cells {
            pausedEditing.append((cell, cell.isJittering, cell.closeboxLayer))
            cell.setJittering(false)
            cell.closeboxLayer?.removeFromSuperlayer()
            cell.closeboxLayer = nil
        }
        CATransaction.commit()
    }

    /// Jitter and badges return as they were, unless the cell got a badge of its own meanwhile.
    private func resumeEditing() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (cell, jittering, closebox) in pausedEditing {
            if jittering { cell.setJittering(true) }
            if let closebox, cell.closeboxLayer == nil {
                cell.jitterLayer.addSublayer(closebox)
                cell.closeboxLayer = closebox
            }
        }
        CATransaction.commit()
        pausedEditing = []
    }

    private func hideThumbnail(_ index: Int, in folder: ClassicalFolderItemLayer) {
        folder.setThumbnailVisible(false, at: index)
        hiddenThumbnails.append((folder, index))
    }

    private func forgetThumbnail(_ index: Int, in folder: ClassicalFolderItemLayer) {
        hiddenThumbnails.removeAll { $0.cell === folder && $0.index == index }
    }

    /// A copy of `image` added on top of `folder`'s layers where the icon is on screen (`image.frame`
    /// is in `host`), until its minimize finishes.
    private func imageLayer(_ image: IconImage, from host: CALayer, in folder: ClassicalFolderItemLayer) -> CALayer {
        let layer = CALayer()
        let frame = folder.convert(image.frame, from: host)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image.contents
        layer.contentsGravity = .resizeAspect
        layer.bounds = CGRect(origin: .zero, size: frame.size)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
        folder.addSublayer(layer)
        CATransaction.commit()
        thumbnails.append(layer)
        return layer
    }

    /// Scales `layer` about its centre to the thumbnail's width less 3 pt, moves it onto the
    /// thumbnail offset by (−1, +1) and fades its shadow in, using the current transaction's
    /// duration and timing. The thumbnail then fades in and the copy goes.
    private func animate(_ layer: CALayer, image: IconImage, into destination: CGRect,
                         folder: ClassicalFolderItemLayer, index: Int,
                         onShrinkComplete: (@MainActor () -> Void)? = nil) {
        guard image.frame.width > 0, destination.width > ClassicalDragParameters.groupThumbnailWidthInset else {
            onShrinkComplete?()
            layer.removeFromSuperlayer()
            thumbnails.removeAll { $0 === layer }
            folder.setThumbnailVisible(true, at: index)
            forgetThumbnail(index, in: folder)
            folder.scrollToTop()
            scrolledFolders.removeAll { $0 === folder }
            return
        }
        let generation = animationGeneration
        let scale = (destination.width - ClassicalDragParameters.groupThumbnailWidthInset) / image.frame.width
        CATransaction.begin()
        if slowMotionAllowed() && shiftKeyDown() {
            CATransaction.setAnimationDuration(ClassicalDragParameters.groupShrinkSlowDuration)
        }
        CATransaction.setCompletionBlock { [weak self, weak layer, weak folder] in
            MainActor.assumeIsolated {
                guard let self, self.animationGeneration == generation else {
                    layer?.removeFromSuperlayer()
                    return
                }
                onShrinkComplete?()
                guard let folder else { layer?.removeFromSuperlayer(); return }
                folder.revealThumbnail(at: index) { [weak self, weak layer, weak folder] in
                    guard let self, self.animationGeneration == generation else {
                        layer?.removeFromSuperlayer()
                        return
                    }
                    layer?.removeFromSuperlayer()
                    if let layer { self.thumbnails.removeAll { $0 === layer } }
                    if let folder { self.forgetThumbnail(index, in: folder) }
                    if let folder {
                        folder.scrollToAvailableSpace()
                    }
                }
            }
        }
        applyShrink(to: layer, scale: scale, destination: destination)
        CATransaction.commit()
    }

    /// A newly inserted copy has no committed presentation value from which Core Animation can
    /// synthesize implicit actions, so set its final model values and animate from its initial state.
    private func applyShrink(to layer: CALayer, scale: CGFloat, destination: CGRect) {
        let transform = CATransform3DMakeScale(scale, scale, 1)
        let position = CGPoint(x: destination.midX + ClassicalDragParameters.groupThumbnailPositionOffset.x,
                               y: destination.midY + ClassicalDragParameters.groupThumbnailPositionOffset.y)
        let shadowOffset = ClassicalDragParameters.groupThumbnailShadowOffset
        let shadowRadius = ClassicalDragParameters.groupThumbnailShadowRadius
        let shadowOpacity = ClassicalDragParameters.groupThumbnailShadowOpacity
        let values: [(key: String, from: Any, to: Any)] = [
            ("transform", NSValue(caTransform3D: layer.transform), NSValue(caTransform3D: transform)),
            ("position", NSValue(point: layer.position), NSValue(point: position)),
            ("shadowOffset", NSValue(size: layer.shadowOffset), NSValue(size: shadowOffset)),
            ("shadowRadius", layer.shadowRadius, shadowRadius),
            ("shadowOpacity", layer.shadowOpacity, shadowOpacity),
        ]
        let duration = CATransaction.animationDuration()
        let timing = CATransaction.animationTimingFunction()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        layer.position = position
        layer.shadowOffset = shadowOffset
        layer.shadowRadius = shadowRadius
        layer.shadowOpacity = shadowOpacity
        for value in values {
            let animation = CABasicAnimation(keyPath: value.key)
            animation.fromValue = value.from
            animation.toValue = value.to
            animation.duration = duration
            animation.timingFunction = timing
            layer.add(animation, forKey: value.key)
        }
    }

    /// The pulse replaces the layer's implicit opacity animation, so the highlight shows at full
    /// opacity at once.
    private static let pulseKey = "opacity"

    private func pulse(_ layer: CALayer, slow: Bool) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = ClassicalAnimationParameters.Drag.visibleOpacity
        animation.toValue = ClassicalDragParameters.groupPulseMinimumOpacity
        animation.duration = slow ? ClassicalDragParameters.slowGroupPulseDuration
            : ClassicalDragParameters.groupPulseDuration
        animation.repeatCount = ClassicalDragParameters.groupPulseRepeatCount
        animation.autoreverses = true
        animation.beginTime = CACurrentMediaTime() + ClassicalDragParameters.groupPulseStartDelay
        layer.add(animation, forKey: Self.pulseKey)
    }
}
