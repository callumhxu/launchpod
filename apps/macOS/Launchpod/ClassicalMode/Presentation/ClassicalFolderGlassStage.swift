import AppKit
import QuartzCore

/// Places native folder glass between the desktop and the Classical icon layers, and a second glass
/// layer between the pages and dragged cells, which the springboard draws in `dragLayer`.
@available(macOS 26.0, *)
@MainActor
final class ClassicalFolderGlassStage: NSView {
    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private let rootLayer: CALayer
    private let foreground = PassthroughView()
    // Glass views are not grouped in an `NSGlassEffectContainerView`: a container draws its
    // descendants' glass itself and ignores their `alphaValue`, and each glass must fade with its cell.
    private let glassContent = PassthroughView()
    /// The open panel's glass, which does not belong to the content layer and so does not take its
    /// transform and opacity.
    private let panelGlassHost = PassthroughView()
    /// The search field's glass, above the open panel's; like `glassContent`, it takes the content
    /// layer's transform and opacity.
    private let searchGlassHost = PassthroughView()
    /// Which of the content layer's transform and opacity animations each content glass host carries.
    private var mirroredContent: [ObjectIdentifier: [String: String]] = [:]
    private var closedGlass: [ObjectIdentifier: NSGlassEffectView] = [:]
    /// Glass for cells on the root pages. The pager scrolls this view's sublayers with its strip, in
    /// the same transaction and with the same settle animation, so the glass moves with its page.
    private let stripGlassView = PassthroughView()
    private let openGlass = NSGlassEffectView()
    /// The search field's glass, following the field's background layer.
    private let searchGlass = NSGlassEffectView()
    private let searchBackground: @MainActor () -> CALayer?
    /// Glass for folder cells held in `dragLayer`, above the pages and below the dragged cells.
    private let dragGlassContent = PassthroughView()
    private let dragForeground = PassthroughView()
    /// The springboard's drag host while this stage is installed, with the content layer's geometry.
    private let dragLayer = CALayer()
    private let contentLayer: CALayer
    /// Holds the folder background and drop glow materials, between the desktop and the glass; a
    /// view keeps its place in the stage's layer order.
    private let dropGlowView = PassthroughView()
    private let materials: ClassicalFolderMaterials
    private weak var springboard: ClassicalSpringboard?
    private var displayLink: CADisplayLink?
    /// Runs `synchronize()` before each Core Animation commit on the main run loop, so glass follows
    /// layer changes in the same commit rather than on the next display frame.
    private var commitObserver: CFRunLoopObserver?

