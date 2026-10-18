import AppKit
import Testing
@testable import Launchpod

/// Quit, held-quit, restart and termination-reply behavior of the application delegate.
/// Nested so the parent suite's `.serialized` trait also orders these native-window tests.
extension AppDelegateTests {
    @MainActor
    @Suite
    struct Termination {
        @Test
        func cancelledQuitPreservesServicesAndAcceptedRepeatedRequestsFlushOnce() async throws {
            let fixture = try ApplicationDiscoveryTestDirectory()
            defer { fixture.remove() }
            let preferences = try TemporaryPreferences()
            let defaults = preferences.defaults
            defer { #expect(throws: Never.self) { try preferences.cleanup() } }
            let store = try AppDataStore(directoryURL: fixture.root)
            try await store.save(AppData())
            let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                       directories: [], onError: { Issue.record($0) })
            var replies: [Bool] = []
            let accepted = MainActorBox(false)
            var confirmations = 0
            let delegate = AppDelegate(defaults: defaults, makeServices: { services },
                                       presentError: { Issue.record($0) }, replyToTermination: { replies.append($0) },
                                       makePlaceholder: nil, installStatusItem: false,
                                       confirmQuit: { _ in confirmations += 1; return accepted.value })
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try await NativeAppTestSupport.waitUntil(description: "application services start", timeout: .seconds(5), state: { "services.isRunning=\(String(describing: services.isRunning))" }) { services.isRunning }
            let coordinator = try #require(delegate.coordinator)
            let session = try #require(coordinator.sessionForSelectedMode())
            let shortcut = delegate.globalShortcut
            let binding = shortcut.binding
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateCancel)
            #expect(services.isRunning)
            #expect(delegate.coordinator === coordinator)
            #expect(coordinator.session === session)
            #expect(session.state == .preparing)
            #expect(delegate.globalShortcut === shortcut)
            #expect(shortcut.binding == binding)
            #expect(replies.isEmpty)
            #expect(delegate.toggleLauncher() != nil)
            accepted.value = true
            _ = session.presentation.requestVisibility(false)
            let opening = session.presentation.toggle()

            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)
            #expect(confirmations == 2)
            #expect(coordinator.session === session)
            #expect(delegate.toggleLauncher() == nil)
            #expect(!delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: true))
            #expect(session.state == .preparing)
            try await NativeAppTestSupport.waitUntil(description: "termination delivers a reply", timeout: .seconds(5), state: { "replies=\(String(describing: replies)), services.isRunning=\(String(describing: services.isRunning))" }) { !replies.isEmpty }
            #expect(coordinator.session == nil)
            #expect(session.state == .inactive)
            #expect(!session.presentation.complete(opening))
            #expect(replies == [true])
            #expect(!services.isRunning)
            #expect(services.availableRecords.isEmpty)
            #expect(try await store.load() == services.data)
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)
            #expect(replies == [true])
        }

        /// Step 15: an abnormal close right after a drop must not lose the committed order, so the
        /// termination reply waits for the Classical layout write that the drop started.
        @Test
        func terminationRepliesOnlyAfterThePendingClassicalLayoutSaveFinishes() async throws {
            let fixture = try ApplicationDiscoveryTestDirectory()
            defer { fixture.remove() }
            let preferences = try TemporaryPreferences()
            let defaults = preferences.defaults
            defer { #expect(throws: Never.self) { try preferences.cleanup() } }
            let gate = BlockingLayoutWrite()
            defer { gate.release() }
            let layoutStore = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory),
                                                   write: gate.write)
            let dataStore = try AppDataStore(directoryURL: fixture.root.appending(path: "Data", directoryHint: .isDirectory))
            let services = AppServices(store: dataStore, icons: AppIconRepository(cacheCostLimit: 0),
                                       directories: [], onError: { Issue.record($0) })
            var replies: [Bool] = []
            let delegate = AppDelegate(defaults: defaults, makeServices: { services },
                                       makeClassicalLayout: { ClassicalLayoutModel(store: layoutStore) },
                                       presentError: { Issue.record($0) }, replyToTermination: { replies.append($0) },
                                       makePlaceholder: nil, installStatusItem: false, confirmQuit: { _ in true })
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try await NativeAppTestSupport.waitUntil(description: "services start and Classical layout loads", timeout: .seconds(5), state: { "services.isRunning=\(String(describing: services.isRunning)), delegate.classicalLayout?.isLoaded=\(String(describing: delegate.classicalLayout?.isLoaded))" }) { services.isRunning && delegate.classicalLayout?.isLoaded == true }
            let layout = try #require(delegate.classicalLayout)
            let dropped = try ClassicalLayout(pages: [[AppIdentity(), AppIdentity()], [AppIdentity()]])

            layout.commit(dropped)
            try await NativeAppTestSupport.waitUntil(description: "layout write reaches the blocking gate", timeout: .seconds(5), state: { "gate.hasStarted=\(String(describing: gate.hasStarted))" }) { gate.hasStarted }
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)
            try await Task.sleep(for: .milliseconds(300))
            #expect(replies.isEmpty, "Termination must not reply while the dropped arrangement is still being written")

            gate.release()
            try await NativeAppTestSupport.waitUntil(description: "termination delivers a reply", timeout: .seconds(5), state: { "replies=\(String(describing: replies)), services.isRunning=\(String(describing: services.isRunning))" }) { !replies.isEmpty }
            #expect(replies == [true])
            let saved = try await layoutStore.load()
            #expect(saved?.pages == dropped.pages)
        }

        /// The relaunched instance loads the Classical layout at startup, so restart relaunches only
        /// after this process finished writing the arrangement the drop started.
        @Test
        func restartRelaunchesOnlyAfterThePendingClassicalLayoutSaveFinishes() async throws {
            let fixture = try ApplicationDiscoveryTestDirectory()
            defer { fixture.remove() }
            let preferences = try TemporaryPreferences()
            let defaults = preferences.defaults
            defer { #expect(throws: Never.self) { try preferences.cleanup() } }
            let gate = BlockingLayoutWrite()
            defer { gate.release() }
            let layoutStore = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory),
                                                   write: gate.write)
            let dataStore = try AppDataStore(directoryURL: fixture.root.appending(path: "Data", directoryHint: .isDirectory))
            let services = AppServices(store: dataStore, icons: AppIconRepository(cacheCostLimit: 0),
                                       directories: [], onError: { Issue.record($0) })
            var replies: [Bool] = []
            var relaunched: [ClassicalLayout?] = []
            let delegate = AppDelegate(
                defaults: defaults, makeServices: { services },
                makeClassicalLayout: { ClassicalLayoutModel(store: layoutStore) },
                presentError: { Issue.record($0) }, replyToTermination: { replies.append($0) },
                makePlaceholder: nil, installStatusItem: false, requestTermination: {},
                relaunch: { relaunched.append(try await layoutStore.load()) },
                confirmQuit: { _ in Issue.record("Restart must not request quit confirmation."); return false }
            )
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try await NativeAppTestSupport.waitUntil(description: "services start and Classical layout loads", timeout: .seconds(5), state: { "services.isRunning=\(String(describing: services.isRunning)), delegate.classicalLayout?.isLoaded=\(String(describing: delegate.classicalLayout?.isLoaded))" }) { services.isRunning && delegate.classicalLayout?.isLoaded == true }
            let layout = try #require(delegate.classicalLayout)
            let dropped = try ClassicalLayout(pages: [[AppIdentity(), AppIdentity()], [AppIdentity()]])

            layout.commit(dropped)
            try await NativeAppTestSupport.waitUntil(description: "layout write reaches the blocking gate", timeout: .seconds(5), state: { "gate.hasStarted=\(String(describing: gate.hasStarted))" }) { gate.hasStarted }
            delegate.restartApplication()
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)
            try await NativeAppTestSupport.waitUntil(description: "!services.isRunning", timeout: .seconds(5), state: { "services.isRunning=\(String(describing: services.isRunning))" }) { !services.isRunning }
            try await Task.sleep(for: .milliseconds(300))
            #expect(relaunched.isEmpty, "The new instance must not start while the arrangement is being written")
            #expect(replies.isEmpty)

            gate.release()
            try await NativeAppTestSupport.waitUntil(description: "termination delivers a reply", timeout: .seconds(5), state: { "replies=\(String(describing: replies)), services.isRunning=\(String(describing: services.isRunning))" }) { !replies.isEmpty }
            #expect(replies == [true])
            #expect(relaunched.count == 1)
            #expect(relaunched.first??.pages == dropped.pages, "The relaunched instance reads the dropped arrangement")
        }

        @Test
        func serviceCreationFailurePresentsOriginalErrorAndDoesNotDelayTermination() throws {
            let preferences = try TemporaryPreferences()
            let defaults = preferences.defaults
            defer { #expect(throws: Never.self) { try preferences.cleanup() } }
            let failure = CocoaError(.fileReadNoPermission)
            var errors: [NSError] = []
            var replies: [Bool] = []
            let delegate = AppDelegate(defaults: defaults, makeServices: { throw failure },
                                       presentError: { errors.append($0 as NSError) },
                                       replyToTermination: { replies.append($0) }, makePlaceholder: nil, installStatusItem: false,
                                       confirmQuit: { _ in true })

            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            #expect(errors == [failure as NSError])
            #expect(delegate.services == nil)
            #expect(delegate.coordinator == nil)
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateNow)
            #expect(replies.isEmpty)
        }

        @Test
        func unsavedUpdateCancelsTerminationAndRestartsSharedServices() async throws {
            let fixture = try ApplicationDiscoveryTestDirectory()
            defer { fixture.remove() }
            let preferences = try TemporaryPreferences()
            let defaults = preferences.defaults
            defer { #expect(throws: Never.self) { try preferences.cleanup() } }
            let failure = CocoaError(.fileWriteOutOfSpace)
            let store = try AppDataStore(directoryURL: fixture.root, write: { _, _ in throw failure })
            var updateErrors: [NSError] = []
            let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0), directories: [],
                                       onError: { updateErrors.append($0 as NSError) })
            var presentedErrors: [NSError] = []
            var replies: [Bool] = []
            let delegate = AppDelegate(defaults: defaults, makeServices: { services },
                                       presentError: { presentedErrors.append($0 as NSError) },
                                       replyToTermination: { replies.append($0) }, makePlaceholder: nil, installStatusItem: false,
                                       confirmQuit: { _ in true })
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try await NativeAppTestSupport.waitUntil(description: "initial save reports the injected failure", timeout: .seconds(5), state: { "updateErrors=\(String(describing: updateErrors))" }) { !updateErrors.isEmpty }
            let coordinator = try #require(delegate.coordinator)
            let session = try #require(coordinator.sessionForSelectedMode())
            _ = session.presentation.requestVisibility(false)
            #expect(coordinator.complete(session.presentation.toggle()))

            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)
            try await NativeAppTestSupport.waitUntil(description: "failed termination replies false and restores services", timeout: .seconds(5), state: { "replies=\(String(describing: replies)), services.isRunning=\(String(describing: services.isRunning))" }) { replies == [false] && services.isRunning }
            #expect(presentedErrors == [failure as NSError])
            #expect(delegate.services === services)
            #expect(delegate.coordinator === coordinator)
            #expect(coordinator.session === session)
            #expect(session.state == .visible)
            #expect(services.data != nil)
            #expect(delegate.toggleLauncher()?.targetIsVisible == false)
            #expect(session.state == .dismissing)
            do {
                try await services.stop()
            } catch {
                #expect(error as NSError == failure as NSError)
            }
        }

        @Test(arguments: ["success", "saveFailure", "relaunchFailure"])
        func restartFlushesBeforeRelaunchAndKeepsTheCurrentProcessOnFailure(outcome: String) async throws {
            let fixture = try ApplicationDiscoveryTestDirectory()
            defer { fixture.remove() }
            let preferences = try TemporaryPreferences()
            let defaults = preferences.defaults
            defer { #expect(throws: Never.self) { try preferences.cleanup() } }
            let failure = CocoaError(.fileWriteOutOfSpace)
            let store = try AppDataStore(directoryURL: fixture.root, write: { data, url in
                if outcome == "saveFailure" { throw failure }
                try data.write(to: url, options: .atomic)
            })
            let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                       directories: [], onError: { error in
                if outcome != "saveFailure" { Issue.record(error) }
            })
            var terminationRequests = 0
            var relaunches = 0
            var replies: [Bool] = []
            var errors: [NSError] = []
            let delegate = AppDelegate(
                defaults: defaults, makeServices: { services }, presentError: { errors.append($0 as NSError) },
                replyToTermination: { replies.append($0) }, makePlaceholder: nil, installStatusItem: false,
                requestTermination: { terminationRequests += 1 },
                relaunch: {
                    relaunches += 1
                    #expect(!services.isRunning)
                    #expect(try await store.load() == services.data)
                    #expect(replies.isEmpty)
                    if outcome == "relaunchFailure" { throw failure }
                },
                confirmQuit: { _ in Issue.record("Restart must not request quit confirmation."); return false }
            )
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            // Restart must find the first scan's data to save; the app directories are the system's.
            try await NativeAppTestSupport.waitUntil(description: "services finish the initial application scan", timeout: .seconds(5), state: { "services.isRunning=\(String(describing: services.isRunning)), services.hasCurrentScan=\(String(describing: services.hasCurrentScan))" }) { services.isRunning && services.hasCurrentScan }
            let coordinator = try #require(delegate.coordinator)
            delegate.restartApplication()
            delegate.restartApplication()
            #expect(terminationRequests == 1)
            #expect(relaunches == 0)
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)
            delegate.restartApplication()
            #expect(terminationRequests == 1)
            try await NativeAppTestSupport.waitUntil(description: "termination delivers a reply", timeout: .seconds(5), state: { "replies=\(String(describing: replies)), services.isRunning=\(String(describing: services.isRunning))" }) { !replies.isEmpty }

            if outcome == "success" {
                #expect(replies == [true])
                #expect(errors.isEmpty)
                #expect(relaunches == 1)
                #expect(!services.isRunning)
                #expect(coordinator.session == nil)
            } else {
                try await NativeAppTestSupport.waitUntil(description: "application services start", timeout: .seconds(5), state: { "services.isRunning=\(String(describing: services.isRunning))" }) { services.isRunning }
                #expect(replies == [false])
                #expect(errors == [failure as NSError])
                #expect(relaunches == (outcome == "saveFailure" ? 0 : 1))
                #expect(delegate.coordinator === coordinator)
                #expect(coordinator.session != nil)
                do {
                    try await services.stop()
                } catch {
                    #expect(outcome == "saveFailure")
                    #expect(error as NSError == failure as NSError)
                }
            }
        }

        @Test(arguments: [false, true])
        func completedHoldBypassesConfirmationAndFailedSaveRestoresMenuConfirmation(saveFails: Bool) async throws {
            let fixture = try ApplicationDiscoveryTestDirectory()
            defer { fixture.remove() }
            let preferences = try TemporaryPreferences()
            let defaults = preferences.defaults
            defer { #expect(throws: Never.self) { try preferences.cleanup() } }
            let failure = CocoaError(.fileWriteOutOfSpace)
            let store = try AppDataStore(directoryURL: fixture.root, write: { data, url in
                if saveFails { throw failure }
                try data.write(to: url, options: .atomic)
            })
            let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                       directories: [], onError: { _ in })
            var confirmations = 0
            var requests = 0
            var replies: [Bool] = []
            var errors: [NSError] = []
            let delegate = AppDelegate(
                defaults: defaults, makeServices: { services }, presentError: { errors.append($0 as NSError) },
                replyToTermination: { replies.append($0) }, makePlaceholder: nil, installStatusItem: false,
                requestTermination: { requests += 1 },
                confirmQuit: { _ in confirmations += 1; return false },
                isKeyPressed: { _ in false }
            )
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try await NativeAppTestSupport.waitUntil(description: "services finish the initial application scan", timeout: .seconds(5), state: { "services.isRunning=\(String(describing: services.isRunning)), services.hasCurrentScan=\(String(describing: services.hasCurrentScan))" }) { services.isRunning && services.hasCurrentScan }
            delegate.quitAfterHoldingShortcut(keyCode: 12)
            delegate.quitAfterHoldingShortcut(keyCode: 12)
            #expect(requests == 1)
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)
            #expect(confirmations == 0)
            try await NativeAppTestSupport.waitUntil(description: "termination delivers a reply", timeout: .seconds(5), state: { "replies=\(String(describing: replies)), services.isRunning=\(String(describing: services.isRunning))" }) { !replies.isEmpty }
            if saveFails {
                try await NativeAppTestSupport.waitUntil(description: "application services start", timeout: .seconds(5), state: { "services.isRunning=\(String(describing: services.isRunning))" }) { services.isRunning }
                #expect(replies == [false])
                #expect(errors == [failure as NSError])
                #expect(delegate.applicationShouldTerminate(.shared) == .terminateCancel)
                #expect(confirmations == 1)
                #expect(services.isRunning)
                do {
                    try await services.stop()
                } catch {
                    #expect(error as NSError == failure as NSError)
                }
            } else {
                #expect(replies == [true])
                #expect(errors.isEmpty)
                #expect(!services.isRunning)
            }
        }

        @Test
        func aCompletedHoldKeepsTheProcessAliveBeyondFiveSecondsUntilTheKeyComesUp() async throws {
            let fixture = try ApplicationDiscoveryTestDirectory()
            defer { fixture.remove() }
            let preferences = try TemporaryPreferences()
            let defaults = preferences.defaults
            defer { #expect(throws: Never.self) { try preferences.cleanup() } }
            let services = AppServices(store: try AppDataStore(directoryURL: fixture.root),
                                       icons: AppIconRepository(cacheCostLimit: 0), directories: [],
                                       onError: { Issue.record($0) })
            var replies: [Bool] = []
            var quitKeyIsDown = true
            defer { quitKeyIsDown = false }
            var keyChecks = 0
            let delegate = AppDelegate(
                defaults: defaults, makeServices: { services }, presentError: { Issue.record($0) },
                replyToTermination: { replies.append($0) }, makePlaceholder: nil, installStatusItem: false,
                requestTermination: {}, confirmQuit: { _ in Issue.record("A held quit skips confirmation"); return true },
                isKeyPressed: { keyChecks += 1; return $0 == 12 && quitKeyIsDown }
            )
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try await NativeAppTestSupport.waitUntil(description: "application services start", timeout: .seconds(5), state: { "services.isRunning=\(String(describing: services.isRunning))" }) { services.isRunning }

            delegate.quitAfterHoldingShortcut(keyCode: 12)
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)

            // Still physically down: quitting now would hand the rest of the chord
            // to the app that owns the keyboard next.
            try await NativeAppTestSupport.waitUntil(description: "held quit begins checking key release", timeout: .seconds(5), state: { "keyChecks=\(String(describing: keyChecks))" }) { keyChecks > 0 }
            try await Task.sleep(for: .milliseconds(5_300))
            #expect(replies.isEmpty)
            #expect(services.isRunning)
            delegate.quitAfterHoldingShortcut(keyCode: 12)
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)

            quitKeyIsDown = false
            try await NativeAppTestSupport.waitUntil(description: "termination delivers a reply", timeout: .seconds(5), state: { "replies=\(String(describing: replies)), services.isRunning=\(String(describing: services.isRunning))" }) { !replies.isEmpty }
            #expect(replies == [true])
            #expect(!services.isRunning)
        }

        @Test(.enabled(if: NativeAppTestSupport.isEnabled))
        func aCompletedHoldHidesNativePresentationBeforeBlockedStartupFinishes() async throws {
            let restoreHostWindows = try NativeAppTestSupport.isolateHostWindows()
            defer { restoreHostWindows() }
            let fixture = try ApplicationDiscoveryTestDirectory()
            defer { fixture.remove() }
            let preferences = try TemporaryPreferences()
            let defaults = preferences.defaults
            defer { #expect(throws: Never.self) { try preferences.cleanup() } }
            let writerEntered = DispatchSemaphore(value: 0)
            let releaseWriter = DispatchSemaphore(value: 0)
            defer { releaseWriter.signal() }
            let store = try AppDataStore(directoryURL: fixture.root, write: { data, url in
                writerEntered.signal()
                releaseWriter.wait()
                try data.write(to: url, options: .atomic)
            })
            let seedWrite = Task { try await store.save(AppData()) }
            var writerIsBlocked = false
            try await NativeAppTestSupport.waitUntil(description: "startup seed write reaches the blocking gate", timeout: .seconds(5)) {
                if !writerIsBlocked { writerIsBlocked = writerEntered.wait(timeout: .now()) == .success }
                return writerIsBlocked
            }
            let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                       directories: [], onError: { Issue.record($0) })
            let quitKeyIsDown = MainActorBox(true)
            defer { quitKeyIsDown.value = false }
            var keyChecks = 0
            var replies: [Bool] = []
            let delegate = AppDelegate(
                defaults: defaults, makeServices: { services }, presentError: { Issue.record($0) },
                replyToTermination: { replies.append($0) }, requestTermination: {},
                confirmQuit: { _ in Issue.record("A completed hold skips confirmation."); return false },
                isKeyPressed: { _ in keyChecks += 1; return quitKeyIsDown.value }
            )
            defer { delegate.launcherPlaceholder?.stop(); delegate.statusItemController?.stop() }
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            let placeholder = try #require(delegate.launcherPlaceholder as? LauncherPlaceholderWindowController)
            let window = try #require(placeholder.window)
            let statusItem = try #require(delegate.statusItemController?.statusItem)
            try await NativeAppTestSupport.waitUntil(description: "launcher acquires key focus", timeout: .seconds(5), state: { "window.isKeyWindow=\(String(describing: window.isKeyWindow)), window.isVisible=\(String(describing: window.isVisible))" }) { window.isKeyWindow }
            try await Task.sleep(for: .milliseconds(20))
            let keyDown = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "q",
                charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12
            ))
            #expect(delegate.holdToQuitController.process(keyDown))
            let prompt = try #require(NSApplication.shared.windows.first {
                $0.accessibilityIdentifier() == "holdToQuitPrompt" && $0.isVisible
            })
            #expect(window.isVisible && window.alphaValue > 0)
            #expect(statusItem.isVisible)
            #expect(!services.isRunning && services.data == nil)

            delegate.quitAfterHoldingShortcut(keyCode: 12)
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)
            #expect(!window.isVisible || window.alphaValue == 0)
            #expect(!prompt.isVisible)
            #expect(!statusItem.isVisible)
            try await Task.sleep(for: .milliseconds(100))
            #expect(services.data == nil && replies.isEmpty)
            #expect(!window.isVisible || window.alphaValue == 0)
            #expect(!statusItem.isVisible)

            releaseWriter.signal()
            try await seedWrite.value
            try await NativeAppTestSupport.waitUntil(description: "held quit begins checking key release", timeout: .seconds(5), state: { "keyChecks=\(String(describing: keyChecks))" }) { keyChecks > 0 }
            #expect(replies.isEmpty)
            #expect(!window.isVisible || window.alphaValue == 0)
            #expect(!statusItem.isVisible)
            quitKeyIsDown.value = false
            try await NativeAppTestSupport.waitUntil(description: "termination delivers a reply", timeout: .seconds(5), state: { "replies=\(String(describing: replies)), services.isRunning=\(String(describing: services.isRunning))" }) { !replies.isEmpty }
            #expect(replies == [true])
            #expect(!window.isVisible)
            #expect(!statusItem.isVisible)
        }

        @Test(.enabled(if: NativeAppTestSupport.isEnabled), arguments: [false, true])
        func failedHeldQuitRestoresNativeVisibilityOpacityAndMenuPreference(menuVisible: Bool) async throws {
            let restoreHostWindows = try NativeAppTestSupport.isolateHostWindows()
            defer { restoreHostWindows() }
            let fixture = try ApplicationDiscoveryTestDirectory()
            defer { fixture.remove() }
            let preferences = try TemporaryPreferences()
            let defaults = preferences.defaults
            defer { #expect(throws: Never.self) { try preferences.cleanup() } }
            defaults.set(menuVisible, forKey: "showInMenuBar")
            let failure = CocoaError(.fileWriteOutOfSpace)
            var saveErrors: [NSError] = []
            let services = AppServices(
                store: try AppDataStore(directoryURL: fixture.root, write: { _, _ in throw failure }),
                icons: AppIconRepository(cacheCostLimit: 0), directories: [],
                onError: { saveErrors.append($0 as NSError) }
            )
            var quitKeyIsDown = true
            defer { quitKeyIsDown = false }
            var errors: [NSError] = []
            var replies: [Bool] = []
            let delegate = AppDelegate(
                defaults: defaults, makeServices: { services }, presentError: { errors.append($0 as NSError) },
                replyToTermination: { replies.append($0) }, requestTermination: {},
                confirmQuit: { _ in Issue.record("A completed hold skips confirmation."); return false },
                isKeyPressed: { $0 == 12 && quitKeyIsDown }
            )
            defer { delegate.launcherPlaceholder?.stop(); delegate.statusItemController?.stop() }
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try await NativeAppTestSupport.waitUntil(description: "services start and report the injected save failure", timeout: .seconds(5), state: { "services.isRunning=\(String(describing: services.isRunning)), saveErrors=\(String(describing: saveErrors))" }) { services.isRunning && !saveErrors.isEmpty }
            let placeholder = try #require(delegate.launcherPlaceholder as? LauncherPlaceholderWindowController)
            let window = try #require(placeholder.window)
            let item = try #require(delegate.statusItemController?.statusItem)
            try await NativeAppTestSupport.waitUntil(description: "launcher acquires key focus", timeout: .seconds(5), state: { "window.isKeyWindow=\(String(describing: window.isKeyWindow)), window.isVisible=\(String(describing: window.isVisible))" }) { window.isKeyWindow }
            window.alphaValue = 0.63
            #expect(window.isVisible)
            #expect(item.isVisible == menuVisible)

            delegate.quitAfterHoldingShortcut(keyCode: 12)
            #expect(delegate.applicationShouldTerminate(.shared) == .terminateLater)
            #expect(!window.isVisible || window.alphaValue == 0)
            #expect(!item.isVisible)
            window.orderOut(nil)
            quitKeyIsDown = false
            try await NativeAppTestSupport.waitUntil(description: "failed termination replies false and restores services", timeout: .seconds(5), state: { "replies=\(String(describing: replies)), services.isRunning=\(String(describing: services.isRunning))" }) { replies == [false] && services.isRunning }
            #expect(errors == [failure as NSError])
            #expect(placeholder.window === window)
            #expect(window.isVisible)
            #expect(window.alphaValue == 0.63)
            #expect(delegate.statusItemController?.statusItem === item)
            #expect(item.isVisible == menuVisible)
            #expect(defaults.bool(forKey: "showInMenuBar") == menuVisible)
            #expect(delegate.toggleLauncher()?.targetIsVisible == false)
            do { try await services.stop() }
            catch { #expect(error as NSError == failure as NSError) }
        }
    }
}

/// Holds the Classical layout's primary write until the test releases it, so termination can be
/// observed while that write is still in progress.
private nonisolated final class BlockingLayoutWrite: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var started = false
    private var released = false

    var hasStarted: Bool { lock.withLock { started } }

    var write: @Sendable (Data, URL) throws -> Void {
        { [self] data, url in
            if url.lastPathComponent == "layout.json" {
                let wait = lock.withLock { () -> Bool in
                    started = true
                    return !released
                }
                if wait { semaphore.wait() }
            }
            try data.write(to: url, options: .atomic)
        }
    }

    func release() {
        let signal = lock.withLock { () -> Bool in
            guard !released else { return false }
            released = true
            return started
        }
        if signal { semaphore.signal() }
    }
}
