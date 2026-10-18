import CoreGraphics

/// Orders Classical icon preparation from visible root cells through folders to distant pages.
@MainActor
enum ClassicalIconPreparation {
    static func prepare(_ pages: [[ClassicalPageItem]], geometry: ClassicalSpringboardGeometry,
                        scale: CGFloat, visiblePages: [ClassicalGridPage], currentPage: Int,
                        cache: ClassicalIconCache,
                        source: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage) {
        let rootLayout = ClassicalItemLayout(cellSize: geometry.grid.cellSize)
        guard let rootSize = try? AppIconSize(pointSize: rootLayout.iconFrame.size,
                                              backingScale: scale) else { return }

        // Visible cells have queued loads in their pager. Start their shared cache requests first.
        for index in visiblePages.indices where abs(index - currentPage) <= 1 {
            cache.prepare(visiblePages[index].records, size: rootSize, source: source)
        }
        for page in pages {
            for item in page {
                guard case let .folder(folder) = item else { continue }
                let side = ClassicalFolderGeometry.Cell.miniIconSide(iconSide: rootLayout.iconFrame.height)
                if let size = try? AppIconSize(pointSize: CGSize(width: side, height: side), backingScale: scale) {
                    cache.prepare(folder.pages.first ?? [], size: size, source: source)
                }
                if let size = folderIconSize(for: folder, geometry: geometry, scale: scale) {
                    cache.prepare(folder.records, size: size, source: source)
                }
            }
        }
        for index in visiblePages.indices where abs(index - currentPage) > 1 {
            cache.prepare(visiblePages[index].records, size: rootSize, source: source)
        }
        for page in pages {
            cache.prepare(page.compactMap(\.record), size: rootSize, source: source)
        }
    }

    static func folderIconSize(for folder: ClassicalPageFolder, geometry: ClassicalSpringboardGeometry,
                               scale: CGFloat) -> AppIconSize? {
        let panel = ClassicalFolderGeometry.Panel(springboard: geometry, itemCount: folder.records.count)
        let layout = ClassicalItemLayout(cellSize: panel.grid.cellSize)
        return try? AppIconSize(pointSize: layout.iconFrame.size, backingScale: scale)
    }
}
