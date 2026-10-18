import CoreGraphics

/// What the Classical pages show: the arranged applications and folders for a page capacity, their
/// icon rasters, and where a finished rearrangement or a folder's new title goes.
struct ClassicalPageContent {
    var pages: @MainActor (_ capacity: Int) -> [[ClassicalPageItem]]
    let icon: @MainActor (AppRecord, AppIconSize) async throws -> CGImage
    var commit: @MainActor (ClassicalLayout) -> Void = { _ in }
    var commitFolderDrag: @MainActor (ClassicalLayout) -> Void = { _ in }
    var didDelete: @MainActor (AppIdentity) -> Void = { _ in }
    var didOpen: @MainActor (AppIdentity) -> Void = { _ in }
    /// Saves a folder's new title and returns the folder as saved; nil when nothing was saved.
    var renameFolder: @MainActor (ClassicalLayoutFolder.ID, String) -> ClassicalLayoutFolder? = { _, _ in nil }

    /// Applications in full pages, in the given order, with nothing saved.
    init(records: @escaping @MainActor () -> [AppRecord],
         icon: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage) {
        pages = { ClassicalPager.chunk(records().map(ClassicalPageItem.app), capacity: $0) }
        self.icon = icon
    }
}

extension ClassicalPageContent {
    /// The catalog's applications in the user's saved arrangement.
    @MainActor init(services: AppServices, layout: ClassicalLayoutModel) {
        self.init(records: { [] }, icon: { [weak services] record, size in
            guard let services else { throw CancellationError() }
            return try await services.icons.icon(for: record, size: size).cgImage
        })
        pages = { [weak services, weak layout] capacity in
            guard let services, let records = services.data?.records else { return [] }
            if !services.hasCurrentScan { return [] }
            let presentationRecords = services.presentationRecords
            let hiddenIDs = Set(records.map(\.id)).subtracting(presentationRecords.map(\.id))
            return layout?.pages(for: records, hiding: hiddenIDs, capacity: capacity)
                ?? ClassicalPager.chunk(presentationRecords.map(ClassicalPageItem.app), capacity: capacity)
        }
        commit = { [weak layout] in layout?.commit($0) }
        commitFolderDrag = { [weak layout] in layout?.commitFolderDrag($0) }
        renameFolder = { [weak layout] in layout?.renameFolder($0, to: $1) }
        didDelete = { [weak layout] in layout?.excludeDeleted($0) }
        didOpen = { [weak services] in services?.markOpened($0) }
    }
}
