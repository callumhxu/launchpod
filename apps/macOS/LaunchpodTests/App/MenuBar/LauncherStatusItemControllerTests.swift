import AppKit
import Combine
import XCTest
@testable import Launchpod

@MainActor
final class LauncherStatusItemControllerTests: XCTestCase {
    func testNativeStatusItemUsesAutomaticWidthAndSeparatesLeftAndRightClicks() throws {
        let preference = try makePreference()
        var toggles = 0
        var menus = 0
        var presentedMenu: NSMenu?
        let controller = LauncherStatusItemController(
            languagePreference: preference, softwareUpdates: makeUpdates(), toggle: { toggles += 1 }, openSettings: {}, restart: {},
            showMenu: { _, menu in
                menus += 1
                presentedMenu = menu
            }
        )
        defer { controller.stop() }
        let item = try XCTUnwrap(controller.statusItem)
        let button = try XCTUnwrap(item.button)
        XCTAssertEqual(item.length, NSStatusItem.variableLength)
        XCTAssertNil(item.menu)
        XCTAssertNotNil(button.image)
        XCTAssertTrue(button.image?.isTemplate == true)
        XCTAssertEqual(button.title, "")

        button.performClick(nil)
        XCTAssertEqual(toggles, 1)
        XCTAssertEqual(menus, 0)
        controller.handleClick(try mouseEvent(.rightMouseUp))
        XCTAssertEqual(toggles, 1)
        XCTAssertEqual(menus, 1)
        XCTAssertTrue(presentedMenu === controller.menu)
        controller.handleClick(try mouseEvent(.leftMouseUp))
        XCTAssertEqual(toggles, 2)
        XCTAssertEqual(menus, 1)
        XCTAssertNil(item.menu)
    }

    func testNativeMenuItemsInvokeOnlyTheirCorrespondingActions() throws {
        var toggles = 0
        var settings = 0
        var restarts = 0
        var quits = 0
        let controller = LauncherStatusItemController(
            languagePreference: try makePreference(), softwareUpdates: makeUpdates(), toggle: { toggles += 1 },
            openSettings: { settings += 1 }, restart: { restarts += 1 }, quit: { quits += 1 }
        )
        defer { controller.stop() }
        XCTAssertEqual(controller.menu.numberOfItems, 7)
        XCTAssertTrue(controller.menu.items[1].isSeparatorItem)
        XCTAssertTrue(controller.menu.items[4].isSeparatorItem)
        XCTAssertNil(controller.menu.items[2].image)
        controller.menu.performActionForItem(at: 0)
        XCTAssertEqual(toggles, 1)
        XCTAssertEqual(settings, 0)
        XCTAssertEqual(quits, 0)
        controller.menu.performActionForItem(at: 2)
        XCTAssertEqual(toggles, 1)
        XCTAssertEqual(settings, 1)
        XCTAssertEqual(quits, 0)
        XCTAssertEqual(restarts, 0)
        controller.menu.performActionForItem(at: 5)
        XCTAssertEqual(restarts, 1)
        XCTAssertEqual(quits, 0)
        controller.menu.performActionForItem(at: 6)
        XCTAssertEqual(toggles, 1)
        XCTAssertEqual(settings, 1)
        XCTAssertEqual(quits, 1)
    }

