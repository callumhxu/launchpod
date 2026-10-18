import CoreGraphics
import Foundation

/// Shares Classical icon requests and retains recently used rasters for page and folder rebuilds.
@MainActor
final class ClassicalIconCache {
    private struct Key: Hashable {
        let id: AppIdentity
        let size: AppIconSize
    }

    private struct Pending {
        let token: UUID
        let task: Task<CGImage, Error>
    }

    private struct Entry {
        let image: CGImage
        let cost: Int
        var lastUsed: UInt64
    }

    private let cacheCostLimit: Int
    private var images: [Key: Entry] = [:]
    private var pending: [Key: Pending] = [:]
    private var prepared: Set<Key> = []
    private var accessCount: UInt64 = 0
    private(set) var cachedCost = 0

    init(cacheCostLimit: Int = 64 * 1024 * 1024) {
        precondition(cacheCostLimit >= 0)
        self.cacheCostLimit = cacheCostLimit
    }

    isolated deinit {
        pending.values.forEach { $0.task.cancel() }
    }

    /// Whether one complete set of requested rasters fits this cache's completed-image budget.
    func canRetain(count: Int, size: AppIconSize) -> Bool {
        guard count >= 0 else { return false }
        let bytesPerImage = size.pixelWidth * 4 * size.pixelHeight
        let (total, overflow) = bytesPerImage.multipliedReportingOverflow(by: count)
        return !overflow && total <= cacheCostLimit
    }

    func image(for record: AppRecord, size: AppIconSize) -> CGImage? {
        let key = Key(id: record.id, size: size)
        guard let image = images[key]?.image else { return nil }
        accessCount &+= 1
        images[key]?.lastUsed = accessCount
        return image
    }

    /// Loads through `source`, sharing work with preparation and other cells of the same size.
    func loader(_ source: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage)
        -> @MainActor (AppRecord, AppIconSize) async throws -> CGImage {
        { [weak self] record, size in
            guard let self else { throw CancellationError() }
            try Task.checkCancellation()
            if let image = self.image(for: record, size: size) { return image }
            let image = try await self.request(record, size: size, source: source).value
            try Task.checkCancellation()
            return image
        }
    }

    /// Begins loading records before their cells are visible; calls for an existing key share work.
    /// `retryEvicted` refreshes missing images when their folder becomes active.
    func prepare(_ records: [AppRecord], size: AppIconSize,
                 source: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage,
                 retryEvicted: Bool = false) {
        for record in records {
            let key = Key(id: record.id, size: size)
            if (retryEvicted || !prepared.contains(key)), images[key] == nil {
                prepared.insert(key)
                _ = request(record, size: size, source: source)
            }
        }
    }

    func removeAll() {
        pending.values.forEach { $0.task.cancel() }
        pending.removeAll()
        prepared.removeAll()
        images.removeAll()
        cachedCost = 0
    }

    /// Keeps only the rasters and pending work of `ids`.
    func retain(_ ids: Set<AppIdentity>) {
        remove(Set(images.keys.map(\.id)).union(pending.keys.map(\.id))
            .union(prepared.map(\.id)).subtracting(ids))
    }

    func remove(_ ids: Set<AppIdentity>) {
        guard !ids.isEmpty else { return }
        for key in pending.keys.filter({ ids.contains($0.id) }) {
            pending.removeValue(forKey: key)?.task.cancel()
        }
        prepared = prepared.filter { !ids.contains($0.id) }
        for key in images.keys.filter({ ids.contains($0.id) }) {
            discard(key)
        }
    }

    private func request(_ record: AppRecord, size: AppIconSize,
                         source: @escaping @MainActor (AppRecord, AppIconSize) async throws -> CGImage) -> Task<CGImage, Error> {
        let key = Key(id: record.id, size: size)
        if let pending = pending[key] { return pending.task }
        let token = UUID()
        let task = Task { [weak self] in
            do {
                let image = try await source(record, size)
                try Task.checkCancellation()
                self?.finish(key, token: token, image: image)
                return image
            } catch {
                self?.finish(key, token: token, image: nil)
                throw error
            }
        }
        pending[key] = Pending(token: token, task: task)
        return task
    }

    private func finish(_ key: Key, token: UUID, image: CGImage?) {
        guard pending[key]?.token == token else { return }
        pending.removeValue(forKey: key)
        if let image {
            store(image, for: key)
        } else {
            prepared.remove(key)
        }
    }

    private func store(_ image: CGImage, for key: Key) {
        let (cost, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !overflow, cost > 0, cost <= cacheCostLimit else { return }
        if images[key] != nil { discard(key) }
        while cachedCost > cacheCostLimit - cost,
              let oldest = images.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
            discard(oldest)
        }
        accessCount &+= 1
        images[key] = Entry(image: image, cost: cost, lastUsed: accessCount)
        cachedCost += cost
    }

    private func discard(_ key: Key) {
        guard let entry = images.removeValue(forKey: key) else { return }
        cachedCost -= entry.cost
    }
}
