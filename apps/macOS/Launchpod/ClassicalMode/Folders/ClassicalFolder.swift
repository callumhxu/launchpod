import AppKit
import QuartzCore

/// An open Classical folder: its applications on pages inside the panel, the keyboard selection and
/// deleting mode there, and the edits made while it is open. Its pages turn with their own
/// `ClassicalPager`. `ClassicalFolderPresenter` shows and hides it.
///
/// Points are in the coordinates of the layer holding the panel, which the content view shares.
@MainActor
final class ClassicalFolder {
    /// How a key press inside the folder was handled.
    enum Navigation: Equatable {
        case handled, ignored, close
    }

    private(set) var content: ClassicalPageFolder
    /// The closed folder's cell on its root page.
    private(set) var cell: ClassicalFolderItemLayer
    let layer: ClassicalFolderLayer
    let pager = ClassicalPager()
    let geometry: ClassicalFolderGeometry.Panel
    let rightToLeft: Bool
    private let pageCapacity: Int
    private let scale: CGFloat
    private let icon: @MainActor (AppRecord, AppIconSize) async throws -> CGImage
    private let cachedIcon: @MainActor (AppRecord, AppIconSize) -> CGImage?
    private(set) var selectedID: AppIdentity?
    private(set) var isDeleting = false
    private var removing: Set<AppIdentity> = []
    /// Whether an application may be deleted, as its delete badge shows.
    var canDelete: @MainActor (AppRecord) -> Bool = { _ in false }
    /// Called with the folder and its new, non-empty title after an edit changed it.
    var didRename: (@MainActor (ClassicalLayoutFolder.ID, String) -> Void)?
    let titleEditor = ClassicalFolderTitleEditor()

    /// A folder opened while an item is `dragging` may get a row for it; see `ClassicalFolderGeometry.Panel`.
    init(content: ClassicalPageFolder, cell: ClassicalFolderItemLayer, springboard: ClassicalSpringboardGeometry,
         scale: CGFloat, rightToLeft: Bool, icon: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage,
         cachedIcon: @escaping @MainActor (AppRecord, AppIconSize) -> CGImage?, dragging: Bool = false) {
        var content = content
        content.pages = Self.paginate(content.pages, capacity: springboard.grid.capacity)
        self.content = content
        self.cell = cell
        layer = ClassicalFolderLayer(glassEnabled: cell.glassEnabled)
        geometry = ClassicalFolderGeometry.Panel(springboard: springboard, itemCount: content.records.count,
                                                 dragging: dragging)
        pageCapacity = springboard.grid.capacity
        self.scale = scale
        self.rightToLeft = rightToLeft
        self.icon = icon
        self.cachedIcon = cachedIcon
        pager.pageWillChange = { [weak self] in
            guard let self, self.selectedID != nil else { return }
            self.selectedID = nil
            self.applySelection()
        }
        showPages(animatingMoves: false)
        layer.layOut(geometry, title: content.title, scale: scale, pagerLayer: pager.layer)
        titleEditor.commit = { [weak self] in self?.commitTitle($0) }
    }

    // MARK: Hit testing

    /// `point` in the pager's holding layer, for the pager's own event handling.
    func pagerPoint(_ point: CGPoint) -> CGPoint {
        layer.maskContainerLayer.convert(point, from: layer.superlayer)
    }

    func panelContains(_ point: CGPoint) -> Bool {
        layer.frame.contains(point)
    }

    func backdropContains(_ point: CGPoint) -> Bool {
        layer.backdropContains(layer.convert(point, from: layer.superlayer))
    }

    /// Whether `point` is on the title label.
    func titleContains(_ point: CGPoint) -> Bool {
        layer.titleLayer.frame.contains(layer.convert(point, from: layer.superlayer))
    }

    /// The application whose icon is under `point` on the current folder page.
    func item(at point: CGPoint) -> (item: ClassicalPageItem, cell: ClassicalItemLayer)? {
        currentCells.first { _, cell in
            cell.iconLayer.frame.contains(cell.jitterLayer.convert(point, from: layer.superlayer))
        }.map { (item: .app($0.record), cell: $0.cell) }
    }

