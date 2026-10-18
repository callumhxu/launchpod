import AppKit
import Testing
@testable import Launchpod

nonisolated enum AppIconTestSupport {
    static func record(
        id: AppIdentity = AppIdentity(),
        path: String = "/Applications/Example.app",
        identifier: String? = "com.example.IconTest",
        version: String? = nil,
        build: String? = nil,
        modified: Date? = nil
    ) throws -> AppRecord {
        let url = URL(filePath: path, directoryHint: .isDirectory)
        return AppRecord(
            id: id,
            metadata: try AppMetadata(
                bundleIdentifier: identifier, bundleURL: url, displayName: "Example",
                version: version, buildVersion: build, contentModificationDate: modified
            ),
            source: try AppSource(kind: .custom, directoryURL: url.deletingLastPathComponent())
        )
    }

    static func icon(size: AppIconSize, red: CGFloat = 1) throws -> AppIcon {
        let context = try #require(CGContext(
            data: nil, width: size.pixelWidth, height: size.pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: red, green: 0.25, blue: 1 - red, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size.pixelWidth, height: size.pixelHeight))
        return AppIcon(cgImage: try #require(context.makeImage()), size: size)
    }

    @MainActor
    static func wait(until condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await condition(), "Timed out waiting for the asynchronous icon operation.")
    }
}

actor ControlledAppIconLoader: AppIconLoading {
    struct Request: Sendable {
        let metadata: AppMetadata
        let size: AppIconSize
    }

    private(set) var requests: [Request] = []
    private(set) var completed = Set<Int>()
    private var pending: [Int: CheckedContinuation<AppIcon, any Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var renditions: [Int: AppIcon] = [:]
    private var reloadsCompletedRenditions = false

    func allowCompletedRenditionReloads() { reloadsCompletedRenditions = true }
    func requireExplicitCompletions() { reloadsCompletedRenditions = false }

    func loadIcon(for metadata: AppMetadata, size: AppIconSize) async throws -> AppIcon {
        let index = requests.count
        requests.append(Request(metadata: metadata, size: size))
        defer { completed.insert(index) }
        if reloadsCompletedRenditions,
           let previous = renditions.keys.sorted(by: >).first(where: {
               requests[$0].metadata == metadata && requests[$0].size == size
           }), let icon = renditions[previous] {
            return icon
        }
        deadlines[index] = Task {
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            fail(index)
        }
        // Completion is explicitly controlled even after cancellation, like an in-progress system call.
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }

    func succeed(_ index: Int, with icon: AppIcon) {
        deadlines.removeValue(forKey: index)?.cancel()
        if let continuation = pending.removeValue(forKey: index) {
            renditions[index] = icon
            continuation.resume(returning: icon)
        }
    }

    func fail(_ index: Int) {
        deadlines.removeValue(forKey: index)?.cancel()
        pending.removeValue(forKey: index)?.resume(throwing: CocoaError(.fileReadUnknown))
    }

    func finish() {
        for deadline in deadlines.values { deadline.cancel() }
        deadlines.removeAll()
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }
}
