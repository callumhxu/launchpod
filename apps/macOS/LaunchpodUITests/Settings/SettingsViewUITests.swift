import XCTest

final class SettingsViewUITests: XCTestCase {
    @MainActor
    func testClosingAndReopeningSettingsReturnsToGeneral() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(en)", "-appLanguage", "en", "-inMemoryDockStore", "YES", "-showInMenuBar", "YES"]
        try SettingsUITestSupport.launchAndOpenSettings(in: app, testCase: self)
        let window = SettingsUITestSupport.settingsWindow(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        for title in ["Shortcuts", "About", "Interface"] {
            let tab = window.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", title)).firstMatch
            XCTAssertTrue(tab.exists, title)
            tab.click()
            XCTAssertFalse(window.popUpButtons["appLanguagePicker"].exists)
            app.typeKey("w", modifierFlags: .command)
            XCTAssertTrue(window.waitForNonExistence(timeout: 3))
            let statusItem = app.statusItems["launcherStatusItem"]
            XCTAssertTrue(statusItem.exists, app.debugDescription)
            statusItem.click()
            let launcher = try SettingsUITestSupport.readyLauncher(in: app)
            launcher.typeKey(",", modifierFlags: .command)
            XCTAssertTrue(window.popUpButtons["appLanguagePicker"].waitForExistence(timeout: 5), title)
        }
    }

    @MainActor
    func testRequestingAlreadyOpenSettingsPreservesSelectedPage() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(en)", "-appLanguage", "en", "-inMemoryDockStore", "YES"]
        try SettingsUITestSupport.launchAndOpenSettings(in: app, testCase: self)
        let window = SettingsUITestSupport.settingsWindow(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        window.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Shortcuts")).firstMatch.click()
        XCTAssertTrue(window.buttons["launcherShortcutRecorder"].waitForExistence(timeout: 3))

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(window.buttons["launcherShortcutRecorder"].waitForExistence(timeout: 3))
        XCTAssertFalse(window.popUpButtons["appLanguagePicker"].exists)

        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        app.activate()
        XCTAssertTrue(window.buttons["launcherShortcutRecorder"].waitForExistence(timeout: 3))
        XCTAssertFalse(window.popUpButtons["appLanguagePicker"].exists)
    }

