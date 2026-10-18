import AppKit
import XCTest
@testable import Launchpod

// Run with parallel testing disabled: these tests own native windows and keyboard focus.
@MainActor
final class ClassicalWindowControllerTests: XCTestCase {
    func testPresentationUsesWholeScreenAndCompletesWithKeyboardFocus() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        let presentationOptions = NSApp.presentationOptions
        var menuRequests: [String] = []
        var panel: NSWindow?
        let menu = menuVisibility { request in
            XCTAssertEqual(panel?.isVisible == true, request == "hide")
            menuRequests.append(request)
        }
        var selectedScreen: NSScreen?
        let controller = ClassicalWindowController(desktopImage: { screen in
            selectedScreen = screen
            return image
        }, presentError: { XCTFail("Unexpected image error: \($0)") }, menuBarVisibility: menu)
        panel = controller.window
        defer { controller.stop() }
        var results: [Bool] = []
        controller.setVisible(true) { success in
            results.append(success)
            if success {
                XCTAssertTrue(controller.window?.isKeyWindow == true)
                XCTAssertTrue(controller.window?.firstResponder === controller.window?.initialFirstResponder)
            }
        }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion delivers a result", state: { "results=\(String(describing: results))" }) { !results.isEmpty }
        XCTAssertEqual(results, [true])
        let window = try XCTUnwrap(controller.window)
        let screen = try XCTUnwrap(selectedScreen)
        XCTAssertEqual(window.frame, screen.frame)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(window.level.rawValue, 19)
        XCTAssertLessThan(window.level.rawValue, Int(CGWindowLevelForKey(.dockWindow)))
        XCTAssertEqual(window.identifier, AppShortcutFocus.launcherWindowIdentifier)
        XCTAssertEqual(window.contentView?.bounds.size, screen.frame.size)
        XCTAssertTrue(controller.isVisible)
        // The window server does not render an application-defined CIFilter subclass set as a layer's
        // compositing filter; the whole launcher then draws nothing.
        let host = try XCTUnwrap(window.contentView?.layer)
        let appFilters = LayerCompositingFilters.all(in: host).filter { LayerCompositingFilters.isApplicationDefinedCIFilter($0.filter) }
        XCTAssertTrue(appFilters.isEmpty, "Application-defined compositing filters: \(appFilters.map(\.filter))")
        // Core Image layer filters would replace Core Animation's named filters such as plusD.
        XCTAssertFalse(window.contentView?.layerUsesCoreImageFilters ?? true)
        XCTAssertEqual(menuRequests, ["hide"])
        XCTAssertEqual(NSApp.presentationOptions, presentationOptions)

