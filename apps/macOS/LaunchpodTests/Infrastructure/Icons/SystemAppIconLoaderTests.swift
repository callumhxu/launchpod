import AppKit
import Testing
@testable import Launchpod

@MainActor
struct SystemAppIconLoaderTests {
    @Test(arguments: [CGFloat(16), 23.25, 32, 96], [CGFloat(1), 2])
    func nativeApplicationIconsRenderTheRequestedPixelVariant(points: CGFloat, scale: CGFloat) async throws {
        let path = "/System/Applications/Utilities/Terminal.app"
        try #require(FileManager.default.fileExists(atPath: path))
        let record = try AppIconTestSupport.record(path: path)
        let size = try AppIconSize(pointSize: CGSize(width: points, height: points), backingScale: scale)

        let icon = try await SystemAppIconLoader().loadIcon(for: record.metadata, size: size)
        let bitmap = NSBitmapImageRep(cgImage: icon.cgImage)
        let bytes = try #require(bitmap.bitmapData)

        #expect(icon.size == size)
        #expect(icon.cgImage.width == Int(ceil(points * scale)))
        #expect(icon.cgImage.height == Int(ceil(points * scale)))
        #expect(icon.makeNSImage().size == CGSize(width: points, height: points))
        #expect(Set(UnsafeBufferPointer(start: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)).count > 2)
    }

    @Test
    func missingPathsCanReturnASystemFallbackWithoutProvingAppAvailability() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let path = fixture.root.appendingPathComponent("Not Installed.app").path
        let record = try AppIconTestSupport.record(path: path)
        let size = try AppIconSize(pointSize: CGSize(width: 32, height: 32), backingScale: 2)

        let icon = try await SystemAppIconLoader().loadIcon(for: record.metadata, size: size)

        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(icon.cgImage.width == 64)
        #expect(icon.cgImage.height == 64)
    }

    @Test
    func literalPercentSeparatorsAndUnicodeLoadTheActualFileIcon() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let url = try fixture.application("\u{5de5}\u{5177}%2F\u{7f16}\u{8f91}\u{5668}.app")
        let size = try AppIconSize(pointSize: CGSize(width: 64, height: 64), backingScale: 2)
        let custom = try AppIconTestSupport.icon(size: size)
        try #require(NSWorkspace.shared.setIcon(custom.makeNSImage(), forFile: url.path, options: []))
        let record = try AppIconTestSupport.record(path: url.path)

        let icon = try await SystemAppIconLoader().loadIcon(for: record.metadata, size: size)
        let bitmap = NSBitmapImageRep(cgImage: icon.cgImage)
        let center = try #require(bitmap.colorAt(x: 64, y: 64)?.usingColorSpace(.deviceRGB))

        #expect(center.redComponent > 0.8)
        #expect(center.blueComponent < 0.2)
        #expect(center.alphaComponent > 0.9)
    }

    @Test
    func aCancelledNativeLoadDoesNotReturnAnIcon() async throws {
        let record = try AppIconTestSupport.record(path: "/System/Applications/Utilities/Terminal.app")
        let size = try AppIconSize(pointSize: CGSize(width: 32, height: 32), backingScale: 2)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SystemAppIconLoader().loadIcon(for: record.metadata, size: size)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func manyNativeLoadsPermitMainActorProgressWhileWorkIsOutstanding() async throws {
        var requests: [(AppRecord, AppIconSize)] = []
        for path in [
            "/System/Applications/Utilities/Terminal.app", "/System/Applications/Calculator.app",
            "/System/Applications/TextEdit.app", "/System/Applications/Notes.app"
        ] {
            try #require(FileManager.default.fileExists(atPath: path))
            let record = try AppIconTestSupport.record(path: path)
            for points in stride(from: 48, through: 224, by: 16) {
                for scale in [CGFloat(1), 2] {
                    let size = try AppIconSize(pointSize: CGSize(width: points, height: points), backingScale: scale)
                    requests.append((record, size))
                }
            }
        }
        let cacheBudget = 32 * 1024 * 1024
        let repository = AppIconRepository(cacheCostLimit: cacheBudget)
        var completed = 0
        let tasks = requests.map { record, size in
            Task { @MainActor in
                let icon = try await repository.icon(for: record, size: size)
                #expect(icon.cgImage.width == size.pixelWidth)
                #expect(icon.cgImage.height == size.pixelHeight)
                completed += 1
            }
        }
        defer { for task in tasks { task.cancel() } }
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        var ticks = 0
        while completed < requests.count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
            if completed < requests.count { ticks += 1 }
        }
        try #require(completed == requests.count)
        for task in tasks { try await task.value }

        #expect(ticks > 1)
    }
}
