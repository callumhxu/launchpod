import AppKit
import QuartzCore

/// The paged applications and folders with the search filter and keyboard selection.
///
/// Filtering remembers the current page and jumps to the first; results fill pages in model order
/// and the first item of the current page is selected. Clearing restores the full pages and the
/// remembered page without animation. Search looks inside folders: their applications appear
/// among the results, folders never do. While a folder is open (`folders`), hit testing,
/// selection, navigation and deleting mode apply inside it.
@MainActor
final class ClassicalSpringboard {
    let pager = ClassicalPager()
    let noResultsContainer = ClassicalNoResultsLayer()
    var noResultsLayer: ClassicalShadowTextLayer { noResultsContainer.textLayer }
    let folders = ClassicalFolderPresenter()
    /// The arranged pages, unfiltered; a drag rearranges them and a drop reports the new layout.
    private(set) var pages: [[ClassicalPageItem]] = []
    /// Every application on the pages, including those in folders.
    var records: [AppRecord] { pages.flatMap { $0.flatMap(\.records) } }
    private(set) var results: [AppRecord]?
    /// Called with the arrangement after a drop changed it.
    var layoutDidChange: (@MainActor (ClassicalLayout) -> Void)?
    var folderDragDidChange: (@MainActor (ClassicalLayout) -> Void)?
    var folderTitleLocale: @MainActor () -> Locale = { .current }
    /// Called with a folder and its new title after it was renamed; returns the folder as saved,
    /// whose title state the root pages then take. Nil when nothing was saved.
    var folderRenamed: (@MainActor (ClassicalLayoutFolder.ID, String) -> ClassicalLayoutFolder?)?
    /// The selected item on the root pages.
    private(set) var selectedItemID: ClassicalPageItem.ID?
    private var pageBeforeFiltering = 0
    /// Deleting (jiggle) mode on the root pages: every cell jitters and deletable ones show a badge.
    private var isDeletingRoot = false
    /// Deleting mode was entered by holding Option and ends when it is released.
    private var deletingByOption = false
    /// Which applications may be deleted; tests replace its `isDeletable`.
    let deletability = ClassicalDeletabilityCache()
    private var configuration: Configuration?
    private let icons = ClassicalIconCache()
    private(set) lazy var groupDragSession = ClassicalGroupDragSession(springboard: self)
    var groupVisuals: ClassicalGroupDragVisuals { groupDragSession.visuals }
    /// Whether folders use the glass appearance, which the presentation owner sets from Launchpod's
    /// settings: folder cells made by later layouts and the drop glow while grouping follow it.
    var folderGlassEnabled: Bool {
        get { pager.folderGlassEnabled }
        set {
            pager.folderGlassEnabled = newValue
            groupVisuals.showsDropGlow = newValue
        }
    }

    private struct Configuration {
        var geometry: ClassicalSpringboardGeometry
        var scale: CGFloat
        var rightToLeft: Bool
        var icon: @MainActor (AppRecord, AppIconSize) async throws -> CGImage
    }

    init() {
        pager.pageWillChange = { [weak self] in
            // Every page change clears the selection.
            guard let self, self.selectedItemID != nil else { return }
            self.selectedItemID = nil
            self.applySelection()
        }
        folders.didClose = { [weak self] in
            // The root page is laid out again after a folder closed, with any catalog update that waited.
            guard let self, self.drag == nil, self.removing.isEmpty else { return }
            self.deferredPages = nil
            self.deferredRefreshNeeded?()
        }
        pager.layer.addSublayer(noResultsContainer)
    }

    var isFiltering: Bool { results != nil }

    /// The selected application: inside the open folder, otherwise on the root pages.
    var selectedRecord: AppRecord? {
        if let folder = folders.openFolder { return folder.selectedRecord }
        guard let selectedID else { return nil }
        return pager.pages.lazy.flatMap(\.records).first { $0.id == selectedID }
    }

    /// The selected application on the root pages; nil when nothing or a folder is selected.
    var selectedID: AppIdentity? {
        guard case let .app(id) = selectedItemID else { return nil }
        return id
    }

    /// Lays out `records` in full pages, re-applying an active filter to them.
    func show(_ records: [AppRecord], geometry: ClassicalSpringboardGeometry, scale: CGFloat, rightToLeft: Bool,
              noResultsText: String, icon: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage) {
        show(pages: ClassicalPager.chunk(records.map(ClassicalPageItem.app), capacity: geometry.grid.capacity),
             geometry: geometry, scale: scale, rightToLeft: rightToLeft, noResultsText: noResultsText, icon: icon)
    }

