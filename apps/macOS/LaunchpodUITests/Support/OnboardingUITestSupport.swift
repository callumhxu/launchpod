import XCTest

@MainActor
enum OnboardingUITestSupport {
    static func launch(in app: XCUIApplication) throws -> XCUIElement {
        app.launchArguments = ["-AppleLanguages", "(en)", "-appLanguage", "en",
                               "-inMemoryDockStore", "YES", "-hasCompletedOnboarding", "NO"]
        app.launch()
        let window = app.descendants(matching: .any)["onboarding"]
        guard window.waitForExistence(timeout: 5) else {
            XCTFail("The introduction window must appear.\n\(app.debugDescription)")
            throw WindowUnavailable()
        }
        guard window.buttons["Continue"].waitForExistence(timeout: 5) else {
            XCTFail("The introduction content must be ready.\n\(app.debugDescription)")
            throw WindowUnavailable()
        }
        return window
    }

    private struct WindowUnavailable: Error {}
}
