import AppKit
import SwiftUI
import XCTest
@testable import Launchpod

@MainActor
final class DockApplicationIconTests: XCTestCase {
    func testSwiftUIIconFitsThe48PointSettingsSlot() throws {
        let host = NSHostingView(rootView: DockApplicationIcon().frame(width: 48, height: 48))
        host.frame = NSRect(x: 0, y: 0, width: 48, height: 48)
        host.layoutSubtreeIfNeeded()
        let icon = try XCTUnwrap(findIcon(in: host))

        XCTAssertEqual(icon.frame.width, 48, accuracy: 1)
        XCTAssertEqual(icon.frame.height, 48, accuracy: 1)
    }

    func testDisplayedImageUsesTheColorfulBuiltApplicationIcon() throws {
        let applicationURL = try makeApplicationDirectory()
        let view = DockApplicationIconView(applicationURL: applicationURL)
        let displayedIcon = try XCTUnwrap(view.image)
        let builtIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let displayedPixels = try pixels(in: displayedIcon)
        let builtPixels = try pixels(in: builtIcon)

        XCTAssertEqual(displayedPixels, builtPixels)
        XCTAssertTrue(builtPixels.contains { pixel in
            pixel.alphaComponent > 0.5 &&
                max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) -
                min(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.15
        }, "The running app should have its colorful built icon, not a generic placeholder")
    }

    func testEachBuiltInSelectionIsTheImageShownForTheDockRepresentation() throws {
        for applicationIcon in ApplicationIcon.allCases {
            let host = NSHostingView(rootView: DockApplicationIcon(applicationIcon: applicationIcon)
                .frame(width: 48, height: 48))
            host.frame = NSRect(x: 0, y: 0, width: 48, height: 48)
            host.layoutSubtreeIfNeeded()
            let displayedIcon = try XCTUnwrap(findIcon(in: host)?.image)
            let selectedIcon = try XCTUnwrap(NSImage(named: applicationIcon.assetName))
            let expectedIcon: NSImage
            if applicationIcon == .colorTiles {
                expectedIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
            } else {
                expectedIcon = selectedIcon
                XCTAssertTrue(displayedIcon === selectedIcon, applicationIcon.rawValue)
            }

            XCTAssertEqual(try pixels(in: displayedIcon), try pixels(in: expectedIcon), applicationIcon.rawValue)
        }
    }

    func testIconChoicesKeepTheBundledDefaultIndependentOfAlternateSelections() throws {
        let bundledDefault = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let assets: [String: NSImage] = [
            ApplicationIcon.colorGrid.assetName: try XCTUnwrap(NSImage(named: ApplicationIcon.colorGrid.assetName)),
            ApplicationIcon.darkGrid.assetName: try XCTUnwrap(NSImage(named: ApplicationIcon.darkGrid.assetName)),
            ApplicationIcon.rocket.assetName: try XCTUnwrap(NSImage(named: ApplicationIcon.rocket.assetName))
        ]
        var requestedAssets: [String] = []
        func resolve(_ icon: ApplicationIcon?) -> NSImage {
            ApplicationIconPreviewImage.resolve(icon, bundledDefault: bundledDefault) { name in
                requestedAssets.append(name)
                return assets[name]
            }
        }

        XCTAssertTrue(resolve(.colorTiles) === bundledDefault)
        for icon in [ApplicationIcon.darkGrid, .rocket, .colorGrid] {
            let resolved = resolve(icon)
            let expected = try XCTUnwrap(assets[icon.assetName])
            XCTAssertTrue(resolved === expected, icon.rawValue)
            XCTAssertTrue(resolve(.colorTiles) === bundledDefault,
                          "The first option must keep its bundled artwork after \(icon.rawValue)")
        }
        XCTAssertTrue(resolve(nil) === bundledDefault)
        XCTAssertEqual(requestedAssets, [ApplicationIcon.darkGrid.assetName,
                                         ApplicationIcon.rocket.assetName,
                                         ApplicationIcon.colorGrid.assetName])
    }

    func testDraggingItemOffersTheApplicationFileURLInsteadOfImageData() throws {
        let applicationURL = try makeApplicationDirectory()
        let view = DockApplicationIconView(applicationURL: applicationURL)
        view.frame = NSRect(x: 0, y: 0, width: 48, height: 48)
        let item = try XCTUnwrap(view.makeDraggingItem())
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let writer = try XCTUnwrap(item.item as? NSPasteboardWriting)
        XCTAssertTrue(pasteboard.writeObjects([writer]))

        XCTAssertTrue(pasteboard.types?.contains(.fileURL) == true)
        let urls = try XCTUnwrap(pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL])
        XCTAssertEqual(urls, [applicationURL])
        XCTAssertFalse(pasteboard.types?.contains(.tiff) == true)
        XCTAssertFalse(pasteboard.types?.contains(.png) == true)
        XCTAssertEqual(item.draggingFrame, view.bounds)
    }

    func testUnavailableOrNonApplicationURLsDoNotStartFileDrags() throws {
        let applicationURL = try makeApplicationDirectory()
        for url in [
            URL(string: "https://example.com/Launchpod.app")!,
            applicationURL.appendingPathComponent("Missing.app"),
            applicationURL.deletingLastPathComponent()
        ] {
            let view = DockApplicationIconView(applicationURL: url)
            XCTAssertNil(view.makeDraggingItem(), url.absoluteString)
        }
    }

    private func makeApplicationDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockApplicationIconTests-\(UUID().uuidString)", isDirectory: true)
        let applicationURL = directory.appendingPathComponent("Launchpod Test.app", isDirectory: true)
        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return applicationURL
    }

    private func pixels(in image: NSImage) throws -> [NSColor] {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
        context.flushGraphics()
        return try (0..<64).flatMap { y in
            try (0..<64).map { x in
                try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            }
        }
    }

    private func findIcon(in view: NSView) -> DockApplicationIconView? {
        if let icon = view as? DockApplicationIconView { return icon }
        return view.subviews.lazy.compactMap(findIcon(in:)).first
    }
}
