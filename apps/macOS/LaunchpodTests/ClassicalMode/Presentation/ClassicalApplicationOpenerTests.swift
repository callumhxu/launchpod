import Foundation
import XCTest
@testable import Launchpod

final class ClassicalApplicationOpenerTests: XCTestCase {
    func testAvailabilityFollowsBundleRemovalAndRestorationAtTheSameURL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = directory.appendingPathComponent("Sample.app", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertFalse(ClassicalApplicationOpener.canOpen(bundle))
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        XCTAssertTrue(ClassicalApplicationOpener.canOpen(bundle))
        try FileManager.default.removeItem(at: bundle)
        XCTAssertFalse(ClassicalApplicationOpener.canOpen(bundle), "A previously present app must not leave cached availability")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        XCTAssertTrue(ClassicalApplicationOpener.canOpen(bundle))
    }
}
