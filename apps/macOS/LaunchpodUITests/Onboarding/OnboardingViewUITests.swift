import XCTest

@MainActor
final class OnboardingViewUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNavigationSettingsAndCompletionUseTheirProductionOwners() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        let window = try OnboardingUITestSupport.launch(in: app)
        XCTAssertFalse(window.buttons["Back"].exists)
        window.buttons["Continue"].click()
        XCTAssertTrue(window.buttons["Try Search"].waitForExistence(timeout: 3))
        window.buttons["Back"].click()
        XCTAssertTrue(window.staticTexts["Welcome to Launchpod"].waitForExistence(timeout: 3))
        XCTAssertFalse(window.buttons["Back"].exists)
        for _ in 0..<4 { window.buttons["Continue"].click() }
        let finish = window.buttons["Get Started"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertFalse(window.buttons["Continue"].exists)
        XCTAssertFalse(window.buttons["Skip Introduction"].exists)
        window.buttons["Open Settings…"].click()
        let settings = app.descendants(matching: .any)["settingsWindow"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertTrue(window.exists, "Opening Settings must not complete the introduction")
        settings.buttons[XCUIIdentifierCloseWindow].click()
        window.click()
        finish.click()
        XCTAssertTrue(window.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["launcherPlaceholderWindow"].waitForExistence(timeout: 5))
    }

    func testSkippingClosesTheIntroductionAndShowsTheLauncher() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        let window = try OnboardingUITestSupport.launch(in: app)
        window.buttons["Skip Introduction"].click()
        XCTAssertTrue(window.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["launcherPlaceholderWindow"].waitForExistence(timeout: 5))
    }
}
