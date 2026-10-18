import AppKit

/// Receives key focus, forwards keys to the keyboard handler and paging input to the pager, and
/// treats a click on empty space as a dismissal. The click dismisses on release, and only when the
/// pointer stayed within 3 pt on both axes. A press on an icon darkens it while the pointer stays
/// over it and opens the application on release.
///
/// While a folder is open, presses on its backdrop go to its cells and pager. A press outside the
/// page area closes the folder at once; one elsewhere outside the panel closes it on release. A
/// press inside the panel but off the backdrop closes it on release unless the pointer moved 3 pt
/// on either axis at some point, and ends a title edit either way. Releasing on the title starts
/// editing it.
final class ClassicalContentView: NSView, NSDraggingSource {
    static let externalDragOperations: NSDragOperation = [.copy, .link, .delete]

    private struct ExternalDrag {
        let record: AppRecord
        let windowLevel: NSWindow.Level?
    }

    var dismiss: (@MainActor () -> Void)?
    var openSettings: (@MainActor () -> Void)?
    var showsMenuBarItem: @MainActor () -> Bool = { true }
    var menuLocale: @MainActor () -> Locale = { .current }
    weak var pager: ClassicalPager?
    weak var keyboard: ClassicalKeyboard? {
        didSet { keyboard?.drag = drag }
    }
    weak var springboard: ClassicalSpringboard? {
        didSet {
            press.springboard = springboard
            deletion.springboard = springboard
            drag.springboard = springboard
        }
    }
    var launch: (@MainActor (AppRecord) -> Void)? {
        get { press.launch }
        set { press.launch = newValue }
    }
    let press = ClassicalItemPress()
    let deletion = ClassicalDeletion()
    let drag = ClassicalItemDrag()
    private var pressLocation: CGPoint?
    private var pressMoved = false
    private var pressOnDots = false
    /// A press while a folder is open that is not for its cells or pager.
    private var folderPress: FolderPress?

    private struct FolderPress {
        enum Place {
            /// Outside the panel, within the page area.
            case pageArea
            /// In the panel, off the backdrop and the title.
            case panel
            case title
        }

