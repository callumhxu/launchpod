import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalSpringboardIconPreparationTests: XCTestCase {
    private let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956),
                                                        dock: .bottom(extent: 59))

    func testGeometryChangeKeepsAnIconWhenItsRequestedRasterSizeIsUnchanged() async throws {
        let resized = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1471, height: 956),
                                                   dock: .bottom(extent: 59))
        let originalSize = try AppIconSize(pointSize: ClassicalItemLayout(cellSize: geometry.grid.cellSize).iconFrame.size,
                                           backingScale: 1)
        let resizedSize = try AppIconSize(pointSize: ClassicalItemLayout(cellSize: resized.grid.cellSize).iconFrame.size,
                                          backingScale: 1)
        XCTAssertNotEqual(geometry, resized)
        XCTAssertEqual(originalSize, resizedSize, "The fixture must change geometry without changing the icon raster")
        let record = try AppIconTestSupport.record()
        let board = ClassicalSpringboard()
        var requests = 0
        let load: @MainActor (AppRecord, AppIconSize) async throws -> CGImage = { _, size in
            requests += 1
            return try AppIconTestSupport.icon(size: size).cgImage
        }

        board.show([record], geometry: geometry, scale: 1, rightToLeft: false,
                   noResultsText: "No Results", icon: load)
        try await waitUntil { board.pager.pages[0].itemLayers[0].iconLayer.contents != nil }
        XCTAssertEqual(requests, 1)

        board.show([record], geometry: resized, scale: 1, rightToLeft: false,
                   noResultsText: "No Results", icon: load)
        XCTAssertNotNil(board.pager.pages[0].itemLayers[0].iconLayer.contents)
        await Task.yield()
        XCTAssertEqual(requests, 1, "Relayout should reuse the completed raster at the same size")
    }

    func testLaterFolderPageIconRequestsStartBeforeTheFolderOpens() async throws {
        let records = try (0..<110).map(record)
        let folderID = ClassicalLayoutFolder.ID()
        let folderContent = ClassicalPageFolder(id: folderID, title: "Many Apps",
                                                pages: ClassicalPager.chunk(records, capacity: geometry.grid.capacity))
        let board = ClassicalSpringboard()
        let host = CALayer()
        let background = CALayer()
        host.frame = CGRect(origin: .zero, size: geometry.screenSize)
        background.frame = host.bounds
        host.addSublayer(background)
        background.addSublayer(board.pager.layer)
        let panel = ClassicalFolderGeometry.Panel(springboard: geometry, itemCount: records.count)
        let folderIconSize = try AppIconSize(pointSize: ClassicalItemLayout(cellSize: panel.grid.cellSize).iconFrame.size,
                                             backingScale: 1)
        var requests: [(AppIdentity, AppIconSize)] = []
        var completions: [(AppIdentity, AppIconSize)] = []
        var completedFolderRasterBytes = 0

        board.show(pages: [[.folder(folderContent)]], geometry: geometry, scale: 1,
                   rightToLeft: false, noResultsText: "No Results") { record, size in
            requests.append((record.id, size))
            let image = try AppIconTestSupport.icon(size: size).cgImage
            completions.append((record.id, size))
            if size == folderIconSize { completedFolderRasterBytes += image.bytesPerRow * image.height }
            return image
        }

        let expectedIDs = Set(records.map(\.id))
        try await waitUntil {
            Set(completions.filter { $0.1 == folderIconSize }.map(\.0)) == expectedIDs
        }
        XCTAssertEqual(requests.filter { $0.1 == folderIconSize }.count, records.count,
                       "Preparing a folder must request each application once at the folder icon size")
        XCTAssertEqual(completions.filter { $0.1 == folderIconSize }.count, records.count)
        XCTAssertGreaterThan(completedFolderRasterBytes, 1_000_000,
                             "The fixture should exercise full-size folder rasters, not tiny placeholders")

        XCTAssertTrue(board.openFolder(folderID))
        let folder = try XCTUnwrap(board.folders.openFolder)
        XCTAssertGreaterThan(folder.pager.pageCount, 3)
        XCTAssertTrue(folder.pager.pages.last?.itemLayers.allSatisfy { $0.iconLayer.contents != nil } == true,
                      "The last folder page should contain prepared rasters before navigation")
        folder.pager.jump(to: folder.pager.pageCount - 1)
        await Task.yield()
        XCTAssertEqual(requests.filter { $0.1 == folderIconSize }.count, records.count,
                       "Opening and paging through a prepared folder should not reload the same rasters")
        board.folders.close(animated: false)
    }

    private func record(_ index: Int) throws -> AppRecord {
        let path = "/Applications/Icon Preparation \(index).app"
        return try AppIconTestSupport.record(path: path, identifier: "com.example.icon-preparation.\(index)")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        _ = try XCTUnwrap(condition() ? true : nil, "Timed out waiting for Classical icon preparation")
    }
}
