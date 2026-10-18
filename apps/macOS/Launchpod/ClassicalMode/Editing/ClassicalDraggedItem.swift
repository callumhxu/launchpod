import QuartzCore

/// The item being dragged across the Classical pages. Its cell rides above the pages while its
/// slot moves through the springboard's arrangement; moving to a slot, turning to a neighbouring
/// page, dropping and cancelling change that arrangement here. The springboard owns the pages and
/// their presentation, and this item for the length of one drag.
@MainActor
final class ClassicalDraggedItem {
    /// The application or folder being moved.
    let item: ClassicalPageItem
    let cell: ClassicalItemLayer
    /// The arrangement when the drag began, which a cancel restores.
    let originalPages: [[ClassicalPageItem]]
    private let originalFolderPages: [[AppRecord]]?
    private weak var folder: ClassicalFolder?
    private var createdFolderID: ClassicalLayoutFolder.ID?
    /// The open folder was made by this drag's hover and is not saved yet.
    private var folderIsUnsaved = false
    /// The dragged image has met the open folder's backdrop since the drag began or the folder
    /// last closed; only then does leaving the backdrop close the folder.
    private var hasEnteredFolder = false
    private var changedFolderMembership = false
    private(set) var page: Int
    private(set) var index: Int
    /// Whether the slot ever moved; a cancel before any move stays on the current page.
    private(set) var hasMoved = false
    /// The drop or cancel has started: the cell is on its way back to its page.
    private(set) var isEnding = false
    private unowned let springboard: ClassicalSpringboard

    /// Whether the item is inside a folder this drag made and has not saved.
    var isInUnsavedFolder: Bool { folder != nil && folderIsUnsaved }

    init(item: ClassicalPageItem, cell: ClassicalItemLayer, page: Int, index: Int,
         springboard: ClassicalSpringboard, folder: ClassicalFolder? = nil) {
        self.item = item
        self.cell = cell
        originalPages = springboard.pages
        originalFolderPages = folder?.content.pages
        self.folder = folder
        createdFolderID = folder.flatMap { springboard.groupDragSession.isNewFolder($0.content.id) ? $0.content.id : nil }
        self.page = page
        self.index = index
        self.springboard = springboard
    }

    /// The cell magnifies with the default implicit animation, then leaves its page for `host`
    /// where it is on screen, and stops jittering.
    func lift(to host: CALayer) {
        cell.setMagnified(true)
        let position = host.convert(cell.position, from: cell.superlayer)
        withoutActions {
            cell.removeFromSuperlayer()
            host.addSublayer(cell)
            cell.position = position
        }
        cell.setJittering(false)
    }

    /// Moves the cell's centre (drag-layer coordinates) without animation.
    func follow(to position: CGPoint) {
        guard !isEnding else { return }
        withoutActions { cell.position = position }
    }

    /// The item takes the slot under `center` (drag-layer coordinates), with hysteresis, and the
    /// cells between slide over in `ClassicalDragParameters.moveDuration`. Returns true when the
    /// slot changed.
    @discardableResult
    func moveToSlot(center: CGPoint) -> Bool {
        if let folder { return moveInFolder(folder, center: center) }
        guard !isEnding, let geometry = springboard.geometry, let host = springboard.dragHost,
              springboard.pager.pages.indices.contains(page) else { return false }
        var pages = springboard.pages
        let local = springboard.pager.pages[page].layer.convert(center, from: host)
        let target = geometry.grid.itemIndex(at: local, current: index, usingHysteresis: true,
                                             count: pages[page].count, rightToLeft: springboard.rightToLeft)
        guard target != index else { return false }
        pages[page].insert(pages[page].remove(at: index), at: target)
        index = target
        hasMoved = true
        CATransaction.begin()
        CATransaction.setAnimationDuration(ClassicalDragParameters.moveDuration)
        springboard.rearrange(pages, animatingMoves: true)
        CATransaction.commit()
        return true
    }

