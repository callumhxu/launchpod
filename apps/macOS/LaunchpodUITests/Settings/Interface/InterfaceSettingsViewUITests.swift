import XCTest

final class InterfaceSettingsViewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testClassicalSectionHasDockAndLiquidGlassSwitchesAndOneIconGridRow() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let window = try SettingsUITestSupport.openSettingsPage("Interface", in: app, testCase: self)

        XCTAssertTrue(window.staticTexts["Classical"].waitForExistence(timeout: 3))
        let hideDock = window.switches["classicalHidesDockToggle"]
        XCTAssertTrue(hideDock.exists, window.debugDescription)
        XCTAssertEqual(window.switches.count, 2, "Hide Dock and Liquid Glass are the Classical switches")
        XCTAssertTrue(window.staticTexts["Hide Dock"].exists)
        XCTAssertTrue(window.staticTexts["Covers the Dock while Launchpod is shown full screen."].exists)
        XCTAssertTrue(window.staticTexts["Liquid Glass"].exists)
        XCTAssertFalse(window.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("iOS 27") },
                       "Settings should describe the native macOS glass option")
        XCTAssertTrue(window.switches["classicalFolderLiquidGlassToggle"].exists, window.debugDescription)
        XCTAssertTrue(window.staticTexts["Applies the next time Launchpod opens."].exists)

        // Columns and Rows share one Icon Grid row, each as a number field with its own stepper.
        XCTAssertTrue(window.staticTexts["Icon Grid"].exists, window.debugDescription)
        XCTAssertEqual(window.textFields.count, 2, window.debugDescription)
        for (identifier, label) in [("classicalColumnsStepper", "Columns"), ("classicalRowsStepper", "Rows")] {
            let stepper = window.steppers[identifier]
            XCTAssertTrue(stepper.exists, "\(identifier): \(window.debugDescription)")
            XCTAssertEqual(stepper.label, label)
            XCTAssertTrue(field(labeled: label, in: window).exists, label)
        }
        let columns = field(labeled: "Columns", in: window)
        let rows = field(labeled: "Rows", in: window)
        XCTAssertLessThan(columns.frame.minX, rows.frame.minX, "Columns come before Rows")
        XCTAssertEqual(columns.frame.midY, rows.frame.midY, accuracy: 1, "Both fields sit in one row")
    }

    @MainActor
    func testGridFieldsShowTheStepperValueAfterEachStep() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let window = try SettingsUITestSupport.openSettingsPage("Interface", in: app, testCase: self)

        for (identifier, label) in [("classicalColumnsStepper", "Columns"), ("classicalRowsStepper", "Rows")] {
            let stepper = window.steppers[identifier]
            let field = field(labeled: label, in: window)
            XCTAssertTrue(stepper.waitForExistence(timeout: 3), identifier)
            let original = try XCTUnwrap(Int(value(of: field)), identifier)
            addTeardownBlock { @MainActor in
                if (app.state == .runningForeground || app.state == .runningBackground),
                   field.exists, Int(self.value(of: field)) != original {
                    self.type(String(original), into: field)
                }
            }
            // Step toward the range interior so the change is visible at either bound, then step back.
            let (forward, back) = original > 2
                ? (stepper.decrementArrows.firstMatch, stepper.incrementArrows.firstMatch)
                : (stepper.incrementArrows.firstMatch, stepper.decrementArrows.firstMatch)
            let expected = original > 2 ? original - 1 : original + 1
            forward.click()
            XCTAssertEqual(Int(value(of: field)), expected, identifier)
            back.click()
            XCTAssertEqual(Int(value(of: field)), original, identifier)
        }
    }

    @MainActor
    func testTypedGridValuesAreClampedToTheSupportedRange() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let window = try SettingsUITestSupport.openSettingsPage("Interface", in: app, testCase: self)

        for label in ["Columns", "Rows"] {
            let field = field(labeled: label, in: window)
            XCTAssertTrue(field.waitForExistence(timeout: 3), label)
            let original = try XCTUnwrap(Int(value(of: field)), label)
            addTeardownBlock { @MainActor in
                // Restores the user's real grid if an assertion stopped the test early.
                if (app.state == .runningForeground || app.state == .runningBackground),
                   field.exists, Int(self.value(of: field)) != original {
                    self.type(String(original), into: field)
                }
            }
            // The Classical grid supports 2 through 100 in each dimension.
            for (typed, shown) in [("0", 2), ("500", 100)] {
                type(typed, into: field)
                XCTAssertEqual(Int(value(of: field)), shown, "\(label): typed \(typed)")
            }
            type(String(original), into: field)
            XCTAssertEqual(Int(value(of: field)), original, label)
        }
    }

    @MainActor
    private func field(labeled label: String, in window: XCUIElement) -> XCUIElement {
        window.textFields.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func value(of field: XCUIElement) -> String {
        field.value as? String ?? ""
    }

    @MainActor
    private func type(_ text: String, into field: XCUIElement) {
        field.doubleClick()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
        field.typeKey(.return, modifierFlags: [])
    }
}