    /// Lays out the arranged `pages`, re-applying an active filter to them. An open folder closes at once.
    func show(pages: [[ClassicalPageItem]], geometry: ClassicalSpringboardGeometry, scale: CGFloat, rightToLeft: Bool,
              noResultsText: String, icon: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage) {
        groupDragSession.clearPresentation()
        folders.close(animated: false)
        configuration = Configuration(geometry: geometry, scale: scale, rightToLeft: rightToLeft, icon: icon)
        refresh(pages: pages)
        let page = geometry.pageFrame.offsetBy(dx: -geometry.contentFrame.minX, dy: -geometry.contentFrame.minY)
        noResultsContainer.layOut(text: noResultsText, scale: scale, page: page)
    }

    /// The number of applications one page holds in the current layout.
    var capacity: Int { configuration?.geometry.grid.capacity ?? 1 }

    /// Updates applications in full pages; see `refresh(pages:)`.
    func refreshRecords(_ records: [AppRecord]) {
        refresh(pages: ClassicalPager.chunk(records.map(ClassicalPageItem.app), capacity: capacity))
    }

    /// Updates the arranged pages, preserving the search and remembered page. While a deleted
    /// application animates out, an item is dragged or a folder is shown, the update waits; deleted
    /// applications stay hidden until the catalog no longer lists them.
    func refresh(pages: [[ClassicalPageItem]]) {
        guard removing.isEmpty, drag == nil, !folders.isActive else {
            deferredPages = pages
            return
        }
        apply(pages, animatingMoves: false)
    }

    /// Prepares a hidden launcher's current catalog using its last presentation geometry.
    /// The next presentation lays out the pages; this leaves the displayed pages in place.
    /// Reads `pages` only when a prior presentation supplied the geometry.
    func prepare(pages: () -> [[ClassicalPageItem]]) {
        guard let configuration else { return }
        let pages = pages()
        let ids = Set(pages.flatMap { $0.flatMap(\.records) }.map(\.id))
        icons.retain(ids)
        ClassicalIconPreparation.prepare(pages, geometry: configuration.geometry, scale: configuration.scale,
                                         visiblePages: [], currentPage: 0, cache: icons, source: configuration.icon)
    }

    private func apply(_ pages: [[ClassicalPageItem]], animatingMoves: Bool) {
        removed.formIntersection(pages.joined().flatMap(\.records).map(\.id))
        self.pages = pages.map { $0.compactMap { $0.removing(removed) } }.filter { !$0.isEmpty }
        let records = self.records
        let retainedIDs = Set(records.map(\.id))
        icons.retain(retainedIDs)
        deletability.removeAll()
        if let term = currentTerm {
            results = records.filter { ClassicalSearchMatcher.matches($0, term: term) }
        }
        rebuild(animatingMoves: animatingMoves)
        if let configuration {
            ClassicalIconPreparation.prepare(self.pages, geometry: configuration.geometry, scale: configuration.scale,
                                             visiblePages: pager.pages, currentPage: pager.currentPage,
                                             cache: icons, source: configuration.icon)
        }
        noResultsContainer.setVisible(results?.isEmpty == true)
        if selectedItemID.flatMap(pageIndex(of:)) == nil {
            let first = pager.pages.indices.contains(pager.currentPage) ? pager.pages[pager.currentPage].items.first?.id : nil
            select(item: isFiltering ? first : nil)
        }
    }

    /// Discards changed rasters and prevents pending loads from restoring them.
    func invalidateIcons(for ids: Set<AppIdentity>) {
        guard !ids.isEmpty else { return }
        pager.cancelIconLoads()
        icons.remove(ids)
    }

    // MARK: Filtering

    private var currentTerm: String?

    /// An empty term clears the search.
    func search(_ term: String) {
        guard !term.isEmpty else { return clearSearch() }
        currentTerm = term
        let matches = records.filter { ClassicalSearchMatcher.matches($0, term: term) }
        if results == nil {
            pageBeforeFiltering = pager.currentPage
            results = matches
            rebuild()
            if pager.currentPage != 0 { pager.jump(to: 0) }
        } else {
            results = matches
            rebuild()
        }
        noResultsContainer.setVisible(matches.isEmpty)
        select(item: pager.pages.indices.contains(pager.currentPage) ? pager.pages[pager.currentPage].items.first?.id : nil)
    }

    func clearSearch() {
        currentTerm = nil
        guard results != nil else { return }
        results = nil
        selectedItemID = nil
        rebuild()
        noResultsContainer.setVisible(false)
        pager.jump(to: pageBeforeFiltering)
    }

