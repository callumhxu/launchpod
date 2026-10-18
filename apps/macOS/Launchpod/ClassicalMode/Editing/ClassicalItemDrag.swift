import AppKit

/// A press on an icon becomes a drag once the pointer moves `activationDistance` on either axis
/// while still over that icon. The cell then follows the pointer. Each move asks for a new drag
/// state right away when the pointer travels slower than `restSpeed`; faster moves wait until the
/// pointer rests. A centre past the page grid's left or right edge turns the page after
/// `edgeDelay` and every `edgeRepeat` after that (the slow values with Shift); otherwise the item
/// takes the slot under it. See `ClassicalDragParameters`.
@MainActor
final class ClassicalItemDrag {
    weak var springboard: ClassicalSpringboard?
    /// Replaceable in tests.
    var shiftKeyDown: @MainActor () -> Bool = { NSEvent.modifierFlags.contains(.shift) }
    var sleep: @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    var dockHitRegion: @MainActor (NSScreen) -> CGRect? = { ClassicalDockDisplay.dragHandoffFrame(on: $0) }

    private var startPoint: CGPoint = .zero
    private var startPosition: CGPoint = .zero
    private var lastPoint: CGPoint = .zero
    private var lastTime: TimeInterval = 0
    private var restTask: Task<Void, Never>?
    private var edgeTask: Task<Void, Never>?
    private var groupTask: Task<Void, Never>?
    private var groupTarget: ClassicalPageItem?
    private var edge: Int?
    private(set) var isCancelling = false

    /// A drag follows the pointer until its drop or cancel starts.
    var isDragging: Bool { springboard?.drag?.isEnding == false }

    /// Whether a press on an icon is held, from mouse-down (before any drag) until mouse-up or a
    /// cancelled drag.
    private(set) var isPressHeld = false
    /// While an icon is held or dragged, keys other than Escape and Tab do nothing, and wheel and
    /// trackpad paging are swallowed.
    var holdsKeys: Bool { isPressHeld || isDragging }

    func pressBegan() { isPressHeld = true }
    func pressEnded() { isPressHeld = false }

    /// Starts dragging `cell` from the press at `point` (drag-layer coordinates) and `time`, which
    /// also seed the first speed measurement.
    @discardableResult
    func begin(_ item: ClassicalPageItem, cell: ClassicalItemLayer, at point: CGPoint, time: TimeInterval) -> Bool {
        guard let springboard, springboard.beginDrag(of: item, cell: cell) else { return false }
        isCancelling = false
        startPoint = point
        startPosition = cell.position
        lastPoint = point
        lastTime = time
        return true
    }

    func moved(to point: CGPoint, time: TimeInterval) {
        guard isDragging, !isCancelling else { return }
        springboard?.drag?.follow(to: center(for: point))
        let speed = ClassicalDragParameters.speed(distance: hypot(point.x - lastPoint.x, point.y - lastPoint.y),
                                                  elapsed: time - lastTime)
        lastPoint = point
        lastTime = time
        restTask?.cancel()
        restTask = nil
        if speed < ClassicalDragParameters.restSpeed {
            evaluate()
        } else {
            let delay = shiftKeyDown() ? ClassicalDragParameters.slowRestDelay : ClassicalDragParameters.restDelay
            restTask = Task { [weak self, sleep] in
                do { try await sleep(delay) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.restTask = nil
                self.evaluate()
            }
        }
    }

    /// The release ends the drag in the last state a move applied: a pending re-evaluation is
    /// cancelled, and an icon still highlighted as a group target receives the item.
    func ended(at point: CGPoint) {
        guard isDragging, !isCancelling else { return }
        let target = groupTarget
        stopTimers(preservingGroupPreview: target?.folder != nil)
        springboard?.drag?.drop(center: center(for: point), groupTarget: target)
    }

    func cancel(animated: Bool = true) {
        stopTimers()
        guard isDragging else { return }
        isPressHeld = false
        isCancelling = true
        springboard?.cancelDrag(animated: animated)
    }

    /// Escape still owns the mouse release while the cancelled cell animates home.
    func consumeCancelledMouseUp() -> Bool {
        guard isCancelling else { return false }
        if springboard?.drag == nil { isCancelling = false }
        return true
    }

    /// The panel closed; no delayed drag work may outlive this presentation.
    func reset() {
        stopTimers()
        springboard?.cancelDrag(animated: false)
        isPressHeld = false
        isCancelling = false
    }

    /// Stops internal rearrangement timers while AppKit owns the pointer. The original arrangement
    /// remains available until the system reports whether the Dock accepted, deleted or rejected it.
    func suspendForExternalDrag() {
        stopTimers()
    }

    /// Dock's reported bar rectangle starts a system drag; an auto-hidden Dock uses its collapsed
    /// physical-edge rectangle.
    func shouldHandOffToDock(at point: CGPoint, in view: NSView) -> Bool {
        guard let window = view.window, let screen = window.screen, let dock = dockHitRegion(screen) else { return false }
        let onScreen = window.convertPoint(toScreen: view.convert(point, to: nil))
        return dock.contains(onScreen)
    }

    /// The AppKit item exports the application bundle as a file URL, with its artwork under the
    /// original press location as required by `beginDraggingSession(with:event:source:)`.
    func makeExternalDraggingItem(for record: AppRecord, cell: ClassicalItemLayer, in view: NSView) -> NSDraggingItem? {
        let url = record.metadata.bundleURL
        guard record.isMissing != true, record.source.isOnline != false,
              url.isFileURL, url.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: url.path), let layer = view.layer,
              let cellHost = cell.superlayer else { return nil }
        let renderedFrame = cell.iconLayer.convert(cell.iconLayer.bounds, to: layer)
        let cellCenter = cellHost.convert(cell.position, to: layer)
        let scale = cell.isMagnified ? ClassicalDragParameters.magnifiedScale : 1
        let iconFrame = CGRect(x: cellCenter.x + (renderedFrame.minX - cellCenter.x) / scale,
                               y: cellCenter.y + (renderedFrame.minY - cellCenter.y) / scale,
                               width: renderedFrame.width / scale, height: renderedFrame.height / scale)
            .offsetBy(dx: startPoint.x - lastPoint.x, dy: startPoint.y - lastPoint.y)
        guard iconFrame.width > 0, iconFrame.height > 0 else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(iconFrame, contents: image)
        return item
    }