        var hidden: [Bool] = []
        controller.setVisible(false) { success in
            hidden.append(success)
            XCTAssertFalse(window.isVisible)
        }
        try await NativeAppTestSupport.waitUntil(description: "dismissal completion delivers a result", state: { "hidden=\(String(describing: hidden))" }) { !hidden.isEmpty }
        XCTAssertEqual(hidden, [true])
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(menuRequests, ["hide", "reset"])
        XCTAssertEqual(NSApp.presentationOptions, presentationOptions)
    }

    func testFailedWallpaperNeverPresentsAndReportsFailureOnce() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        var errors = 0
        var menuRequests: [String] = []
        let controller = ClassicalWindowController(desktopImage: { _ in
            throw FixtureError.unavailable
        }, presentError: { _ in errors += 1 }, menuBarVisibility: menuVisibility { menuRequests.append($0) })
        defer { controller.stop() }
        var dismissals = 0
        controller.onDismiss = {
            XCTAssertFalse(controller.isVisible)
            dismissals += 1
        }
        var results: [Bool] = []
        controller.setVisible(true) { results.append($0) }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion delivers a result", state: { "results=\(String(describing: results))" }) { !results.isEmpty }
        XCTAssertEqual(results, [false])
        XCTAssertEqual(errors, 1)
        XCTAssertEqual(dismissals, 1)
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(controller.window?.isVisible == true)
        XCTAssertTrue(menuRequests.isEmpty)
    }

    func testHideDuringWallpaperLoadRejectsOldShowAndLateImageCannotReopen() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let load = PendingImage()
        let image = try fixtureImage()
        var menuRequests: [String] = []
        let controller = ClassicalWindowController(desktopImage: { _ in try await load.image() },
            presentError: { XCTFail("Unexpected error: \($0)") },
            menuBarVisibility: menuVisibility { menuRequests.append($0) })
        defer { controller.stop() }
        var shown: [Bool] = []
        var hidden: [Bool] = []
        controller.setVisible(true) { shown.append($0) }
        try await NativeAppTestSupport.waitUntil(description: "wallpaper loader starts and suspends", state: { "load.continuation != nil=\(String(describing: load.continuation != nil))" }) { load.continuation != nil }
        XCTAssertFalse(controller.isVisible)
        controller.setVisible(false) { hidden.append($0) }
        try await NativeAppTestSupport.waitUntil(description: "dismissal completion delivers a result", state: { "hidden=\(String(describing: hidden))" }) { !hidden.isEmpty }
        XCTAssertEqual(shown, [false])
        XCTAssertTrue(menuRequests.isEmpty)
        XCTAssertEqual(hidden, [true])
        load.complete(with: image)
        await drainTasks()
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(shown, [false])
        XCTAssertTrue(menuRequests.isEmpty)
    }

    func testStopWhileLoadingReleasesWindowAndIgnoresLateFailure() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let load = PendingImage()
        var errors = 0
        let controller = ClassicalWindowController(desktopImage: { _ in try await load.image() },
                                                   presentError: { _ in errors += 1 })
        var results: [Bool] = []
        var dismissed = 0
        controller.onDismiss = { dismissed += 1 }
        controller.setVisible(true) { results.append($0) }
        try await NativeAppTestSupport.waitUntil(description: "wallpaper loader starts and suspends", state: { "load.continuation != nil=\(String(describing: load.continuation != nil))" }) { load.continuation != nil }
        let window = controller.window
        controller.stop()
        XCTAssertEqual(results, [false])
        XCTAssertNil(controller.window)
        XCTAssertFalse(window?.isVisible == true)
        load.fail()
        await drainTasks()
        XCTAssertEqual(errors, 0)
        XCTAssertEqual(dismissed, 0)
        controller.setVisible(true) { results.append($0) }
        XCTAssertEqual(results, [false, false])
    }

    func testEscapeDismissesOnlyAfterWindowIsHiddenAndCanReopen() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        var menuRequests: [String] = []
        let controller = ClassicalWindowController(desktopImage: { _ in image },
            menuBarVisibility: menuVisibility { menuRequests.append($0) })
        defer { controller.stop() }
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        let window = try XCTUnwrap(controller.window)
        var dismissals = 0
        controller.onDismiss = {
            dismissals += 1
            XCTAssertFalse(window.isVisible)
        }
        window.cancelOperation(nil)
        try await NativeAppTestSupport.waitUntil(description: "dismissal callback fires exactly once", state: { "dismissals=\(String(describing: dismissals))" }) { dismissals == 1 }
        XCTAssertFalse(controller.isVisible)
        shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(menuRequests, ["hide", "reset", "hide"])
    }

    func testOwnedFocusTransferIsRetainedAndOrdinaryTransferDismisses() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        let controller = ClassicalWindowController(desktopImage: { _ in image })
        let other = NSPanel(contentRect: CGRect(x: 10, y: 10, width: 100, height: 100),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close(); controller.stop() }
        let retains = MainActorBox(true)
        var dismissals = 0
        controller.retainsFocusForOwnedInteraction = { retains.value }
        controller.onDismiss = { dismissals += 1 }
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        other.orderFrontRegardless()
        other.makeKey()
        try await NativeAppTestSupport.waitUntil(description: "owned interaction panel takes key focus") { other.isKeyWindow }
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(dismissals, 0)
        shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        retains.value = false
        other.makeKey()
        try await NativeAppTestSupport.waitUntil(description: "dismissal callback fires exactly once", state: { "dismissals=\(String(describing: dismissals))" }) { dismissals == 1 }
        XCTAssertFalse(controller.isVisible)
    }

    func testReopenDuringExitDoesNotLetOldCleanupHideNewPresentation() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        var menuRequests: [String] = []
        let controller = ClassicalWindowController(desktopImage: { _ in image },
            menuBarVisibility: menuVisibility { menuRequests.append($0) })
        defer { controller.stop() }
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        var hiddenResults: [Bool] = []
        var reopenResults: [Bool] = []
        controller.setVisible(false) { hiddenResults.append($0) }
        controller.setVisible(true) { reopenResults.append($0) }
        try await NativeAppTestSupport.waitUntil(description: "reopened presentation delivers a result", state: { "reopenResults=\(String(describing: reopenResults)), hiddenResults=\(String(describing: hiddenResults))" }) { !reopenResults.isEmpty }
        XCTAssertEqual(reopenResults, [true])
        XCTAssertEqual(hiddenResults.count, 1)
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(controller.window?.isKeyWindow == true)
        let host = try XCTUnwrap(controller.window?.contentView?.layer)
        XCTAssertEqual(host.sublayers?.count, 1)
        XCTAssertEqual(menuRequests, ["hide", "reset", "hide"])
    }

    func testReleasingControllerDuringLoadDoesNotKeepWindowAlive() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let load = PendingImage()
        var controller: ClassicalWindowController? = ClassicalWindowController(
            desktopImage: { _ in try await load.image() }, presentError: { XCTFail("Late error: \($0)") })
        weak let owner = controller
        let window = controller?.window
        controller?.setVisible(true) { _ in }
        try await NativeAppTestSupport.waitUntil(description: "wallpaper loader starts and suspends", state: { "load.continuation != nil=\(String(describing: load.continuation != nil))" }) { load.continuation != nil }
        controller = nil
        XCTAssertNil(owner)
        XCTAssertNil(window?.delegate)
        XCTAssertFalse(window?.isVisible == true)
        load.fail()
        await drainTasks()
        XCTAssertFalse(window?.isVisible == true)
    }

    func testBlankClickDismissesOnReleaseAndADragDoesNot() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        let controller = ClassicalWindowController(desktopImage: { _ in image })
        defer { controller.stop() }
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        var dismissals = 0
        controller.onDismiss = {
            XCTAssertFalse(window.isVisible)
            dismissals += 1
        }
        let center = CGPoint(x: window.frame.width / 2, y: window.frame.height / 2)
        func mouse(_ type: NSEvent.EventType, _ location: CGPoint, _ time: TimeInterval) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: time,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                                             clickCount: 1, pressure: 1))
        }
        content.mouseDown(with: try mouse(.leftMouseDown, center, 0))
        content.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: center.x, y: center.y + 3), 0.1))
        content.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: center.x, y: center.y + 3), 0.2))
        XCTAssertTrue(controller.isVisible, "A press that moved 3 pt is not a click")

        content.mouseDown(with: try mouse(.leftMouseDown, center, 1))
        XCTAssertTrue(controller.isVisible, "The press alone does not dismiss")
        content.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: center.x + 2, y: center.y), 1.1))
        content.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: center.x + 2, y: center.y), 1.2))
        try await NativeAppTestSupport.waitUntil(description: "dismissal callback fires exactly once", state: { "dismissals=\(String(describing: dismissals))" }) { dismissals == 1 }
        XCTAssertFalse(controller.isVisible)
    }

    /// The launcher starts closing as soon as it submits the open request, without waiting for the app.
    func testClickingAnIconSubmitsTheLaunchAndClosesImmediately() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        let url = URL(filePath: "/Applications/Safari.app", directoryHint: .isDirectory)
        let safari = AppRecord(
            id: AppIdentity(),
            metadata: try AppMetadata(bundleIdentifier: "com.example.\(UUID().uuidString)", bundleURL: url,
                                      displayName: "Safari", version: nil, buildVersion: nil, contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: url.deletingLastPathComponent())
        )
        let controller = ClassicalWindowController(desktopImage: { _ in image })
        defer { controller.stop() }
        var pageContent = ClassicalPageContent(records: { [safari] }, icon: { _, _ in image })
        var markedOpened: [AppIdentity] = []
        pageContent.didOpen = { markedOpened.append($0) }
        controller.pageContent = pageContent
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView as? ClassicalContentView)
        let springboard = try XCTUnwrap(content.springboard)
        let cell = try XCTUnwrap(springboard.cell(for: safari.id))
        try await NativeAppTestSupport.waitUntil(description: "application icon finishes loading") { cell.iconLayer.contents != nil }
        var launched: [AppIdentity] = []
        var dismissals = 0
        var displays: [CGDirectDisplayID?] = []
        controller.openApplication = { launched.append($0.id); displays.append($1) }
        controller.canOpenApplication = { _ in true }
        controller.onDismiss = { dismissals += 1 }
        let host = try XCTUnwrap(content.layer)
        let icon = cell.iconLayer.convert(cell.iconLayer.bounds, to: host)
        let center = CGPoint(x: icon.midX, y: icon.midY)
        func mouse(_ type: NSEvent.EventType, _ time: TimeInterval) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: center, modifierFlags: [], timestamp: time,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                                             clickCount: 1, pressure: 1))
        }
        content.mouseDown(with: try mouse(.leftMouseDown, 0))
        content.mouseUp(with: try mouse(.leftMouseUp, 0.1))
        XCTAssertEqual(launched, [safari.id])
        XCTAssertEqual(markedOpened, [safari.id])
        XCTAssertEqual(displays, [window.screen?.displayNumber?.uint32Value], "It opens on the launcher's display")
        XCTAssertEqual(ClassicalApplicationOpener.launchFlags.rawValue, 0x45, "Launch flags include kLSLaunchAndDisplayErrors")
        XCTAssertEqual(ClassicalApplicationOpener.displayKeyword, 0x6469_7370)
        XCTAssertTrue(host.sublayers?.contains { $0.animation(forKey: "opacity") != nil } == true, "The icon's open animation plays")
        try await NativeAppTestSupport.waitUntil(description: "dismissal callback fires exactly once", state: { "dismissals=\(String(describing: dismissals))" }) { dismissals == 1 }
        XCTAssertFalse(controller.isVisible)
    }

    /// A missing application is neither opened nor closes the launcher.
    func testClickingAMissingApplicationKeepsTheLauncherOpen() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        let url = URL(filePath: "/Applications/Removed \(UUID().uuidString).app", directoryHint: .isDirectory)
        let removed = AppRecord(
            id: AppIdentity(),
            metadata: try AppMetadata(bundleIdentifier: "com.example.\(UUID().uuidString)", bundleURL: url,
                                      displayName: "Removed", version: nil, buildVersion: nil, contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: url.deletingLastPathComponent())
        )
        let controller = ClassicalWindowController(desktopImage: { _ in image })
        defer { controller.stop() }
        var pageContent = ClassicalPageContent(records: { [removed] }, icon: { _, _ in image })
        var markedOpened: [AppIdentity] = []
        pageContent.didOpen = { markedOpened.append($0) }
        controller.pageContent = pageContent
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView as? ClassicalContentView)
        let cell = try XCTUnwrap(content.springboard?.cell(for: removed.id))
        try await NativeAppTestSupport.waitUntil(description: "application icon finishes loading") { cell.iconLayer.contents != nil }
        var opened = 0
        controller.openApplication = { _, _ in opened += 1 }
        let icon = cell.iconLayer.convert(cell.iconLayer.bounds, to: try XCTUnwrap(content.layer))
        let center = CGPoint(x: icon.midX, y: icon.midY)
        for (type, time) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseUp, 0.1)] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: center, modifierFlags: [], timestamp: time,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                                                         clickCount: 1, pressure: 1))
            type == .leftMouseDown ? content.mouseDown(with: event) : content.mouseUp(with: event)
        }
        XCTAssertEqual(opened, 0)
        XCTAssertTrue(markedOpened.isEmpty)
        XCTAssertTrue(controller.isVisible)
    }

    func testAcceptedIconOpenClearsPersistedRecentlyAddedFlag() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let appURL = try fixture.application("New.app", in: apps, identifier: "com.example.New")
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let initial = await ApplicationCatalog(directories: [directory], scanner: ApplicationScanner()).refresh()
        var recentlyAdded = try XCTUnwrap(initial.records.first)
        recentlyAdded.isRecentlyAdded = true
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        try await store.save(AppData(records: [recentlyAdded]))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { XCTFail("Discovery error: \($0)") })
        defer { Task { try? await services.stop() } }
        try await services.start()
        try await NativeAppTestSupport.waitUntil(description: "discovery publishes the seeded recently added application") { services.hasCurrentScan && services.availableRecords.first?.id == recentlyAdded.id }
        XCTAssertEqual(services.availableRecords.first?.isRecentlyAdded, true)

        let image = try fixtureImage()
        let controller = ClassicalWindowController(desktopImage: { _ in image })
        defer { controller.stop() }
        let layout = ClassicalLayoutModel(store: nil)
        controller.pageContent = ClassicalPageContent(services: services, layout: layout)
        var submitted: [URL] = []
        controller.openApplication = { record, _ in submitted.append(record.metadata.bundleURL) }
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView as? ClassicalContentView)
        let cell = try XCTUnwrap(content.springboard?.cell(for: recentlyAdded.id))
        cell.setIcon(image)
        XCTAssertNotNil(cell.flagLayer)
        let icon = cell.iconLayer.convert(cell.iconLayer.bounds, to: try XCTUnwrap(content.layer))
        let center = CGPoint(x: icon.midX, y: icon.midY)
        for (type, time) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseUp, 0.1)] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: center, modifierFlags: [], timestamp: time,
                                                         windowNumber: window.windowNumber, context: nil,
                                                         eventNumber: 1, clickCount: 1, pressure: 1))
            type == .leftMouseDown ? content.mouseDown(with: event) : content.mouseUp(with: event)
        }
        XCTAssertEqual(submitted, [appURL], "The existing bundle passes the production availability check")
        try await NativeAppTestSupport.waitUntil(description: "accepted launch clears recently added state") { services.availableRecords.first?.isRecentlyAdded == false }
        try await services.stop()
        let saved = try await store.load()
        XCTAssertEqual(saved?.records.first?.isRecentlyAdded, false)
    }

    func testScreenParameterNotificationRefreshesVisibleDesktopAndIsInertAfterStop() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let initial = try fixtureImage()
        let replacement = try fixtureImage()
        var loads = 0
        var selectedScreen: NSScreen?
        var menuRequests: [String] = []
        let controller = ClassicalWindowController(desktopImage: { screen in
            selectedScreen = screen
            loads += 1
            return loads == 1 ? initial : replacement
        }, presentError: { XCTFail("Unexpected refresh error: \($0)") },
            menuBarVisibility: menuVisibility { menuRequests.append($0) })
        defer { controller.stop() }
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        let window = try XCTUnwrap(controller.window)
        let root = try XCTUnwrap(window.contentView?.layer?.sublayers?.first)
        let desktop = try XCTUnwrap(root.sublayers?.first?.sublayers?.first)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                        object: NSApplication.shared)
        try await NativeAppTestSupport.waitUntil(description: "desktop refresh installs replacement image") { desktop.contents as AnyObject? === replacement }
        XCTAssertGreaterThanOrEqual(loads, 2)
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(window.frame, try XCTUnwrap(selectedScreen).frame)
        XCTAssertTrue(window.contentView?.layer?.sublayers?.first === root)
        XCTAssertEqual(menuRequests, ["hide"])
        controller.stop()
        let completedLoads = loads
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                        object: NSApplication.shared)
        await drainTasks()
        XCTAssertEqual(loads, completedLoads)
        XCTAssertNil(controller.window)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(menuRequests, ["hide", "reset"])
    }

    func testTransparentWindowResetsMenuAndOnlyVisibleRecoveryRequestsAlphaZeroAgain() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        var requests: [String] = []
        let controller = ClassicalWindowController(desktopImage: { _ in image },
            menuBarVisibility: menuVisibility { requests.append($0) })
        defer { controller.stop() }
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(requests, ["hide"])
        window.alphaValue = 0
        window.alphaValue = 0
        XCTAssertEqual(requests, ["hide", "reset"])
        XCTAssertTrue(window.isVisible)
        let root = try XCTUnwrap(window.contentView?.layer?.sublayers?.first)
        window.orderOut(nil)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(requests, ["hide", "reset"])
        window.orderFrontRegardless()
        window.alphaValue = 1
        XCTAssertEqual(requests, ["hide", "reset", "hide"])
        XCTAssertTrue(window.contentView?.layer?.sublayers?.first === root)
        window.alphaValue = 0
        controller.setVisible(false)
        try await NativeAppTestSupport.waitUntil(description: "native window finishes hiding") { !window.isVisible }
        window.alphaValue = 1
        XCTAssertEqual(requests, ["hide", "reset", "hide", "reset"])
        controller.stop()
        window.alphaValue = 0
        window.alphaValue = 1
        XCTAssertEqual(requests, ["hide", "reset", "hide", "reset"])
    }

    func testRestoringInitiallyHiddenWindowCancelsTransparentPresentationWithoutMenuOverride() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        for imageFinishesBeforeRestore in [false, true] {
            let load = PendingImage()
            var loads = 0
            var requests: [String] = []
            let controller = ClassicalWindowController(desktopImage: { _ in
                loads += 1
                return loads == 1 ? try await load.image() : image
            }, menuBarVisibility: menuVisibility { requests.append($0) })
            defer { controller.stop() }
            var shown: [Bool] = []
            controller.setVisible(true) { shown.append($0) }
            try await NativeAppTestSupport.waitUntil(description: "wallpaper loader starts and suspends", state: { "load.continuation != nil=\(String(describing: load.continuation != nil))" }) { load.continuation != nil }
            let window = try XCTUnwrap(controller.window)
            window.alphaValue = 0
            if imageFinishesBeforeRestore {
                load.complete(with: image)
                try await NativeAppTestSupport.waitUntil(description: "native window becomes visible") { window.isVisible }
            }
            XCTAssertTrue(requests.isEmpty)
            XCTAssertTrue(shown.isEmpty)
            window.orderOut(nil)
            window.alphaValue = 1
            if !imageFinishesBeforeRestore { load.complete(with: image) }
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                            object: NSApplication.shared)
            await drainTasks()
            XCTAssertEqual(loads, 1)
            XCTAssertFalse(window.isVisible)
            XCTAssertTrue(requests.isEmpty)
            XCTAssertEqual(shown, [false])
        }
    }

    func testNativeCloseOrOrderOutDuringRefreshResetsBeforeDismissalAndCannotReopen() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        for closeWindow in [false, true] {
            let load = PendingImage()
            var loads = 0
            var requests: [String] = []
            let controller = ClassicalWindowController(desktopImage: { _ in
                loads += 1
                return loads == 2 ? try await load.image() : image
            }, menuBarVisibility: menuVisibility { requests.append($0) })
            defer { controller.stop() }
            var shown = false
            controller.setVisible(true) { shown = $0 }
            try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
            let window = try XCTUnwrap(controller.window)
            var dismissals = 0
            controller.onDismissRequested = {
                XCTAssertEqual(requests, ["hide", "reset"])
                dismissals += 1
            }
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                            object: NSApplication.shared)
            try await NativeAppTestSupport.waitUntil(description: "wallpaper loader starts and suspends", state: { "load.continuation != nil=\(String(describing: load.continuation != nil))" }) { load.continuation != nil }
            if closeWindow { window.close() } else { window.orderOut(nil) }
            XCTAssertEqual(dismissals, 1)
            XCTAssertEqual(requests, ["hide", "reset"])
            window.alphaValue = 0
            window.alphaValue = 1
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                            object: NSApplication.shared)
            load.complete(with: image)
            await drainTasks()
            XCTAssertEqual(loads, 2)
            XCTAssertFalse(window.isVisible)
            XCTAssertEqual(requests, ["hide", "reset"])
        }
    }

    func testReleasingVisibleControllerClosesWindowAndResetsMenuOverride() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        var requests: [String] = []
        var controller: ClassicalWindowController? = ClassicalWindowController(desktopImage: { _ in image },
            menuBarVisibility: menuVisibility { requests.append($0) })
        defer { controller?.stop() }
        var shown = false
        controller?.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        let window = try XCTUnwrap(controller?.window)
        weak var releasedController = controller
        controller = nil
        XCTAssertNil(releasedController, "The presentation controller remained retained after its owner released it.")
        XCTAssertFalse(window.isVisible, "Controller retained=\(releasedController != nil), menu requests=\(requests)\n\(NativeAppTestSupport.captureFailureSnapshot())")
        XCTAssertEqual(requests, ["hide", "reset"])
    }

    func testWallpaperRefreshFailureResetsMenuBeforeReportingDismissal() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        var loads = 0
        var errors = 0
        var requests: [String] = []
        let controller = ClassicalWindowController(desktopImage: { _ in
            loads += 1
            guard loads == 1 else { throw FixtureError.unavailable }
            return image
        }, presentError: { _ in errors += 1 }, menuBarVisibility: menuVisibility { requests.append($0) })
        defer { controller.stop() }
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        controller.onDismiss = {
            XCTAssertFalse(controller.isVisible)
            XCTAssertEqual(requests, ["hide", "reset"])
        }
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                        object: NSApplication.shared)
        try await NativeAppTestSupport.waitUntil(description: "wallpaper refresh reports its failure once", state: { "errors=\(String(describing: errors))" }) { errors == 1 }
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(requests, ["hide", "reset"])
    }

    func testMenuBarAlphaFollowsLauncherOpacityDuringEnterAndExit() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let image = try fixtureImage()
        var alphas: [Float] = []
        var requests: [String] = []
        let controller = ClassicalWindowController(desktopImage: { _ in image },
            menuBarVisibility: menuVisibility(alpha: { alphas.append($0) }) { requests.append($0) })
        defer { controller.stop() }
        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await NativeAppTestSupport.waitUntil(description: "presentation completion reports success", state: { "shown=\(String(describing: shown))" }) { shown }
        let entering = alphas
        XCTAssertEqual(requests, ["hide"])
        XCTAssertEqual(entering.last, 0)
        XCTAssertGreaterThan(entering.count, 2, "Menu bar alpha must change across frames, not only at the end.")
        XCTAssertGreaterThan(try XCTUnwrap(entering.first), 0.5)
        XCTAssertEqual(entering, entering.sorted(by: >))

        alphas.removeAll()
        var hidden = false
        controller.setVisible(false) { hidden = $0 }
        try await NativeAppTestSupport.waitUntil(description: "dismissal completion reports success", state: { "hidden=\(String(describing: hidden))" }) { hidden }
        XCTAssertEqual(requests, ["hide", "reset"])
        XCTAssertGreaterThan(alphas.count, 1, "Menu bar alpha must return across frames before the reset.")
        XCTAssertGreaterThan(try XCTUnwrap(alphas.last), 0.5)
        XCTAssertEqual(alphas, alphas.sorted())
    }

    private func menuVisibility(alpha recordAlpha: @escaping @MainActor (Float) -> Void = { _ in },
                                record: @escaping @MainActor (String) -> Void) -> ClassicalMenuBarVisibility {
        ClassicalMenuBarVisibility(resolveOperations: {
            .init(connectionID: 73, setAlpha: { connection, inset, scale, alpha in
                XCTAssertEqual(connection, 73)
                XCTAssertEqual(inset, 0)
                XCTAssertEqual(scale, 1)
                XCTAssertTrue((0...1).contains(alpha))
                recordAlpha(alpha)
                if alpha == 0 { record("hide") }
                return 0
            }, reset: { connection in
                XCTAssertEqual(connection, 73)
                record("reset")
                return 0
            })
        })
    }

    private func fixtureImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                                             bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try XCTUnwrap(context.makeImage())
    }

    private func drainTasks() async {
        for _ in 0..<10 { await Task.yield() }
    }

    private enum FixtureError: Error { case unavailable }

    @MainActor
    private final class PendingImage {
        var continuation: CheckedContinuation<CGImage, any Error>?

        func image() async throws -> CGImage {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }

        func complete(with image: CGImage) {
            let pending = continuation
            continuation = nil
            pending?.resume(returning: image)
        }

        func fail() {
            let pending = continuation
            continuation = nil
            pending?.resume(throwing: FixtureError.unavailable)
        }
    }
}
