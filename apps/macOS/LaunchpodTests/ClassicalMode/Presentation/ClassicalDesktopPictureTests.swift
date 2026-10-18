import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalDesktopPictureTests: XCTestCase {
    func testCurrentSystemDesktopRendersAtActualScreenSize() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        XCTAssertNotNil(NSWorkspace.shared.desktopImageURL(for: screen))
        let picture = ClassicalDesktopPicture()
        let image = try await picture.image(for: screen)
        XCTAssertEqual(image.width, Int(ceil(screen.frame.width * screen.backingScaleFactor)))
        XCTAssertEqual(image.height, Int(ceil(screen.frame.height * screen.backingScaleFactor)))
        XCTAssertGreaterThan(image.bytesPerRow, 0)
    }

    func testScalingOptionsCenterActualImageInBackingPixels() {
        let source = CGSize(width: 400, height: 200)
        let target = CGSize(width: 100, height: 100)
        XCTAssertEqual(ClassicalWallpaperRenderer.imageRect(sourceSize: source,
            request: request(size: target, scale: 2)), CGRect(x: 0, y: 50, width: 200, height: 100))
        XCTAssertEqual(ClassicalWallpaperRenderer.imageRect(sourceSize: source,
            request: request(size: target, scale: 2, clipping: true)),
            CGRect(x: -100, y: 0, width: 400, height: 200))
        XCTAssertEqual(ClassicalWallpaperRenderer.imageRect(sourceSize: source,
            request: request(size: target, scale: 2, scaling: .scaleAxesIndependently)),
            CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertEqual(ClassicalWallpaperRenderer.imageRect(sourceSize: source,
            request: request(size: target, scale: 2, scaling: .scaleNone)),
            CGRect(x: -100, y: 0, width: 400, height: 200))
        XCTAssertEqual(ClassicalWallpaperRenderer.imageRect(sourceSize: CGSize(width: 20, height: 10),
            request: request(size: target, scale: 2, scaling: .scaleProportionallyDown)),
            CGRect(x: 90, y: 95, width: 20, height: 10))
    }

    func testActualFileRenderingUsesBackingSizeAndKeepsUniformEdgesOpaque() async throws {
        let url = try writeFixture(width: 24, height: 24, gray: 0.5)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let renderer = ClassicalWallpaperRenderer()
        let parameters = request(url: url, size: CGSize(width: 31, height: 19), scale: 2,
                                 scaling: .scaleAxesIndependently)
        let image = try await renderer.image(for: parameters)
        XCTAssertEqual(image.width, 62)
        XCTAssertEqual(image.height, 38)
        let pixels = try rgbaPixels(image)
        let center = (19 * image.width + 31) * 4
        for offset in [0, (image.width - 1) * 4, (image.width * image.height - 1) * 4] {
            for channel in 0..<3 {
                XCTAssertLessThanOrEqual(abs(Int(pixels[offset + channel]) - Int(pixels[center + channel])), 2)
            }
            XCTAssertEqual(pixels[offset + 3], 255)
        }
        XCTAssertGreaterThan(pixels[center], 0)
        XCTAssertLessThan(pixels[center], 255)
        let repeated = try await renderer.image(for: parameters)
        XCTAssertTrue(image === repeated)
        let resized = try await renderer.image(for: request(url: url, size: CGSize(width: 20, height: 10),
                                                          scaling: .scaleAxesIndependently))
        XCTAssertEqual(resized.width, 20)
        XCTAssertEqual(resized.height, 10)
    }

    func testLetterboxRequiresConfiguredFillAndDoesNotInventBackground() async throws {
        let url = try writeFixture(width: 20, height: 10, gray: 0.5)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let renderer = ClassicalWallpaperRenderer()
        do {
            _ = try await renderer.image(for: request(url: url, size: CGSize(width: 200, height: 200)))
            XCTFail("Unspecified desktop border color must not be fabricated.")
        } catch {
            XCTAssertEqual((error as NSError).code, CocoaError.Code.coderValueNotFound.rawValue)
        }
        let filled = try await renderer.image(for: request(url: url, size: CGSize(width: 200, height: 200),
                                                         fill: SIMD3(0.2, 0.2, 0.2)))
        XCTAssertEqual(filled.width, 200)
        let pixels = try rgbaPixels(filled)
        XCTAssertEqual(pixels[3], 255)
    }

    func testRenderingRunsAtDefaultQoSEvenForUserInitiatedCallers() async throws {
        let renderer = ClassicalWallpaperRenderer()
        let observed = try await Task(priority: .userInitiated) {
            try await renderer.perform { _ in qos_class_self() }
        }.value
        XCTAssertEqual(observed, QOS_CLASS_DEFAULT)
    }

    func testMissingFileAndInvalidGeometryFailWithoutProducingImage() async throws {
        let renderer = ClassicalWallpaperRenderer()
        do {
            _ = try await renderer.image(for: request())
            XCTFail("A missing desktop image must fail.")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
        for invalid in [CGSize.zero, CGSize(width: -1, height: 10), CGSize(width: CGFloat.infinity, height: 10)] {
            do {
                _ = try await renderer.image(for: request(size: invalid))
                XCTFail("Invalid render geometry must fail.")
            } catch {
                XCTAssertEqual((error as NSError).code, CocoaError.Code.coderInvalidValue.rawValue)
            }
        }
    }

    func testTransparentFullScreenImageCompositesConfiguredFill() async throws {
        let url = try writeFixture(width: 20, height: 20, gray: 0.7, alpha: 0.5)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let renderer = ClassicalWallpaperRenderer()
        let image = try await renderer.image(for: request(url: url, size: CGSize(width: 20, height: 20),
                                                        fill: SIMD3(0.2, 0.3, 0.4)))
        let pixels = try rgbaPixels(image)
        for index in stride(from: 3, to: pixels.count, by: 4) {
            XCTAssertEqual(pixels[index], 255, "Desktop fill must prevent other windows showing through.")
        }
    }

    private func request(url: URL? = nil, size: CGSize = CGSize(width: 100, height: 100), scale: CGFloat = 1,
                         scaling: NSImageScaling = .scaleProportionallyUpOrDown, clipping: Bool = false,
                         fill: SIMD3<Double>? = nil) -> ClassicalWallpaperRenderer.Request {
        ClassicalWallpaperRenderer.Request(
            url: url ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
            size: size, scale: scale, scaling: scaling.rawValue, allowClipping: clipping, fill: fill,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
    }

    private func writeFixture(width: Int, height: Int, gray: CGFloat, alpha: CGFloat = 1) throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ClassicalPictureTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("wallpaper.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
