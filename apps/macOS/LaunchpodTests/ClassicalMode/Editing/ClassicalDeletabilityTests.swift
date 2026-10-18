import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalDeletabilityTests: XCTestCase {
    func testSystemApplicationsAreNotDeletable() {
        XCTAssertFalse(ClassicalDeletability.isDeletable(URL(fileURLWithPath: "/System/Applications/Calculator.app")))
    }
}
