import XCTest

@MainActor
final class OnboardingFeatureDemoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSearchReorderAndResetChangeTheRenderedSample() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        let window = try OnboardingUITestSupport.launch(in: app)
        for identifier in ["Try Search", "Try Reordering", "Reset Demo"] {
            XCTAssertFalse(window.buttons[identifier].exists,
                           "The welcome illustration does not expose interactive controls")
        }
        window.buttons["Continue"].click()
        let search = window.buttons["Try Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        func tile(_ name: String) -> XCUIElement {
            window.descendants(matching: .other).matching(NSPredicate(format: "label == %@", name)).firstMatch
        }
        func waitForOrder(_ expected: [String]) {
            let ordered = NSPredicate { _, _ in
                MainActor.assumeIsolated {
                    let elements = expected.map(tile)
                    guard elements.allSatisfy(\.exists) else { return false }
                    return zip(elements, elements.dropFirst()).allSatisfy { $0.frame.minX < $1.frame.minX }
                }
            }
            let expectation = XCTNSPredicateExpectation(predicate: ordered, object: nil)
            expectation.expectationDescription = "Sample order becomes \(expected.joined(separator: ", "))"
            wait(for: [expectation], timeout: 3)
        }
        let names = ["Notes", "Music", "Photos", "Calendar"]
        for name in names { XCTAssertTrue(tile(name).exists, window.debugDescription) }
        waitForOrder(names)
        search.click()
        XCTAssertTrue(tile("Music").waitForNonExistence(timeout: 3))
        XCTAssertTrue(tile("Notes").exists)
        XCTAssertFalse(tile("Photos").exists)
        XCTAssertFalse(tile("Calendar").exists)
        window.buttons["Try Reordering"].click()
        waitForOrder(["Calendar", "Notes", "Music", "Photos"])
        window.buttons["Reset Demo"].click()
        waitForOrder(names)
    }
}