        let start: CGPoint
        let place: Place
        /// The pointer went 3 pt or more from `start` on either axis at some point.
        var moved = false
    }
    private var mouseDownEvent: NSEvent?
    private var externalDrag: ExternalDrag?
    /// Rebuilt for each presentation, because it adopts that presentation's root layer.
    private var glassStage: NSView?
    var isExternalDragging: Bool { externalDrag != nil }
    /// The window owner resolves the current level after a drag, which may outlive a folder.
    var externalDragDidEnd: (@MainActor () -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        press.requestDeletion = { [weak self] record, cell in
            guard let self else { return }
            self.deletion.present(record, cell: cell, in: self)
        }
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    func installGlassStage(rootLayer: CALayer, contentLayer: CALayer) {
        removeGlassStage()
        guard #available(macOS 26.0, *), let springboard, springboard.folderGlassEnabled else { return }
        contentLayer.removeFromSuperlayer()
        let stage = ClassicalFolderGlassStage(frame: bounds, rootLayer: rootLayer,
                                              contentLayer: contentLayer, springboard: springboard,
                                              searchBackground: { [weak self] in
                                                  guard let field = self?.keyboard?.field, field.usesGlass else { return nil }
                                                  return field.backgroundLayer
                                              })
        // Below every other subview: the search text field and the folder title editor stay above the
        // stage's glass and layers, including when the stage is installed again on a later show.
        addSubview(stage, positioned: .below, relativeTo: nil)
        glassStage = stage
    }

    func removeGlassStage() {
        if #available(macOS 26.0, *) { (glassStage as? ClassicalFolderGlassStage)?.tearDown() }
        glassStage?.removeFromSuperview()
        glassStage = nil
    }

    override func cancelOperation(_ sender: Any?) {
        if deletion.isPanelShown { return deletion.dismiss() }
        if let keyboard { keyboard.cancel() } else { dismiss?() }
    }

    override func keyDown(with event: NSEvent) {
        if deletion.keyDown(event) { return }
        if keyboard?.keyDown(event) != true { super.keyDown(with: event) }
    }

    /// Holding Option shows deleting mode while it is down.
    override func flagsChanged(with event: NSEvent) {
        springboard?.optionChanged(isDown: event.modifierFlags.contains(.option))
        super.flagsChanged(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard !showsMenuBarItem(), bounds.contains(point), let springboard, let pager,
              !deletion.isPanelShown, !springboard.isDeleting, !springboard.folders.isActive,
              springboard.drag == nil, !drag.isCancelling, !isExternalDragging,
              pressLocation == nil, springboard.item(at: point) == nil,
              pager.closebox(at: point) == nil,
              keyboard?.field.contains(point) != true else { return nil }
        let pagerPoint = pager.layer.convert(point, from: layer)
        guard pager.dotsLayer.isHidden || !pager.dotsLayer.frame.contains(pagerPoint) else { return nil }

        let menu = NSMenu()
        let title = String(localized: LocalizedStringResource("Settings", locale: menuLocale())) + "…"
        let item = NSMenuItem(title: title, action: #selector(openSettingsFromContextMenu(_:)), keyEquivalent: "")
        item.target = self
        item.setAccessibilityIdentifier("openSettings")
        menu.addItem(item)
        return menu
    }

    @objc private func openSettingsFromContextMenu(_ sender: Any?) {
        openSettings?()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = nil
        if drag.isCancelling {
            guard springboard?.drag == nil else { return }
            _ = drag.consumeCancelledMouseUp()
        }
        // Clicks are swallowed while the deletion panel is open.
        if deletion.isPanelShown { return }
        let point = convert(event.locationInWindow, from: nil)
        if let folders = springboard?.folders, folders.isActive {
            if folderMouseDown(at: point, folders: folders) { return }
        } else {
            if keyboard?.mouseDown(at: point) == true { return }
            // Outside the page area (the band above the Dock) the launcher closes on
            // the press itself; inside it the pager takes the press.
            if let pager, pager.layer.superlayer != nil, !pager.layer.frame.contains(point) {
                dismiss?()
                return
            }
        }
        if press.beginBadge(at: point) { return }
        pressLocation = point
        pressMoved = false
        // Scrolling that is still under way ends before an icon is held; see `scrollWheel(with:)`.
        if springboard?.item(at: point) != nil { activePager?.endScrolling() }
        pressOnDots = activePager?.mouseDown(at: pagerPoint(point), time: event.timestamp) ?? false
        if !pressOnDots {
            press.beginIcon(at: point)
            if press.pressedItem != nil {
                mouseDownEvent = event
                drag.pressBegan()
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isExternalDragging { return }
        if drag.isCancelling { return }
        if deletion.isPanelShown { return }
        if keyboard?.isTrackingClearButton == true {
            keyboard?.mouseDragged(to: convert(event.locationInWindow, from: nil))
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if var folderPress {
            let tolerance = ClassicalFolderParameters.outsideClickTolerance
            if abs(point.x - folderPress.start.x) >= tolerance || abs(point.y - folderPress.start.y) >= tolerance {
                folderPress.moved = true
                self.folderPress = folderPress
            }
            return
        }
        if drag.isDragging {
            drag.moved(to: point, time: event.timestamp)
            if drag.shouldHandOffToDock(at: point, in: self) { beginExternalItemDrag() }
            return
        }
        if beginItemDrag(at: point, time: event.timestamp) { return }
        guard let pressLocation else {
            press.dragged(to: point, pagerIsDragging: false)
            return
        }
        if abs(point.x - pressLocation.x) >= ClassicalPagerTracking.dragActivation
            || abs(point.y - pressLocation.y) >= ClassicalPagerTracking.dragActivation {
            pressMoved = true
        }
        if !pressOnDots { activePager?.mouseDragged(to: pagerPoint(point)) }
        press.dragged(to: point, pagerIsDragging: activePager?.tracking.isDragging == true)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        drag.pressEnded()
        if drag.consumeCancelledMouseUp() {
            pressLocation = nil
            press.cancel()
            return
        }
        if isExternalDragging { return }
        if deletion.isPanelShown { return }
        if keyboard?.isTrackingClearButton == true {
            keyboard?.mouseUp(at: convert(event.locationInWindow, from: nil))
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if drag.isDragging {
            pressLocation = nil
            drag.ended(at: point)
            return
        }
        if let folderPress {
            self.folderPress = nil
            folderMouseUp(at: point, press: folderPress)
            return
        }
        guard pressLocation != nil else {
            _ = press.end(at: point)
            return
        }
        pressLocation = nil
        if pressOnDots {
            press.cancel()
            activePager?.dotsMouseUp(at: pagerPoint(point))
        } else if activePager?.mouseUp(at: pagerPoint(point), time: event.timestamp) == true {
            press.cancel()
        } else if press.end(at: point) {
            return
        } else if !pressMoved, springboard?.folders.isActive != true {
            // A blank click first leaves deleting mode.
            if let springboard, springboard.isDeleting { springboard.setDeleting(false) } else { dismiss?() }
        }
    }

    /// The root pager, or the open folder's.
    private var activePager: ClassicalPager? {
        springboard?.folders.folder?.pager ?? pager
    }

    /// `point` where the active pager expects it.
    private func pagerPoint(_ point: CGPoint) -> CGPoint {
        springboard?.folders.folder?.pagerPoint(point) ?? point
    }

    /// Returns true when the press is not for the folder's cells or pager.
    private func folderMouseDown(at point: CGPoint, folders: ClassicalFolderPresenter) -> Bool {
        guard let folder = folders.openFolder else { return true }
        guard folder.panelContains(point) else {
            // A press outside the page area closes the folder at once; one inside it closes the
            // folder on release. The page area is where the pages are drawn, scaled down while the
            // folder is open.
            if let pager, let layer, pager.layer.superlayer != nil,
               !pager.layer.convert(pager.layer.bounds, to: layer).contains(point) {
                folders.close()
            } else {
                folderPress = FolderPress(start: point, place: .pageArea)
            }
            return true
        }
        if folder.backdropContains(point) { return false }
        folderPress = FolderPress(start: point, place: folder.titleContains(point) ? .title : .panel)
        return true
    }

    private func folderMouseUp(at point: CGPoint, press: FolderPress) {
        guard let folders = springboard?.folders, let folder = folders.openFolder else { return }
        switch press.place {
        case .title:
            if folder.titleContains(point) { folder.beginTitleEditing(in: self) }
        case .panel:
            folder.endTitleEditing()
            if !press.moved { folders.close() }
        case .pageArea:
            folders.close()
        }
    }

    /// Three points of travel on either axis with the
    /// pointer still over the pressed icon starts dragging it instead of the pages.
    private func beginItemDrag(at point: CGPoint, time: TimeInterval) -> Bool {
        guard !pressOnDots, let item = press.pressedItem,
              (springboard?.pages.joined().contains(where: { $0.id == item.item.id }) == true
                || springboard?.folders.openFolder?.content.records.contains(where: { $0.id == item.item.record?.id }) == true),
              pager?.tracking.isDragging != true,
              abs(point.x - press.start.x) >= ClassicalDragParameters.activationDistance
                || abs(point.y - press.start.y) >= ClassicalDragParameters.activationDistance,
              springboard?.item(at: point)?.cell === item.cell else { return false }
        let wasFiltering = springboard?.isFiltering == true
        press.handOffToDrag()
        // The press's location and time seed the first speed measurement.
        guard drag.begin(item.item, cell: item.cell, at: press.start, time: mouseDownEvent?.timestamp ?? time) else {
            return false
        }
        if wasFiltering { keyboard?.clearSearchForDrag() }
        drag.moved(to: point, time: time)
        if drag.shouldHandOffToDock(at: point, in: self) { beginExternalItemDrag() }
        return true
    }

    private func beginExternalItemDrag() {
        guard !isExternalDragging, !drag.isCancelling, let mouseDownEvent, let current = springboard?.drag,
              let record = current.item.record,
              let item = drag.makeExternalDraggingItem(for: record, cell: current.cell, in: self) else { return }
        drag.suspendForExternalDrag()
        pressLocation = nil
        pressMoved = false
        pressOnDots = false
        self.mouseDownEvent = nil
        var windowLevel: NSWindow.Level?
        if let window, window.level.rawValue > ClassicalPresentationParameters.windowLevel {
            windowLevel = window.level
            window.level = NSWindow.Level(rawValue: ClassicalPresentationParameters.windowLevel)
        }
        externalDrag = ExternalDrag(record: record, windowLevel: windowLevel)
        beginDraggingSession(with: [item], event: mouseDownEvent, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        Self.externalDragOperations
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard let externalDrag else { return }
        if let windowLevel = externalDrag.windowLevel { window?.level = windowLevel }
        self.externalDrag = nil
        externalDragDidEnd?()
        completeExternalDrag(record: externalDrag.record, operation: operation)
    }

    /// Finishes the retained internal drag only after AppKit reports the destination: the item
    /// returns to its slot without persisting a rearrangement. A Trash drop of a deletable
    /// application then asks for the same confirmation as its delete badge; nothing is removed
    /// unless the user confirms, and other applications stay as they are.
    func completeExternalDrag(record: AppRecord, operation: NSDragOperation) {
        drag.cancel(animated: false)
        _ = drag.consumeCancelledMouseUp()
        guard operation.contains(.delete), let springboard, springboard.canDelete(record),
              let cell = springboard.cell(for: record.id) else { return }
        deletion.present(record, cell: cell, in: self)
    }

    /// While an icon is held or dragged, wheel and trackpad paging are swallowed. While a folder is
    /// open its pages turn instead, and only with the pointer over its backdrop.
    override func scrollWheel(with event: NSEvent) {
        if drag.holdsKeys { return }
        let point = convert(event.locationInWindow, from: nil)
        if let folders = springboard?.folders, folders.isActive {
            guard folders.openFolder?.backdropContains(point) == true else { return }
        }
        activePager?.scrollWheel(deltaX: event.deltaX, deltaY: event.deltaY, phase: event.phase,
                                 momentumPhase: event.momentumPhase, at: pagerPoint(point), time: event.timestamp)
    }

    override func swipe(with event: NSEvent) {
        if drag.holdsKeys || springboard?.folders.isClosing == true { return }
        activePager?.swipe(deltaX: event.deltaX, deltaY: event.deltaY)
    }

    /// The open folder is an accessibility child while it is shown.
    override func accessibilityChildren() -> [Any]? {
        let children = super.accessibilityChildren()
        guard let folder = springboard?.folders.accessibilityElement else { return children }
        return (children ?? []) + [folder]
    }
}
