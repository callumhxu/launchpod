import XCTest

final class AdvancedSettingsViewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLayoutSectionShowsRestoreImportAndExportActions() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let window = try SettingsUITestSupport.openSettingsPage("Advanced", in: app, testCase: self)

        XCTAssertTrue(window.staticTexts["Layout"].waitForExistence(timeout: 3), window.debugDescription)
        XCTAssertTrue(window.staticTexts["Default Classical Layout"].exists)
        XCTAssertTrue(window.staticTexts["Layout Backup"].exists)
        let restore = window.buttons["Restore…"]
        let importButton = window.buttons["Import…"]
        let export = window.buttons["Export…"]
        for button in [restore, importButton, export] {
            XCTAssertTrue(button.exists, window.debugDescription)
        }
        XCTAssertTrue(importButton.isEnabled)
    }

    @MainActor
    func testStartupSectionReflectsTheCurrentLaunchAtLoginState() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let window = try SettingsUITestSupport.openSettingsPage("Advanced", in: app, testCase: self)

        XCTAssertTrue(window.staticTexts["Startup"].waitForExistence(timeout: 3), window.debugDescription)
        XCTAssertTrue(window.staticTexts["Launch at Login"].exists, window.debugDescription)
        XCTAssertTrue(window.staticTexts["Open Launchpod automatically when you log in."].exists, window.debugDescription)
        let toggle = window.checkBoxes["launchAtLoginToggle"]
        XCTAssertTrue(toggle.exists, window.debugDescription)
        let value = try XCTUnwrap(toggle.value as? NSNumber).intValue
        XCTAssertTrue([0, 1].contains(value), toggle.debugDescription)
    }
}
