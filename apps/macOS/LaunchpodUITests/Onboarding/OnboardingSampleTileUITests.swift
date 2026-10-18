import XCTest

@MainActor
final class OnboardingSampleTileUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSampleTilesExposeOneReadableNameWithoutTheirDecorativeSymbol() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        let window = try OnboardingUITestSupport.launch(in: app)
        for title in ["Notes", "Music", "Photos", "Calendar"] {
            let matches = window.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title))
            XCTAssertEqual(matches.count, 1, window.debugDescription)
            XCTAssertEqual(matches.firstMatch.children(matching: .any).count, 0,
                           "The tile exposes its name once without exposing the decorative symbol")
        }
    }
}