    // MARK: Selection

    /// Selects the application `id`: inside the open folder, otherwise on the root pages.
    func select(_ id: AppIdentity?) {
        if let folder = folders.openFolder { return folder.select(id) }
        select(item: id.map(ClassicalPageItem.ID.app))
    }

    /// Selecting an item on another page first turns to it, which clears any earlier selection.
    func select(item id: ClassicalPageItem.ID?) {
        if let id, let page = pageIndex(of: id), page != pager.currentPage { pager.settle(on: page) }
        selectedItemID = id
        applySelection()
    }

    /// With Command, left and right turn the page and move an existing selection to the first item
    /// there, and down opens a selected folder with its first item selected; otherwise the selection
    /// moves within its page. Inside an open folder the folder handles the arrows; when Command-Up
    /// closes it, its cell is selected once it has closed.
    @discardableResult
    func navigate(_ direction: ClassicalNavigation, command: Bool) -> Bool {
        if let folder = folders.openFolder {
            let result = folder.navigate(direction, command: command)
            if result == .close {
                let id = folder.content.id
                folders.close { [weak self] in self?.select(item: .folder(id)) }
            }
            return result != .ignored
        }
        guard let configuration else { return false }
        if command, direction == .down, case let .folder(id)? = selectedItemID {
            return openFolder(id, selectingFirstItem: true)
        }
        if command, direction == .left || direction == .right {
            let forward = (direction == .right) != configuration.rightToLeft
            let page = pager.currentPage + (forward ? 1 : -1)
            guard pager.pageCount > 1, pager.pages.indices.contains(page) else { return false }
            let hadSelection = selectedItemID != nil
            pager.settle(on: page)
            if hadSelection { select(item: pager.pages[page].items.first?.id) }
            return true
        }
        let pageIndex = selectedItemID.flatMap(pageIndex(of:)) ?? pager.currentPage
        guard pager.pages.indices.contains(pageIndex) else { return false }
        let items = pager.pages[pageIndex].items
        let selected = selectedItemID.flatMap { id in items.firstIndex { $0.id == id } }
        if selectedItemID != nil, selected == nil { return false }
        guard let target = ClassicalSelectionMove.target(direction, selected: selected, count: items.count,
                                                         columns: configuration.geometry.columns,
                                                         rightToLeft: configuration.rightToLeft) else { return false }
        select(item: items[target].id)
        return true
    }

    /// The cell showing the application `id`: in the open folder, or directly on a root page.
    func cell(for id: AppIdentity) -> ClassicalItemLayer? {
        folders.folder?.cell(for: id) ?? pager.cell(for: .app(id))
    }

    /// The item whose icon is under `point` (content-layer coordinates): on the open folder's current
    /// page, otherwise on a visible root page (see `ClassicalPager.item(at:excluding:)`). While a
    /// folder opens or closes no icon is under the pointer.
    func item(at point: CGPoint) -> (item: ClassicalPageItem, cell: ClassicalItemLayer)? {
        if let folder = folders.folder { return folders.isClosing || folders.isOpening ? nil : folder.item(at: point) }
        return pager.item(at: point, excluding: removing)
    }

    // MARK: Folders

    /// Opens the folder `id` from its visible root cell, unless a folder is already shown,
    /// an item is dragged or a search is active. The root selection clears.
    @discardableResult
    func openFolder(_ id: ClassicalLayoutFolder.ID, selectingFirstItem: Bool = false,
                    duringDrag: Bool = false) -> Bool {
        guard !folders.isActive, (drag == nil || duringDrag), !isFiltering, let configuration,
              let background = pager.layer.superlayer,
              let host = background.superlayer,
              let pageIndex = pager.pages.firstIndex(where: { $0.items.contains(where: { $0.id == .folder(id) }) })
        else { return false }
        if pageIndex != pager.currentPage { pager.jump(to: pageIndex) }
        let page = pager.pages[pageIndex]
        guard let index = page.items.firstIndex(where: { $0.id == .folder(id) }),
              let content = pages.lazy.flatMap({ $0 }).first(where: { $0.id == .folder(id) })?.folder,
              let cell = page.itemLayers[index] as? ClassicalFolderItemLayer else { return false }
        select(item: nil)
        let folder = ClassicalFolder(content: content, cell: cell, springboard: configuration.geometry,
                                     scale: configuration.scale, rightToLeft: configuration.rightToLeft,
                                     icon: icons.loader(configuration.icon), cachedIcon: icons.image,
                                     dragging: duringDrag)
        folder.canDelete = { [weak self] in self?.canDelete($0) ?? false }
        folder.didRename = { [weak self] id, title in
            guard let self else { return }
            let saved = self.folderRenamed?(id, title) ?? nil
            ClassicalPageFolder.rename(id, to: title, saved: saved, locale: self.folderTitleLocale(), in: &self.pages)
        }
        folder.setDeleting(isDeletingRoot)
        folders.open(folder, host: host, background: background, mainPager: pager, selectingFirstItem: selectingFirstItem)
        if let size = ClassicalIconPreparation.folderIconSize(for: content, geometry: configuration.geometry,
                                                             scale: configuration.scale) {
            icons.prepare(content.records, size: size, source: configuration.icon, retryEvicted: true)
            if icons.canRetain(count: content.records.count, size: size) { folder.loadAllIcons() }
        }
        return true
    }

