import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalSpringboardTests: XCTestCase {
    private let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956), dock: .bottom(extent: 59))

    private func springboard(_ names: [String]) throws -> ClassicalSpringboard {
        let springboard = ClassicalSpringboard()
        springboard.pager.shiftKeyDown = { false }
        springboard.show(try names.map(record), geometry: geometry, scale: 1, rightToLeft: false,
                         noResultsText: "No Results") { _, _ in throw CancellationError() }
        return springboard
    }

    func testSearchStartsOnTheFirstPageSelectsTheFirstResultAndClearingRestoresThePage() throws {
        let names = (0..<80).map { String(format: "App %02d", $0) } + ["Safari", "Stocks"]
        let board = try springboard(names)
        board.pager.jump(to: 2)
        board.search("s")
        XCTAssertTrue(board.isFiltering)
        XCTAssertEqual(board.pager.currentPage, 0)
        XCTAssertEqual(board.pager.pageCount, 1)
        XCTAssertEqual(board.pager.pages.first?.records.map(\.metadata.displayName), ["Safari", "Stocks"])
        XCTAssertEqual(board.selectedRecord?.metadata.displayName, "Safari")
        XCTAssertTrue(board.pager.pages[0].itemLayers[0].isSelected)
        XCTAssertEqual(board.noResultsLayer.opacity, 0)

        board.search("st")
        XCTAssertEqual(board.selectedRecord?.metadata.displayName, "Stocks")

        board.clearSearch()
        XCTAssertFalse(board.isFiltering)
        XCTAssertEqual(board.pager.pageCount, 3)
        XCTAssertEqual(board.pager.currentPage, 2, "The page shown before searching comes back")
        XCTAssertEqual(board.pager.stripLayer.bounds.origin.x, 2 * 1470)
        XCTAssertNil(board.pager.stripLayer.animation(forKey: ClassicalPager.settleAnimationKey), "Restoring is not animated")
        XCTAssertNil(board.selectedRecord)
    }

    func testNoResultsShowsCentredOnThePageArea() throws {
        let board = try springboard(["Safari"])
        board.search("zzz")
        XCTAssertEqual(board.noResultsLayer.opacity, 1)
        XCTAssertEqual(board.noResultsLayer.compositingFilter as? String, "plusL")
        XCTAssertEqual(board.noResultsContainer.value(forKey: "allowsGroupBlending") as? Bool, false,
                       "Plus-lighter reaches the pages behind the container")
        XCTAssertEqual(board.noResultsLayer.string as? String, "No Results")
        let page = geometry.pageFrame.offsetBy(dx: -geometry.contentFrame.minX, dy: -geometry.contentFrame.minY)
        XCTAssertEqual(board.noResultsContainer.frame.midX, page.midX, accuracy: 1)
        XCTAssertEqual(board.noResultsContainer.frame.midY, page.midY, accuracy: 1)
        XCTAssertNil(board.selectedRecord)
        board.search("saf")
        XCTAssertEqual(board.noResultsLayer.opacity, 0)
    }

    func testShowingUpdatedRecordsReplacesNoResultsWithTheFirstMatchingSelection() throws {
        let board = try springboard(["Calendar"])
        board.search("saf")
        XCTAssertEqual(board.noResultsLayer.opacity, 1)
        XCTAssertNil(board.selectedID)
        let safari = try record("Safari")

        show(board.records + [safari], on: board)

        XCTAssertTrue(board.isFiltering)
        XCTAssertEqual(board.results?.map(\.id), [safari.id])
        XCTAssertEqual(board.noResultsLayer.opacity, 0)
        XCTAssertEqual(board.selectedRecord?.id, safari.id)
        XCTAssertTrue(board.pager.pages[0].itemLayers[0].isSelected)
    }

    func testShowingUpdatedRecordsClearsSelectionWhenTheLastMatchDisappears() throws {
        let board = try springboard(["Calendar", "Safari"])
        board.search("saf")
        XCTAssertNotNil(board.selectedID)

        show(board.records.filter { $0.metadata.displayName == "Calendar" }, on: board)

        XCTAssertTrue(board.isFiltering)
        XCTAssertEqual(board.results, [])
        XCTAssertEqual(board.noResultsLayer.opacity, 1)
        XCTAssertNil(board.selectedID)
        XCTAssertNil(board.selectedRecord)
        XCTAssertTrue(board.pager.pages.allSatisfy { $0.itemLayers.allSatisfy { !$0.isSelected } })
    }

    func testShowingUpdatedResultsPreservesSurvivingSelectionAndReplacesRemovedSelection() throws {
        let board = try springboard(["Safari", "Stocks"])
        board.search("s")
        let stocks = try XCTUnwrap(board.records.last)
        board.select(stocks.id)
        let screenSharing = try record("Screen Sharing")
        let refreshed = [screenSharing] + board.records

        show(refreshed, on: board)

        XCTAssertEqual(board.selectedID, stocks.id)
        XCTAssertTrue(board.pager.pages[0].itemLayers[2].isSelected)
        XCTAssertFalse(board.pager.pages[0].itemLayers[0].isSelected)

        show(refreshed.filter { $0.id != stocks.id }, on: board)

        XCTAssertEqual(board.selectedID, screenSharing.id)
        XCTAssertTrue(board.pager.pages[0].itemLayers[0].isSelected)
        XCTAssertEqual(board.noResultsLayer.opacity, 0)
    }

    func testRefreshingWhileSearchingKeepsTheOriginalPageForClearing() throws {
        let board = try springboard((0..<80).map { String(format: "App %02d", $0) } + ["Safari"])
        board.pager.jump(to: 2)
        board.search("saf")

        show(board.records + [try record("Safari Technology Preview")], on: board)
        XCTAssertEqual(board.pager.currentPage, 0)
        board.refreshRecords(board.records + [try record("Calendar")])
        board.clearSearch()

        XCTAssertEqual(board.pager.currentPage, 2)
        XCTAssertEqual(board.pager.stripLayer.bounds.origin.x, 2 * geometry.screenSize.width)
        XCTAssertNil(board.pager.stripLayer.animation(forKey: ClassicalPager.settleAnimationKey))
        XCTAssertNil(board.selectedID)
        XCTAssertEqual(board.noResultsLayer.opacity, 0)
    }

    func testRefreshingUnfilteredRecordsClearsASelectionWhoseApplicationWasRemoved() throws {
        let board = try springboard(["Calendar", "Safari"])
        board.select(try XCTUnwrap(board.records.last).id)

        board.refreshRecords(Array(board.records.prefix(1)))

        XCTAssertFalse(board.isFiltering)
        XCTAssertNil(board.selectedID)
        XCTAssertEqual(board.noResultsLayer.opacity, 0)
        XCTAssertTrue(board.navigate(.right, command: false))
        XCTAssertEqual(board.selectedRecord?.metadata.displayName, "Calendar")
    }

    func testOfflineApplicationKeepsItsUnfilteredCellButDoesNotAppearInSearch() throws {
        let calendar = try record("Calendar")
        let studio = try record("Studio")
        let offline = AppRecord(id: studio.id, metadata: studio.metadata,
                                source: try AppSource(kind: .custom, directoryURL: studio.source.directoryURL,
                                                      isOnline: false))
        let board = ClassicalSpringboard()
        board.show([calendar, offline], geometry: geometry, scale: 1, rightToLeft: false,
                   noResultsText: "No Results") { _, _ in throw CancellationError() }
        XCTAssertEqual(board.pager.pages.first?.records.map(\.id), [calendar.id, studio.id])

        board.search("stu")
        XCTAssertTrue(board.isFiltering)
        XCTAssertTrue(board.results?.isEmpty == true)
        XCTAssertEqual(board.noResultsLayer.opacity, 1)

        board.clearSearch()
        XCTAssertEqual(board.pager.pages.first?.records.map(\.id), [calendar.id, studio.id])
    }

    func testArrowsSelectWithinThePageAndCommandArrowsTurnIt() throws {
        let board = try springboard((0..<40).map { String(format: "App %02d", $0) })
        XCTAssertTrue(board.navigate(.right, command: false))
        XCTAssertEqual(board.selectedRecord?.metadata.displayName, "App 00")
        XCTAssertTrue(board.navigate(.down, command: false))
        XCTAssertEqual(board.selectedRecord?.metadata.displayName, "App 07")
        XCTAssertTrue(board.navigate(.left, command: false))
        XCTAssertEqual(board.selectedRecord?.metadata.displayName, "App 06")
        XCTAssertTrue(board.navigate(.right, command: true))
        XCTAssertEqual(board.pager.currentPage, 1)
        XCTAssertEqual(board.selectedRecord?.metadata.displayName, "App 35", "The selection moves to the new page's first item")
        XCTAssertFalse(board.navigate(.right, command: true), "No page after the last")
        board.reset()
        XCTAssertNil(board.selectedRecord)
        XCTAssertTrue(board.pager.pages.allSatisfy { $0.itemLayers.allSatisfy { !$0.isSelected } })
    }

    /// The selection is cleared whenever the page changes.
    func testTurningThePageClearsTheSelection() throws {
        let board = try springboard((0..<40).map { String(format: "App %02d", $0) })
        XCTAssertTrue(board.navigate(.right, command: false))
        XCTAssertNotNil(board.selectedRecord)
        board.pager.settle(on: 1)
        XCTAssertNil(board.selectedRecord)
        XCTAssertTrue(board.pager.pages.allSatisfy { $0.itemLayers.allSatisfy { !$0.isSelected } })
        board.pager.settle(on: 1)
        XCTAssertTrue(board.navigate(.down, command: false))
        board.pager.settle(on: 1)
        XCTAssertNotNil(board.selectedRecord, "Settling on the same page keeps it")
    }

    func testCommandArrowWithoutSelectionOnlyTurnsThePage() throws {
        let board = try springboard((0..<40).map { String(format: "App %02d", $0) })
        XCTAssertTrue(board.navigate(.right, command: true))
        XCTAssertEqual(board.pager.currentPage, 1)
        XCTAssertNil(board.selectedRecord)
    }

    // MARK: Folders

    /// Search looks inside folders: their applications appear among the results; folders never do,
    /// even when the term matches a folder's title.
    func testSearchFlattensFoldersIntoTheirApplications() throws {
        let fixture = try ClassicalFolderTestBoard([["Safari", .folder("Stuff", [["Stocks", "Notes"], ["Sketch"]])]])
        let board = fixture.board
        board.search("s")
        let shown = board.pager.pages.flatMap(\.items)
        XCTAssertTrue(shown.allSatisfy { $0.folder == nil }, "No folder is a result")
        XCTAssertEqual(Set(shown.compactMap(\.record?.metadata.displayName)), ["Safari", "Stocks", "Sketch"])
        board.search("stuff")
        XCTAssertTrue(board.pager.pages.flatMap(\.items).isEmpty, "A folder title is not searched")
        board.clearSearch()
        XCTAssertNotNil(board.pager.pages.first?.items.last?.folder, "The folder returns when the search clears")
    }

    func testAFolderDoesNotOpenDuringASearch() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["Safari", "Notes"]])]])
        fixture.board.search("saf")
        XCTAssertFalse(fixture.board.openFolder(try fixture.folderID("Work")))
    }

    /// A deleted application leaves the open folder; the folder closes once it is empty.
    func testDeletingInsideAFolderRemovesTheAppAndClosesAnEmptiedFolder() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        let board = fixture.board
        let folder = try fixture.open("Work")
        board.removeRecord(try fixture.record("B").id)
        ClassicalFolderTestBoard.waitUntil { folder.content.records.count == 1 }
        XCTAssertEqual(folder.content.records.map(\.metadata.displayName), ["C"])
        XCTAssertTrue(board.folders.openFolder === folder, "A folder with an application left stays open")

        board.removeRecord(try fixture.record("C").id)
        fixture.waitUntilClosed()
        // The next catalog update may still list both deleted applications.
        board.refresh(pages: board.pages)
        XCTAssertEqual(ClassicalDragTestBoard.names(board.pages), [["A"]], "The emptied folder is gone from the root page")
    }

    /// While a folder is shown a catalog update waits, and applies once the folder has closed.
    func testCatalogUpdatesWaitWhileAFolderIsShown() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        let board = fixture.board
        var refreshes = 0
        board.deferredRefreshNeeded = { refreshes += 1 }
        let folder = try fixture.open("Work")
        board.refresh(pages: [[.app(try fixture.record("A"))]])
        XCTAssertTrue(board.folders.openFolder === folder, "The update does not close the folder")
        XCTAssertNotNil(board.pages[0].last?.folder)
        board.folders.close()
        fixture.waitUntilClosed()
        ClassicalFolderTestBoard.waitUntil { refreshes == 1 }
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

    private func show(_ records: [AppRecord], on board: ClassicalSpringboard) {
        board.show(records, geometry: geometry, scale: 1, rightToLeft: false,
                   noResultsText: "No Results") { _, _ in throw CancellationError() }
    }
}
