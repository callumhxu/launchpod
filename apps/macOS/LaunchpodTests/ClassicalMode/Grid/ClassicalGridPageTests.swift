import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalGridPageTests: XCTestCase {
    private let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956), dock: .bottom(extent: 59))

    func testPagePlacesOnePageOfCellsAtTheGridPositions() async throws {
        let page = ClassicalGridPage()
        let records = try (0..<40).map { try record("App \($0)") }
        var requested: [AppIconSize] = []
        let image = try pixel()
        page.show(records, geometry: geometry, scale: 2, rightToLeft: false) { _, size in
            requested.append(size)
            return image
        }
        XCTAssertEqual(page.layer.frame, geometry.pageFrame)
        XCTAssertEqual(page.itemLayers.filter { !$0.isHidden }.count, 35, "A page shows rows × columns cells")
        XCTAssertTrue(page.itemLayers.dropFirst(35).allSatisfy(\.isHidden),
                      "Items past the capacity stay hidden until a drop moves them (_layoutItemLayers 0x10001f7fc)")
        let item = ClassicalItemLayout(cellSize: geometry.grid.cellSize)
        for (index, cell) in page.itemLayers.prefix(35).enumerated() {
            XCTAssertEqual(cell.frame, geometry.grid.cellFrame(at: index))
            XCTAssertEqual(cell.iconLayer.frame, item.iconFrame)
            XCTAssertEqual(cell.titleLayer.frame.minY,
                           ClassicalItemLayout.bottomPadding(cellHeight: geometry.grid.cellSize.height) + ClassicalItemLayout.titleInset)
            XCTAssertEqual(cell.titleLayer.string as? String, "App \(index)")
            XCTAssertEqual(cell.titleLayer.alignmentMode, .center)
            XCTAssertEqual(cell.titleLayer.truncationMode, .middle)
            XCTAssertEqual(cell.titleLayer.contentsScale, 2)
        }
        try await waitUntil { page.itemLayers.allSatisfy { $0.iconLayer.contents != nil } }
        XCTAssertEqual(requested.count, 40)
        XCTAssertEqual(requested.first?.pointSize, item.iconFrame.size)
        XCTAssertEqual(requested.first?.backingScale, 2)
    }

    func testLongTitlesStopSixPointsInsideTheCell() throws {
        let page = ClassicalGridPage()
        let long = String(repeating: "Very Long Application Name ", count: 4)
        page.show([try record(long)], geometry: geometry, scale: 1, rightToLeft: false) { _, _ in throw CancellationError() }
        let title = try XCTUnwrap(page.itemLayers.first?.titleLayer)
        XCTAssertEqual(title.frame.width, geometry.grid.cellSize.width - 12 - 2 * ClassicalItemLayout.titleInset)
        XCTAssertEqual(title.frame.minX, 6 + ClassicalItemLayout.titleInset, "The label stops 6 pt inside the cell; its text 2 pt further")
    }

    func testRecentlyAddedRecordShowsFlagUntilItsObservedStateClears() throws {
        let page = ClassicalGridPage()
        var newApp = try record("New App")
        newApp.isRecentlyAdded = true
        let ordinary = try record("Ordinary")
        let grid = geometry.grid
        let frame = geometry.pageFrame
        page.show([.app(newApp), .app(ordinary)], grid: grid, frame: frame, scale: 2,
                  rightToLeft: false, icon: { _, _ in throw CancellationError() })
        XCTAssertNotNil(page.itemLayers[0].flagLayer)
        XCTAssertNil(page.itemLayers[1].flagLayer)

        newApp.isRecentlyAdded = false
        page.show([.app(newApp), .app(ordinary)], grid: grid, frame: frame, scale: 2,
                  rightToLeft: false, icon: { _, _ in throw CancellationError() })
        XCTAssertNil(page.itemLayers[0].flagLayer)
        XCTAssertNil(page.itemLayers[1].flagLayer)
    }

    func testShiftSlowsRemovalOnlyWhenSlowMotionIsAllowed() throws {
        for (allowed, shift, expectedDuration) in [(false, true, 0.5), (true, true, 5.0), (true, false, 0.5)] {
            let page = ClassicalGridPage()
            page.slowMotionAllowed = { allowed }
            page.shiftKeyDown = { shift }
            let cell = ClassicalItemLayer(title: "Removable", layout: ClassicalItemLayout(cellSize: .init(width: 100, height: 120)),
                                          scale: 1)
            let observer = RemovalDurationObserver()
            cell.delegate = observer
            page.layer.addSublayer(cell)
            page.animateRemoval(of: cell) {}
            XCTAssertEqual(observer.opacityDuration, expectedDuration, accuracy: 0.01)
        }
    }

    func testRightToLeftStartsAtTheRightEdgeAndReplacingCancelsPendingIcons() async throws {
        let page = ClassicalGridPage()
        page.show([try record("First")], geometry: geometry, scale: 1, rightToLeft: true) { _, _ in
            try await Task.sleep(for: .seconds(30))
            return try self.pixel()
        }
        XCTAssertEqual(page.itemLayers.first?.frame, geometry.grid.cellFrame(at: 0, rightToLeft: true))
        let stale = try XCTUnwrap(page.itemLayers.first)
        page.show([], geometry: geometry, scale: 1, rightToLeft: true) { _, _ in try self.pixel() }
        XCTAssertTrue(page.itemLayers.isEmpty)
        XCTAssertNil(stale.superlayer)
        XCTAssertNil(stale.iconLayer.contents)
    }

    func testTitleTextIsWhiteWithTheDockTitleShadowBelowIt() throws {
        let layer = ClassicalShadowTextLayer()
        layer.string = "HHHH"
        layer.font = ClassicalTitleFont.font
        layer.fontSize = ClassicalTitleFont.size
        layer.foregroundColor = .white
        layer.contentsScale = 2
        layer.frame = CGRect(x: 0, y: 0, width: 60, height: 19)
        let width = 120, height = 38
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 2, y: 2)
        layer.render(in: context)
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var white = 0, shadow = 0
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let (r, a) = (data[i], data[i + 3])
            if a > 200 && r > 200 { white += 1 }
            if a > 0 && a < 90 && r < 40 { shadow += 1 }
        }
        XCTAssertGreaterThan(white, 50, "White glyphs are drawn")
        XCTAssertGreaterThan(shadow, 20, "A faint dark shadow surrounds them")
    }

    func testDockPlacementComesFromTheVisibleFrameInsetOnTheDockSide() {
        let frame = CGRect(x: 0, y: 0, width: 1470, height: 956)
        typealias Placement = ClassicalSpringboardGeometry.DockPlacement
        XCTAssertEqual(Placement(frame: frame, visibleFrame: CGRect(x: 0, y: 59, width: 1470, height: 864), hidesDock: false),
                       .bottom(extent: 59))
        XCTAssertEqual(Placement(frame: frame, visibleFrame: CGRect(x: 70, y: 0, width: 1400, height: 923), hidesDock: false),
                       .left(extent: 70))
        XCTAssertEqual(Placement(frame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 1400, height: 923), hidesDock: false),
                       .right(extent: 70))
        XCTAssertEqual(Placement(frame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 923), hidesDock: false),
                       .hidden, "Only the menu bar is reserved: the Dock auto-hides")
        XCTAssertEqual(Placement(frame: frame, visibleFrame: CGRect(x: 0, y: 59, width: 1470, height: 864), hidesDock: true),
                       .hidden, "A covered Dock reserves nothing")
    }

    private func record(_ name: String) throws -> AppRecord {
        let url = URL(filePath: "/Applications/\(name).app", directoryHint: .isDirectory)
        return AppRecord(
            id: AppIdentity(),
            metadata: try AppMetadata(bundleIdentifier: "com.example.\(UUID().uuidString)", bundleURL: url,
                                      displayName: name, version: nil, buildVersion: nil, contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: url.deletingLastPathComponent())
        )
    }

    private func pixel() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }


    /// Folder cells take the presentation's Liquid Glass choice when they are built: glass leaves the
    /// backing clear, and the classic appearance keeps the gray backdrop.
    func testFolderCellsFollowTheLiquidGlassOption() throws {
        for enabled in [true, false] {
            let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]], folderGlass: enabled)
            let cell = try fixture.folderCell("Work")
            XCTAssertEqual(cell.glassEnabled, enabled)
            XCTAssertEqual(cell.backdropLayer.backgroundColor == nil, enabled)
        }
    }
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out waiting for icon loads.")
    }
}

private final class RemovalDurationObserver: NSObject, CALayerDelegate {
    var opacityDuration: CFTimeInterval = -1

    nonisolated func action(for layer: CALayer, forKey event: String) -> (any CAAction)? {
        MainActor.assumeIsolated {
            if event == "opacity" { opacityDuration = CATransaction.animationDuration() }
            return nil
        }
    }
}
