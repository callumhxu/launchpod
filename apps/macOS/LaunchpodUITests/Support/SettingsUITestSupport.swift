import XCTest

/// Launches Launchpod in English and reaches a settings page through ⌘, and the native toolbar.
enum SettingsUITestSupport {
    @MainActor
    static func openSettingsPage(_ title: String, in app: XCUIApplication, testCase: XCTestCase) throws -> XCUIElement {
        app.launchArguments = ["-AppleLanguages", "(en)", "-appLanguage", "en", "-inMemoryDockStore", "YES"]
        let window = try launchAndOpenSettings(in: app, testCase: testCase)
        XCTAssertEqual(window.title, "Settings")
        let tab = window.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(tab.exists, title)
        tab.click()
        return window
    }

    /// The launcher loads its presentation after the process launches. Route the shortcut only
    /// after its native panel is visible, using the panel's stable identifier across AX roles.
    @MainActor
    @discardableResult
    static func launchAndOpenSettings(in app: XCUIApplication, testCase: XCTestCase) throws -> XCUIElement {
        var arguments = app.launchArguments
        while let index = arguments.firstIndex(of: "-hasCompletedOnboarding") {
            arguments.removeSubrange(index..<min(index + 2, arguments.count))
        }
        app.launchArguments = arguments + ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let launcher = try readyLauncher(in: app)
        try KeyboardInputSourceSupport.prepareCommaShortcut(for: testCase)
        launcher.typeKey(",", modifierFlags: .command)
        let window = settingsWindow(in: app)
        guard window.waitForExistence(timeout: 5) else {
            XCTFail("Command-comma must open the settings panel.\n\(app.debugDescription)")
            throw ReadinessError.settingsUnavailable
        }
        return window
    }

    @MainActor
    static func readyLauncher(in app: XCUIApplication) throws -> XCUIElement {
        let launcher = app.descendants(matching: .any)["launcherPlaceholderWindow"]
        func waitForReadyLauncher() -> Bool {
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND hittable == true"), object: launcher
            )
            return XCTWaiter.wait(for: [ready], timeout: 5) == .completed
        }
        if waitForReadyLauncher() { return launcher }
        // Classical can dismiss when another app takes focus during XCTest launch.
        let statusItem = app.statusItems["launcherStatusItem"]
        if statusItem.waitForExistence(timeout: 2), statusItem.isHittable {
            statusItem.click()
        }
        guard waitForReadyLauncher() else {
            XCTFail("The launcher panel must be visible before sending Command-comma.\n\(app.debugDescription)")
            throw ReadinessError.launcherUnavailable
        }
        return launcher
    }

    @MainActor
    static func settingsWindow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["settingsWindow"]
    }

    private enum ReadinessError: Error {
        case launcherUnavailable, settingsUnavailable
    }
}
