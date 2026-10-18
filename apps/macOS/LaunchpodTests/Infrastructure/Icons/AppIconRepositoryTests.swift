import AppKit
import Testing
@testable import Launchpod

@MainActor
struct AppIconRepositoryTests {
    private let cacheBudget = 1024 * 1024

    enum MetadataField: CaseIterable {
        case path, identifier, version, build, modified
    }

    enum ObsoleteRequestReason: CaseIterable {
        case lastCancellation, targetedInvalidation, globalInvalidation, metadataChange
    }

    @Test
    func repeatedRequestsUseTheLoadedBitmap() async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let record = try AppIconTestSupport.record()
        let size = try iconSize()
        let original = try await load(record, size: size, repository: repository, loader: loader)

        let cached = try await cachedOrReloaded(record, size: size, repository: repository, loader: loader)

        #expect(cached.cgImage === original.cgImage)
        #expect(await loader.requests.allSatisfy { $0.metadata == record.metadata && $0.size == size })
    }

    @Test(arguments: [0, 1])
    func imagesExceedingTheMemoryBudgetAreDeliveredButNotRetained(budget: Int) async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: budget)
        let record = try AppIconTestSupport.record()
        let size = try iconSize()

        let first = try await load(record, size: size, repository: repository, loader: loader)
        let second = try await load(record, size: size, repository: repository, loader: loader)

        #expect(first.cgImage.width == size.pixelWidth)
        #expect(second.cgImage.width == size.pixelWidth)
        #expect(await loader.requests.count == 2)
    }

    @Test
    func concurrentRequestsShareOneOutstandingLoad() async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let record = try AppIconTestSupport.record()
        let size = try iconSize()
        let expected = try AppIconTestSupport.icon(size: size)
        let tasks = (0..<24).map { _ in Task { try await repository.icon(for: record, size: size) } }
        defer { for task in tasks { task.cancel() } }
        try await AppIconTestSupport.wait { await loader.requests.count == 1 }
        try await Task.sleep(for: .milliseconds(20))
        #expect(await loader.requests.count == 1)
        await loader.succeed(0, with: expected)

        for task in tasks { #expect(try await task.value.cgImage === expected.cgImage) }
        #expect(await loader.requests.count == 1)
    }

    @Test
    func pointSizeAndBackingScaleRemainDistinctEvenWhenPixelCountsMatch() async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let record = try AppIconTestSupport.record()
        let sizes = try [iconSize(points: 32, scale: 1), iconSize(points: 32, scale: 2), iconSize(points: 64, scale: 1)]
        var originals: [AppIcon] = []
        for size in sizes {
            originals.append(try await load(record, size: size, repository: repository, loader: loader))
        }
        for (index, size) in sizes.enumerated() {
            let cached = try await cachedOrReloaded(record, size: size, repository: repository, loader: loader)
            #expect(cached.size == size)
            #expect(cached.cgImage === originals[index].cgImage)
        }
        let requests = await loader.requests
        #expect(requests.prefix(sizes.count).map(\.size) == sizes)
        #expect(requests.allSatisfy { $0.metadata == record.metadata && sizes.contains($0.size) })
    }

    @Test(arguments: [0, 1, 2])
    func removingOneCachedSizePreservesOtherVariantsAndApplications(index: Int) async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let record = try AppIconTestSupport.record()
        let other = try AppIconTestSupport.record(path: "/Applications/Other.app")
        let sizes = try [iconSize(points: 32, scale: 1), iconSize(points: 32, scale: 2), iconSize(points: 64, scale: 1)]
        var originals: [AppIcon] = []
        for size in sizes {
            originals.append(try await load(record, size: size, repository: repository, loader: loader))
        }
        let untouched = try await load(other, size: sizes[index], repository: repository, loader: loader)

        await repository.removeCachedIcon(for: record.id, size: sizes[index])
        await repository.removeCachedIcon(for: record.id, size: sizes[index])

        for remaining in sizes.indices where remaining != index {
            #expect(try await cachedOrReloaded(record, size: sizes[remaining], repository: repository,
                                               loader: loader).cgImage === originals[remaining].cgImage)
        }
        #expect(try await cachedOrReloaded(other, size: sizes[index], repository: repository,
                                           loader: loader).cgImage === untouched.cgImage)
        let refreshed = try await load(record, size: sizes[index], repository: repository, loader: loader)
        #expect(refreshed.cgImage !== originals[index].cgImage)
        #expect(try await cachedOrReloaded(record, size: sizes[index], repository: repository,
                                           loader: loader).cgImage === refreshed.cgImage)
        #expect(await loader.requests.filter {
            $0.metadata == record.metadata && $0.size == sizes[index]
        }.count >= 2)
    }

    @Test(arguments: [false, true])
    func removingCachedIconsLeavesPendingLoadsIntact(removePendingSize: Bool) async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let record = try AppIconTestSupport.record()
        let small = try iconSize(scale: 1)
        let large = try iconSize(scale: 2)
        let cached = try await load(record, size: small, repository: repository, loader: loader)
        let task = Task { try await repository.icon(for: record, size: large) }
        defer { task.cancel() }
        try await AppIconTestSupport.wait { await loader.requests.count == 2 }

        await repository.removeCachedIcon(for: record.id, size: removePendingSize ? large : small)
        let expected = try AppIconTestSupport.icon(size: large)
        await loader.succeed(1, with: expected)

        #expect(try await task.value.cgImage === expected.cgImage)
        #expect(try await cachedOrReloaded(record, size: large, repository: repository,
                                           loader: loader).cgImage === expected.cgImage)
        if removePendingSize {
            #expect(try await cachedOrReloaded(record, size: small, repository: repository,
                                               loader: loader).cgImage === cached.cgImage)
        } else {
            let refreshed = try await load(record, size: small, repository: repository, loader: loader)
            #expect(refreshed.cgImage !== cached.cgImage)
        }
        #expect(await loader.requests.filter { $0.size == small }.count >= (removePendingSize ? 1 : 2))
    }

    @Test
    func copiesSharingABundleIdentifierHaveIndependentIcons() async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let first = try AppIconTestSupport.record(path: "/Applications/Example.app")
        let second = try AppIconTestSupport.record(path: "/Users/Shared/Example.app")
        let size = try iconSize()
        let original = try await load(first, size: size, repository: repository, loader: loader)
        let copy = try await load(second, size: size, repository: repository, loader: loader)

        #expect(original.cgImage !== copy.cgImage)
        #expect(try await cachedOrReloaded(first, size: size, repository: repository,
                                           loader: loader).cgImage === original.cgImage)
        #expect(try await cachedOrReloaded(second, size: size, repository: repository,
                                           loader: loader).cgImage === copy.cgImage)
        let requests = await loader.requests
        #expect(requests.prefix(2).map(\.metadata.bundleURL) == [first.metadata.bundleURL, second.metadata.bundleURL])
        #expect(requests.allSatisfy {
            [first.metadata.bundleURL, second.metadata.bundleURL].contains($0.metadata.bundleURL)
        })
    }

    @Test(arguments: MetadataField.allCases)
    func changedIconMetadataRefreshesTheSameStableIdentity(field: MetadataField) async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let before = try AppIconTestSupport.record()
        let after = try AppIconTestSupport.record(
            id: before.id, path: field == .path ? "/Applications/Moved.app" : before.metadata.bundleURL.path,
            identifier: field == .identifier ? "com.example.Replaced" : before.metadata.bundleIdentifier,
            version: field == .version ? "2" : nil, build: field == .build ? "200" : nil,
            modified: field == .modified ? Date(timeIntervalSince1970: 100) : nil
        )
        let size = try iconSize()
        let original = try await load(before, size: size, repository: repository, loader: loader)
        let refreshed = try await load(after, size: size, repository: repository, loader: loader)

        #expect(refreshed.cgImage !== original.cgImage)
        #expect(try await cachedOrReloaded(after, size: size, repository: repository,
                                           loader: loader).cgImage === refreshed.cgImage)
        #expect(await loader.requests.dropFirst().allSatisfy { $0.metadata == after.metadata })
    }

    @Test(arguments: [false, true])
    func availabilityTransitionsRefreshPreviousRenditions(changeMissing: Bool) async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let original = try AppIconTestSupport.record()
        let size = try iconSize()
        for observation in [Bool?.none, false, true, nil] {
            let record = AppRecord(
                id: original.id, metadata: original.metadata,
                source: try AppSource(kind: .custom, directoryURL: original.source.directoryURL,
                                      isOnline: changeMissing ? nil : observation),
                isMissing: changeMissing ? observation : nil
            )
            _ = try await load(record, size: size, repository: repository, loader: loader)
        }

        #expect(await loader.requests.count == 4)
    }

    @Test
    func metadataChangesInvalidateCachedAndPendingOtherSizes() async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let before = try AppIconTestSupport.record()
        let after = try AppIconTestSupport.record(id: before.id, version: "2")
        let small = try iconSize(points: 16)
        let large = try iconSize(points: 64)
        _ = try await load(before, size: small, repository: repository, loader: loader)
        let obsolete = Task { try await repository.icon(for: before, size: large) }
        defer { obsolete.cancel() }
        try await AppIconTestSupport.wait { await loader.requests.count == 2 }

        _ = try await load(after, size: small, repository: repository, loader: loader)
        await #expect(throws: CancellationError.self) { try await obsolete.value }
        _ = try await load(after, size: large, repository: repository, loader: loader)

        #expect(await loader.requests.count == 4)
        #expect(await loader.requests.suffix(2).allSatisfy { $0.metadata.version == "2" })
    }

    @Test
    func targetedInvalidationRefreshesEveryVariantAndPreservesOtherApplications() async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let record = try AppIconTestSupport.record()
        let other = try AppIconTestSupport.record(path: "/Applications/Other.app")
        let sizes = try [iconSize(scale: 1), iconSize(scale: 2)]
        for size in sizes { _ = try await load(record, size: size, repository: repository, loader: loader) }
        let untouched = try await load(other, size: sizes[0], repository: repository, loader: loader)

        await repository.invalidate(record.id)

        #expect(try await cachedOrReloaded(other, size: sizes[0], repository: repository,
                                           loader: loader).cgImage === untouched.cgImage)
        for size in sizes { _ = try await load(record, size: size, repository: repository, loader: loader) }
        #expect(await loader.requests.filter { $0.metadata == record.metadata }.count >= 4)
    }

    @Test
    func globalInvalidationRefreshesAllCachedApplications() async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let records = try [AppIconTestSupport.record(), AppIconTestSupport.record(path: "/Applications/Other.app")]
        let size = try iconSize()
        for record in records { _ = try await load(record, size: size, repository: repository, loader: loader) }

        await repository.invalidateAll()

        for record in records { _ = try await load(record, size: size, repository: repository, loader: loader) }
        #expect(await loader.requests.count == 4)
    }

    @Test
    func failedLoadsAreRetriedInsteadOfCached() async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let record = try AppIconTestSupport.record()
        let size = try iconSize()
        let first = Task { try await repository.icon(for: record, size: size) }
        try await AppIconTestSupport.wait { await loader.requests.count == 1 }
        await loader.fail(0)
        await #expect(throws: CocoaError.self) { try await first.value }

        _ = try await load(record, size: size, repository: repository, loader: loader)

        #expect(await loader.requests.count == 2)
    }

    @Test
    func anAlreadyCancelledCallerDoesNotStartLoading() async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let record = try AppIconTestSupport.record()
        let size = try iconSize()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await repository.icon(for: record, size: size)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await loader.requests.isEmpty)
    }

    @Test
    func cancellingOneWaiterReturnsPromptlyAndPreservesOtherWaiters() async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let record = try AppIconTestSupport.record()
        let size = try iconSize()
        var cancelled = false
        let first = Task {
            do { _ = try await repository.icon(for: record, size: size); Issue.record("Cancelled caller received an icon.") }
            catch is CancellationError { cancelled = true }
            catch { Issue.record(error) }
        }
        try await AppIconTestSupport.wait { await loader.requests.count == 1 }
        let second = Task { try await repository.icon(for: record, size: size) }
        defer { first.cancel(); second.cancel() }
        try await Task.sleep(for: .milliseconds(20))

        first.cancel()
        try await AppIconTestSupport.wait { cancelled }
        #expect(await loader.completed.isEmpty)
        #expect(await loader.requests.count == 1)
        let expected = try AppIconTestSupport.icon(size: size)
        await loader.succeed(0, with: expected)

        #expect(try await second.value.cgImage === expected.cgImage)
        #expect(try await cachedOrReloaded(record, size: size, repository: repository,
                                           loader: loader).cgImage === expected.cgImage)
        #expect(await loader.requests.allSatisfy { $0.metadata == record.metadata && $0.size == size })
    }

    @Test(arguments: ObsoleteRequestReason.allCases, [false, true])
    func obsoleteCompletionsCannotReplaceTheNewRequest(reason: ObsoleteRequestReason, oldCompletesFirst: Bool) async throws {
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let repository = AppIconRepository(loader: loader, cacheCostLimit: cacheBudget)
        let before = try AppIconTestSupport.record()
        let after = try AppIconTestSupport.record(id: before.id, version: reason == .metadataChange ? "2" : nil)
        let size = try iconSize()
        let obsolete = try AppIconTestSupport.icon(size: size, red: 1)
        let expected = try AppIconTestSupport.icon(size: size, red: 0)
        var cancelled = false
        let first = Task {
            do { _ = try await repository.icon(for: before, size: size); Issue.record("Obsolete caller received an icon.") }
            catch is CancellationError { cancelled = true }
            catch { Issue.record(error) }
        }
        try await AppIconTestSupport.wait { await loader.requests.count == 1 }
        switch reason {
        case .lastCancellation:
            first.cancel()
            try await AppIconTestSupport.wait { cancelled }
        case .targetedInvalidation: await repository.invalidate(before.id)
        case .globalInvalidation: await repository.invalidateAll()
        case .metadataChange: break
        }
        let replacement = Task { try await repository.icon(for: after, size: size) }
        defer { first.cancel(); replacement.cancel() }
        try await AppIconTestSupport.wait { await loader.requests.count == 2 }
        try await AppIconTestSupport.wait { cancelled }
        if oldCompletesFirst {
            await loader.succeed(0, with: obsolete)
            try await AppIconTestSupport.wait { await loader.completed.contains(0) }
            try await Task.sleep(for: .milliseconds(20))
        }
        await loader.succeed(1, with: expected)
        #expect(try await replacement.value.cgImage === expected.cgImage)
        if !oldCompletesFirst { await loader.succeed(0, with: obsolete) }
        try await AppIconTestSupport.wait { await loader.completed.count == 2 }
        try await Task.sleep(for: .milliseconds(20))

        #expect(try await cachedOrReloaded(after, size: size, repository: repository,
                                           loader: loader).cgImage === expected.cgImage)
        let requests = await loader.requests
        #expect(requests.prefix(2).map(\.metadata) == [before.metadata, after.metadata])
        #expect(requests.dropFirst(2).allSatisfy { $0.metadata == after.metadata })
    }

    private func iconSize(points: CGFloat = 32, scale: CGFloat = 2) throws -> AppIconSize {
        try AppIconSize(pointSize: CGSize(width: points, height: points), backingScale: scale)
    }

    private func load(
        _ record: AppRecord, size: AppIconSize,
        repository: AppIconRepository, loader: ControlledAppIconLoader
    ) async throws -> AppIcon {
        await loader.requireExplicitCompletions()
        let index = await loader.requests.count
        let expected = try AppIconTestSupport.icon(size: size)
        let task = Task { try await repository.icon(for: record, size: size) }
        defer { task.cancel() }
        try await AppIconTestSupport.wait { await loader.requests.count == index + 1 }
        let request = await loader.requests[index]
        #expect(request.metadata == record.metadata)
        #expect(request.size == size)
        await loader.succeed(index, with: expected)
        return try await task.value
    }

    private func cachedOrReloaded(
        _ record: AppRecord, size: AppIconSize,
        repository: AppIconRepository, loader: ControlledAppIconLoader
    ) async throws -> AppIcon {
        await loader.allowCompletedRenditionReloads()
        return try await repository.icon(for: record, size: size)
    }
}
