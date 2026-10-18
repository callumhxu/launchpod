import QuartzCore
import XCTest
@testable import Launchpod

/// A closed folder on a root page: a translucent backdrop with the icons of the folder's first page
/// in a 3 × 3 grid, and the folder title below.
@MainActor
final class ClassicalFolderItemLayerTests: XCTestCase {
    func testThumbnailsShowOnlyTheFirstFolderPageInOrder() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C", "D", "E"], ["F", "G"]])]])
        let cell = try fixture.folderCell("Work")
        XCTAssertEqual(cell.thumbnailRecords.map(\.metadata.displayName), ["B", "C", "D", "E"])
        XCTAssertEqual(cell.thumbnailLayers.count, 4, "Later folder pages add no thumbnails")
        XCTAssertEqual(cell.titleLayer.string as? String, "Work")

        let frames = cell.thumbnailLayers.map(\.frame)
        XCTAssertLessThan(frames[0].midX, frames[1].midX)
        XCTAssertLessThan(frames[1].midX, frames[2].midX)
        XCTAssertEqual(frames[0].midY, frames[2].midY, "The first three fill the top row")
        XCTAssertLessThan(frames[3].midY, frames[0].midY, "The fourth starts the next row down")
        XCTAssertEqual(frames[3].midX, frames[0].midX)
    }

    func testAtMostNineThumbnailsAreVisible() throws {
        let names = (1...12).map { "App \($0)" }
        let fixture = try ClassicalFolderTestBoard([[.folder("Many", [names])]])
        let cell = try fixture.folderCell("Many")
        XCTAssertTrue(cell.miniGridLayer.masksToBounds)
        let visible = cell.thumbnailLayers.filter { cell.miniGridLayer.bounds.intersects($0.frame) }
        XCTAssertEqual(visible.count, 9)
        XCTAssertEqual(Array(cell.thumbnailLayers.prefix(9)).map(\.frame), visible.map(\.frame),
                       "The first nine in folder order are the visible ones")
    }

    func testPreviewScrollShowsAvailableRowAndCanReturnToTop() throws {
        for (count, rows) in [(8, 0), (9, 1), (10, 1), (12, 2)] {
            let names = (1...count).map { "App \($0)" }
            let fixture = try ClassicalFolderTestBoard([[.folder("Many", [names])]])
            let cell = try fixture.folderCell("Many")
            XCTAssertEqual(cell.miniGridLayer.bounds.origin.y, 0)

            cell.scrollToAvailableSpace()

            XCTAssertEqual(cell.miniGridLayer.bounds.origin.y,
                           -CGFloat(rows) * cell.geometry.miniCellSize.height, "\(count) items")
            cell.scrollToTop()
            XCTAssertEqual(cell.miniGridLayer.bounds.origin.y, 0)
        }
    }

    /// The backdrop is gray 0.9686 at 50 % opacity with continuous corners of radius
    /// round(icon height × 0.15625); the cell shows no application icon of its own.
    func testClosedCellShowsATranslucentBackdropInsteadOfAnIcon() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let shown = try fixture.folderCell("Work")
        let cell = ClassicalFolderItemLayer(folder: shown.folder, layout: shown.layout, scale: shown.scale,
                                            rightToLeft: shown.rightToLeft, glassEnabled: false)
        XCTAssertFalse(cell.glassEnabled, "Explicitly disabling glass keeps the Classical backdrop")
        XCTAssertNil(cell.iconLayer.contents)
        let backdropColor = try XCTUnwrap(cell.backdropLayer.backgroundColor)
        XCTAssertEqual(backdropColor.colorSpace?.model, .monochrome)
        let color = try XCTUnwrap(backdropColor.components)
        XCTAssertEqual(color[0], 0.9686, accuracy: 0.001)
        XCTAssertEqual(color[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(cell.backdropLayer.cornerRadius, (cell.layout.iconFrame.height * 0.15625).rounded())
        XCTAssertEqual(cell.backdropLayer.cornerCurve, .continuous)
        XCTAssertTrue(cell.iconLayer.frame.contains(cell.backdropLayer.frame), "The backdrop lies inside the icon area")
        XCTAssertTrue(cell.backdropLayer.frame.contains(cell.miniGridLayer.frame))
    }

    func testEnabledGlassLeavesATransparentGuideBehindTheClosedFolderThumbnails() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let original = try fixture.folderCell("Work")
        let cell = ClassicalFolderItemLayer(folder: original.folder, layout: original.layout, scale: original.scale,
                                            rightToLeft: original.rightToLeft, glassEnabled: true)
        XCTAssertTrue(cell.glassEnabled)
        XCTAssertNil(cell.backdropLayer.backgroundColor)
        XCTAssertNil(cell.backdropLayer.backgroundFilters)
        XCTAssertTrue(cell.backdropLayer.frame.contains(cell.miniGridLayer.frame),
                      "The thumbnail grid remains over the glass surface")
    }

    /// The pressed look multiplies the backdrop and the thumbnail grid by gray 0.4 through a layer
    /// filter; the thumbnails' images themselves are not replaced.
    func testPressingMultipliesTheBackdropAndThumbnailGridByGray() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let cell = try fixture.folderCell("Work")
        let image = try solidImage()
        cell.setThumbnail(image, at: 0)
        let regularBackdrop = cell.backdropLayer.backgroundColor
        cell.setDarkened(true)
        XCTAssertTrue(cell.isDarkened)
        for layer in [cell.backdropLayer, cell.miniGridLayer] {
            XCTAssertEqual(CoreAnimationFilterReading.types(layer.filters), ["multiplyColor"])
            let filter = CoreAnimationFilterReading.first("multiplyColor", in: layer.filters)
            XCTAssertEqual(filter?.value(forKey: "inputColor") as! CGColor?, CGColor(gray: 0.4, alpha: 1))
        }
        XCTAssertEqual(cell.backdropLayer.backgroundColor, regularBackdrop)
        XCTAssertTrue(cell.thumbnailLayers[0].contents as AnyObject? === image)
        cell.setDarkened(false)
        XCTAssertFalse(cell.isDarkened)
        XCTAssertNil(cell.backdropLayer.filters)
        XCTAssertNil(cell.miniGridLayer.filters)
        XCTAssertTrue(cell.thumbnailLayers[0].contents as AnyObject? === image)
    }

    /// With glass the backing has no colour to darken, so pressing darkens only the thumbnail grid.
    func testPressingAGlassCellDarkensOnlyTheThumbnailGrid() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let shown = try fixture.folderCell("Work")
        let cell = ClassicalFolderItemLayer(folder: shown.folder, layout: shown.layout, scale: shown.scale,
                                            rightToLeft: shown.rightToLeft, glassEnabled: true)
        cell.setDarkened(true)
        XCTAssertTrue(cell.isDarkened)
        XCTAssertNil(cell.backdropLayer.filters)
        XCTAssertEqual(CoreAnimationFilterReading.types(cell.miniGridLayer.filters), ["multiplyColor"])
        cell.setDarkened(false)
        XCTAssertNil(cell.miniGridLayer.filters)
    }

    func testThumbnailArrivingWhilePressedIsShownUnchangedUnderTheGridFilter() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        let target = try fixture.folderCell("Work")
        XCTAssertNil(target.thumbnailLayers[0].contents)
        target.setDarkened(true)
        let loaded = try solidImage()
        target.setThumbnail(loaded, at: 0)
        XCTAssertTrue(target.thumbnailLayers[0].contents as AnyObject? === loaded)
        XCTAssertEqual(CoreAnimationFilterReading.types(target.miniGridLayer.filters), ["multiplyColor"])
        target.setDarkened(false)
        XCTAssertTrue(target.thumbnailLayers[0].contents as AnyObject? === loaded)
        XCTAssertNil(target.miniGridLayer.filters)
    }

    private func solidImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                                             bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.5, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try XCTUnwrap(context.makeImage())
    }
}
