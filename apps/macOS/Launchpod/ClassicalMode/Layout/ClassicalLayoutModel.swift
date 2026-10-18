import Foundation

/// The main-actor owner of the layout: loads it once, reconciles it with each catalog, and saves
/// only after loading finished so a slow load never overwrites the user's arrangement.
@MainActor
final class ClassicalLayoutModel {
    private let store: ClassicalLayoutStore?
    private(set) var layout: ClassicalLayout?
    private(set) var isLoaded: Bool
    private var saveTask: Task<Void, Never>?
    private var isReplacingLayout = false
    private var hiddenPresentationIDs = Set<AppIdentity>()
    var onError: (@MainActor (Error) -> Void)?

    init(store: ClassicalLayoutStore?) {
        self.store = store
        isLoaded = store == nil
    }

    /// Loads the saved layout; an unreadable one keeps persistence disabled until explicit recovery.
    func load() async {
        guard let store, !isLoaded else { return }
        do {
            layout = try await store.load()
            isLoaded = true
        } catch {
            onError?(error)
        }
    }

    /// The pages for `records` at `capacity`, saving the layout when reconciling changed it.
    /// New applications use system priority, then title order. The first arrangement uses the predefined
    /// system app order. A saved identity absent from `records` whose bundle identifier and location
    /// match exactly one record keeps its slot under that record's identity. A folder shows the
    /// applications of its pages that `records` holds; a folder with none of them is left out of the
    /// pages but kept in the layout.
    func pages(for records: [AppRecord], hiding hiddenIDs: Set<AppIdentity> = [],
               capacity: Int) -> [[ClassicalPageItem]] {
        if records.isEmpty {
            hiddenPresentationIDs = []
            return []
        }
        let sorted = ClassicalLayoutTitleOrder.sorted(records)
        var observed = layout ?? ClassicalInitialLayout.make(records: records, capacity: capacity)
        // A replaced catalog identity for the same app keeps its slot instead of reading as an uninstall.
        observed.adoptReplacedIdentities(from: records)
        observed.observeExcluded(records)
        observed = ClassicalInitialLayout.insertingLateTemplateApps(into: observed, records: records,
                                                                    capacity: capacity)
        var reconciled = observed.reconciled(with: sorted.map(\.id), capacity: capacity)
        reconciled.rememberApplications(records)
        if reconciled != layout && isLoaded && !isReplacingLayout {
            layout = reconciled
            save()
        }
        let hasSiriLauncher = records.contains {
            $0.metadata.knownBundleIdentifier == "com.apple.siri.launcher"
                && $0.isMissing != true && $0.source.isOnline != false
        }
        // Keep saved positions intact for applications omitted from Classical presentation.
        let visibleRecords = records.filter {
            !hiddenIDs.contains($0.id) && (!hasSiriLauncher || $0.metadata.knownBundleIdentifier != "com.apple.campo")
        }
        hiddenPresentationIDs = Set(records.map(\.id)).subtracting(visibleRecords.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: visibleRecords.map { ($0.id, $0) })
        return reconciled.pages.map { $0.compactMap { item -> ClassicalPageItem? in
            switch item {
            case let .app(id):
                return byID[id].map(ClassicalPageItem.app)
            case let .folder(folder):
                let pages = folder.pages.map { $0.compactMap { byID[$0] } }.filter { !$0.isEmpty }
                return pages.isEmpty ? nil : .folder(ClassicalPageFolder(id: folder.id, title: folder.title,
                                                                         pages: pages, usesDefaultTitle: folder.usesDefaultTitle,
                                                                         directoryOtherBaseTitle: folder.directoryOtherBaseTitle))
            }
        } }.filter { !$0.isEmpty }
    }

