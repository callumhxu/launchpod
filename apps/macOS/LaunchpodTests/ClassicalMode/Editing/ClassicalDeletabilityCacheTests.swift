import Foundation
import XCTest
@testable import Launchpod

/// Delete badges ask once per application whether it may be deleted; a page refresh asks again.
@MainActor
final class ClassicalDeletabilityCacheTests: XCTestCase {
    func testEachApplicationIsAskedOnceUntilTheAnswersAreCleared() throws {
        let editor = try ClassicalDragTestBoard.record("Editor")
        let viewer = try ClassicalDragTestBoard.record("Viewer")
        let cache = ClassicalDeletabilityCache()
        var asked: [String] = []
        var deletable: Set<String> = ["Editor"]
        cache.isDeletable = { record in
            asked.append(record.metadata.displayName)
            return deletable.contains(record.metadata.displayName)
        }

        XCTAssertTrue(cache.canDelete(editor))
        XCTAssertFalse(cache.canDelete(viewer))
        deletable = ["Viewer"]
        XCTAssertTrue(cache.canDelete(editor), "An answer is kept")
        XCTAssertFalse(cache.canDelete(viewer))
        XCTAssertEqual(asked, ["Editor", "Viewer"])

        cache.removeAll()
        XCTAssertFalse(cache.canDelete(editor), "Cleared answers are asked again")
        XCTAssertTrue(cache.canDelete(viewer))
        XCTAssertEqual(asked, ["Editor", "Viewer", "Editor", "Viewer"])
    }

    /// The springboard clears the answers whenever it shows its pages again.
    func testShowingThePagesAgainAsksAgain() throws {
        let board = ClassicalSpringboard()
        let records = [try ClassicalDragTestBoard.record("Editor")]
        var answer = false
        board.deletability.isDeletable = { _ in answer }
        board.show(records, geometry: ClassicalDragTestBoard.geometry, scale: 1, rightToLeft: false,
                   noResultsText: "No Results") { _, _ in throw CancellationError() }
        XCTAssertFalse(board.deletability.canDelete(records[0]))
        answer = true
        XCTAssertFalse(board.deletability.canDelete(records[0]))
        board.show(records, geometry: ClassicalDragTestBoard.geometry, scale: 1, rightToLeft: false,
                   noResultsText: "No Results") { _, _ in throw CancellationError() }
        XCTAssertTrue(board.deletability.canDelete(records[0]))
    }
}