    // MARK: Deleting mode

    /// Deleting mode where it applies: inside the open folder, otherwise on the root pages.
    var isDeleting: Bool { folders.openFolder?.isDeleting ?? isDeletingRoot }

    /// Every cell jitters; badges appear on deletable applications.
    /// While a folder is open only its cells change.
    func setDeleting(_ deleting: Bool) {
        guard deleting != isDeleting else { return }
        if !deleting { deletingByOption = false }
        if let folder = folders.openFolder { return folder.setDeleting(deleting) }
        isDeletingRoot = deleting
        applyEditing()
    }

    /// Pressing Option enters deleting mode, and releasing it leaves the mode only when Option
    /// started it.
    func optionChanged(isDown: Bool) {
        if isDown {
            guard !isDeleting else { return }
            setDeleting(true)
            deletingByOption = true
        } else if deletingByOption {
            setDeleting(false)
        }
    }

    /// The long press: toggles deleting mode; the held icon magnifies and stops
    /// jittering until it is released.
    func longPress(on cell: ClassicalItemLayer) {
        setDeleting(!isDeleting)
        cell.setMagnified(true)
        cell.setJittering(false)
    }

    /// The held icon returns to the page's state when released.
    func releasePress(on cell: ClassicalItemLayer) {
        cell.setMagnified(false)
        cell.setJittering(isDeleting)
    }

    /// The deletable application whose badge is under `point` (content-layer coordinates).
    func closebox(at point: CGPoint) -> (record: AppRecord, cell: ClassicalItemLayer)? {
        if let folder = folders.folder { return folders.isClosing || folders.isOpening ? nil : folder.closebox(at: point) }
        guard isDeleting, let (item, cell) = pager.closebox(at: point, excluding: removing),
              let record = item.record else { return nil }
        return (record, cell)
    }

    /// Items animating out, and deleted applications the catalog may still list.
    private var removing: Set<ClassicalPageItem.ID> = []
    private var removed: Set<AppIdentity> = []
    private var deferredPages: [[ClassicalPageItem]]?

    /// A deleted application leaves the pages before the catalog notices the bundle is gone: its
    /// cell shrinks and fades, then the cells after it slide into place. Inside the open folder
    /// the folder closes up the same way, and closes once it is empty; a closed folder shows the
    /// change when the root pages are laid out again.
    func removeRecord(_ id: AppIdentity) {
        guard records.contains(where: { $0.id == id }), !removing.contains(.app(id)) else { return }
        removed.insert(id)
        if let folder = folders.folder,
           folder.removeRecord(id, completion: { [weak self] emptied in if emptied { self?.folders.close() } }) {
            return
        }
        guard !folders.isActive else { return }
        guard let page = pager.pages.first(where: { $0.items.contains { $0.id == .app(id) } }), let cell = cell(for: id) else {
            return apply(deferredPages ?? pages, animatingMoves: false)
        }
        removing.insert(.app(id))
        page.animateRemoval(of: cell) { [weak self] in
            guard let self else { return }
            self.removing.remove(.app(id))
            guard self.removing.isEmpty else { return }
            let pages = self.deferredPages ?? self.pages
            self.deferredPages = nil
            self.apply(pages, animatingMoves: true)
        }
    }

    private func applyEditing() {
        let rightToLeft = configuration?.rightToLeft ?? false
        for page in pager.pages {
            for (item, cell) in zip(page.items, page.itemLayers) {
                // A dragged cell jitters again only once it has landed (`dragDidEnd()`).
                cell.setJittering(isDeletingRoot && !cell.isMagnified && cell !== drag?.cell)
                // Folders have no delete badge.
                let showsBadge = isDeletingRoot && item.record.map(canDelete) == true
                cell.setCloseboxVisible(showsBadge, rightToLeft: rightToLeft)
            }
        }
    }

