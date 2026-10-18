import Foundation
import XCTest
@testable import Launchpod

final class ClassicalLayoutTitleOrderTests: XCTestCase {
    private func record(_ bundleID: String, name: String, directoryPath: String) throws -> AppRecord {
        let directory = URL(filePath: directoryPath, directoryHint: .isDirectory)
        return AppRecord(
            id: AppIdentity(),
            metadata: try AppMetadata(bundleIdentifier: bundleID,
                                      bundleURL: directory.appending(path: "\(name).app", directoryHint: .isDirectory),
                                      displayName: name, version: nil, buildVersion: nil,
                                      contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: directory, isOnline: true)
        )
    }

    func testAutomaticPlacementPrioritizesKnownSystemAppsThenUsesTitleOrderWithinEachGroup() throws {
        let systemZ = try record("com.example.systemZ", name: "Z System", directoryPath: "/System/Applications")
        let templateA = try record("com.apple.Safari", name: "A Template", directoryPath: "/Applications")
        let userA = try record("com.example.userA", name: "A User", directoryPath: "/Applications")
        let userZ = try record("com.example.userZ", name: "Z User", directoryPath: "/Applications")

        let sorted = ClassicalLayoutTitleOrder.sorted([userZ, systemZ, userA, templateA])

        XCTAssertEqual(sorted.map(\.id), [templateA.id, systemZ.id, userA.id, userZ.id],
                       "Known system apps lead automatic placement; titles order each priority group")
    }

    func testNumericTitlesWithLeadingZerosCompareEqually() {
        XCTAssertFalse(ClassicalLayoutTitleOrder.lessThan("App1", "App01"))
        XCTAssertFalse(ClassicalLayoutTitleOrder.lessThan("App01", "App1"))
        XCTAssertNotEqual("App1".localizedStandardCompare("App01"), .orderedSame,
                          "Standard Finder ordering distinguishes these names; Dock's comparison does not")
        XCTAssertTrue(ClassicalLayoutTitleOrder.lessThan("App2", "App10"))
    }
}