    /// The new drag state for where the cell is now.
    private func evaluate() {
        guard let springboard else { return }
        let center = center(for: lastPoint)
        if springboard.drag?.leaveFolder() == true {
            setGroupTarget(nil)
            return
        }
        if let direction = springboard.drag?.edge(center: center) {
            setGroupTarget(nil)
            guard edge != direction else { return }
            startEdgeTimer(direction)
        } else {
            edgeTask?.cancel()
            edgeTask = nil
            edge = nil
            if let target = springboard.groupDragSession.target(at: center) {
                setGroupTarget(target)
            } else {
                setGroupTarget(nil)
                springboard.drag?.moveToSlot(center: center)
            }
        }
    }

    private func setGroupTarget(_ target: ClassicalPageItem?) {
        guard groupTarget?.id != target?.id else { return }
        groupTask?.cancel()
        groupTask = nil
        groupTarget = target
        springboard?.groupVisuals.endHover()
        guard let target, let springboard, let cell = springboard.groupDragSession.targetCell(target),
              let dragged = springboard.drag?.cell else { return }
        springboard.groupVisuals.hover(target: cell, dragged: dragged, slow: shiftKeyDown())
        let delay = shiftKeyDown() ? ClassicalDragParameters.slowGroupDelay : ClassicalDragParameters.groupDelay
        groupTask = Task { [weak self, sleep] in
            do { try await sleep(delay) } catch { return }
            guard let self, !Task.isCancelled, self.groupTarget?.id == target.id,
                  self.springboard?.groupDragSession.target(at: self.center(for: self.lastPoint))?.id == target.id else { return }
            self.groupTask = nil
            self.springboard?.drag?.enterGroup(target: target)
            self.groupTarget = nil
        }
    }

    private func startEdgeTimer(_ direction: Int) {
        edgeTask?.cancel()
        edge = direction
        let slow = shiftKeyDown()
        let first = slow ? ClassicalDragParameters.slowEdgeDelay : ClassicalDragParameters.edgeDelay
        let interval = slow ? ClassicalDragParameters.slowEdgeRepeat : ClassicalDragParameters.edgeRepeat
        edgeTask = Task { [weak self, sleep] in
            var delay = first
            while true {
                do { try await sleep(delay) } catch { return }
                guard let self, !Task.isCancelled, self.edge == direction else { return }
                self.springboard?.drag?.changePage(direction: direction)
                delay = interval
            }
        }
    }

    /// The cell's centre follows the pointer from where the press started.
    private func center(for point: CGPoint) -> CGPoint {
        CGPoint(x: startPosition.x + point.x - startPoint.x, y: startPosition.y + point.y - startPoint.y)
    }

    private func stopTimers(preservingGroupPreview: Bool = false) {
        groupTask?.cancel()
        groupTask = nil
        groupTarget = nil
        springboard?.groupVisuals.endHover(restorePreview: !preservingGroupPreview)
        restTask?.cancel()
        restTask = nil
        edgeTask?.cancel()
        edgeTask = nil
        edge = nil
    }
}
