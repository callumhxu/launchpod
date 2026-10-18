import Foundation
import CoreGraphics

/// Shares pending icon requests and keeps replaceable, size-specific rasters in memory.
actor AppIconRepository {
    private struct RequestKey: Hashable {
        let identity: AppIdentity
        let size: AppIconSize
    }

    private struct Revision: Equatable {
        let bundleIdentifier: String?
        let bundleURL: URL
        let version: String?
        let buildVersion: String?
        let contentModificationDate: Date?
        let isMissing: Bool?
        let isOnline: Bool?

        init(_ app: AppRecord) {
            bundleIdentifier = app.metadata.bundleIdentifier
            bundleURL = app.metadata.bundleURL
            version = app.metadata.version
            buildVersion = app.metadata.buildVersion
            contentModificationDate = app.metadata.contentModificationDate
            isMissing = app.isMissing
            isOnline = app.source.isOnline
        }
    }

    /// This object and its variants are accessed only by the repository actor.
    private final class CachedIcons {
        let revision: Revision
        var variants: [AppIconSize: AppIcon] = [:]
        var cost = 0

        init(revision: Revision) {
            self.revision = revision
        }
    }

    private struct Pending {
        let token: UUID
        let revision: Revision
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<AppIcon, Error>]
    }

    private let loader: any AppIconLoading
    private let cacheCostLimit: Int
    private let cache = NSCache<NSUUID, CachedIcons>()
    private var pending: [RequestKey: Pending] = [:]

    /// The owner chooses its memory budget in bytes. Zero disables completed-image caching.
    init(loader: any AppIconLoading = SystemAppIconLoader(), cacheCostLimit: Int) {
        precondition(cacheCostLimit >= 0)
        self.loader = loader
        self.cacheCostLimit = cacheCostLimit
        cache.totalCostLimit = cacheCostLimit
    }

    /// A cancelled caller stops waiting independently. The final waiter also cancels shared work.
    func icon(for app: AppRecord, size: AppIconSize) async throws -> AppIcon {
        try Task.checkCancellation()
        let key = RequestKey(identity: app.id, size: size)
        let waiter = UUID()
        let icon: AppIcon = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppIcon, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    register(continuation, waiter: waiter, key: key, app: app)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiter, for: key) }
        }
        try Task.checkCancellation()
        return icon
    }

    /// Removes one cached size without cancelling pending loads, which may populate it again.
    func removeCachedIcon(for identity: AppIdentity, size: AppIconSize) {
        let key = identity.rawValue as NSUUID
        guard let entry = cache.object(forKey: key),
              let icon = entry.variants.removeValue(forKey: size) else { return }
        entry.cost -= icon.cgImage.bytesPerRow * icon.cgImage.height
        if entry.variants.isEmpty {
            cache.removeObject(forKey: key)
        } else {
            cache.setObject(entry, forKey: key, cost: entry.cost)
        }
    }

    /// Invalidates every size and cancels pending callers for this stable identity.
    func invalidate(_ identity: AppIdentity) {
        cache.removeObject(forKey: identity.rawValue as NSUUID)
        for key in pending.keys.filter({ $0.identity == identity }) {
            cancelRequest(key)
        }
    }

    /// Also use when the system icon environment changes without refreshed app metadata.
    func invalidateAll() {
        cache.removeAllObjects()
        for key in Array(pending.keys) {
            cancelRequest(key)
        }
    }

    private func register(
        _ continuation: CheckedContinuation<AppIcon, Error>, waiter: UUID,
        key: RequestKey, app: AppRecord
    ) {
        let revision = Revision(app)
        let cached = cache.object(forKey: app.id.rawValue as NSUUID)
        let previous = cached?.revision
            ?? pending.first(where: { $0.key.identity == app.id })?.value.revision
        if let previous, previous != revision {
            invalidate(app.id)
        } else if let icon = cached?.variants[key.size] {
            continuation.resume(returning: icon)
            return
        }

        if pending[key] != nil {
            pending[key]?.waiters[waiter] = continuation
            return
        }

        let token = UUID()
        let loader = self.loader
        let task = Task { [weak self] in
            let result: Result<AppIcon, Error>
            do {
                let icon = try await loader.loadIcon(for: app.metadata, size: key.size)
                try Task.checkCancellation()
                result = .success(icon)
            } catch {
                result = .failure(error)
            }
            await self?.complete(result, key: key, token: token)
        }
        pending[key] = Pending(token: token, revision: revision, task: task,
                               waiters: [waiter: continuation])
    }

    private func complete(_ result: Result<AppIcon, Error>, key: RequestKey, token: UUID) {
        // An invalidation or final cancellation removes the token before old work can finish.
        guard let request = pending[key], request.token == token else { return }
        pending.removeValue(forKey: key)
        if case .success(let icon) = result {
            cacheIcon(icon, for: key.identity, revision: request.revision)
        }
        for waiter in request.waiters.values {
            waiter.resume(with: result)
        }
    }

    private func cacheIcon(_ icon: AppIcon, for identity: AppIdentity, revision: Revision) {
        let (cost, overflow) = icon.cgImage.bytesPerRow.multipliedReportingOverflow(by: icon.cgImage.height)
        guard !overflow, cost > 0, cost <= cacheCostLimit else { return }
        let key = identity.rawValue as NSUUID
        let entry = cache.object(forKey: key) ?? CachedIcons(revision: revision)
        let (totalCost, totalOverflow) = entry.cost.addingReportingOverflow(cost)
        guard !totalOverflow else { return }
        entry.variants[icon.size] = icon
        entry.cost = totalCost
        cache.setObject(entry, forKey: key, cost: entry.cost)
    }

    private func cancelWaiter(_ waiter: UUID, for key: RequestKey) {
        guard var request = pending[key],
              let continuation = request.waiters.removeValue(forKey: waiter) else { return }
        pending[key] = request
        continuation.resume(throwing: CancellationError())
        if request.waiters.isEmpty {
            pending.removeValue(forKey: key)
            request.task.cancel()
        }
    }

    private func cancelRequest(_ key: RequestKey) {
        guard let request = pending.removeValue(forKey: key) else { return }
        request.task.cancel()
        for waiter in request.waiters.values {
            waiter.resume(throwing: CancellationError())
        }
    }
}