    /// The deletable application whose badge is under `point`.
    func closebox(at point: CGPoint) -> (record: AppRecord, cell: ClassicalItemLayer)? {
        guard isDeleting else { return nil }
        return currentCells.first { _, cell in
            cell.closeboxContains(cell.jitterLayer.convert(point, from: layer.superlayer))
        }
    }

    func cell(for id: AppIdentity) -> ClassicalItemLayer? {
        for page in pager.pages {
            if let index = page.records.firstIndex(where: { $0.id == id }), page.itemLayers.indices.contains(index) {
                return page.itemLayers[index]
            }
        }
        return nil
    }

    private var currentCells: [(record: AppRecord, cell: ClassicalItemLayer)] {
        guard pager.pages.indices.contains(pager.currentPage) else { return [] }
        let page = pager.pages[pager.currentPage]
        return zip(page.records, page.itemLayers).filter { !removing.contains($0.0.id) }.map { (record: $0.0, cell: $0.1) }
    }

    // MARK: Selection

    var selectedRecord: AppRecord? {
        guard let selectedID else { return nil }
        return content.records.first { $0.id == selectedID }
    }

    /// Selecting an item on another folder page first turns to it.
    func select(_ id: AppIdentity?) {
        if let id, let page = pager.pages.firstIndex(where: { $0.records.contains { $0.id == id } }),
           page != pager.currentPage {
            pager.settle(on: page)
        }
        selectedID = id
        applySelection()
    }

    /// Arrows move the selection within the current folder page, as on the root pages. Command-Up
    /// with a selection closes the folder. Command-Left and Command-Right turn the folder's page and
    /// move an existing selection to the first item there; other Command-arrows act as plain arrows.
    func navigate(_ direction: ClassicalNavigation, command: Bool) -> Navigation {
        if command, direction == .up, selectedID != nil { return .close }
        if command, direction == .left || direction == .right {
            let forward = (direction == .right) != rightToLeft
            let page = pager.currentPage + (forward ? 1 : -1)
            guard pager.pageCount > 1, pager.pages.indices.contains(page) else { return .ignored }
            let hadSelection = selectedID != nil
            pager.settle(on: page)
            if hadSelection { select(pager.pages[page].records.first?.id) }
            return .handled
        }
        let pageIndex = selectedID.flatMap { id in pager.pages.firstIndex { $0.records.contains { $0.id == id } } }
            ?? pager.currentPage
        guard pager.pages.indices.contains(pageIndex) else { return .ignored }
        let records = pager.pages[pageIndex].records
        let selected = selectedID.flatMap { id in records.firstIndex { $0.id == id } }
        if selectedID != nil, selected == nil { return .ignored }
        guard let target = ClassicalSelectionMove.target(direction, selected: selected, count: records.count,
                                                         columns: geometry.columns, rightToLeft: rightToLeft) else {
            return .ignored
        }
        select(records[target].id)
        return .handled
    }

    private func applySelection() {
        for page in pager.pages {
            for (record, cell) in zip(page.records, page.itemLayers) { cell.setSelected(record.id == selectedID) }
        }
    }

    // MARK: Deleting mode

    func setDeleting(_ deleting: Bool) {
        guard deleting != isDeleting else { return }
        isDeleting = deleting
        applyEditing()
    }

    /// In deleting mode every cell jitters, except a held one, and deletable applications show a badge.
    func applyEditing() {
        for page in pager.pages {
            for (record, cell) in zip(page.records, page.itemLayers) {
                cell.setJittering(isDeleting && !cell.isMagnified)
                cell.setCloseboxVisible(isDeleting && canDelete(record), rightToLeft: rightToLeft)
            }
        }
    }