    private func moveInFolder(_ folder: ClassicalFolder, center: CGPoint) -> Bool {
        guard !isEnding, let host = springboard.dragHost, folder.pager.pages.indices.contains(page),
              folder.content.pages.indices.contains(page), let record = item.record else { return false }
        var pages = folder.content.pages
        let local = folder.pager.pages[page].layer.convert(center, from: host)
        let target = folder.geometry.grid.itemIndex(at: local, current: index, usingHysteresis: true,
                                                    count: pages[page].count, rightToLeft: springboard.rightToLeft)
        guard target != index else { return false }
        pages[page].insert(pages[page].remove(at: index), at: target)
        index = target
        hasMoved = true
        CATransaction.begin()
        CATransaction.setAnimationDuration(ClassicalDragParameters.moveDuration)
        folder.rearrange(pages, dragged: cell, id: record.id, animatingMoves: true)
        CATransaction.commit()
        return true
    }

    /// The page edge a dragged centre (drag-layer coordinates) is past, as −1 (left) or +1 (right):
    /// the centre's x against the page grid's frame. A folder the drag made and has not saved yet
    /// has no page edges.
    func edge(center: CGPoint) -> Int? {
        if isInUnsavedFolder { return nil }
        if let folder = springboard.folders.openFolder, let host = springboard.dragHost,
           folder.pager.pages.indices.contains(folder.pager.currentPage) {
            let page = folder.pager.pages[folder.pager.currentPage]
            let local = page.layer.convert(center, from: host)
            if local.x < 0 { return -1 }
            if local.x > folder.geometry.grid.pageSize.width { return 1 }
            return nil
        }
        guard let geometry = springboard.geometry else { return nil }
        if center.x < geometry.pageFrame.minX { return -1 }
        if center.x > geometry.pageFrame.maxX { return 1 }
        return nil
    }

    /// The item joins the end of the neighbouring page in `direction` (visual, −1 left) and the
    /// pager turns to it. Past the last page a new page is added, unless the item is alone on its
    /// page. Returns false when there is no page to turn to.
    @discardableResult
    func changePage(direction: Int) -> Bool {
        if let folder { return changeFolderPage(folder, direction: direction) }
        guard !isEnding, springboard.geometry != nil else { return false }
        let target = page + (springboard.rightToLeft ? -direction : direction)
        guard target >= 0 else { return false }
        var pages = springboard.pages
        if target == pages.count {
            guard pages[page].count > 1 else { return false }
            pages.append([])
        }
        guard pages.indices.contains(target) else { return false }
        pages[target].append(pages[page].remove(at: index))
        page = target
        index = pages[target].count - 1
        hasMoved = true
        springboard.rearrange(pages, animatingMoves: true)
        springboard.pager.settle(on: target)
        return true
    }

    /// A folder this drag made and has not saved has no other pages to turn to.
    private func changeFolderPage(_ folder: ClassicalFolder, direction: Int) -> Bool {
        guard !isEnding, !folderIsUnsaved, let record = item.record else { return false }
        let target = page + (springboard.rightToLeft ? -direction : direction)
        guard target >= 0 else { return false }
        var pages = folder.content.pages
        if target == pages.count { pages.append([]) }
        guard pages.indices.contains(target) else { return false }
        let insertion = min(pages[target].count, folder.geometry.grid.capacity - 1)
        pages[target].insert(pages[page].remove(at: index), at: insertion)
        hasMoved = true
        folder.rearrange(pages, dragged: cell, id: record.id, animatingMoves: true)
        guard let actualPage = folder.content.pages.firstIndex(where: { $0.contains { $0.id == record.id } }),
              let actualIndex = folder.content.pages[actualPage].firstIndex(where: { $0.id == record.id }) else {
            return false
        }
        page = actualPage
        index = actualIndex
        folder.pager.settle(on: actualPage)
        return true
    }

