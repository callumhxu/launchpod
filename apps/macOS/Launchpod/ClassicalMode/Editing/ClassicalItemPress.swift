import AppKit

/// A press on an icon or a delete badge.
///
/// The icon darkens while the pointer stays over it; a release over it opens the application, or the
/// folder, unless the press was a long press. A long press fires after 1 s (5 s with Shift) and
/// toggles deleting mode; moving 3 pt over the icon cancels it. A press on a badge
/// shows the pressed badge image and asks to delete on release over it.
@MainActor
final class ClassicalItemPress {
    static var longPressDelay: TimeInterval { ClassicalAnimationParameters.Editing.longPressDelay }
    static var slowLongPressDelay: TimeInterval { ClassicalAnimationParameters.Editing.slowLongPressDelay }

    weak var springboard: ClassicalSpringboard?
    var launch: (@MainActor (AppRecord) -> Void)?
    var requestDeletion: (@MainActor (AppRecord, ClassicalItemLayer) -> Void)?
    /// Replaceable in tests.
    var shiftKeyDown: @MainActor () -> Bool = { NSEvent.modifierFlags.contains(.shift) }
    var sleep: @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }

    private(set) var pressedItem: (item: ClassicalPageItem, cell: ClassicalItemLayer)?
    private var pressedBadge: (record: AppRecord, cell: ClassicalItemLayer)?
    /// Where the press began, in content-layer coordinates.
    private(set) var start: CGPoint = .zero
    private var longPressTask: Task<Void, Never>?
    private(set) var didLongPress = false

    var isTracking: Bool { pressedItem != nil || pressedBadge != nil }

    /// Returns true when the press landed on a badge, which the pager must not see.
    func beginBadge(at point: CGPoint) -> Bool {
        guard let badge = springboard?.closebox(at: point) else { return false }
        pressedBadge = badge
        badge.cell.setCloseboxPressed(true)
        return true
    }

    func beginIcon(at point: CGPoint) {
        guard let item = springboard?.item(at: point) else { return }
        pressedItem = item
        start = point
        didLongPress = false
        // Pressing an icon ends keyboard selection.
        springboard?.select(nil)
        item.cell.setDarkened(true)
        let delay = shiftKeyDown() ? Self.slowLongPressDelay : Self.longPressDelay
        longPressTask = Task { [weak self, sleep] in
            do { try await sleep(delay) } catch { return }
            guard let self, !Task.isCancelled, let item = self.pressedItem else { return }
            self.longPressTask = nil
            self.didLongPress = true
            self.springboard?.longPress(on: item.cell)
        }
    }

    func dragged(to point: CGPoint, pagerIsDragging: Bool) {
        if let badge = pressedBadge {
            badge.cell.setCloseboxPressed(springboard?.closebox(at: point)?.cell === badge.cell)
            return
        }
        guard let item = pressedItem else { return }
        let overIcon = springboard?.item(at: point)?.cell === item.cell
        if overIcon, abs(point.x - start.x) >= ClassicalDragParameters.activationDistance
            || abs(point.y - start.y) >= ClassicalDragParameters.activationDistance { cancelLongPress() }
        if pagerIsDragging {
            // The page follows the pointer; the press is no longer a click on the icon.
            cancelLongPress()
            release(item)
            pressedItem = nil
        } else {
            item.cell.setDarkened(overIcon)
        }
    }

    /// Returns true when the release belonged to an icon or badge press.
    func end(at point: CGPoint) -> Bool {
        cancelLongPress()
        if let badge = pressedBadge {
            pressedBadge = nil
            badge.cell.setCloseboxPressed(false)
            if springboard?.closebox(at: point)?.cell === badge.cell { requestDeletion?(badge.record, badge.cell) }
            return true
        }
        guard let item = pressedItem else { return false }
        pressedItem = nil
        release(item)
        if !didLongPress, let releasedItem = springboard?.item(at: point), releasedItem.item.id == item.item.id {
            switch releasedItem.item {
            case let .app(record): launch?(record)
            case let .folder(folder): springboard?.openFolder(folder.id)
            }
        }
        didLongPress = false
        return true
    }

    /// The press became a drag of its icon: no launch, and the icon stays as it is for the drag.
    func handOffToDrag() {
        cancelLongPress()
        pressedItem = nil
        didLongPress = false
    }

    func cancel() {
        cancelLongPress()
        if let item = pressedItem { release(item) }
        pressedBadge?.cell.setCloseboxPressed(false)
        pressedItem = nil
        pressedBadge = nil
        didLongPress = false
    }

    private func release(_ item: (item: ClassicalPageItem, cell: ClassicalItemLayer)) {
        item.cell.setDarkened(false)
        springboard?.releasePress(on: item.cell)
    }

    private func cancelLongPress() {
        longPressTask?.cancel()
        longPressTask = nil
    }
}