    /// A finished edit of the root arrangement. A folder keeps its saved contents, even when the
    /// presentation has fewer applications than the persisted folder.
    func commit(_ arrangement: ClassicalLayout) {
        guard isLoaded, !isReplacingLayout else { return }
        var updated = layout ?? ClassicalLayout()
        do {
            let arranged = try Self.arrangement(arrangement, keepingFoldersOf: updated)
            updated.replacePages(from: try Self.restoringHiddenApplications(in: arranged, from: updated,
                                                                            hiddenIDs: hiddenPresentationIDs))
        } catch {
            onError?(error)
            return
        }
        guard updated != layout else { return }
        updated.markUserArranged()
        layout = updated
        save()
    }

    /// A finished folder drag. Its visible membership and root placement are authoritative; saved
    /// applications absent from this presentation retain their positions inside their folders.
    func commitFolderDrag(_ arrangement: ClassicalLayout) {
        guard isLoaded, !isReplacingLayout else { return }
        var updated = layout ?? ClassicalLayout()
        do {
            let arranged = try Self.arrangement(arrangement, preservingUnshownOf: updated)
            updated.replacePages(from: try Self.restoringHiddenApplications(in: arranged, from: updated,
                                                                            hiddenIDs: hiddenPresentationIDs))
        } catch {
            onError?(error)
            return
        }
        guard updated != layout else { return }
        updated.markUserArranged()
        layout = updated
        save()
    }

    /// Renames folder `id`; an empty title keeps the old one. Saves when the title changed.
    /// - Returns: The folder as saved after the rename; nil when nothing changed.
    @discardableResult
    func renameFolder(_ id: ClassicalLayoutFolder.ID, to title: String) -> ClassicalLayoutFolder? {
        guard isLoaded, !isReplacingLayout else { return nil }
        guard var updated = layout, updated.renameFolder(id, to: title) else { return nil }
        updated.markUserArranged()
        layout = updated
        save()
        return updated.folder(id)
    }

    /// A successful, user-confirmed deletion is different from a temporarily missing bundle.
    func excludeDeleted(_ id: AppIdentity) {
        guard isLoaded, !isReplacingLayout else { return }
        var updated = layout ?? ClassicalLayout()
        updated.excludeDeleted(id)
        guard updated != layout else { return }
        updated.markUserArranged()
        layout = updated
        save()
    }

    /// Returns once every save requested so far, and any requested while waiting, has finished.
    func flush() async {
        while let task = saveTask {
            await task.value
            if saveTask == task { return }
        }
    }

    /// Exports the current user arrangement in the same validated format used on disk.
    func exportData() async throws -> Data {
        await flush()
        guard let layout else { throw CocoaError(.fileNoSuchFile) }
        return try JSONEncoder().encode(layout)
    }

    /// Replaces the arrangement only after the complete imported file validates.
    func importData(_ data: Data) async throws {
        let imported = try JSONDecoder().decode(ClassicalLayout.self, from: data)
        guard !isReplacingLayout else { throw CocoaError(.fileWriteUnknown) }
        isReplacingLayout = true
        defer { isReplacingLayout = false }
        await flush()
        try await store?.save(imported)
        layout = imported
        isLoaded = true
    }

    /// Returns to the built-in system order on the next catalog presentation.
    func resetToSystemLayout() async throws {
        guard !isReplacingLayout else { throw CocoaError(.fileWriteUnknown) }
        isReplacingLayout = true
        defer { isReplacingLayout = false }
        await flush()
        try await store?.removeSavedLayout()
        layout = nil
        isLoaded = true
    }

    private static func arrangement(_ arrangement: ClassicalLayout,
                                    keepingFoldersOf current: ClassicalLayout) throws -> ClassicalLayout {
        let folders = current.folders
        guard !folders.isEmpty else { return arrangement }
        let folderOf = Dictionary(uniqueKeysWithValues: folders.flatMap { folder in
            folder.identities.map { ($0, folder) }
        })
        var placed = Set(arrangement.folders.map(\.id))
        let arranged = placed
        var pages = arrangement.pages.map { page in
            page.compactMap { item -> ClassicalLayoutItem? in
                if let folder = item.folder { return current.folder(folder.id).map(ClassicalLayoutItem.folder) ?? item }
                guard let id = item.app, let folder = folderOf[id], !arranged.contains(folder.id) else { return item }
                return placed.insert(folder.id).inserted ? .folder(folder) : nil
            }
        }
        for folder in folders where !placed.contains(folder.id) {
            guard let slot = current.position(ofFolder: folder.id) else { continue }
            if pages.indices.contains(slot.page) {
                pages[slot.page].insert(.folder(folder), at: min(slot.index, pages[slot.page].count))
            } else {
                pages.append([.folder(folder)])
            }
        }
        return try ClassicalLayout(pages: pages)
    }