    func testMenuRefreshUsesTheCurrentAppLanguage() throws {
        try XCTSkipUnless(Bundle(for: AppDelegate.self).bundleURL == Bundle.main.bundleURL
                          && Bundle.main.bundleURL.pathExtension == "app", "Requires the application host and compiled localization catalog.")
        let preference = try makePreference()
        let controller = LauncherStatusItemController(languagePreference: preference, softwareUpdates: makeUpdates(), toggle: {}, openSettings: {}, restart: {})
        defer { controller.stop() }
        for (language, toggle, settings, update, restart, quit) in [
            (AppLanguage.english, "Toggle Launchpod", "Settings…", "Check for Updates…", "Restart Launchpod", "Quit Launchpod"),
            (.simplifiedChinese, CatalogTestSupport.text("Show or Hide Launchpod", locale: "zh-Hans"), CatalogTestSupport.text("Settings", locale: "zh-Hans") + "…", CatalogTestSupport.text("Check for Updates…", locale: "zh-Hans"), CatalogTestSupport.text("Restart Launchpod", locale: "zh-Hans"), CatalogTestSupport.text("Quit Launchpod", locale: "zh-Hans")),
            (.japanese, CatalogTestSupport.text("Show or Hide Launchpod", locale: "ja"), CatalogTestSupport.text("Settings", locale: "ja") + "…", CatalogTestSupport.text("Check for Updates…", locale: "ja"), CatalogTestSupport.text("Restart Launchpod", locale: "ja"), CatalogTestSupport.text("Quit Launchpod", locale: "ja"))
        ] {
            preference.selection = language
            controller.refreshMenu()
            XCTAssertEqual(controller.menu.items[0].title, toggle)
            XCTAssertEqual(controller.menu.items[2].title, settings)
            XCTAssertEqual(controller.menu.items[3].title, update)
            XCTAssertEqual(controller.menu.items[5].title, restart)
            XCTAssertEqual(controller.menu.items[6].title, quit)
        }
    }

    func testStopRemovesTheNativeStatusItemAndIsRepeatable() throws {
        var toggles = 0
        let controller = LauncherStatusItemController(languagePreference: try makePreference(), softwareUpdates: makeUpdates(), toggle: { toggles += 1 }, openSettings: {}, restart: {})
        let button = try XCTUnwrap(controller.statusItem?.button)
        controller.stop()
        XCTAssertNil(controller.statusItem)
        XCTAssertNil(button.target)
        XCTAssertNil(button.action)
        controller.handleClick(try mouseEvent(.leftMouseUp))
        XCTAssertEqual(toggles, 0)
        controller.stop()
        XCTAssertNil(controller.statusItem)
    }

    func testUpdateMenuUsesDiscoveryForItsBadgeAndForwardsChecksToTheSharedController() throws {
        let driver = StatusMenuUpdateDriver()
        let updates = makeUpdates(driver: driver)
        let controller = LauncherStatusItemController(
            languagePreference: try makePreference(), softwareUpdates: updates,
            toggle: {}, openSettings: {}, restart: {}
        )
        defer { controller.stop() }
        let item = controller.menu.items[3]
        XCTAssertEqual(item.title, "Check for Updates…")
        XCTAssertNil(item.image)
        XCTAssertTrue(controller.validateMenuItem(item))
        controller.menu.performActionForItem(at: 3)
        XCTAssertEqual(driver.checkCount, 1)
        driver.updates.send(true)
        XCTAssertNotNil(item.image)
        driver.availability.send(false)
        XCTAssertFalse(controller.validateMenuItem(item))
        XCTAssertFalse(item.isEnabled)
        XCTAssertNotNil(item.image)
        driver.updates.send(false)
        XCTAssertNil(item.image)
    }

    private func makeUpdates(driver: StatusMenuUpdateDriver? = nil) -> SoftwareUpdateController {
        let driver = driver ?? StatusMenuUpdateDriver()
        let configuration = SoftwareUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://updates.example.test/appcast.xml", "SUPublicEDKey": "test-key"
        ])
        return SoftwareUpdateController(configuration: configuration) { driver }
    }

    private func makePreference() throws -> AppLanguagePreference {
        _ = NSApplication.shared
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        addTeardownBlock { try preferences.cleanup() }
        return AppLanguagePreference(defaults: defaults, preferredLanguages: { ["en-US"] })
    }

    private func mouseEvent(_ type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
    }
}

@MainActor
private final class StatusMenuUpdateDriver: SoftwareUpdateDriving {
    let availability = CurrentValueSubject<Bool, Never>(true)
    let updates = CurrentValueSubject<Bool, Never>(false)
    private(set) var checkCount = 0
    var canCheckForUpdates: Bool { availability.value }
    var hasAvailableUpdate: Bool { updates.value }
    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> { availability.eraseToAnyPublisher() }
    var hasAvailableUpdatePublisher: AnyPublisher<Bool, Never> { updates.eraseToAnyPublisher() }
    func checkForUpdates() { checkCount += 1 }
}
