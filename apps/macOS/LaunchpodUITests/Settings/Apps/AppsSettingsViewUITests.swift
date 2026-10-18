import Darwin
import XCTest

final class AppsSettingsViewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppSourcesListsApplicationsFirstAndKeepsBuiltInFoldersFixed() throws {
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let window = try SettingsUITestSupport.openSettingsPage("Apps", in: app, testCase: self)

        XCTAssertTrue(window.staticTexts["App Sources"].waitForExistence(timeout: 3), window.debugDescription)
        // Built-in and added folders share one list instead of separate sections.
        XCTAssertFalse(window.staticTexts["Built-in App Folders"].exists)
        XCTAssertFalse(window.staticTexts["Added App Folders"].exists)

        // Each folder row names the folder and shows its full path beneath.
        let applications = window.staticTexts["/Applications"]
        let systemApplications = window.staticTexts["/System/Applications"]
        XCTAssertTrue(applications.exists, window.debugDescription)
        XCTAssertTrue(window.staticTexts["Applications"].exists)
        XCTAssertTrue(systemApplications.exists)
        XCTAssertLessThan(applications.frame.minY, systemApplications.frame.minY, "/Applications is listed first")

        let add = window.buttons["Add Folder…"]
        let remove = window.buttons["Remove Folder"]
        XCTAssertTrue(add.exists)
        XCTAssertTrue(add.isEnabled)
        XCTAssertTrue(remove.exists, window.debugDescription)
        XCTAssertFalse(remove.isEnabled, "Nothing is selected")
        assertMatchingFolderControls(add: add, remove: remove)

        applications.click()
        XCTAssertFalse(remove.isEnabled, "A built-in folder cannot be removed")
        systemApplications.click()
        XCTAssertFalse(remove.isEnabled, "A built-in folder cannot be removed")
    }

    @MainActor
    func testAddedFolderShowsItsNameAndPathAndCanBeRemovedOnceSelected() throws {
        let requestedFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Launchpod UI Test Apps \(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: requestedFolder, withIntermediateDirectories: true)
        // The open panel returns the filesystem path through /private/var; Foundation's
        // resolvingSymlinksInPath can shorten that path back to the /var alias.
        let resolved = try XCTUnwrap(requestedFolder.withUnsafeFileSystemRepresentation { path in
            path.flatMap { realpath($0, nil) }
        })
        let folder = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        free(resolved)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }

        let app = XCUIApplication()
        addTeardownBlock { @MainActor in app.terminate() }
        let window = try SettingsUITestSupport.openSettingsPage("Apps", in: app, testCase: self)
        let add = window.buttons["Add Folder…"]
        let remove = window.buttons["Remove Folder"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertFalse(remove.isEnabled)
        assertMatchingFolderControls(add: add, remove: remove)
        let controlSize = add.frame.size
        let disabled = XCTAttachment(screenshot: window.screenshot())
        disabled.name = "App-folder-controls-disabled"
        disabled.lifetime = .keepAlways
        self.add(disabled)
        let title = window.staticTexts[folder.lastPathComponent]
        let path = window.staticTexts[folder.path]
        XCTAssertFalse(title.exists)

        add.click()
        let panel = app.sheets["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), app.debugDescription)
        app.typeKey("g", modifierFlags: [.command, .shift])
        let goTo = app.sheets["GoToWindow"]
        XCTAssertTrue(goTo.waitForExistence(timeout: 5), app.debugDescription)
        let pathField = goTo.textFields["PathTextField"]
        XCTAssertTrue(pathField.waitForExistence(timeout: 3), goTo.debugDescription)
        pathField.click()
        pathField.typeKey("a", modifierFlags: [.command])
        pathField.typeText(folder.path)
        let pathEntered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", folder.path), object: pathField)
        XCTAssertEqual(XCTWaiter.wait(for: [pathEntered], timeout: 5), .completed,
                       "Go to Folder must contain the complete target directory path")
        pathField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(goTo.waitForNonExistence(timeout: 5), panel.debugDescription)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let open = panel.buttons["OKButton"]
        let readyToOpen = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"),
            object: open)
        XCTAssertEqual(XCTWaiter.wait(for: [readyToOpen], timeout: 5), .completed,
                       panel.debugDescription)
        open.click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), app.debugDescription)

        XCTAssertTrue(title.waitForExistence(timeout: 5), window.debugDescription)
        XCTAssertTrue(path.exists, window.debugDescription)
        addTeardownBlock { @MainActor in
            // Leaves the user's real folder list as it was if an assertion stopped the test early.
            if (app.state == .runningForeground || app.state == .runningBackground), title.exists {
                title.click()
                remove.click()
            }
        }

        title.click()
        XCTAssertTrue(remove.isEnabled, "A selected added folder can be removed")
        assertMatchingFolderControls(add: add, remove: remove)
        XCTAssertEqual(add.frame.width, controlSize.width, accuracy: 1)
        XCTAssertEqual(add.frame.height, controlSize.height, accuracy: 1,
                       "Selection must not resize the folder controls")
        let enabled = XCTAttachment(screenshot: window.screenshot())
        enabled.name = "App-folder-controls-enabled"
        enabled.lifetime = .keepAlways
        self.add(enabled)
        remove.click()
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))
        XCTAssertFalse(path.exists)
        XCTAssertFalse(remove.isEnabled, "Removing the folder clears the selection")
        assertMatchingFolderControls(add: add, remove: remove)

        // Removal is persisted, not only hidden.
        app.terminate()
        let reopened = try SettingsUITestSupport.openSettingsPage("Apps", in: app, testCase: self)
        XCTAssertTrue(reopened.buttons["Add Folder…"].waitForExistence(timeout: 3))
        XCTAssertFalse(reopened.staticTexts[folder.lastPathComponent].exists)
    }

    @MainActor
    private func assertMatchingFolderControls(add: XCUIElement, remove: XCUIElement,
                                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(add.frame.width, remove.frame.width, accuracy: 1,
                       "Add and Remove have the same rendered width", file: file, line: line)
        XCTAssertEqual(add.frame.height, remove.frame.height, accuracy: 1,
                       "Add and Remove have the same rendered height regardless of enabled state", file: file, line: line)
        XCTAssertEqual(add.frame.midY, remove.frame.midY, accuracy: 1,
                       "The folder controls align on one row", file: file, line: line)
        for control in [add, remove] {
            XCTAssertGreaterThan(control.frame.height, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(control.frame.width, 48, "Folder controls stay compact", file: file, line: line)
            XCTAssertLessThanOrEqual(control.frame.height, 32, "Folder controls stay compact", file: file, line: line)
        }
    }

}