    /// A deleted application leaves its folder page as it leaves a root page: its cell shrinks and
    /// fades, then the rest of the folder closes up. `completion` receives whether the folder is now empty.
    /// False when the application is not shown in this folder.
    @discardableResult
    func removeRecord(_ id: AppIdentity, completion: @escaping @MainActor (_ emptied: Bool) -> Void) -> Bool {
        guard content.records.contains(where: { $0.id == id }), !removing.contains(id) else { return false }
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.removing.remove(id)
            self.content.pages = self.content.pages.map { $0.filter { $0.id != id } }.filter { !$0.isEmpty }
            if self.selectedID == id { self.selectedID = nil }
            self.cell.setFolder(self.content)
            guard !self.content.pages.isEmpty else { return completion(true) }
            CATransaction.begin()
            self.showPages(animatingMoves: true)
            CATransaction.commit()
            completion(false)
        }
        guard let page = pager.pages.first(where: { $0.records.contains { $0.id == id } }), let cell = cell(for: id) else {
            finish()
            return true
        }
        removing.insert(id)
        page.animateRemoval(of: cell, completion: finish)
        return true
    }

    private func showPages(animatingMoves: Bool) {
        pager.show(pages: content.pages.map { $0.map(ClassicalPageItem.app) }, layout: geometry.pagerLayout, scale: scale,
                   rightToLeft: rightToLeft, icon: icon, cachedIcon: cachedIcon, animatesMoves: animatingMoves)
        applySelection()
        applyEditing()
    }

    /// Starts the remaining page loads while the folder opens, when its full raster set fits the cache budget.
    func loadAllIcons() {
        pager.pages.forEach { $0.loadIcons() }
    }

    /// The root pages were rebuilt while the folder is shown; `cell` now stands for it there.
    func replaceCell(_ cell: ClassicalFolderItemLayer) {
        self.cell = cell
    }

    /// Updates the visible folder arrangement while one of its cells is detached for a drag.
    func rearrange(_ pages: [[AppRecord]], dragged: ClassicalItemLayer, id: AppIdentity,
                   animatingMoves: Bool) {
        content.pages = Self.paginate(pages, capacity: pageCapacity)
        pager.show(pages: content.pages.map { $0.map(ClassicalPageItem.app) }, layout: geometry.pagerLayout, scale: scale,
                   rightToLeft: rightToLeft, icon: icon, cachedIcon: cachedIcon,
                   animatesMoves: animatingMoves, detached: (.app(id), dragged))
        applySelection()
        applyEditing()
    }

    /// Keeps existing page breaks and carries excess items into the start of following pages.
    private static func paginate(_ pages: [[AppRecord]], capacity: Int) -> [[AppRecord]] {
        let capacity = max(capacity, 1)
        var result = pages
        var page = 0
        while page < result.count {
            ClassicalLayout.pushOverflow(&result, from: page, capacity: capacity)
            page += 1
        }
        return result
    }

    // MARK: Title

    /// A release on the title starts editing it in `view`.
    func beginTitleEditing(in view: NSView) {
        guard let host = layer.superlayer, let viewLayer = view.layer else { return }
        let frame = viewLayer.convert(layer.convert(layer.titleEditFrame, to: host), from: host)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        titleEditor.begin(title: content.title, frame: frame, font: ClassicalFolderLayer.titleFont, in: view)
        layer.titleLayer.isHidden = true
        CATransaction.commit()
    }

    /// Ends an edit in progress, keeping its title unless it is empty.
    func endTitleEditing() {
        titleEditor.end()
    }

    /// A non-empty title different from the current one renames the folder, even one of only
    /// spaces; anything else keeps it.
    func commitTitle(_ title: String) {
        let renamed = !ClassicalLayoutFolder.isEmptyTitle(title) && title != content.title
        if renamed {
            content.title = title
            layer.setTitle(title)
            cell.setFolder(content)
            layer.titleLayer.display()
            cell.titleLayer.display()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.titleLayer.isHidden = false
        CATransaction.commit()
        if renamed { didRename?(content.id, title) }
    }
}