    init(frame: CGRect, rootLayer: CALayer, contentLayer: CALayer, springboard: ClassicalSpringboard,
         searchBackground: @escaping @MainActor () -> CALayer? = { nil }) {
        self.rootLayer = rootLayer
        self.searchBackground = searchBackground
        self.contentLayer = contentLayer
        self.springboard = springboard
        materials = ClassicalFolderMaterials(host: dropGlowView)
        super.init(frame: frame)
        wantsLayer = true
        layer = rootLayer
        autoresizingMask = [.width, .height]

        dropGlowView.frame = bounds
        dropGlowView.autoresizingMask = [.width, .height]
        dropGlowView.wantsLayer = true
        addSubview(dropGlowView)

        glassContent.frame = bounds
        glassContent.autoresizingMask = [.width, .height]
        addSubview(glassContent)
        stripGlassView.frame = glassContent.bounds
        stripGlassView.autoresizingMask = [.width, .height]
        stripGlassView.wantsLayer = true
        glassContent.addSubview(stripGlassView)
        panelGlassHost.frame = bounds
        panelGlassHost.autoresizingMask = [.width, .height]
        addSubview(panelGlassHost)
        searchGlassHost.frame = bounds
        searchGlassHost.autoresizingMask = [.width, .height]
        searchGlassHost.wantsLayer = true
        addSubview(searchGlassHost)

        foreground.frame = bounds
        foreground.autoresizingMask = [.width, .height]
        foreground.wantsLayer = true
        addSubview(foreground)
        foreground.layer?.addSublayer(contentLayer)

        dragGlassContent.frame = bounds
        dragGlassContent.autoresizingMask = [.width, .height]
        addSubview(dragGlassContent)

        dragForeground.frame = bounds
        dragForeground.autoresizingMask = [.width, .height]
        dragForeground.wantsLayer = true
        addSubview(dragForeground)
        dragLayer.frame = contentLayer.frame
        dragForeground.layer?.addSublayer(dragLayer)

        openGlass.style = ClassicalFolderParameters.panelGlassStyle
        openGlass.isHidden = true
        openGlass.contentView = PassthroughView()
        panelGlassHost.addSubview(openGlass)

        searchGlass.style = ClassicalFolderParameters.closedGlassStyle
        if searchGlass.responds(to: NSSelectorFromString("set_variant:")) {
            searchGlass.setValue(ClassicalFolderParameters.searchGlassVariant, forKey: "_variant")
        }
        searchGlass.isHidden = true
        searchGlass.contentView = PassthroughView()
        searchGlassHost.addSubview(searchGlass)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Stops following the springboard: the display link and run-loop observer end, and the drag
    /// overlay and strip mirror are released if they are still this stage's. Leaving the window does
    /// this too; the owner calls it before discarding the stage so teardown does not depend on it.
    func tearDown() {
        displayLink?.invalidate()
        displayLink = nil
        if let commitObserver { CFRunLoopRemoveObserver(CFRunLoopGetMain(), commitObserver, .commonModes) }
        commitObserver = nil
        if springboard?.dragOverlay === dragLayer { springboard?.dragOverlay = nil }
        if springboard?.pager.stripMirror === stripGlassView.layer { springboard?.pager.stripMirror = nil }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tearDown()
        guard window != nil else { return }
        springboard?.dragOverlay = dragLayer
        springboard?.pager.stripMirror = stripGlassView.layer
        synchronize()
        let link = super.displayLink(target: self, selector: #selector(displayFrame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        // Core Animation commits in the before-waiting phase at order 2 000 000; this runs just before.
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true,
                                                          ClassicalFolderParameters.glassCommitObserverOrder) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.synchronize() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        commitObserver = observer
    }

    @objc private func displayFrame(_ link: CADisplayLink) { synchronize() }

    func synchronize() {
        guard let springboard else { return }
        followContentGeometry()
        mirrorContent()
        var visible = Set<ObjectIdentifier>()
        var cells = springboard.pager.pages.flatMap(\.itemLayers)
        // A dragged cell rides above the pages and may have left them.
        if let dragged = springboard.drag?.cell, !cells.contains(where: { $0 === dragged }) { cells.append(dragged) }
        for case let cell as ClassicalFolderItemLayer in cells where cell.glassEnabled {
            let id = ObjectIdentifier(cell)
            visible.insert(id)
            let glass = closedGlass[id] ?? makeClosedGlass(for: id)
            let strip = springboard.pager.stripLayer
            if ClassicalGlassPlacement.isDescendant(cell, of: dragLayer) {
                place(glass, in: dragGlassContent)
                apply(ClassicalGlassPlacement.covering(cell.backdropLayer, in: rootLayer), to: glass)
            } else if ClassicalGlassPlacement.isDescendant(cell, of: strip) {
                place(glass, in: stripGlassView)
                let placement = ClassicalGlassPlacement.onStrip(cell.backdropLayer, strip: strip, in: contentLayer)
                apply(untransformed(placement), to: glass)
            } else {
                place(glass, in: glassContent)
                apply(untransformed(ClassicalGlassPlacement.covering(cell.backdropLayer, in: contentLayer)), to: glass)
            }
        }
        for id in closedGlass.keys.filter({ !visible.contains($0) }) {
            closedGlass.removeValue(forKey: id)?.removeFromSuperview()
        }
        materials.synchronize(folders: springboard.folders, dropGlowGuides: springboard.groupVisuals.dropGlowGuides,
                              in: rootLayer)
        let search = searchBackground().flatMap { ClassicalGlassPlacement.covering($0, in: contentLayer) }
        apply(untransformed(search), to: searchGlass)
        if let panel = springboard.folders.folder?.layer, panel.glassEnabled {
            apply(ClassicalGlassPlacement.covering(panel.backdropLayer, in: rootLayer), to: openGlass)
        } else {
            openGlass.isHidden = true
        }
    }

    /// `glassContent` and `searchGlassHost` take the content layer's transform (about the content's
    /// anchor, as a sublayer transform) and opacity, with their animations copied in the same commit,
    /// so glass for content follows the launcher's zoom and the folder fade on the render server.
    /// Placements for them are therefore computed in the content layer's coordinates (`untransformed`).
    private func mirrorContent() {
        for view in [glassContent, searchGlassHost] {
            guard let host = view.layer else { continue }
            let key = ObjectIdentifier(view)
            var mirrored = mirroredContent[key] ?? [:]
            mirrorContent(to: host, mirrored: &mirrored)
            mirroredContent[key] = mirrored
        }
    }

    private func mirrorContent(to host: CALayer, mirrored mirroredContent: inout [String: String]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let transform = conjugated(contentLayer.transform, in: host)
        if !CATransform3DEqualToTransform(host.sublayerTransform, transform) { host.sublayerTransform = transform }
        if host.opacity != contentLayer.opacity { host.opacity = contentLayer.opacity }
        for (source, target) in [("transform", "sublayerTransform"), ("opacity", "opacity")] {
            let key = "classicalContent." + source
            guard let animation = contentLayer.animation(forKey: source) as? CABasicAnimation else {
                if mirroredContent.removeValue(forKey: source) != nil { host.removeAnimation(forKey: key) }
                continue
            }
            let signature = "\(String(describing: animation.fromValue))|\(String(describing: animation.toValue))|"
                + "\(String(describing: contentLayer.value(forKey: source)))|\(animation.duration)"
            guard mirroredContent[source] != signature else { continue }
            let mirrored = CABasicAnimation(keyPath: target)
            if source == "transform" {
                func mapped(_ value: Any?) -> NSValue? {
                    (value as? NSValue).map { NSValue(caTransform3D: conjugated($0.caTransform3DValue, in: host)) }
                }
                mirrored.fromValue = mapped(animation.fromValue)
                mirrored.toValue = mapped(animation.toValue)
            } else {
                mirrored.fromValue = animation.fromValue
                mirrored.toValue = animation.toValue
            }
            mirrored.beginTime = animation.beginTime
            mirrored.duration = animation.duration
            mirrored.timingFunction = animation.timingFunction
            mirrored.fillMode = animation.fillMode
            mirrored.isRemovedOnCompletion = animation.isRemovedOnCompletion
            host.add(mirrored, forKey: key)
            mirroredContent[source] = signature
        }
    }

    /// `transform` applied about the content layer's anchor, expressed as `host`'s sublayer transform,
    /// which applies about `host`'s own anchor.
    private func conjugated(_ transform: CATransform3D, in host: CALayer) -> CATransform3D {
        guard !CATransform3DIsIdentity(transform) else { return transform }
        let anchor = CGPoint(x: host.bounds.minX + host.anchorPoint.x * host.bounds.width,
                             y: host.bounds.minY + host.anchorPoint.y * host.bounds.height)
        let center = host.convert(contentLayer.position, from: contentLayer.superlayer)
        let offset = CGPoint(x: center.x - anchor.x, y: center.y - anchor.y)
        return CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-offset.x, -offset.y, 0), transform),
                                   CATransform3DMakeTranslation(offset.x, offset.y, 0))
    }

    /// A placement in the content layer's coordinates, taken to the stage as if the content layer
    /// had no transform (`glassContent` applies it).
    private func untransformed(_ placement: ClassicalGlassPlacement?) -> ClassicalGlassPlacement? {
        guard var placement, let parent = contentLayer.superlayer else { return placement }
        let bounds = contentLayer.bounds
        let anchor = CGPoint(x: bounds.minX + contentLayer.anchorPoint.x * bounds.width,
                             y: bounds.minY + contentLayer.anchorPoint.y * bounds.height)
        let inParent = CGPoint(x: contentLayer.position.x + placement.center.x - anchor.x,
                               y: contentLayer.position.y + placement.center.y - anchor.y)
        placement.center = rootLayer.convert(inParent, from: parent)
        return placement
    }

    /// The drag layer keeps the content layer's frame and transform, so drag-host coordinates match.
    private func followContentGeometry() {
        guard dragLayer.frame != contentLayer.frame || !CATransform3DEqualToTransform(dragLayer.transform,
                                                                                      contentLayer.transform) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dragLayer.transform = CATransform3DIdentity
        dragLayer.frame = contentLayer.frame
        dragLayer.transform = contentLayer.transform
        CATransaction.commit()
    }

    /// A folder cell in the drag layer has its glass above the pages; one on the root page strip in
    /// the strip glass view; any other, in the content glass host.
    private func place(_ glass: NSGlassEffectView, in host: NSView) {
        guard glass.superview !== host else { return }
        glass.removeFromSuperview()
        host.addSubview(glass)
    }

    private func makeClosedGlass(for id: ObjectIdentifier) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = ClassicalFolderParameters.closedGlassStyle
        glass.contentView = PassthroughView()
        glassContent.addSubview(glass)
        closedGlass[id] = glass
        return glass
    }

    /// Moves `glass` onto `placement` without animation; unchanged values are left alone so an idle
    /// frame does not relayout the glass.
    private func apply(_ placement: ClassicalGlassPlacement?, to glass: NSGlassEffectView) {
        guard let placement else {
            if !glass.isHidden { glass.isHidden = true }
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if glass.isHidden { glass.isHidden = false }
        let frame = CGRect(x: placement.center.x - placement.size.width / 2,
                           y: placement.center.y - placement.size.height / 2,
                           width: placement.size.width, height: placement.size.height)
        let degrees = placement.rotation * 180 / .pi
        if glass.frame != frame || glass.frameCenterRotation != degrees {
            // The frame is the unrotated rectangle; rotation then turns it about its centre.
            if glass.frameCenterRotation != 0 { glass.frameCenterRotation = 0 }
            glass.frame = frame
            if degrees != 0 { glass.frameCenterRotation = degrees }
        }
        if glass.cornerRadius != placement.cornerRadius { glass.cornerRadius = placement.cornerRadius }
        let alpha = CGFloat(placement.opacity)
        if glass.alphaValue != alpha { glass.alphaValue = alpha }
        CATransaction.commit()
    }
}
