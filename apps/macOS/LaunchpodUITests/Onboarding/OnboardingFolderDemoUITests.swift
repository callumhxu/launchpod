import XCTest

@MainActor
final class OnboardingFolderDemoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFolderControlsFollowCreationOpeningClosingAndReset() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        let window = try OnboardingUITestSupport.launch(in: app)
        for _ in 0..<2 { window.buttons["Continue"].click() }
        let reset = window.buttons["Reset Demo"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3))
        reset.click()
        let create = window.buttons["Create Folder"]
        let openControls = window.buttons.matching(NSPredicate(format: "label == %@", "Open Folder"))
        let open = openControls.firstMatch
        XCTAssertTrue(create.isEnabled)
        XCTAssertFalse(open.isEnabled)
        create.click()
        XCTAssertTrue(create.wait(for: \.isEnabled, toEqual: false, timeout: 3))
        XCTAssertEqual(openControls.count, 2, "The collapsed folder and its footer action both open the folder")
        XCTAssertTrue(open.isEnabled)
        open.click()
        let close = window.buttons["Close Folder"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertTrue(window.staticTexts["Sample Folder"].exists)
        for name in ["Notes", "Music"] {
            XCTAssertTrue(window.descendants(matching: .other).matching(NSPredicate(format: "label == %@", name)).firstMatch.exists)
        }
        for name in ["Photos", "Calendar"] {
            XCTAssertFalse(window.descendants(matching: .other).matching(NSPredicate(format: "label == %@", name)).firstMatch.exists)
        }
        close.click()
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertFalse(close.exists)
        XCTAssertEqual(openControls.count, 2)
        reset.click()
        XCTAssertTrue(create.wait(for: \.isEnabled, toEqual: true, timeout: 3))
        XCTAssertEqual(openControls.count, 1, "Reset removes the collapsed folder control")
        XCTAssertFalse(open.isEnabled)
        for name in ["Notes", "Music", "Photos", "Calendar"] {
            XCTAssertTrue(window.descendants(matching: .other).matching(NSPredicate(format: "label == %@", name)).firstMatch.exists)
        }
    }
}