    @MainActor
    func testWindowTitleRemainsLocalizedSettingsAcrossTabs() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }

        for (language, windowTitle, tabs) in [
            ("en", "Settings", ["General", "Interface", "Apps", "Shortcuts", "Advanced", "About"]),
            ("zh-Hans", CatalogTestSupport.text("Settings", locale: "zh-Hans"), [CatalogTestSupport.text("General", locale: "zh-Hans"), CatalogTestSupport.text("Interface", locale: "zh-Hans"), CatalogTestSupport.text("Apps", locale: "zh-Hans"), CatalogTestSupport.text("Shortcuts", locale: "zh-Hans"), CatalogTestSupport.text("Advanced", locale: "zh-Hans"), CatalogTestSupport.text("About", locale: "zh-Hans")]),
            ("zh-Hant", CatalogTestSupport.text("Settings", locale: "zh-Hant"), [CatalogTestSupport.text("General", locale: "zh-Hant"), CatalogTestSupport.text("Interface", locale: "zh-Hant"), CatalogTestSupport.text("Apps", locale: "zh-Hant"), CatalogTestSupport.text("Shortcuts", locale: "zh-Hant"), CatalogTestSupport.text("Advanced", locale: "zh-Hant"), CatalogTestSupport.text("About", locale: "zh-Hant")]),
            ("fr", CatalogTestSupport.text("Settings", locale: "fr"), [CatalogTestSupport.text("General", locale: "fr"), "Interface", "Apps", CatalogTestSupport.text("Shortcuts", locale: "fr"), CatalogTestSupport.text("Advanced", locale: "fr"), CatalogTestSupport.text("About", locale: "fr")]),
            ("de", CatalogTestSupport.text("Settings", locale: "de"), [CatalogTestSupport.text("General", locale: "de"), CatalogTestSupport.text("Interface", locale: "de"), "Apps", CatalogTestSupport.text("Shortcuts", locale: "de"), CatalogTestSupport.text("Advanced", locale: "de"), CatalogTestSupport.text("About", locale: "de")]),
            ("ko", CatalogTestSupport.text("Settings", locale: "ko"), [CatalogTestSupport.text("General", locale: "ko"), CatalogTestSupport.text("Interface", locale: "ko"), CatalogTestSupport.text("Apps", locale: "ko"), CatalogTestSupport.text("Shortcuts", locale: "ko"), CatalogTestSupport.text("Advanced", locale: "ko"), CatalogTestSupport.text("About", locale: "ko")]),
            ("es", CatalogTestSupport.text("Settings", locale: "es"), ["General", CatalogTestSupport.text("Interface", locale: "es"), "Apps", CatalogTestSupport.text("Shortcuts", locale: "es"), CatalogTestSupport.text("Advanced", locale: "es"), CatalogTestSupport.text("About", locale: "es")]),
            ("ja", CatalogTestSupport.text("Settings", locale: "ja"), [CatalogTestSupport.text("General", locale: "ja"), CatalogTestSupport.text("Interface", locale: "ja"), CatalogTestSupport.text("Apps", locale: "ja"), CatalogTestSupport.text("Shortcuts", locale: "ja"), CatalogTestSupport.text("Advanced", locale: "ja"), CatalogTestSupport.text("About", locale: "ja")])
        ] {
            app.launchArguments = ["-AppleLanguages", "(en)", "-appLanguage", language, "-inMemoryDockStore", "YES"]
            try SettingsUITestSupport.launchAndOpenSettings(in: app, testCase: self)

            let window = SettingsUITestSupport.settingsWindow(in: app)
            XCTAssertTrue(window.waitForExistence(timeout: 5))
            XCTAssertEqual(window.title, windowTitle, language)
            for title in tabs {
                let tab = window.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", title)).firstMatch
                XCTAssertTrue(tab.exists, title)
                tab.click()
                XCTAssertEqual(window.title, windowTitle, "\(language): \(title)")
                XCTAssertLessThanOrEqual(window.frame.width, 520, "\(language): \(title)")
                XCTAssertGreaterThan(window.frame.height, window.frame.width, "\(language): \(title)")
            }
            app.terminate()
        }
    }

    @MainActor
    func testShortcutsHasItsOwnPageAndExplainsTheLauncherAction() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(en)", "-appLanguage", "en", "-inMemoryDockStore", "YES"]
        try SettingsUITestSupport.launchAndOpenSettings(in: app, testCase: self)

        let general = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "General")).firstMatch
        let shortcuts = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Shortcuts")).firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        XCTAssertTrue(shortcuts.exists)
        for title in ["Interface", "Apps", "Advanced", "About"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch.exists, title)
        }
        general.click()
        XCTAssertTrue(app.popUpButtons["appLanguagePicker"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["launcherShortcutRecorder"].exists)

        shortcuts.click()
        let recorder = app.buttons["launcherShortcutRecorder"]
        XCTAssertTrue(recorder.waitForExistence(timeout: 3))
        XCTAssertTrue(recorder.isEnabled)
        XCTAssertTrue(recorder.isHittable)
        XCTAssertTrue(app.staticTexts["Show or Hide Launchpod"].exists)
        XCTAssertTrue(app.staticTexts["Keyboard Shortcut"].exists)
        XCTAssertFalse(app.popUpButtons["appLanguagePicker"].exists)
        XCTAssertFalse(app.staticTexts["Use Command, Control, or Option with a letter, number, or symbol. Press Escape to cancel."].exists)

        general.click()
        XCTAssertTrue(app.popUpButtons["appLanguagePicker"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["launcherShortcutRecorder"].exists)
    }
}
