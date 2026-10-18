import XCTest

final class GeneralSettingsViewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMenuBarSwitchPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        app.launchArguments = ["-inMemoryDockStore", "YES"]
        try SettingsUITestSupport.launchAndOpenSettings(in: app, testCase: self)
        let toggle = app.switches["showInMenuBarToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = try XCTUnwrap(toggle.value as? NSNumber).intValue
        XCTAssertTrue([0, 1].contains(original), toggle.debugDescription)
        addTeardownBlock { @MainActor in
            if app.state == .runningForeground || app.state == .runningBackground {
                app.typeKey(",", modifierFlags: .command)
                if toggle.waitForExistence(timeout: 3),
                   let value = toggle.value as? NSNumber, value.intValue != original {
                    toggle.click()
                }
            }
        }

        for _ in 0..<2 {
            let before = try XCTUnwrap(toggle.value as? NSNumber).intValue
            toggle.click()
            let changed = NSPredicate(format: "value != %@", NSNumber(value: before))
            expectation(for: changed, evaluatedWith: toggle)
            waitForExpectations(timeout: 3)
            let selected = try XCTUnwrap(toggle.value as? NSNumber).intValue
            XCTAssertEqual(selected, before == 0 ? 1 : 0)
            app.terminate()
            try SettingsUITestSupport.launchAndOpenSettings(in: app, testCase: self)
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            XCTAssertEqual(try XCTUnwrap(toggle.value as? NSNumber).intValue, selected)
        }
    }

    @MainActor
    func testKeepInDockRowOffersTheDraggableApplicationIcon() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let window = try SettingsUITestSupport.openSettingsPage("General", in: app, testCase: self)

        XCTAssertTrue(dockText("Keep in Dock", in: window).waitForExistence(timeout: 3), window.debugDescription)
        XCTAssertTrue(window.staticTexts["Menu Bar & Dock"].exists, window.debugDescription)
        XCTAssertTrue(dockText("Drag this app icon to the Dock.", in: window).exists, window.debugDescription)
        let icon = window.descendants(matching: .any)["dockApplicationIcon"]
        XCTAssertTrue(icon.exists, window.debugDescription)
        // The accessibility frame can extend one point per edge beyond the 48-point image view.
        XCTAssertEqual(icon.frame.width, 48, accuracy: 2)
        XCTAssertEqual(icon.frame.height, 48, accuracy: 2)
        XCTAssertTrue(window.switches["showInMenuBarToggle"].exists)
    }

    @MainActor
    func testKeepInDockRowOffersAddUntilTheAppIsInTheDock() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let window = try SettingsUITestSupport.openSettingsPage("General", in: app, testCase: self)
        let addToDock = window.buttons["addToDockButton"]
        let icon = window.descendants(matching: .any)["dockApplicationIcon"]
        XCTAssertTrue(addToDock.waitForExistence(timeout: 3), window.debugDescription)
        XCTAssertTrue(addToDock.isEnabled)
        XCTAssertTrue(addToDock.isHittable)
        XCTAssertTrue(dockText("Keep in Dock", in: window).exists, window.debugDescription)
        XCTAssertTrue(dockText("Drag this app icon to the Dock.", in: window).exists, window.debugDescription)
        XCTAssertTrue(icon.exists)
        let before = XCTAttachment(screenshot: window.screenshot())
        before.name = "Dock-row-before-add"
        before.lifetime = .keepAlways
        add(before)

        addToDock.click()

        XCTAssertTrue(addToDock.waitForNonExistence(timeout: 3), window.debugDescription)
        XCTAssertTrue(dockText("Keep in Dock", in: window).exists, window.debugDescription)
        XCTAssertTrue(dockText("This app is in the Dock.", in: window).waitForExistence(timeout: 3), window.debugDescription)
        XCTAssertFalse(dockText("Drag this app icon to the Dock.", in: window).exists, window.debugDescription)
        XCTAssertTrue(icon.exists, "The draggable application icon remains after adding")
        let after = XCTAttachment(screenshot: window.screenshot())
        after.name = "Dock-row-after-add"
        after.lifetime = .keepAlways
        add(after)
    }

    @MainActor
    func testApplicationIconRowShowsSubtitleAndFourCenteredChoicesWithOneAccessibleSelection() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let window = try SettingsUITestSupport.openSettingsPage("General", in: app, testCase: self)

        let label = window.staticTexts["Application Icon"]
        let subtitle = window.staticTexts["Choose the icon shown in the Dock."]
        let picker = window.descendants(matching: .any)["applicationIconPicker"]
        XCTAssertTrue(label.waitForExistence(timeout: 3), window.debugDescription)
        XCTAssertTrue(subtitle.exists, window.debugDescription)
        XCTAssertTrue(picker.exists, window.debugDescription)
        let choices = [
            ("colorTiles", "Color Tiles"),
            ("colorGrid", "Color Grid"),
            ("darkGrid", "Dark Grid"),
            ("rocket", "Rocket")
        ].map { identifier, name in
            (window.buttons["applicationIcon.\(identifier)"], name)
        }
        for (icon, name) in choices {
            XCTAssertTrue(icon.exists, window.debugDescription)
            XCTAssertTrue(icon.isHittable, icon.debugDescription)
            XCTAssertEqual(icon.label, name)
            XCTAssertEqual(icon.frame.width, 34, accuracy: 1, "Each choice shows the same compact square image")
            XCTAssertLessThanOrEqual(icon.frame.height, 48, "Icon choices stay compact")
        }
        // The selected button's accessible bounds include its dot below the square image;
        // unselected buttons exclude the clear dot. Compare the image tops and square sizes.
        let imageFrames = choices.map { choice in
            let frame = choice.0.frame
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.width)
        }
        let tops = imageFrames.map(\.minY)
        XCTAssertLessThanOrEqual((tops.max() ?? 0) - (tops.min() ?? 0), 2, "All icon images share one row")
        XCTAssertLessThanOrEqual(picker.frame.height, 56, "The icon picker remains a compact row control")
        let textBlock = label.frame.union(subtitle.frame)
        for imageFrame in imageFrames {
            XCTAssertEqual(textBlock.midY, imageFrame.midY, accuracy: 3,
                           "Each icon image is vertically centered beside the title and subtitle")
        }
        XCTAssertEqual(choices.filter { $0.0.isSelected }.count, 1,
                       "The blue selection dot is also exposed through the selected accessibility trait")
    }

    @MainActor
    func testApplicationIconSelectionPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let window = try SettingsUITestSupport.openSettingsPage("General", in: app, testCase: self)
        let identifiers = ["colorTiles", "colorGrid", "darkGrid", "rocket"]
        let original = try XCTUnwrap(identifiers.first { applicationIcon($0, in: window).isSelected })
        let replacement = try XCTUnwrap(identifiers.first { $0 != original })
        addTeardownBlock { @MainActor in
            guard app.state == .runningForeground || app.state == .runningBackground else { return }
            let originalIcon = self.applicationIcon(original, in: SettingsUITestSupport.settingsWindow(in: app))
            if originalIcon.waitForExistence(timeout: 2), !originalIcon.isSelected {
                originalIcon.click()
            }
        }

        applicationIcon(replacement, in: window).click()
        XCTAssertTrue(applicationIcon(replacement, in: window).wait(for: \.isSelected, toEqual: true, timeout: 3))
        XCTAssertFalse(applicationIcon(original, in: window).isSelected)

        app.terminate()
        let reopenedWindow = try SettingsUITestSupport.openSettingsPage("General", in: app, testCase: self)
        XCTAssertTrue(applicationIcon(replacement, in: reopenedWindow).waitForExistence(timeout: 3))
        XCTAssertTrue(applicationIcon(replacement, in: reopenedWindow).isSelected)
        XCTAssertFalse(applicationIcon(original, in: reopenedWindow).isSelected)
    }

    @MainActor
    func testLanguageAndAppearanceMenusOfferTheSupportedChoices() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(en)", "-appLanguage", "en", "-appAppearance", "automatic", "-inMemoryDockStore", "YES"]
        try SettingsUITestSupport.launchAndOpenSettings(in: app, testCase: self)
        XCTAssertTrue(app.staticTexts["Language & Appearance"].waitForExistence(timeout: 5))

        let languagePicker = app.popUpButtons["appLanguagePicker"]
        XCTAssertTrue(languagePicker.waitForExistence(timeout: 5))
        languagePicker.click()
        for title in ["Follow System", "English", CatalogTestSupport.text("Simplified Chinese", locale: "zh-Hans"), CatalogTestSupport.text("Traditional Chinese", locale: "zh-Hant"), CatalogTestSupport.text("French", locale: "fr"), CatalogTestSupport.text("German", locale: "de"), CatalogTestSupport.text("Japanese", locale: "ja"), CatalogTestSupport.text("Korean", locale: "ko"), CatalogTestSupport.text("Spanish", locale: "es")] {
            XCTAssertTrue(app.menuItems[title].waitForExistence(timeout: 2), title)
        }
        app.typeKey(.escape, modifierFlags: [])

        let appearancePicker = app.popUpButtons["appAppearancePicker"]
        XCTAssertTrue(appearancePicker.exists)
        appearancePicker.click()
        for title in ["Auto", "Light", "Dark"] {
            XCTAssertTrue(app.menuItems[title].waitForExistence(timeout: 2), title)
        }
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testLanguagePickerUpdatesSettingsAndPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(en)", "-appAppearance", "automatic", "-inMemoryDockStore", "YES"]
        try SettingsUITestSupport.launchAndOpenSettings(in: app, testCase: self)
        let picker = app.popUpButtons["appLanguagePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let originalSelection = try XCTUnwrap(picker.value as? String)
        let autonyms = ["English", CatalogTestSupport.text("Simplified Chinese", locale: "zh-Hans"), CatalogTestSupport.text("Traditional Chinese", locale: "zh-Hant"), CatalogTestSupport.text("French", locale: "fr"), CatalogTestSupport.text("German", locale: "de"), CatalogTestSupport.text("Japanese", locale: "ja"), CatalogTestSupport.text("Korean", locale: "ko"), CatalogTestSupport.text("Spanish", locale: "es")]
        addTeardownBlock { @MainActor in
            picker.click()
            app.menuItems["English"].click()
            picker.click()
            app.menuItems[autonyms.contains(originalSelection) ? originalSelection : "Follow System"].click()
        }

        for (selection, label, appearanceChoices) in [
            (CatalogTestSupport.text("French", locale: "fr"), CatalogTestSupport.text("Language", locale: "fr"), [CatalogTestSupport.text("Auto", locale: "fr"), CatalogTestSupport.text("Light", locale: "fr"), CatalogTestSupport.text("Dark", locale: "fr")]),
            (CatalogTestSupport.text("Japanese", locale: "ja"), CatalogTestSupport.text("Language", locale: "ja"), [CatalogTestSupport.text("Auto", locale: "ja"), CatalogTestSupport.text("Light", locale: "ja"), CatalogTestSupport.text("Dark", locale: "ja")]),
            ("English", "Language", ["Auto", "Light", "Dark"])
        ] {
            picker.click()
            let item = app.menuItems[selection]
            XCTAssertTrue(item.waitForExistence(timeout: 2))
            item.click()
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 3))
            XCTAssertEqual(picker.value as? String, selection)
            let appearancePicker = app.popUpButtons["appAppearancePicker"]
            XCTAssertEqual(appearancePicker.value as? String, appearanceChoices[0])
            appearancePicker.click()
            for title in appearanceChoices {
                XCTAssertTrue(app.menuItems[title].waitForExistence(timeout: 2), app.debugDescription)
            }
            SettingsUITestSupport.settingsWindow(in: app).typeKey(.escape, modifierFlags: [])

            app.terminate()
            try SettingsUITestSupport.launchAndOpenSettings(in: app, testCase: self)
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            XCTAssertEqual(picker.value as? String, selection)
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testAppearancePickerPersistsSelectionAcrossRelaunch() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(en)", "-appLanguage", "en", "-inMemoryDockStore", "YES"]
        try SettingsUITestSupport.launchAndOpenSettings(in: app, testCase: self)
        let picker = app.popUpButtons["appAppearancePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let originalSelection = try XCTUnwrap(picker.value as? String)
        addTeardownBlock { @MainActor in
            if app.state == .runningForeground || app.state == .runningBackground {
                app.typeKey(",", modifierFlags: .command)
                if picker.waitForExistence(timeout: 3) {
                    picker.click()
                    let originalItem = app.menuItems[originalSelection]
                    if originalItem.waitForExistence(timeout: 2) { originalItem.click() }
                }
            }
        }

        for title in ["Light", "Dark", "Auto"] {
            picker.click()
            let item = app.menuItems[title]
            XCTAssertTrue(item.waitForExistence(timeout: 2))
            item.click()
            XCTAssertEqual(picker.value as? String, title)

            app.terminate()
            try SettingsUITestSupport.launchAndOpenSettings(in: app, testCase: self)
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            XCTAssertEqual(picker.value as? String, title)
        }
    }

    @MainActor
    private func dockText(_ text: String, in window: XCUIElement) -> XCUIElement {
        window.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@ OR title CONTAINS %@", text, text, text
        )).firstMatch
    }

    @MainActor
    private func applicationIcon(_ identifier: String, in window: XCUIElement) -> XCUIElement {
        window.descendants(matching: .any)["applicationIcon.\(identifier)"]
    }

}