    private static func arrangement(_ arrangement: ClassicalLayout,
                                    preservingUnshownOf current: ClassicalLayout) throws -> ClassicalLayout {
        let shown = Set(arrangement.identities)
        let arrangedFolders = Set(arrangement.folders.map(\.id))
        var pages = arrangement.pages.map { page in
            page.map { item -> ClassicalLayoutItem in
                guard var folder = item.folder, let saved = current.folder(folder.id) else { return item }
                folder.title = saved.title
                folder.usesDefaultTitle = saved.usesDefaultTitle
                folder.directoryOtherBaseTitle = saved.directoryOtherBaseTitle
                for (pageIndex, members) in saved.pages.enumerated() {
                    let unshown = members.enumerated().filter { !shown.contains($0.element) }
                    guard !unshown.isEmpty else { continue }
                    if folder.pages.indices.contains(pageIndex) {
                        var lastHiddenIndex: Int?
                        for (index, id) in unshown {
                            let current = folder.pages[pageIndex]
                            let nextIndex = members.dropFirst(index + 1).compactMap { current.firstIndex(of: $0) }.first
                            let previousIndex = members.prefix(index).reversed().compactMap {
                                current.firstIndex(of: $0)
                            }.first
                            let position = nextIndex ?? previousIndex.map { $0 + 1 } ?? current.count
                            let insertionIndex = max(position, (lastHiddenIndex ?? -1) + 1)
                            folder.pages[pageIndex].insert(id, at: insertionIndex)
                            lastHiddenIndex = insertionIndex
                        }
                    } else {
                        folder.pages.append(unshown.map(\.element))
                    }
                }
                return .folder(folder)
            }
        }
        for folder in current.folders where !arrangedFolders.contains(folder.id) {
            let unshown = folder.pages.map { $0.filter { !shown.contains($0) } }.filter { !$0.isEmpty }
            guard !unshown.isEmpty, let slot = current.position(ofFolder: folder.id) else { continue }
            let retained = ClassicalLayoutFolder(id: folder.id, title: folder.title, pages: unshown,
                                                 usesDefaultTitle: folder.usesDefaultTitle,
                                                 directoryOtherBaseTitle: folder.directoryOtherBaseTitle)
            if pages.indices.contains(slot.page) {
                pages[slot.page].insert(.folder(retained), at: min(slot.index, pages[slot.page].count))
            } else {
                pages.append([.folder(retained)])
            }
        }
        return try ClassicalLayout(pages: pages)
    }

    private static func restoringHiddenApplications(in arrangement: ClassicalLayout, from current: ClassicalLayout,
                                                     hiddenIDs: Set<AppIdentity>) throws -> ClassicalLayout {
        guard !hiddenIDs.isEmpty else { return arrangement }
        var pages = arrangement.pages
        let arrangedIDs = Set(arrangement.identities)
        for (pageIndex, page) in current.pages.enumerated() {
            for (itemIndex, item) in page.enumerated() {
                guard let id = item.app, hiddenIDs.contains(id), !arrangedIDs.contains(id) else { continue }
                while pages.count <= pageIndex { pages.append([]) }
                pages[pageIndex].insert(.app(id), at: min(itemIndex, pages[pageIndex].count))
            }
        }
        return try ClassicalLayout(pages: pages)
    }

    private func save() {
        guard isLoaded, !isReplacingLayout, let store, let layout else { return }
        let previous = saveTask
        saveTask = Task { [weak self] in
            await previous?.value
            do {
                try await store.save(layout)
            } catch {
                self?.onError?(error)
            }
        }
    }
}
