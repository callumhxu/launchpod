import AppKit
import QuartzCore

/// Session-owned group hover targets, new-folder identity and delayed opening. A presentation
/// reset cancels its pending work; the springboard owns the current drag and page arrangement.
@MainActor
final class ClassicalGroupDragSession {
    weak var springboard: ClassicalSpringboard?
    let visuals = ClassicalGroupDragVisuals()
    private var newFolderIDs: Set<ClassicalLayoutFolder.ID> = []
    private var pendingOpen: Task<Void, Never>?
    /// Changes whenever pending opening work is cancelled, so a settling drop left over from before does nothing.
    private var openGeneration = 0

    init(springboard: ClassicalSpringboard) {
        self.springboard = springboard
    }

    func cancelPendingOpen() {
        openGeneration += 1
        pendingOpen?.cancel()
        pendingOpen = nil
    }

    func clearPresentation() {
        cancelPendingOpen()
        visuals.clear()
    }

    func isNewFolder(_ id: ClassicalLayoutFolder.ID) -> Bool { newFolderIDs.contains(id) }
    func markNewFolder(_ id: ClassicalLayoutFolder.ID) { newFolderIDs.insert(id) }

    /// A different root icon whose image contains the dragged cell's centre (drag-layer coordinates).
    func target(at center: CGPoint) -> ClassicalPageItem? {
        guard let springboard, let drag = springboard.drag, drag.item.record != nil,
              !springboard.folders.isActive, let host = springboard.dragHost,
              let geometry = springboard.geometry,
              springboard.pager.pages.indices.contains(drag.page),
              springboard.pages.indices.contains(drag.page) else { return nil }
        let page = springboard.pager.pages[drag.page]
        let local = page.layer.convert(center, from: host)
        let target = geometry.grid.itemIndex(at: local, current: drag.index, usingHysteresis: false,
                                             count: springboard.pages[drag.page].count,
                                             rightToLeft: springboard.rightToLeft)
        guard target != drag.index, page.itemLayers.indices.contains(target),
              springboard.pages[drag.page].indices.contains(target) else { return nil }
        let cell = page.itemLayers[target]
        return cell.iconLayer.frame.contains(cell.jitterLayer.convert(center, from: host))
            ? springboard.pages[drag.page][target] : nil
    }

    func targetCell(_ target: ClassicalPageItem) -> ClassicalItemLayer? {
        guard let springboard, let drag = springboard.drag,
              springboard.pager.pages.indices.contains(drag.page) else { return nil }
        let page = springboard.pager.pages[drag.page]
        guard let index = page.items.firstIndex(where: { $0.id == target.id }),
              page.itemLayers.indices.contains(index) else { return nil }
        return page.itemLayers[index]
    }

    func rootFolderCell(_ id: ClassicalLayoutFolder.ID) -> ClassicalFolderItemLayer? {
        guard let springboard else { return nil }
        for page in springboard.pager.pages {
            guard let index = page.items.firstIndex(where: { $0.id == .folder(id) }),
                  page.itemLayers.indices.contains(index) else { continue }
            return page.itemLayers[index] as? ClassicalFolderItemLayer
        }
        return nil
    }

    /// The completion for the transaction in which a drop made folder `id` and the pages settle:
    /// once that has finished, and unless a folder is shown by then, the folder opens after
    /// `ClassicalFolderParameters.newFolderOpenDelay`. A presentation reset or a new drag first
    /// cancels it.
    func openAfterSettling(_ id: ClassicalLayoutFolder.ID) -> @MainActor () -> Void {
        let generation = openGeneration
        return { [weak self] in
            guard let self, self.openGeneration == generation, self.springboard?.folders.isActive == false else { return }
            self.scheduleOpen(id)
        }
    }

    private func scheduleOpen(_ id: ClassicalLayoutFolder.ID) {
        cancelPendingOpen()
        pendingOpen = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(ClassicalFolderParameters.newFolderOpenDelay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.pendingOpen = nil
            self.springboard?.openFolder(id)
        }
    }
}
