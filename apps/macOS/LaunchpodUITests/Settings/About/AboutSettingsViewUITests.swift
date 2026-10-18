import XCTest

final class AboutSettingsViewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testShowIntroductionReplaysOnboardingFromTheWelcomePage() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let settings = try SettingsUITestSupport.openSettingsPage("About", in: app, testCase: self)
        let button = settings.buttons["showIntroductionButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.click()
        let introduction = app.descendants(matching: .any)["onboarding"]
        XCTAssertTrue(introduction.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(introduction.staticTexts["Welcome to Launchpod"].exists)
        let next = introduction.buttons["Continue"]
        XCTAssertTrue(next.exists)
        XCTAssertFalse(introduction.buttons["Back"].exists)
        next.click()
        XCTAssertTrue(introduction.buttons["Back"].waitForExistence(timeout: 3))
        introduction.buttons["Skip Introduction"].click()
        XCTAssertTrue(introduction.waitForNonExistence(timeout: 3))
        settings.click()
        button.click()
        XCTAssertTrue(introduction.waitForExistence(timeout: 3))
        XCTAssertTrue(introduction.staticTexts["Welcome to Launchpod"].exists)
        XCTAssertFalse(introduction.buttons["Back"].exists, "Replay starts a new introduction")
    }

    @MainActor
    func testAboutShowsNameVersionLinksAndSoftwareUpdate() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let window = try SettingsUITestSupport.openSettingsPage("About", in: app, testCase: self)

        XCTAssertTrue(window.staticTexts["Launchpod"].waitForExistence(timeout: 3), window.debugDescription)
        let version = window.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "Version ")
        ).firstMatch
        XCTAssertTrue(version.exists, window.debugDescription)
        let versionText = try XCTUnwrap(version.value as? String)
        XCTAssertNotNil(versionText.range(of: #"^Version [0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression),
                        "About shows only the marketing version: \(versionText)")
        XCTAssertFalse(versionText.contains("("), "About must not show the internal build number")

        // The rows follow the app's name directly, without a section title.
        XCTAssertFalse(window.staticTexts["Information"].exists)
        let externalLinks = [
            (title: "GitHub", identifier: "githubLink"),
            (title: "X", identifier: "xLink"),
            (title: "YouTube", identifier: "youtubeLink"),
            (title: "TikTok", identifier: "tiktokLink")
        ]
        for (title, identifier) in externalLinks {
            XCTAssertTrue(window.staticTexts[title].exists, title)
            let link = window.links[identifier]
            XCTAssertTrue(link.exists, "Missing link: \(title)\n\(window.debugDescription)")
            XCTAssertTrue(link.isEnabled, "Disabled link: \(title)")
        }
        XCTAssertTrue(window.staticTexts["Software Update"].exists, window.debugDescription)
        let updateButton = window.buttons["checkForUpdatesButton"]
        XCTAssertTrue(updateButton.exists, window.debugDescription)
        XCTAssertFalse(window.staticTexts["Coming Soon"].exists, window.debugDescription)
    }
}
