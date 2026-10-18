import Foundation

/// One slot of a Classical page as shown: an application, or a folder whose applications are
/// resolved against the catalog. Search results and the pages inside a folder hold only applications.
nonisolated enum ClassicalPageItem: Equatable, Sendable {
    case app(AppRecord)
    case folder(ClassicalPageFolder)

    /// The identity of the item in a slot, stable across refreshes and renames.
    enum ID: Hashable, Sendable {
        case app(AppIdentity)
        case folder(ClassicalLayoutFolder.ID)

        /// The identity of the item a layout slot holds.
        init(_ item: ClassicalLayoutItem) {
            switch item {
            case let .app(id): self = .app(id)
            case let .folder(folder): self = .folder(folder.id)
            }
        }
    }

    var id: ID {
        switch self {
        case let .app(record): .app(record.id)
        case let .folder(folder): .folder(folder.id)
        }
    }

    /// The application in this slot, or nil for a folder.
    var record: AppRecord? {
        guard case let .app(record) = self else { return nil }
        return record
    }

    /// The folder in this slot, or nil for an application.
    var folder: ClassicalPageFolder? {
        guard case let .folder(folder) = self else { return nil }
        return folder
    }

    var title: String {
        switch self {
        case let .app(record): record.metadata.displayName
        case let .folder(folder): folder.title
        }
    }

    /// Every application this slot shows: the application itself, or the folder's in page order.
    var records: [AppRecord] {
        switch self {
        case let .app(record): [record]
        case let .folder(folder): folder.records
        }
    }

    /// The layout slot this item stands for. A folder carries only the applications shown in it;
    /// `ClassicalLayoutModel` keeps the saved contents of a folder it already knows.
    var layoutItem: ClassicalLayoutItem {
        switch self {
        case let .app(record):
            .app(record.id)
        case let .folder(folder):
            .folder(ClassicalLayoutFolder(id: folder.id, title: folder.title, pages: folder.pages.map { $0.map(\.id) },
                                          usesDefaultTitle: folder.usesDefaultTitle,
                                          directoryOtherBaseTitle: folder.directoryOtherBaseTitle))
        }
    }

    /// This item without the applications in `ids`: nil for a removed application or a folder left
    /// empty; a folder page left empty goes.
    func removing(_ ids: Set<AppIdentity>) -> ClassicalPageItem? {
        switch self {
        case let .app(record):
            return ids.contains(record.id) ? nil : self
        case var .folder(folder):
            folder.pages = folder.pages.map { $0.filter { !ids.contains($0.id) } }.filter { !$0.isEmpty }
            return folder.pages.isEmpty ? nil : .folder(folder)
        }
    }
}

/// A folder as shown on a root page: its title and the non-empty pages of its applications that
/// the catalog knows, in folder order.
nonisolated struct ClassicalPageFolder: Equatable, Sendable {
    let id: ClassicalLayoutFolder.ID
    var title: String
    var pages: [[AppRecord]]
    var usesDefaultTitle = false
    var directoryOtherBaseTitle: String?

    var records: [AppRecord] { pages.flatMap { $0 } }

    /// Gives the folder `id` on the root `pages` its renamed title: the saved folder's title state,
    /// shown in `locale`, or `title` alone when nothing was saved.
    static func rename(_ id: ClassicalLayoutFolder.ID, to title: String, saved: ClassicalLayoutFolder?,
                       locale: Locale, in pages: inout [[ClassicalPageItem]]) {
        for page in pages.indices {
            guard let index = pages[page].firstIndex(where: { $0.id == .folder(id) }),
                  var folder = pages[page][index].folder else { continue }
            if let saved {
                folder.usesDefaultTitle = saved.usesDefaultTitle
                folder.directoryOtherBaseTitle = saved.directoryOtherBaseTitle
                folder.title = ClassicalLayoutFolder.displayTitle(for: id, title: saved.title,
                                                                  usesDefaultTitle: saved.usesDefaultTitle, locale: locale,
                                                                  directoryOtherBaseTitle: saved.directoryOtherBaseTitle)
            } else {
                folder.title = title
            }
            pages[page][index] = .folder(folder)
            return
        }
    }
}