    /// Whether `record` may be deleted, as its delete badge shows; answers are kept until the next
    /// refresh of the pages.
    func canDelete(_ record: AppRecord) -> Bool { deletability.canDelete(record) }

    // MARK: Dragging

    /// The item being dragged, from the press that lifted it until its cell is back on its page.
    private(set) var drag: ClassicalDraggedItem?
    /// Called when a catalog update waited for a drag and should now be applied.
    var deferredRefreshNeeded: (@MainActor () -> Void)?

    /// A layer with the pager's geometry above the Liquid Glass drawn under the pages, set by the
    /// glass stage so a dragged folder's glass can stay between the pages and the dragged cell.
    weak var dragOverlay: CALayer?
    /// Where dragged cells are drawn: the glass stage's overlay, otherwise the layer holding the
    /// pager, so they pass over the page edges.
    var dragHost: CALayer? { dragOverlay ?? folders.folder?.layer.superlayer ?? pager.layer.superlayer }
    var geometry: ClassicalSpringboardGeometry? { configuration?.geometry }
    var rightToLeft: Bool { configuration?.rightToLeft ?? false }

    /// The cell magnifies, leaves its page for the drag layer and stops jittering. A search-result
    /// drag clears the filter first and shows the item's page. While a folder is open only its
    /// applications move; nothing is dragged while a folder is closing.
    @discardableResult
    func beginDrag(of item: ClassicalPageItem, cell: ClassicalItemLayer) -> Bool {
        groupDragSession.clearPresentation()
        guard drag == nil, let host = dragHost else { return false }
        // Inside the open folder only applications are dragged, from the folder's pages.
        let folder = item.record == nil ? nil : folders.openFolder
        let source = folder.map { $0.content.pages.map { $0.map(ClassicalPageItem.app) } } ?? pages
        guard folder != nil || !folders.isActive,
              let page = source.firstIndex(where: { $0.contains { $0.id == item.id } }),
              let index = source[page].firstIndex(where: { $0.id == item.id }) else { return false }
        let wasFiltering = folder == nil && isFiltering
        let drag = ClassicalDraggedItem(item: item, cell: cell, page: page, index: index, springboard: self, folder: folder)
        self.drag = drag
        drag.lift(to: host)
        if wasFiltering {
            clearSearch()
            pager.jump(to: page)
        }
        return true
    }

    /// See `ClassicalDraggedItem.cancel(animated:)`.
    func cancelDrag(animated: Bool = true) {
        drag?.cancel(animated: animated)
    }

    /// A drag's new arrangement of the unfiltered pages. With `animatingMoves`, cells that stay on
    /// their page slide to their new slots in the current transaction.
    func rearrange(_ pages: [[ClassicalPageItem]], animatingMoves: Bool) {
        self.pages = pages
        rebuild(animatingMoves: animatingMoves)
    }

    /// The dragged cell is back on its page: editing visuals return and a waiting update applies.
    func dragDidEnd() {
        drag = nil
        groupVisuals.endHover()
        applyEditing()
        if deferredPages != nil {
            deferredPages = nil
            deferredRefreshNeeded?()
        }
    }

    /// The launcher closed: an open folder, the search and selection are gone before the next presentation.
    func reset() {
        groupDragSession.clearPresentation()
        folders.close(animated: false)
        cancelDrag(animated: false)
        setDeleting(false)
        selectedItemID = nil
        clearSearch()
        applySelection()
    }

    // MARK: Layout

    private func rebuild(animatingMoves: Bool = false) {
        guard let configuration else { return }
        let capacity = configuration.geometry.grid.capacity
        let shown = results.map { ClassicalPager.chunk($0.map(ClassicalPageItem.app), capacity: capacity) } ?? pages
        pager.show(pages: shown, geometry: configuration.geometry, scale: configuration.scale,
                   rightToLeft: configuration.rightToLeft, icon: icons.loader(configuration.icon),
                   cachedIcon: icons.image, animatesMoves: animatingMoves,
                   detached: drag.map { ($0.item.id, $0.cell) })
        applySelection()
        applyEditing()
    }

    private func applySelection() {
        for page in pager.pages {
            for (item, cell) in zip(page.items, page.itemLayers) {
                cell.setSelected(item.id == selectedItemID)
            }
        }
    }

    private func pageIndex(of id: ClassicalPageItem.ID) -> Int? {
        pager.pages.firstIndex { $0.items.contains { $0.id == id } }
    }
}
