import QuartzCore

/// Grouping a dragged root application with the icon it is over. A hover long enough opens the
/// folder that icon makes or is, with the item inside and still dragged; a release on the icon
/// saves the group at once and minimizes the icons into the folder's thumbnails.
/// `ClassicalDraggedItem` keeps the drag's state; this works out the arrangement and starts the
/// transitions.
@MainActor
enum ClassicalOpenGroupDrag {
    struct Entry {
        let folder: ClassicalFolder
        let page: Int
        let index: Int
        let created: Bool
    }

    /// Opens the folder for a hover on `target`. On an application, a new folder of the target then
    /// the dragged item takes the target's slot, the target's icon minimizes into it and it opens.
    /// On a folder, the item leaves its root page, the folder opens with its own applications, and
    /// the item joins the end of the page the folder shows. Nothing is saved. Nil, with the
    /// arrangement restored, when the folder cannot open.
    static func enter(target: ClassicalPageItem, dragged: ClassicalDraggedItem,
                      springboard: ClassicalSpringboard) -> Entry? {
        guard let record = dragged.item.record,
              var layout = try? ClassicalLayout(pages: springboard.pages.map { $0.map(\.layoutItem) }) else { return nil }
        let host = springboard.dragHost
        let folderID: ClassicalLayoutFolder.ID
        var targetImage: ClassicalGroupDragVisuals.IconImage?
        switch target {
        case let .app(targetRecord):
            targetImage = host.flatMap { host in springboard.groupDragSession.targetCell(target).map {
                springboard.groupVisuals.image(of: $0, in: host)
            } }
            folderID = layout.makeFolder(target: targetRecord.id, dragged: record.id,
                                         title: defaultTitle(for: targetRecord, springboard: springboard))
        case let .folder(folder):
            layout.remove(record.id)
            layout.removeEmptyPages()
            folderID = folder.id
        }
        let created = target.folder == nil
        springboard.rearrange(dragged.resolvedPages(layout), animatingMoves: true)
        if let host, let targetImage, let newCell = springboard.groupDragSession.rootFolderCell(folderID) {
            springboard.groupVisuals.minimizeTarget(targetImage, into: newCell, host: host)
        }
        guard springboard.openFolder(folderID, duringDrag: true), let opened = springboard.folders.folder else {
            springboard.rearrange(dragged.originalPages, animatingMoves: false)
            return nil
        }
        var pages = opened.content.pages
        if !created {
            let current = min(max(opened.pager.currentPage, 0), max(pages.count - 1, 0))
            if pages.isEmpty { pages = [[]] }
            pages[current].append(record)
        }
        opened.rearrange(pages, dragged: dragged.cell, id: record.id, animatingMoves: false)
        guard let page = opened.content.pages.firstIndex(where: { $0.contains { $0.id == record.id } }),
              let index = opened.content.pages[page].firstIndex(where: { $0.id == record.id }) else { return nil }
        if opened.pager.currentPage != page { opened.pager.settle(on: page) }
        return Entry(folder: opened, page: page, index: index, created: created)
    }

    /// A release on `target` groups at once and saves: an application makes a new folder in its
    /// slot, a folder takes the item at the end of its last page. Both icons appear over the new
    /// folder cell and minimize into its thumbnails; a new folder then opens once the pages have
    /// settled. False when nothing could be grouped.
    static func drop(on target: ClassicalPageItem, dragged: ClassicalDraggedItem,
                     springboard: ClassicalSpringboard) -> Bool {
        guard let record = dragged.item.record,
              var layout = try? ClassicalLayout(pages: springboard.pages.map { $0.map(\.layoutItem) }) else { return false }
        let folderID: ClassicalLayoutFolder.ID
        switch target {
        case let .app(targetRecord):
            folderID = layout.makeFolder(target: targetRecord.id, dragged: record.id,
                                         title: defaultTitle(for: targetRecord, springboard: springboard))
        case let .folder(folder):
            guard layout.insert(record.id, intoFolder: folder.id, capacity: springboard.capacity) else { return false }
            folderID = folder.id
        }
        let created = target.folder == nil
        let host = springboard.dragHost
        let targetCell = springboard.groupDragSession.targetCell(target)
        let draggedImage = host.map { springboard.groupVisuals.image(of: dragged.cell, in: $0) }
        let targetImage = created ? host.flatMap { host in targetCell.map { springboard.groupVisuals.image(of: $0, in: host) } } : nil
        let previewScrollOrigin = (targetCell as? ClassicalFolderItemLayer)?.miniGridLayer.bounds.origin
        let openAfterSettling = created ? springboard.groupDragSession.openAfterSettling(folderID) : nil
        CATransaction.begin()
        if let openAfterSettling {
            CATransaction.setCompletionBlock {
                MainActor.assumeIsolated { openAfterSettling() }
            }
        }
        springboard.rearrange(dragged.resolvedPages(layout), animatingMoves: true)
        CATransaction.commit()
        if let host, let draggedImage, let folder = layout.folder(folderID),
           let newCell = springboard.groupDragSession.rootFolderCell(folderID) {
            if let previewScrollOrigin {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                newCell.miniGridLayer.bounds.origin = previewScrollOrigin
                CATransaction.commit()
            }
            let draggedIndex = created ? 1 : max((folder.pages.first?.count ?? 1) - 1, 0)
            springboard.groupVisuals.minimize(target: targetImage, dragged: draggedImage,
                                              into: newCell, host: host, draggedIndex: draggedIndex)
        }
        springboard.folderDragDidChange?(layout)
        if created { springboard.groupDragSession.markNewFolder(folderID) }
        return true
    }

    private static func defaultTitle(for target: AppRecord, springboard: ClassicalSpringboard) -> String {
        ClassicalLayoutFolder.defaultTitle(categoryIdentifier: target.metadata.categoryIdentifier,
                                           locale: springboard.folderTitleLocale())
    }
}
