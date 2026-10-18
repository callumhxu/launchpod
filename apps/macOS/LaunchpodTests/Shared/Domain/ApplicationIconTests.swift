import AppKit
import Testing
@testable import Launchpod

@MainActor
struct ApplicationIconTests {
    @Test
    func fourDistinctBuiltInChoicesHaveLoadableImages() throws {
        #expect(ApplicationIcon.allCases.count == 4)
        #expect(ApplicationIcon.allCases.map(\.rawValue) == [
            "colorTiles", "colorGrid", "darkGrid", "rocket"
        ])
        #expect(Set(ApplicationIcon.allCases.map(\.assetName)).count == 4)

        let images = try ApplicationIcon.allCases.map { icon in
            #expect(!icon.rawValue.isEmpty)
            #expect(!icon.assetName.isEmpty)
            return try #require(NSImage(named: icon.assetName), "Missing bundled image for \(icon.rawValue)")
        }
        #expect(Set(images.compactMap(\.tiffRepresentation)).count == 4, "Each choice must show a distinct icon")
    }

    @Test(arguments: ApplicationIcon.allCases)
    func finishedAssetsHaveTransparentCornersAndMatchTheBundledIconFootprint(icon: ApplicationIcon) throws {
        let image = try #require(NSImage(named: icon.assetName))
        let finishedBitmap = try bitmap(in: image)
        for (x, y) in [(10, 10), (245, 10), (10, 245), (245, 245)] {
            #expect(try color(x: x, y: y, in: finishedBitmap).alphaComponent < 0.05,
                    "\(icon.rawValue) needs transparent corners in the finished asset")
        }
        let bundled = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let expected = try visibleBounds(in: bitmap(in: bundled))
        let actual = try visibleBounds(in: finishedBitmap)
        #expect(abs(actual.width - expected.width) <= 2, "\(icon.rawValue)")
        #expect(abs(actual.height - expected.height) <= 2, "\(icon.rawValue)")
        #expect(abs(actual.midX - expected.midX) <= 1, "\(icon.rawValue)")
        #expect(abs(actual.midY - expected.midY) <= 1, "\(icon.rawValue)")
    }

    @Test
    func finishedAlternativeAssetsContainTheirWhiteBlackAndGrayBackings() throws {
        for icon in [ApplicationIcon.colorGrid, .darkGrid, .rocket] {
            let image = try #require(NSImage(named: icon.assetName))
            let backing = try color(x: 128, y: 31, in: bitmap(in: image))
            #expect(backing.alphaComponent > 0.95, "\(icon.rawValue) needs opaque backing inside its rounded edge")
            let components = [backing.redComponent, backing.greenComponent, backing.blueComponent]
            switch icon {
            case .colorGrid:
                #expect(components.allSatisfy { $0 > 0.85 }, "Color Grid keeps its white backing")
            case .darkGrid:
                #expect(components.allSatisfy { $0 < 0.30 }, "Dark Grid keeps its black backing")
            case .rocket:
                #expect((components.max() ?? 1) - (components.min() ?? 0) < 0.08)
                #expect(components.allSatisfy { 0.60 < $0 && $0 < 0.95 }, "Rocket keeps its gray backing")
            case .colorTiles:
                Issue.record("The bundled default has no alternate backing expectation")
            }
        }
    }

    @Test(arguments: [
        ("en", ["Color Tiles", "Color Grid", "Dark Grid", "Rocket"]),
        ("zh-Hans", [CatalogTestSupport.text("Color Tiles", locale: "zh-Hans"), CatalogTestSupport.text("Color Grid", locale: "zh-Hans"), CatalogTestSupport.text("Dark Grid", locale: "zh-Hans"), CatalogTestSupport.text("Rocket", locale: "zh-Hans")]),
        ("zh-Hant", [CatalogTestSupport.text("Color Tiles", locale: "zh-Hant"), CatalogTestSupport.text("Color Grid", locale: "zh-Hant"), CatalogTestSupport.text("Dark Grid", locale: "zh-Hant"), CatalogTestSupport.text("Rocket", locale: "zh-Hant")]),
        ("fr", [CatalogTestSupport.text("Color Tiles", locale: "fr"), CatalogTestSupport.text("Color Grid", locale: "fr"), CatalogTestSupport.text("Dark Grid", locale: "fr"), CatalogTestSupport.text("Rocket", locale: "fr")]),
        ("de", [CatalogTestSupport.text("Color Tiles", locale: "de"), CatalogTestSupport.text("Color Grid", locale: "de"), CatalogTestSupport.text("Dark Grid", locale: "de"), CatalogTestSupport.text("Rocket", locale: "de")]),
        ("ja", [CatalogTestSupport.text("Color Tiles", locale: "ja"), CatalogTestSupport.text("Color Grid", locale: "ja"), CatalogTestSupport.text("Dark Grid", locale: "ja"), CatalogTestSupport.text("Rocket", locale: "ja")]),
        ("ko", [CatalogTestSupport.text("Color Tiles", locale: "ko"), CatalogTestSupport.text("Color Grid", locale: "ko"), CatalogTestSupport.text("Dark Grid", locale: "ko"), CatalogTestSupport.text("Rocket", locale: "ko")]),
        ("es", [CatalogTestSupport.text("Color Tiles", locale: "es"), CatalogTestSupport.text("Color Grid", locale: "es"), CatalogTestSupport.text("Dark Grid", locale: "es"), CatalogTestSupport.text("Rocket", locale: "es")])
    ])
    func namesResolveInEverySupportedLanguage(identifier: String, expected: [String]) {
        let locale = Locale(identifier: identifier)
        let names = ApplicationIcon.allCases.map { icon in
            var resource = icon.name
            resource.locale = locale
            return String(localized: resource)
        }

        #expect(names == expected)
    }

    private func bitmap(in image: NSImage) throws -> NSBitmapImageRep {
        let side = 256
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: side, height: side))
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        return bitmap
    }

    private func color(x: Int, y: Int, in bitmap: NSBitmapImageRep) throws -> NSColor {
        try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
    }

    private func visibleBounds(in bitmap: NSBitmapImageRep) throws -> CGRect {
        var minX = bitmap.pixelsWide
        var minY = bitmap.pixelsHigh
        var maxX = -1
        var maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        try #require(maxX > minX && maxY > minY, "The finished asset must contain visible artwork")
        return CGRect(x: CGFloat(minX), y: CGFloat(minY),
                      width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
    }
}
