import XCTest

@MainActor
final class OnboardingGlassDemoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testGlassExpandsAndCollapsesOrExplainsTheSystemMaterialFallback() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        let window = try OnboardingUITestSupport.launch(in: app)
        for _ in 0..<3 { window.buttons["Continue"].click() }
        XCTAssertTrue(window.staticTexts["Made for Your Mac"].waitForExistence(timeout: 3))
        let expand = window.buttons["Expand Glass"]
        let collapse = window.buttons["Collapse Glass"]
        if #available(macOS 26.0, *) {
            XCTAssertTrue(expand.exists)
            expand.click()
            XCTAssertTrue(collapse.waitForExistence(timeout: 3))
            XCTAssertTrue(window.staticTexts["Liquid Glass"].exists)
            collapse.click()
            XCTAssertTrue(expand.waitForExistence(timeout: 3))
            XCTAssertFalse(window.staticTexts["Liquid Glass"].exists)
        } else {
            XCTAssertFalse(expand.exists)
            XCTAssertFalse(collapse.exists)
            XCTAssertTrue(window.staticTexts["System Material"].exists)
            XCTAssertTrue(window.staticTexts["Liquid Glass requires macOS 26 or later. This Mac shows the standard system material."].exists)
        }
        XCTAssertFalse(window.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Calendar")).firstMatch.exists,
                       "Decorative background apps are hidden from accessibility")
    }
}
