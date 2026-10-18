import AppKit
import QuartzCore

/// Opens and closes Classical folders over the root pages and owns the folder while it is shown.
///
/// Opening hides the closed cell and grows the panel out of the cell's backdrop: the mask, backdrop
/// and corner radius expand, the first page's icons move from the thumbnail grid to their slots
/// with their titles rising from under the thumbnails, and the folder title fades in, while the
/// root pages scale to 0.95 and fade out. When that finishes the page dots fade in over 0.1 s
/// (0.5 s with Shift).
/// Closing reverses it; once the panel has shrunk back the cell reappears and, 0.25 s later,
/// `didClose` asks for the root pages to be laid out again. Both transitions use the implicit
/// animation of one transaction. With Reduce Motion the panel changes at once and the root pages do
/// not scale, but they still fade.
@MainActor
final class ClassicalFolderPresenter {
    private(set) var folder: ClassicalFolder?
    private(set) var isOpening = false
    private(set) var isClosing = false
    /// The accessibility element of the open folder, a child of `accessibilityParent`.
    private(set) var accessibilityElement: NSAccessibilityElement?
    /// The view whose accessibility children include the open folder.
    weak var accessibilityParent: NSView?
    /// The language of the folder's accessibility role description.
    var locale: @MainActor () -> Locale = { .current }
    var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Allows the Shift-key slow animation when the invoking presentation permits it.
    var slowMotionAllowed: @MainActor () -> Bool = {
        UserDefaults(suiteName: "com.apple.dock").map(ClassicalFolderPresenter.slowMotionAllowed(in:)) ?? false
    }
    var shiftKeyDown: @MainActor () -> Bool = { NSEvent.modifierFlags.contains(.shift) }
    /// Called when a folder starts opening (true) and when one has closed (false).
    var visibilityChanged: (@MainActor (Bool) -> Void)?
    /// Called when an open folder starts its closing transition.
    var willClose: (@MainActor () -> Void)?
    /// Called once the root pages should be laid out again after a folder closed.
    var didClose: (@MainActor () -> Void)?
    /// Replaceable in tests: waits before `didClose`.
    var sleep: @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }

    static func slowMotionAllowed(in defaults: UserDefaults) -> Bool {
        ClassicalAnimationParameters.slowMotionAllowed(in: defaults)
    }

    private var anchors: Anchors?
    private weak var background: CALayer?
    /// The layer holding the root pages, which fades out while a folder is open.
    var backgroundLayer: CALayer? { background }
    private weak var mainPager: ClassicalPager?
    private var dotsWereHidden = false
    private var settleTask: Task<Void, Never>?
    private var closeCompletion: (@MainActor () -> Void)?

    /// Where the closed cell is, in the panel's coordinates, captured before the root pages scale.
    private struct Anchors {
        let backdrop: CGRect
        let cornerRadius: CGFloat
        let cell: CGRect
        let thumbnails: [CGRect]
    }

    isolated deinit {
        settleTask?.cancel()
    }

    /// True from the start of opening until closing has finished.
    var isActive: Bool { folder != nil }
    /// The folder that is shown and not closing.
    var openFolder: ClassicalFolder? { isClosing ? nil : folder }
    /// The layers that make up the shown panel in its host.
    var panelLayers: [CALayer] { folder.map { [$0.layer] } ?? [] }

    /// Shows `folder` in `host` above `background`, the layer holding the root pages, whose page dots
    /// hide meanwhile. With `selectingFirstItem`, the folder's first application is selected once open.
    func open(_ folder: ClassicalFolder, host: CALayer, background: CALayer, mainPager: ClassicalPager,
              selectingFirstItem: Bool) {
        guard self.folder == nil else { return }
        settleTask?.cancel()
        self.folder = folder
        self.background = background
        self.mainPager = mainPager
        isOpening = true
        let cell = folder.cell
        withoutActions {
            dotsWereHidden = mainPager.dotsLayer.isHidden
            mainPager.dotsLayer.isHidden = true
            cell.opacity = ClassicalAnimationParameters.Folder.hiddenOpacity
            cell.titleLayer.isHidden = true
            host.addSublayer(folder.layer)
        }
        let anchors = Self.anchors(of: folder)
        self.anchors = anchors
        withoutActions { applyClosedState(folder, anchors: anchors) }
        CATransaction.flush()
        visibilityChanged?(true)
        let reduceMotion = reduceMotion()
        let slow = !reduceMotion && slowMotionAllowed() && shiftKeyDown()
        CATransaction.begin()
        if slow {
            CATransaction.setAnimationDuration(ClassicalFolderParameters.slowMotionDuration)
        }
        CATransaction.setCompletionBlock { [weak self, weak folder] in
            MainActor.assumeIsolated {
                guard let self, let folder, self.folder === folder, !self.isClosing else { return }
                self.isOpening = false
                self.fadeInDots(folder, reduceMotion: reduceMotion)
                self.restoreFilters(folder)
                if selectingFirstItem { folder.select(folder.content.pages.first?.first?.id) }
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        applyOpenState(folder)
        CATransaction.commit()
        if !reduceMotion {
            background.transform = CATransform3DMakeScale(ClassicalFolderParameters.backgroundScale,
                                                          ClassicalFolderParameters.backgroundScale, 1)
        }
        background.opacity = ClassicalFolderParameters.backgroundOpacity
        CATransaction.commit()
        postAccessibilityCreated(for: folder)
    }

    /// Closes the open folder: its title edit ends and its deleting mode stops first. Without
    /// `animated` everything returns at once and neither `didClose` nor `completion` is called;
    /// otherwise `completion` runs once the panel has shrunk back and the cell reappeared.
    func close(animated: Bool = true, completion: (@MainActor () -> Void)? = nil) {
        guard let folder, animated ? !isClosing : true else { return }
        folder.endTitleEditing()
        folder.setDeleting(false)
        folder.select(nil)
        guard animated, let anchors else { return finishClosing(folder, settles: false) }
        isClosing = true
        isOpening = false
        closeCompletion = completion
        willClose?()
        folder.cell.setFolder(folder.content)
        let reduceMotion = reduceMotion()
        CATransaction.begin()
        if !reduceMotion && slowMotionAllowed() && shiftKeyDown() {
            CATransaction.setAnimationDuration(ClassicalFolderParameters.slowMotionDuration)
        }
        CATransaction.setCompletionBlock { [weak self, weak folder] in
            MainActor.assumeIsolated {
                guard let self, let folder, self.folder === folder else { return }
                self.finishClosing(folder, settles: true)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        applyClosedState(folder, anchors: anchors)
        CATransaction.commit()
        background?.transform = CATransform3DIdentity
        background?.opacity = ClassicalAnimationParameters.Folder.visibleOpacity
        CATransaction.commit()
        postAccessibilityDestroyed()
    }

    /// The root pages were rebuilt while the folder is shown: `cell` now stands for it on its page.
    /// It stays hidden until the folder has closed, and the panel still closes into the slot where
    /// the folder was when it opened.
    func replaceCell(_ cell: ClassicalFolderItemLayer) {
        guard let folder, cell !== folder.cell else { return }
        withoutActions {
            cell.opacity = ClassicalAnimationParameters.Folder.hiddenOpacity
            cell.titleLayer.isHidden = true
        }
        folder.replaceCell(cell)
    }

    private func finishClosing(_ folder: ClassicalFolder, settles: Bool) {
        withoutActions {
            folder.layer.removeFromSuperlayer()
            background?.transform = CATransform3DIdentity
            background?.opacity = ClassicalAnimationParameters.Folder.visibleOpacity
            if let mainPager { mainPager.dotsLayer.isHidden = dotsWereHidden || mainPager.dotsLayer.layout.isHidden }
            folder.cell.opacity = ClassicalAnimationParameters.Folder.visibleOpacity
            folder.cell.titleLayer.isHidden = false
        }
        postAccessibilityDestroyed()
        self.folder = nil
        anchors = nil
        isOpening = false
        isClosing = false
        let completion = closeCompletion
        closeCompletion = nil
        visibilityChanged?(false)
        guard settles else { return }
        completion?()
        settleTask = Task { [weak self, sleep] in
            do { try await sleep(ClassicalFolderParameters.closeSettleDelay) } catch { return }
            guard let self, !Task.isCancelled, self.folder == nil else { return }
            self.settleTask = nil
            self.didClose?()
        }
    }

    // MARK: States

    private static func anchors(of folder: ClassicalFolder) -> Anchors {
        let cell = folder.cell, panel = folder.layer
        let capacity = folder.geometry.grid.capacity
        return Anchors(backdrop: panel.convert(cell.backdropLayer.frame, from: cell.jitterLayer),
                       cornerRadius: cell.geometry.cornerRadius,
                       cell: panel.convert(cell.bounds, from: cell),
                       thumbnails: (0..<capacity).map { cell.thumbnailFrame(at: $0, in: panel) })
    }

    /// The panel collapsed into the cell: icons of the folder's first page in the thumbnail cells,
    /// each title hidden just under its thumbnail, and those past the ninth hidden; page dots faded
    /// out at the cell's bottom. The visible icons use trilinear minification while they are small.
    private func applyClosedState(_ folder: ClassicalFolder, anchors: Anchors) {
        folder.layer.applyClosedState(itemBackdrop: anchors.backdrop, cornerRadius: anchors.cornerRadius, cell: anchors.cell)
        let dots = folder.pager.dotsLayer
        dots.opacity = ClassicalAnimationParameters.Folder.hiddenOpacity
        if let holder = dots.superlayer {
            let cell = holder.convert(anchors.cell, from: folder.layer)
            dots.frame = CGRect(x: cell.midX - dots.bounds.width / 2, y: cell.minY,
                                width: dots.bounds.width, height: dots.bounds.height)
        }
        let thumbnails = ClassicalFolderParameters.miniGridRows * ClassicalFolderParameters.miniGridColumns
        for (index, cell) in firstPageCells(of: folder).enumerated() {
            if anchors.thumbnails.indices.contains(index) {
                let thumbnail = anchors.thumbnails[index]
                cell.iconLayer.frame = cell.jitterLayer.convert(thumbnail, from: folder.layer)
                let size = cell.titleLayer.bounds.size
                let title = CGRect(x: CGFloat(Int(thumbnail.midX - size.width / 2)), y: thumbnail.minY - size.height,
                                   width: size.width, height: size.height)
                cell.titleLayer.frame = cell.jitterLayer.convert(title, from: folder.layer)
            }
            cell.titleLayer.opacity = ClassicalAnimationParameters.Folder.hiddenOpacity
            if index >= thumbnails {
                cell.opacity = ClassicalAnimationParameters.Folder.hiddenOpacity
            } else {
                cell.iconLayer.minificationFilter = ClassicalFolderParameters.transitionMinificationFilter
            }
        }
    }

    private func applyOpenState(_ folder: ClassicalFolder) {
        folder.layer.applyOpenState()
        folder.pager.dotsLayer.frame = folder.geometry.dotsFrame
        for cell in firstPageCells(of: folder) {
            cell.iconLayer.frame = cell.layout.iconFrame
            cell.titleLayer.frame = cell.titleFrame
            cell.titleLayer.opacity = ClassicalAnimationParameters.Folder.visibleOpacity
            cell.opacity = ClassicalAnimationParameters.Folder.visibleOpacity
        }
    }

    private func restoreFilters(_ folder: ClassicalFolder) {
        withoutActions {
            for cell in firstPageCells(of: folder) { cell.iconLayer.minificationFilter = .linear }
        }
    }

    private func fadeInDots(_ folder: ClassicalFolder, reduceMotion: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(shiftKeyDown() ? ClassicalFolderParameters.slowSecondPhaseDuration
                                                          : ClassicalFolderParameters.secondPhaseDuration)
        CATransaction.setDisableActions(reduceMotion)
        folder.pager.dotsLayer.opacity = ClassicalAnimationParameters.Folder.visibleOpacity
        CATransaction.commit()
    }

    /// Opening and closing always move the folder's first page, whichever page is shown.
    private func firstPageCells(of folder: ClassicalFolder) -> [ClassicalItemLayer] {
        folder.pager.pages.first?.itemLayers ?? []
    }

    // MARK: Accessibility

    private func postAccessibilityCreated(for folder: ClassicalFolder) {
        guard let parent = accessibilityParent, let host = folder.layer.superlayer, let viewLayer = parent.layer else { return }
        let element = NSAccessibilityElement()
        element.setAccessibilityRole(.group)
        element.setAccessibilityRoleDescription(String(localized: LocalizedStringResource(
            "folder", locale: locale(), comment: "Accessibility role description of an open Classical folder")))
        element.setAccessibilityLabel(folder.content.title)
        element.setAccessibilityParent(parent)
        let frame = folder.layer.convert(folder.geometry.backdropFrame, to: host)
        element.setAccessibilityFrameInParentSpace(viewLayer.convert(frame, from: host))
        accessibilityElement = element
        NSAccessibility.post(element: element, notification: .created)
    }

    private func postAccessibilityDestroyed() {
        guard let element = accessibilityElement else { return }
        accessibilityElement = nil
        NSAccessibility.post(element: element, notification: .uiElementDestroyed)
    }

    private func withoutActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
