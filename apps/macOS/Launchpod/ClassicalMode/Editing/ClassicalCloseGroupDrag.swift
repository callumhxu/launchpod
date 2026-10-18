import QuartzCore

/// Dragging an application out of an open Classical folder: the application joins the folder's
/// root page, the folder closes with its animation, and a folder left with too few applications
/// dissolves once it has closed. `ClassicalDraggedItem` keeps the drag's state; this changes the
/// arrangement and runs the close and dissolve transitions.
@MainActor
enum ClassicalCloseGroupDrag {
    /// Moves `record` out of `folder` onto the folder's root page, at its end when there is room and
    /// otherwise in its last slot with the overflow passed on, and starts closing the folder. The
    /// folder dissolves after closing when it held at most one application with the item, or two
    /// when `isNewFolder`. Nothing is saved. Returns the item's position on the root pages.
    static func leave(_ folder: ClassicalFolder, record: AppRecord, dragged: ClassicalDraggedItem,
                      springboard: ClassicalSpringboard, isNewFolder: Bool) -> (page: Int, index: Int)? {
        let id = folder.content.id
        let visible = springboard.pages.map { page in page.map { item -> ClassicalLayoutItem in
            guard case var .folder(saved) = item.layoutItem, saved.id == id else { return item.layoutItem }
            saved.pages = folder.content.pages.filter { !$0.isEmpty }.map { $0.map(\.id) }
            return .folder(saved)
        } }
        guard var layout = try? ClassicalLayout(pages: visible), let slot = layout.position(ofFolder: id) else { return nil }
        let dissolves = layout.folder(id).map { $0.identities.count <= (isNewFolder ? 2 : 1) } ?? false
        let capacity = springboard.capacity
        let count = layout.pages[slot.page].count
        layout.move(record.id, toRootPage: slot.page, index: count < capacity ? count : max(capacity - 1, 0))
        layout.pushOverflow(from: slot.page, capacity: capacity)
        guard let position = layout.position(of: record.id) else { return nil }
        let remaining = folder.content.pages.map { $0.filter { $0.id != record.id } }.filter { !$0.isEmpty }
        folder.rearrange(remaining, dragged: dragged.cell, id: record.id, animatingMoves: false)
        springboard.rearrange(dragged.resolvedPages(layout), animatingMoves: true)
        if let cell = springboard.groupDragSession.rootFolderCell(id) { springboard.folders.replaceCell(cell) }
        springboard.folders.close { [weak springboard] in
            guard dissolves, let springboard else { return }
            dissolve(id, springboard: springboard, dragged: dragged)
        }
        return position
    }

    /// Replaces a closed folder holding a single application with that application. It grows from
    /// the folder's thumbnail size at the folder's centre into its slot while its title fades in,
    /// and the folder cell fades out while shrinking. The arrangement is saved at once when the drag
    /// has already ended; otherwise its drop saves it.
    private static func dissolve(_ id: ClassicalLayoutFolder.ID, springboard: ClassicalSpringboard,
                                 dragged: ClassicalDraggedItem) {
        guard var layout = try? ClassicalLayout(pages: springboard.pages.map { $0.map(\.layoutItem) }),
              let folder = layout.folder(id), folder.identities.count == 1, let remaining = folder.identities.first,
              let folderCell = springboard.groupDragSession.rootFolderCell(id), let pageLayer = folderCell.superlayer,
              folderCell.frame.width > 0 else { return }
        let scale = folderCell.thumbnailFrame(at: 0, in: folderCell).width / folderCell.frame.width
        let start = folderCell.position
        layout.dissolve(id)
        // Cells that stay are kept; only the folder's slot gets a new cell.
        springboard.rearrange(dragged.resolvedPages(layout), animatingMoves: true)
        guard let cell = springboard.cell(for: remaining), cell.superlayer === pageLayer else { return }
        let offset = ClassicalDragParameters.folderDissolveOffset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pageLayer.addSublayer(folderCell)
        let slot = cell.position
        cell.titleLayer.opacity = ClassicalAnimationParameters.Drag.hiddenOpacity
        cell.transform = CATransform3DMakeScale(scale, scale, 1)
        cell.position = CGPoint(x: start.x + offset.x, y: start.y + offset.y)
        CATransaction.commit()
        CATransaction.flush()
        cell.transform = CATransform3DIdentity
        cell.position = slot
        cell.titleLayer.opacity = ClassicalAnimationParameters.Drag.visibleOpacity
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak folderCell] in
            MainActor.assumeIsolated {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                folderCell?.removeFromSuperlayer()
                CATransaction.commit()
            }
        }
        let shrink = ClassicalDragParameters.folderDissolveScale
        folderCell.opacity = ClassicalAnimationParameters.Drag.hiddenOpacity
        folderCell.transform = CATransform3DMakeScale(shrink, shrink, 1)
        CATransaction.commit()
        if springboard.drag !== dragged || dragged.isEnding {
            springboard.folderDragDidChange?(layout)
        }
    }
}