    /// Drops the item in two phases. First the icon undarkens at once; then, with the default
    /// implicit animation, it shrinks back where it is while the other cells slide to their final
    /// slots. An item past the page's capacity first takes the slot under `center`, overflow moves
    /// on to the following pages, emptied pages go, and the arrangement is committed. When that
    /// animation finishes, `land(animated:)` returns the cell to its page. A drop before the slot
    /// ever moved is an animated cancel instead, and commits nothing.
    func drop(center: CGPoint, groupTarget: ClassicalPageItem? = nil) {
        if let folder { return dropInFolder(folder) }
        if let groupTarget { return dropOnGroup(groupTarget) }
        guard !isEnding, let geometry = springboard.geometry else { return }
        guard hasMoved else { return cancel(animated: true) }
        isEnding = true
        cell.setDarkened(false)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in MainActor.assumeIsolated { self?.land(animated: true) } }
        cell.setMagnified(false)
        let capacity = geometry.grid.capacity
        var pages = springboard.pages
        if index >= capacity, let host = springboard.dragHost, springboard.pager.pages.indices.contains(page) {
            let local = springboard.pager.pages[page].layer.convert(center, from: host)
            let target = min(geometry.grid.itemIndex(at: local, current: index, usingHysteresis: true,
                                                     count: pages[page].count, rightToLeft: springboard.rightToLeft),
                             capacity - 1)
            pages[page].insert(pages[page].remove(at: index), at: target)
            index = target
        }
        var layout = (try? ClassicalLayout(pages: pages.map { $0.map(\.layoutItem) })) ?? ClassicalLayout()
        layout.pushOverflow(from: page, capacity: capacity)
        let byID = Dictionary(uniqueKeysWithValues: pages.flatMap { $0 }.map { ($0.id, $0) })
        let arranged = layout.pages.map { $0.compactMap { byID[ClassicalPageItem.ID($0)] } }
        // The current page number stays, limited to the last remaining page, so removing an
        // emptied page before it shows the page that followed.
        pages = arranged.filter { !$0.isEmpty }
        springboard.rearrange(pages, animatingMoves: true)
        if let committed = try? ClassicalLayout(pages: pages.map { $0.map(\.layoutItem) }) {
            if changedFolderMembership || originalFolderPages != nil {
                springboard.folderDragDidChange?(committed)
            } else {
                springboard.layoutDidChange?(committed)
            }
        }
        CATransaction.commit()
    }

    /// A hover long enough on another root icon opens the folder it makes or is, with the item
    /// inside and still dragged. The hover changes only presentation state; nothing is saved until
    /// the drop. See `ClassicalOpenGroupDrag.enter`.
    func enterGroup(target: ClassicalPageItem) {
        guard !isEnding, folder == nil,
              let entry = ClassicalOpenGroupDrag.enter(target: target, dragged: self, springboard: springboard) else { return }
        folder = entry.folder
        changedFolderMembership = true
        createdFolderID = entry.created ? entry.folder.content.id : nil
        folderIsUnsaved = entry.created
        hasEnteredFolder = false
        page = entry.page
        index = entry.index
        hasMoved = true
    }

    /// Once the dragged image has been over the open folder's backdrop and no longer meets it, the
    /// item returns to the root pages and the folder closes; see `ClassicalCloseGroupDrag.leave`.
    @discardableResult
    func leaveFolder() -> Bool {
        guard !isEnding, let folder, let record = item.record, let host = springboard.dragHost else { return false }
        let image = cell.iconLayer.convert(cell.iconLayer.bounds, to: host)
        let backdrop = folder.layer.convert(folder.geometry.backdropFrame, to: host)
        if image.intersects(backdrop) {
            hasEnteredFolder = true
            return false
        }
        guard hasEnteredFolder,
              let position = ClassicalCloseGroupDrag.leave(folder, record: record, dragged: self, springboard: springboard,
                                                           isNewFolder: createdFolderID == folder.content.id) else {
            return false
        }
        self.folder = nil
        folderIsUnsaved = false
        hasEnteredFolder = false
        page = position.page
        index = position.index
        changedFolderMembership = true
        hasMoved = true
        return true
    }

    private func dropOnGroup(_ target: ClassicalPageItem) {
        guard !isEnding, item.record != nil else { return cancel(animated: true) }
        isEnding = true
        cell.setDarkened(false)
        cell.setMagnified(false)
        guard ClassicalOpenGroupDrag.drop(on: target, dragged: self, springboard: springboard) else {
            isEnding = false
            return cancel(animated: true)
        }
        withoutActions { cell.removeFromSuperlayer() }
        springboard.dragDidEnd()
    }

    /// The pages `layout` describes, with the applications this drag began with.
    func resolvedPages(_ layout: ClassicalLayout) -> [[ClassicalPageItem]] {
        let records = Dictionary(uniqueKeysWithValues: originalPages.flatMap { $0.flatMap(\.records) }
            .map { ($0.id, $0) })
        return layout.pages.map { page in page.compactMap { item -> ClassicalPageItem? in
            switch item {
            case let .app(id): return records[id].map(ClassicalPageItem.app)
            case let .folder(folder):
                let pages = folder.pages.map { $0.compactMap { records[$0] } }.filter { !$0.isEmpty }
                return pages.isEmpty ? nil : .folder(ClassicalPageFolder(id: folder.id, title: folder.title,
                                                                         pages: pages, usesDefaultTitle: folder.usesDefaultTitle))
            }
        } }.filter { !$0.isEmpty }
    }

    /// The drop inside a folder saves its pages, with any page past the root pages' capacity
    /// passing its overflow on to the following folder pages.
    private func dropInFolder(_ folder: ClassicalFolder) {
        guard !isEnding, let record = item.record else { return }
        guard hasMoved else { return cancel(animated: true) }
        isEnding = true
        var pages = folder.content.pages.filter { !$0.isEmpty }
        let root = springboard.pages.map { rootPage in rootPage.map { item -> ClassicalLayoutItem in
            guard case var .folder(saved) = item.layoutItem, saved.id == folder.content.id else {
                return item.layoutItem
            }
            saved.pages = pages.map { $0.map(\.id) }
            return .folder(saved)
        } }
        if var layout = try? ClassicalLayout(pages: root) {
            let dropPage = pages.firstIndex { $0.contains { $0.id == record.id } } ?? page
            layout.pushOverflow(inFolder: folder.content.id, from: dropPage, capacity: springboard.capacity)
            if let saved = layout.folder(folder.content.id) {
                let records = Dictionary(uniqueKeysWithValues: pages.joined().map { ($0.id, $0) })
                pages = saved.pages.map { $0.compactMap { records[$0] } }
            }
            springboard.folderDragDidChange?(layout)
            if let createdFolderID { springboard.groupDragSession.markNewFolder(createdFolderID) }
        }
        folder.rearrange(pages, dragged: cell, id: record.id, animatingMoves: true)
        cell.setDarkened(false)
        cell.setMagnified(false)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in MainActor.assumeIsolated { self?.land(animated: true) } }
        CATransaction.commit()
    }

    /// Restores the original arrangement at once, without animating the other cells. With
    /// `animated`, only the cell slides home while it shrinks back and undarkens, and the pager
    /// turns to the page holding it if the slot ever moved; an item that has left its folder slides
    /// into the closed folder's cell instead. A drop or cancel already under way finishes at once
    /// instead.
    func cancel(animated: Bool) {
        guard !isEnding else { return land(animated: false) }
        isEnding = true
        if originalFolderPages == nil, folder != nil {
            springboard.folders.close(animated: false)
            folder = nil
        }
        springboard.rearrange(originalPages, animatingMoves: false)
        if let folder, let originalFolderPages, let record = item.record {
            folder.rearrange(originalFolderPages, dragged: cell, id: record.id, animatingMoves: false)
        }
        guard let home = home(), let host = springboard.dragHost else {
            if animated, returnIntoFolder() { return }
            return land(animated: false)
        }
        if hasMoved, home.page != springboard.pager.currentPage {
            if animated { springboard.pager.settle(on: home.page) } else { springboard.pager.jump(to: home.page) }
        }
        guard animated else {
            withoutActions {
                cell.setMagnified(false)
                cell.setDarkened(false)
            }
            return land(animated: false)
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in MainActor.assumeIsolated { self?.land(animated: false) } }
        cell.position = host.convert(home.center, from: home.layer)
        cell.setMagnified(false)
        cell.setDarkened(false)
        CATransaction.commit()
    }

    /// The item's home is inside a closed folder on the root pages: the pager turns to the folder's
    /// page, and the cell shrinks back, undarkens and moves onto the folder's cell, scaled to the
    /// thumbnail's share of the cell width and half transparent, then goes. False when there is no such folder.
    private func returnIntoFolder() -> Bool {
        guard let record = item.record, let host = springboard.dragHost else { return false }
        let holdsItem: (ClassicalPageItem) -> Bool = { $0.folder?.records.contains { $0.id == record.id } == true }
        guard let folderPage = originalPages.firstIndex(where: { $0.contains(where: holdsItem) }),
              let folderID = originalPages[folderPage].first(where: holdsItem)?.folder?.id,
              let folderCell = springboard.groupDragSession.rootFolderCell(folderID), let pageLayer = folderCell.superlayer,
              folderCell.frame.width > 0 else { return false }
        if folderPage != springboard.pager.currentPage { springboard.pager.settle(on: folderPage) }
        let scale = folderCell.thumbnailFrame(at: 0, in: folderCell).width / folderCell.frame.width
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in MainActor.assumeIsolated { self?.land(animated: false) } }
        cell.position = host.convert(folderCell.position, from: pageLayer)
        cell.setMagnified(false)
        cell.setDarkened(false)
        cell.opacity = ClassicalDragParameters.folderReturnOpacity
        cell.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
        return true
    }

    /// The cell rejoins its page layer where it is on screen, without animation, then moves to its
    /// slot (with `animated`, by the default implicit animation) and the drag ends.
    private func land(animated: Bool) {
        guard springboard.drag === self else { return }
        if let home = home() {
            let onScreen = home.layer.convert(cell.position, from: cell.superlayer)
            withoutActions {
                cell.removeFromSuperlayer()
                home.layer.addSublayer(cell)
                cell.position = onScreen
            }
            if animated {
                cell.position = home.center
            } else {
                withoutActions { cell.position = home.center }
            }
        } else {
            withoutActions { cell.removeFromSuperlayer() }
        }
        springboard.dragDidEnd()
    }

    /// The page, page layer and slot centre (page-layer coordinates) holding the item.
    private func home() -> (page: Int, layer: CALayer, center: CGPoint)? {
        if let folder, let record = item.record,
           let position = folder.content.pages.enumerated().lazy.compactMap({ page, items in
               items.firstIndex(where: { $0.id == record.id }).map { (page, $0) }
           }).first, folder.pager.pages.indices.contains(position.0) {
            let slot = folder.geometry.grid.cellFrame(at: position.1, rightToLeft: springboard.rightToLeft)
            return (position.0, folder.pager.pages[position.0].layer, CGPoint(x: slot.midX, y: slot.midY))
        }
        guard let geometry = springboard.geometry,
              let position = springboard.pages.enumerated().lazy.compactMap({ page, items in
                  items.firstIndex { $0.id == self.item.id }.map { (page, $0) }
              }).first,
              springboard.pager.pages.indices.contains(position.0) else { return nil }
        let slot = geometry.grid.cellFrame(at: position.1, rightToLeft: springboard.rightToLeft)
        return (position.0, springboard.pager.pages[position.0].layer, CGPoint(x: slot.midX, y: slot.midY))
    }

    private func withoutActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
