import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalIconCacheTests: XCTestCase {
    func testConcurrentRequestsForTheSameIconShareOneLoadAndReuseItsResult() async throws {
        let cache = ClassicalIconCache()
        let record = try AppIconTestSupport.record()
        let size = try AppIconSize(pointSize: CGSize(width: 16, height: 16), backingScale: 1)
        let image = try AppIconTestSupport.icon(size: size).cgImage
        var calls = 0
        var finish: CheckedContinuation<CGImage, any Error>?
        let load = cache.loader { _, _ in
            calls += 1
            return try await withCheckedThrowingContinuation { finish = $0 }
        }
        let first = Task { try await load(record, size) }
        var secondEntered = false
        let second = Task {
            secondEntered = true
            return try await load(record, size)
        }
        defer {
            first.cancel()
            second.cancel()
            finish?.resume(throwing: CancellationError())
        }

        try await waitUntil { calls == 1 && finish != nil && secondEntered }
        XCTAssertEqual(calls, 1, "One application and raster size should have one source request")
        let completion = try XCTUnwrap(finish)
        finish = nil
        completion.resume(returning: image)
        let firstImage = try await first.value
        let secondImage = try await second.value
        let reusedImage = try await load(record, size)
        XCTAssertTrue(firstImage === image)
        XCTAssertTrue(secondImage === image)
        XCTAssertTrue(reusedImage === image)
        XCTAssertEqual(calls, 1, "Later cell layout should use the prepared raster")
    }

    func testMemoryBudgetEvictsLeastRecentlyUsedCompletedRaster() async throws {
        let size = try AppIconSize(pointSize: CGSize(width: 16, height: 16), backingScale: 1)
        let image = try AppIconTestSupport.icon(size: size).cgImage
        let imageCost = image.bytesPerRow * image.height
        let cache = ClassicalIconCache(cacheCostLimit: imageCost * 2)
        let records = try (0..<3).map {
            try AppIconTestSupport.record(path: "/Applications/Cache \($0).app",
                                          identifier: "com.example.cache.\($0)")
        }
        let load = cache.loader { _, _ in image }

        _ = try await load(records[0], size)
        _ = try await load(records[1], size)
        XCTAssertNotNil(cache.image(for: records[0], size: size))
        _ = try await load(records[2], size)

        XCTAssertLessThanOrEqual(cache.cachedCost, imageCost * 2)
        XCTAssertNotNil(cache.image(for: records[0], size: size),
                        "Reading an icon should keep it ahead of less recently used icons")
        XCTAssertNil(cache.image(for: records[1], size: size))
        XCTAssertNotNil(cache.image(for: records[2], size: size))
    }

    func testInvalidationDuringPreparationDoesNotRestoreAnObsoleteRaster() async throws {
        let cache = ClassicalIconCache()
        let record = try AppIconTestSupport.record()
        let size = try AppIconSize(pointSize: CGSize(width: 16, height: 16), backingScale: 1)
        let oldImage = try AppIconTestSupport.icon(size: size, red: 1).cgImage
        let newImage = try AppIconTestSupport.icon(size: size, red: 0).cgImage
        var calls = 0
        var finishOld: CheckedContinuation<CGImage, any Error>?
        let load = cache.loader { _, _ in
            calls += 1
            if calls == 1 {
                return try await withCheckedThrowingContinuation { finishOld = $0 }
            }
            return newImage
        }
        let obsolete = Task { try await load(record, size) }
        defer {
            obsolete.cancel()
            finishOld?.resume(throwing: CancellationError())
        }
        try await waitUntil { calls == 1 && finishOld != nil }

        cache.remove([record.id])
        let refreshed = try await load(record, size)
        XCTAssertTrue(refreshed === newImage)
        XCTAssertEqual(calls, 2, "Invalidation starts a new request for the current icon")
        let oldContinuation = try XCTUnwrap(finishOld)
        finishOld = nil
        oldContinuation.resume(returning: oldImage)
        do {
            _ = try await obsolete.value
            XCTFail("Invalidated preparation should not succeed")
        } catch is CancellationError {
            // Expected: the obsolete caller was cancelled by invalidation.
        }
        XCTAssertTrue(cache.image(for: record, size: size) === newImage,
                      "Finishing obsolete work must not replace the refreshed raster")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        _ = try XCTUnwrap(condition() ? true : nil, "Timed out waiting for a Classical icon request")
    }
}
