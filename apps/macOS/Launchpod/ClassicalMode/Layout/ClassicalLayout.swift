import Foundation

/// The Classical arrangement: root pages of applications and folders in order.
/// Scans preserve known application slots, including those on offline volumes; only a confirmed
/// user deletion excludes an app from the layout.
///
/// Every application appears at most once across root and folder pages, folder identities are
/// unique, and every folder has a non-empty title and at least one application on non-empty pages.
/// Decoding rejects a layout that breaks these rules, and every mutation keeps them.
nonisolated struct ClassicalLayout: Equatable, Codable, Sendable {
    private(set) var pages: [[ClassicalLayoutItem]]
    /// A confirmed deletion is not an unavailable application. Keep it out of the layout until
    /// the catalog has first observed its absence and later discovers it again.
    private(set) var excludedIDs: Set<AppIdentity>
    private(set) var excludedObservedAbsentIDs: Set<AppIdentity>
    /// Nil for a user arrangement or a saved layout whose origin is unknown.
    private(set) var automaticTemplateBundleIDs: [AppIdentity: String]?
    /// The bundle and location of each held or excluded application, by identity, as last seen in
    /// the catalog. Lets the arrangement follow an application whose catalog identity was replaced.
    private(set) var appReferences: [AppIdentity: ClassicalLayoutAppReference]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case pages
        case excludedIDs
        case excludedObservedAbsentIDs
        case automaticTemplateBundleIDs
        case appReferences
    }

    enum ValidationError: Error {
        case duplicateIdentity
        case duplicateFolder
        case duplicateAppReference
    }

    init() {
        pages = []
        excludedIDs = []
        excludedObservedAbsentIDs = []
        automaticTemplateBundleIDs = nil
        appReferences = [:]
    }

    init(pages: [[ClassicalLayoutItem]]) throws {
        var identities = Set<AppIdentity>()
        var folderIDs = Set<ClassicalLayoutFolder.ID>()
        for item in pages.joined() {
            if let folder = item.folder {
                try folder.validate()
                guard folderIDs.insert(folder.id).inserted else { throw ValidationError.duplicateFolder }
            }
            for id in item.identities {
                guard identities.insert(id).inserted else { throw ValidationError.duplicateIdentity }
            }
        }
        self.pages = pages
        excludedIDs = []
        excludedObservedAbsentIDs = []
        automaticTemplateBundleIDs = nil
        appReferences = [:]
    }

    /// Root pages of applications only.
    init(pages: [[AppIdentity]]) throws {
        try self.init(pages: pages.map { $0.map(ClassicalLayoutItem.app) })
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container,
                                                   debugDescription: "Unsupported ClassicalLayout schema version: \(version).")
        }
        try self.init(pages: container.decode([[ClassicalLayoutItem]].self, forKey: .pages))
        excludedIDs = try container.decode(Set<AppIdentity>.self, forKey: .excludedIDs)
        excludedObservedAbsentIDs = try container.decode(Set<AppIdentity>.self,
                                                         forKey: .excludedObservedAbsentIDs)
        excludedObservedAbsentIDs.formIntersection(excludedIDs)
        automaticTemplateBundleIDs = try container.decodeIfPresent([AppIdentity: String].self,
                                                                    forKey: .automaticTemplateBundleIDs)
        let references = try container.decode([ClassicalLayoutAppReference].self, forKey: .appReferences)
        appReferences = try Dictionary(references.map { ($0.id, $0) }) { _, _ in
            throw ValidationError.duplicateAppReference
        }
        pages = Self.filtered(pages) { [excludedIDs] in !excludedIDs.contains($0) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(pages, forKey: .pages)
        try container.encode(excludedIDs.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }, forKey: .excludedIDs)
        try container.encode(excludedObservedAbsentIDs.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString },
                             forKey: .excludedObservedAbsentIDs)
        try container.encodeIfPresent(automaticTemplateBundleIDs, forKey: .automaticTemplateBundleIDs)
        try container.encode(appReferences.values.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString },
                             forKey: .appReferences)
    }

    mutating func markAutomaticTemplate(records: [AppRecord]) {
        automaticTemplateBundleIDs = Dictionary(uniqueKeysWithValues: records.compactMap { record in
            guard let bundleID = record.metadata.knownBundleIdentifier,
                  ClassicalInitialLayout.templateBundleIDs.contains(bundleID) else { return nil }
            return (record.id, bundleID)
        })
    }

    mutating func markUserArranged() {
        automaticTemplateBundleIDs = nil
    }

    mutating func rememberTemplate(records: [AppRecord]) {
        guard automaticTemplateBundleIDs != nil else { return }
        for record in records {
            guard let bundleID = record.metadata.knownBundleIdentifier,
                  ClassicalInitialLayout.templateBundleIDs.contains(bundleID) else { continue }
            automaticTemplateBundleIDs?[record.id] = bundleID
        }
    }

    /// Records where each held or excluded application in `records` is, and forgets references to
    /// applications the layout no longer holds. References of applications absent from `records` stay.
    mutating func rememberApplications(_ records: [AppRecord]) {
        let held = Set(identities).union(excludedIDs)
        var references = appReferences.filter { held.contains($0.key) }
        for record in records where held.contains(record.id) {
            references[record.id] = ClassicalLayoutAppReference(record: record)
        }
        appReferences = references
    }

    /// Gives each saved slot whose identity the catalog no longer holds to the catalog identity for
    /// the same bundle and location, in place: root and folder positions, confirmed-deletion state,
    /// and the automatic-template marker all carry over. Unmatched identities are left for
    /// `reconciled(with:capacity:)`, so only applications without such a replacement leave the layout.
    mutating func adoptReplacedIdentities(from records: [AppRecord]) {
        let replacement = ClassicalLayoutAppReference.replacements(
            for: appReferences.values, in: records, excluding: Set(identities).union(excludedIDs)
        )
        guard !replacement.isEmpty else { return }
        func current(_ id: AppIdentity) -> AppIdentity { replacement[id] ?? id }
        pages = pages.map { page in
            page.map { item in
                switch item {
                case let .app(id):
                    return .app(current(id))
                case var .folder(folder):
                    folder.pages = folder.pages.map { $0.map(current) }
                    return .folder(folder)
                }
            }
        }
        excludedIDs = Set(excludedIDs.map(current))
        excludedObservedAbsentIDs = Set(excludedObservedAbsentIDs.map(current))
        automaticTemplateBundleIDs = automaticTemplateBundleIDs.map { bundleIDs in
            Dictionary(bundleIDs.map { (current($0.key), $0.value) }) { kept, _ in kept }
        }
        for (old, new) in replacement {
            appReferences[old] = nil
            if let record = records.first(where: { $0.id == new }) {
                appReferences[new] = ClassicalLayoutAppReference(record: record)
            }
        }
    }

    /// Every application in root order, with a folder's applications at the folder's slot.
    var identities: [AppIdentity] { pages.flatMap { $0.flatMap(\.identities) } }

    /// Every folder in root order.
    var folders: [ClassicalLayoutFolder] { pages.flatMap { $0.compactMap(\.folder) } }

    func folder(_ id: ClassicalLayoutFolder.ID) -> ClassicalLayoutFolder? {
        position(ofFolder: id).flatMap { pages[$0.page][$0.index].folder }
    }

    /// The root page and slot holding `id`, directly or through the folder that contains it.
    func position(of id: AppIdentity) -> (page: Int, index: Int)? {
        for (page, items) in pages.enumerated() {
            if let index = items.firstIndex(where: { $0.identities.contains(id) }) { return (page, index) }
        }
        return nil
    }

    /// The root page and slot holding the folder `id`.
    func position(ofFolder id: ClassicalLayoutFolder.ID) -> (page: Int, index: Int)? {
        for (page, items) in pages.enumerated() {
            if let index = items.firstIndex(where: { $0.folder?.id == id }) { return (page, index) }
        }
        return nil
    }

    // MARK: Reconciling with the catalog

    /// Brings the layout in line with catalog identities (already in the order new applications are added):
    /// identities no longer retained by the catalog leave their page without pulling others across pages, pages over
    /// `capacity` split, new applications fill the first page with room and then new pages, and
    /// empty pages disappear. The same holds inside folders, except that new applications go only to
    /// root pages; a folder left without applications goes, while a single-application folder stays.
    func reconciled(with available: [AppIdentity], capacity: Int) -> ClassicalLayout {
        let capacity = max(capacity, 1)
        let known = Set(available).subtracting(excludedIDs)
        var layout = self
        layout.pages = Self.filtered(pages, keeping: known.contains)
        layout.splitOverfullPages(capacity: capacity)
        let placed = Set(layout.identities)
        layout.addToNextAvailableSpace(available.filter { known.contains($0) && !placed.contains($0) }, capacity: capacity)
        layout.removeEmptyPages()
        return layout
    }

    /// A page over capacity keeps its first `capacity` items; the rest move to new pages inserted right after it.
    /// Folder pages split the same way inside their folder.
    mutating func splitOverfullPages(capacity: Int) {
        pages = Self.split(pages, capacity: capacity).map { page in
            page.map { item in
                guard var folder = item.folder else { return item }
                folder.pages = Self.split(folder.pages, capacity: capacity)
                return .folder(folder)
            }
        }
    }

    private static func split<Item>(_ pages: [[Item]], capacity: Int) -> [[Item]] {
        var result: [[Item]] = []
        for page in pages {
            result.append(contentsOf: stride(from: 0, to: max(page.count, 1), by: capacity).map {
                Array(page[$0..<min($0 + capacity, page.count)])
            })
        }
        return result
    }

    /// Each item goes to the first page, from the first, with room; when every page is full a new page is appended.
    mutating func addToNextAvailableSpace(_ ids: [AppIdentity], capacity: Int) {
        for id in ids {
            if let page = pages.firstIndex(where: { $0.count < capacity }) {
                pages[page].append(.app(id))
            } else {
                pages.append([.app(id)])
            }
        }
    }

    /// Pages left without items go.
    mutating func removeEmptyPages() {
        pages.removeAll { $0.isEmpty }
    }

    /// Removes `id` from its root or folder page. A folder left without applications goes with its
    /// slot; a folder page left empty goes. Emptied root pages stay for the caller to remove.
    mutating func remove(_ id: AppIdentity) {
        takeOut(id)
        removeEmptyFolders()
    }

    /// Removes `id` from its page, leaving any emptied folder page or folder in place.
    private mutating func takeOut(_ id: AppIdentity) {
        guard let position = position(of: id) else { return }
        guard var folder = pages[position.page][position.index].folder else {
            pages[position.page].remove(at: position.index)
            return
        }
        folder.pages = folder.pages.map { $0.filter { $0 != id } }
        pages[position.page][position.index] = .folder(folder)
    }

    private mutating func removeEmptyFolders() {
        pages = Self.filtered(pages) { _ in true }
    }

    /// `pages` keeping only the applications that satisfy `keep`; folder pages left empty go, and
    /// so do folders left without applications. Root pages are never removed here.
    private static func filtered(_ pages: [[ClassicalLayoutItem]],
                                 keeping keep: (AppIdentity) -> Bool) -> [[ClassicalLayoutItem]] {
        pages.map { page in
            page.compactMap { item in
                switch item {
                case let .app(id):
                    return keep(id) ? item : nil
                case var .folder(folder):
                    folder.pages = folder.pages.map { $0.filter(keep) }.filter { !$0.isEmpty }
                    return folder.pages.isEmpty ? nil : .folder(folder)
                }
            }
        }
    }

    /// Called only after the user's deletion has succeeded. An external volume disappearing
    /// never calls this, so its application keeps its original slot.
    mutating func excludeDeleted(_ id: AppIdentity) {
        excludedIDs.insert(id)
        excludedObservedAbsentIDs.remove(id)
        remove(id)
        removeEmptyPages()
    }

    /// Drag commits contain only page positions. Preserve confirmed-deletion state while taking
    /// the new arrangement, otherwise a rearrangement would resurrect a removed application.
    mutating func replacePages(from arrangement: ClassicalLayout) {
        pages = Self.filtered(arrangement.pages) { [excludedIDs] in !excludedIDs.contains($0) }
        removeEmptyPages()
    }

    /// Reinstallation can restore a deleted application, but a stale pre-deletion catalog
    /// snapshot must not immediately undo the exclusion.
    mutating func observeExcluded(_ records: [AppRecord]) {
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for id in excludedIDs {
            guard let record = byID[id] else {
                excludedObservedAbsentIDs.insert(id)
                continue
            }
            if record.isMissing == true || record.source.isOnline == false {
                excludedObservedAbsentIDs.insert(id)
            } else if excludedObservedAbsentIDs.contains(id), record.isMissing == false,
                      record.source.isOnline == true {
                excludedIDs.remove(id)
                excludedObservedAbsentIDs.remove(id)
            }
        }
    }

    // MARK: Dragging

    /// While `page` holds more than `capacity` items, its
    /// last item moves to the start of the next page, created when needed, and so on down the pages.
    mutating func pushOverflow(from page: Int, capacity: Int) {
        Self.pushOverflow(&pages, from: page, capacity: capacity)
    }

    static func pushOverflow<Item>(_ pages: inout [[Item]], from page: Int, capacity: Int) {
        var page = page
        while pages.indices.contains(page), pages[page].count > capacity {
            let overflow = pages[page].removeLast()
            if page + 1 == pages.count { pages.append([]) }
            pages[page + 1].insert(overflow, at: 0)
            if pages[page].count <= capacity { page += 1 }
        }
    }

    // MARK: Folder transactions

    // Each transaction is one finished edit. Page and slot arguments address the layout with the
    // moved application already taken out; folder pages and folders emptied by the move, and
    // emptied root pages, go afterwards.

    /// Groups `dragged` with `target` in a new folder titled `title`, in `target`'s root slot, on one
    /// page holding `target` then `dragged`. `dragged` first leaves wherever it was.
    ///
    /// `target` must be an application on a root page, `dragged` a different application, and
    /// `title` not empty.
    @discardableResult
    mutating func makeFolder(target: AppIdentity, dragged: AppIdentity, title: String) -> ClassicalLayoutFolder.ID {
        precondition(target != dragged, "A folder groups two different applications")
        precondition(!ClassicalLayoutFolder.isEmptyTitle(title), "A folder title is never empty")
        precondition(pages.joined().contains(.app(target)), "The target is an application on a root page")
        takeOut(dragged)
        guard let slot = position(of: target) else { preconditionFailure("The target is on a root page") }
        let folder = ClassicalLayoutFolder(title: title, pages: [[target, dragged]])
        pages[slot.page][slot.index] = .folder(folder)
        removeEmptyFolders()
        removeEmptyPages()
        return folder.id
    }

    /// Appends `app` to the end of folder `id`'s last page, or to a new page when that page holds
    /// `capacity` applications. False, with nothing changed, when the folder does not exist.
    @discardableResult
    mutating func insert(_ app: AppIdentity, intoFolder id: ClassicalLayoutFolder.ID, capacity: Int) -> Bool {
        guard position(ofFolder: id) != nil else { return false }
        takeOut(app)
        return updateFolder(id) { folder in
            if let last = folder.pages.indices.last, folder.pages[last].count < max(capacity, 1) {
                folder.pages[last].append(app)
            } else {
                folder.pages.append([app])
            }
        }
    }

    /// Moves `app`, from a root or folder page, to `index` on root page `page`; `page` equal to the
    /// page count adds a page. Positions are clamped, and an overfull page is left for `pushOverflow(from:capacity:)`.
    mutating func move(_ app: AppIdentity, toRootPage page: Int, index: Int) {
        takeOut(app)
        let page = min(max(page, 0), pages.count)
        if page == pages.count { pages.append([]) }
        pages[page].insert(.app(app), at: min(max(index, 0), pages[page].count))
        removeEmptyFolders()
        removeEmptyPages()
    }

    /// Replaces folder `id` with its applications, in page order, starting at the folder's root slot.
    /// An overfull root page is left for `pushOverflow(from:capacity:)`. False when the folder does not exist.
    @discardableResult
    mutating func dissolve(_ id: ClassicalLayoutFolder.ID) -> Bool {
        guard let slot = position(ofFolder: id), let folder = pages[slot.page][slot.index].folder else { return false }
        pages[slot.page].replaceSubrange(slot.index...slot.index, with: folder.identities.map(ClassicalLayoutItem.app))
        return true
    }

    /// Renames folder `id`. An empty title is ignored and the old title kept; titles need not be unique.
    /// False when nothing changed.
    @discardableResult
    mutating func renameFolder(_ id: ClassicalLayoutFolder.ID, to title: String) -> Bool {
        guard !ClassicalLayoutFolder.isEmptyTitle(title), let folder = folder(id),
              folder.title != title || folder.usesDefaultTitle else { return false }
        return updateFolder(id) {
            $0.title = title
            $0.usesDefaultTitle = false
            $0.directoryOtherBaseTitle = nil
        }
    }

    /// While folder `id`'s `page` holds more than `capacity` applications, its last application moves
    /// to the start of the folder's next page, created when needed, and so on down the folder's pages.
    mutating func pushOverflow(inFolder id: ClassicalLayoutFolder.ID, from page: Int, capacity: Int) {
        updateFolder(id) { Self.pushOverflow(&$0.pages, from: page, capacity: max(capacity, 1)) }
    }

    /// Applies `change` to folder `id`, then drops emptied folder pages, emptied folders, and emptied root pages.
    @discardableResult
    private mutating func updateFolder(_ id: ClassicalLayoutFolder.ID,
                                       _ change: (inout ClassicalLayoutFolder) -> Void) -> Bool {
        guard let slot = position(ofFolder: id), var folder = pages[slot.page][slot.index].folder else { return false }
        change(&folder)
        pages[slot.page][slot.index] = .folder(folder)
        removeEmptyFolders()
        removeEmptyPages()
        return true
    }
}
