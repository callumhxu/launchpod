import AppKit
import Testing
@testable import Launchpod

@MainActor
@Suite(.serialized)
struct AppDelegateTests {
    @Test(arguments: [false, true])
    func firstInstallIntroductionDefersLauncherUntilCompletion(alreadyCompleted: Bool) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        if alreadyCompleted { OnboardingModel(defaults: defaults).finish() }
        let services = AppServices(
            store: try AppDataStore(directoryURL: fixture.root), icons: AppIconRepository(cacheCostLimit: 0),
            directories: [], onError: { Issue.record($0) }
        )
        let placeholder = FocusablePlaceholder()
        var introductionPresentations = 0
        let delegate = AppDelegate(
            defaults: defaults, makeServices: { services }, presentError: { Issue.record($0) },
            replyToTermination: { _ in }, makePlaceholder: { _ in placeholder }, installStatusItem: false,
            presentOnboarding: { owner in
                introductionPresentations += 1
                #expect(owner.onboarding.isPresented)
                #expect(owner.onboarding.step == .welcome)
            }
        )
        let notification = Notification(name: NSApplication.didFinishLaunchingNotification)
        delegate.applicationDidFinishLaunching(notification)
        delegate.applicationDidFinishLaunching(notification)
        try await wait {
            alreadyCompleted ? placeholder.requests == [true] : introductionPresentations == 1
        }

        #expect(introductionPresentations == (alreadyCompleted ? 0 : 1))
        #expect(placeholder.requests == (alreadyCompleted ? [true] : []))
        if !alreadyCompleted {
            #expect(delegate.showLauncher() == nil)
            #expect(delegate.toggleLauncher() == nil)
            #expect(!delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))
            #expect(placeholder.requests.isEmpty)
            #expect(!delegate.onboarding.hasCompleted)
            delegate.finishOnboarding()
            try await wait { delegate.onboarding.hasCompleted && placeholder.requests == [true] }
            #expect(delegate.onboarding.hasCompleted)
            #expect(!delegate.onboarding.isPresented)
            #expect(OnboardingModel(defaults: defaults).hasCompleted)
            #expect(placeholder.requests == [true])
            #expect(delegate.coordinator?.session?.state == .visible)
        }
        delegate.finishOnboarding()
        #expect(placeholder.requests == [true])
        try await wait { services.isRunning }
        try await services.stop()
    }

    #if DEBUG
    @Test
    func suppressedUnitTestHostDoesNotStartServicesOrPresentIntroduction() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let delegate = AppDelegate(
            defaults: defaults,
            makeServices: {
                Issue.record("The suppressed unit-test host must not start application services.")
                throw CocoaError(.userCancelled)
            },
            presentError: { Issue.record($0) }, replyToTermination: { _ in },
            makePlaceholder: nil, installStatusItem: false,
            presentOnboarding: { _ in Issue.record("The suppressed unit-test host must not show onboarding.") }
        )
        delegate.suppressesTestHostPresentation = true
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(delegate.services == nil)
        #expect(delegate.coordinator == nil)
        #expect(!delegate.onboarding.isPresented)
        #expect(!delegate.onboarding.hasCompleted)
    }
    #endif

    @Test
    func classicalWallpaperFailureRestoresInactiveSession() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let services = AppServices(
            store: try AppDataStore(directoryURL: fixture.root), icons: AppIconRepository(cacheCostLimit: 0),
            directories: [], onError: { Issue.record($0) }
        )
        var failures = 0
        let delegate = AppDelegate(
            defaults: defaults, makeServices: { services }, presentError: { Issue.record($0) },
            replyToTermination: { _ in }, makePlaceholder: { _ in
                ClassicalWindowController(desktopImage: { _ in throw CocoaError(.fileNoSuchFile) },
                                          presentError: { _ in failures += 1 })
            }, installStatusItem: false
        )
        defer { delegate.launcherPlaceholder?.stop() }
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await wait { failures == 1 }
        #expect(delegate.coordinator?.session?.state == .inactive)
        #expect(delegate.launcherPlaceholder?.isVisible == false)
        try await services.stop()
    }

    @Test(arguments: LauncherMode.allCases)
    func nativeReopenAndCommandsToggleTheSameSessionWithoutCompletingPresentation(mode: LauncherMode) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        defaults.set(mode.rawValue, forKey: "launcherMode")
        let services = AppServices(
            store: try AppDataStore(directoryURL: fixture.root), icons: AppIconRepository(cacheCostLimit: 0),
            directories: [], onError: { Issue.record($0) }
        )
        let delegate = AppDelegate(defaults: defaults, makeServices: { services },
                                   presentError: { Issue.record($0) }, replyToTermination: { _ in },
                                   makePlaceholder: nil, installStatusItem: false, confirmQuit: { _ in true })
        #expect(delegate.toggleLauncher() == nil)
        #expect(!delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let coordinator = try #require(delegate.coordinator)
        try await wait { coordinator.session?.state == .preparing }
        #expect(coordinator.session?.state == .preparing)
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(coordinator.session?.state == .preparing)
        let staleDismissal = try #require(delegate.toggleLauncher())
        let session = try #require(coordinator.session)
        #expect(session.mode == mode)
        #expect(session.state == .dismissing)

        #expect(!delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: true))
        #expect(coordinator.session === session)
        #expect(session.state == .preparing)
        #expect(!coordinator.complete(staleDismissal))
        #expect(!delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))
        #expect(coordinator.session === session)
        #expect(session.state == .dismissing)
        let opening = try #require(delegate.toggleLauncher())
        #expect(session.state == .preparing)
        #expect(coordinator.complete(opening))
        #expect(session.state == .visible)
        try await wait { services.isRunning }
        try await services.stop()
    }

    @Test
    func launchOwnsOneServiceSetAndPersistsOnlyCompletedModeSelections() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        defaults.set(LauncherMode.window.rawValue, forKey: "launcherMode")
        let services = AppServices(
            store: try AppDataStore(directoryURL: fixture.root), icons: AppIconRepository(cacheCostLimit: 0),
            directories: [], onError: { Issue.record($0) }
        )
        var creations = 0
        let delegate = AppDelegate(defaults: defaults, makeServices: {
            creations += 1
            return services
        }, presentError: { Issue.record($0) }, replyToTermination: { _ in }, makePlaceholder: nil, installStatusItem: false,
           confirmQuit: { _ in true })
        let notification = Notification(name: NSApplication.didFinishLaunchingNotification)

        delegate.applicationDidFinishLaunching(notification)
        let coordinator = try #require(delegate.coordinator)
        delegate.applicationDidFinishLaunching(notification)
        #expect(creations == 1)
        #expect(delegate.services === services)
        #expect(delegate.coordinator === coordinator)
        #expect(coordinator.mode == .window)
        let session = try #require(coordinator.sessionForSelectedMode())
        _ = session.presentation.requestVisibility(false)
        #expect(coordinator.complete(session.presentation.toggle()))
        let dismissal = try #require(coordinator.selectMode(.classical))
        #expect(defaults.string(forKey: "launcherMode") == "window")
        #expect(coordinator.complete(dismissal))
        #expect(defaults.string(forKey: "launcherMode") == "classical")
        try await wait { services.isRunning }
        try await services.stop()
    }

    @Test(.enabled(if: NativeAppTestSupport.isEnabled), arguments: LauncherMode.allCases)
    func nativePlaceholderVisibilityCompletesTogglesAndUserDismissals(mode: LauncherMode) async throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        defaults.set(mode.rawValue, forKey: "launcherMode")
        let services = AppServices(
            store: try AppDataStore(directoryURL: fixture.root), icons: AppIconRepository(cacheCostLimit: 0),
            directories: [], onError: { Issue.record($0) }
        )
        let delegate = AppDelegate(defaults: defaults, makeServices: { services },
                                   presentError: { Issue.record($0) }, replyToTermination: { _ in }, installStatusItem: false,
                                   confirmQuit: { _ in true })
        defer { delegate.launcherPlaceholder?.stop() }
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let coordinator = try #require(delegate.coordinator)
        let session = try #require(coordinator.session)
        let placeholder = try #require(delegate.launcherPlaceholder as? LauncherPlaceholderWindowController)
        let window = try #require(placeholder.window)
        #expect(window.isVisible)
        try await wait { session.state == .visible }
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(placeholder.window === window)
        #expect(window.isVisible)

        let dismissal = try #require(delegate.toggleLauncher())
        #expect(!window.isVisible)
        #expect(session.state == .inactive)
        #expect(!coordinator.complete(dismissal))
        #expect(!delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))
        #expect(window.isVisible)
        try await wait { session.state == .visible }
        #expect(coordinator.session === session)

        window.performClose(nil)
        #expect(!window.isVisible)
        #expect(session.state == .inactive)
        _ = delegate.toggleLauncher()
        #expect(window.isVisible)
        try await wait { session.state == .visible }
        window.cancelOperation(nil)
        #expect(!window.isVisible)
        #expect(session.state == .inactive)
        _ = delegate.toggleLauncher()
        #expect(window.isVisible)
        try await wait { session.state == .visible }
        try await wait { services.isRunning }
        try await services.stop()
    }

    @Test
    func unavailablePresentationDoesNotCompleteAVisibilityRequest() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let services = AppServices(
            store: try AppDataStore(directoryURL: fixture.root), icons: AppIconRepository(cacheCostLimit: 0),
            directories: [], onError: { Issue.record($0) }
        )
        let placeholder = UnavailablePlaceholder()
        let delegate = AppDelegate(defaults: defaults, makeServices: { services },
                                   presentError: { Issue.record($0) }, replyToTermination: { _ in },
                                   makePlaceholder: { _ in placeholder }, installStatusItem: false, confirmQuit: { _ in true })
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await wait { placeholder.requests == [true] }
        #expect(placeholder.requests == [true])
        #expect(!placeholder.isVisible)
        #expect(delegate.coordinator?.session?.state == .preparing)
        placeholder.isVisible = true
        _ = delegate.toggleLauncher()
        #expect(placeholder.requests == [true, false])
        #expect(placeholder.isVisible)
        #expect(delegate.coordinator?.session?.state == .dismissing)
        try await wait { services.isRunning }
        try await services.stop()
    }

    @Test
    func dockStatusItemAndCommandsToggleTheSameVisibleSessionOncePerInvocation() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let services = AppServices(store: try AppDataStore(directoryURL: fixture.root),
                                   icons: AppIconRepository(cacheCostLimit: 0), directories: [], onError: { Issue.record($0) })
        let placeholder = FocusablePlaceholder()
        let delegate = AppDelegate(
            defaults: defaults, makeServices: { services }, presentError: { Issue.record($0) },
            replyToTermination: { _ in }, makePlaceholder: { _ in placeholder }
        )
        #if DEBUG
        var entries: [WindowInvocationDiagnostics.Entry] = []
        let diagnostics = WindowInvocationDiagnostics.shared
        let previousSink = diagnostics.sink
        diagnostics.sink = { entries.append($0) }
        defer { diagnostics.sink = previousSink }
        #endif
        defer { delegate.statusItemController?.stop() }
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await wait { delegate.coordinator?.session?.state == .visible }
        let session = try #require(delegate.coordinator?.session)
        #expect(session.state == .visible)
        #expect(placeholder.requests == [true])
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(placeholder.requests == [true])
        _ = delegate.toggleLauncher()
        #expect(placeholder.requests == [true, false])
        #expect(!placeholder.isVisible)
        #expect(session.state == .inactive)
        #expect(!delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))
        #expect(placeholder.requests == [true, false, true])
        #expect(!delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: true))
        #expect(placeholder.requests == [true, false, true, false])
        #expect(!placeholder.isVisible)
        #expect(session.state == .inactive)
        let status = try #require(delegate.statusItemController)
        status.handleClick(nil)
        #expect(placeholder.requests == [true, false, true, false, true])
        #expect(session.state == .visible)
        status.menu.performActionForItem(at: 0)
        #expect(placeholder.requests == [true, false, true, false, true, false])
        #expect(session.state == .inactive)
        #expect(!delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: true))
        #expect(placeholder.requests == [true, false, true, false, true, false, true])
        #expect(delegate.coordinator?.session === session)
        #expect(session.state == .visible)
        #if DEBUG
        let presentations = entries.filter { $0.event == "launcher.present" }
        #expect(presentations.map(\.request?.source) == [
            .startup, .directLauncher, .dockReopen, .dockReopen, .statusButton, .menuToggle, .dockReopen
        ])
        #expect(Set(presentations.compactMap { $0.request?.id }).count == placeholder.requests.count)
        #expect(entries.filter { $0.event == "launcher.completion" }.map(\.request) == presentations.map(\.request))
        diagnostics.sink = previousSink
        #endif
        try await wait { services.isRunning }
        try await services.stop()
    }

    /// A global shortcut suppresses slow motion only for the request it triggers.
    @Test(.enabled(if: NativeAppTestSupport.isEnabled))
    func globalHotkeySuppressionDoesNotLeakIntoDirectOrMenuRequests() async throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let binding = try #require(ShortcutPreference.Binding(keyCode: 40, modifiers: [.control, .option], characters: "k"))
        ShortcutPreference(defaults: defaults).selection = binding
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let services = AppServices(store: try AppDataStore(directoryURL: fixture.root),
                                   icons: AppIconRepository(cacheCostLimit: 0), directories: [], onError: { Issue.record($0) })
        let controller = ClassicalWindowController(desktopImage: { _ in image }, presentError: { Issue.record($0) })
        controller.slowMotionAllowed = { true }
        controller.shiftKeyDown = { false }
        var receiveHotkey: (@MainActor (Bool) -> Void)?
        let delegate = AppDelegate(defaults: defaults, makeServices: { services }, presentError: { Issue.record($0) },
                                   replyToTermination: { _ in }, makePlaceholder: { _ in controller },
                                   globalShortcutRegister: { registered, receive in
                                       #expect(registered == binding)
                                       receiveHotkey = receive
                                       return {}
                                   })
        defer { delegate.statusItemController?.stop(); controller.stop() }
        func rootLayer() -> CALayer? { controller.window?.contentView?.layer?.sublayers?.first }

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await wait { delegate.coordinator?.session?.state == .visible && receiveHotkey != nil }
        controller.shiftKeyDown = { true }
        let hotkeyObserver = OpacityDurationObserver()
        let initialRoot = try #require(rootLayer())
        initialRoot.delegate = hotkeyObserver
        do {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.73123456789)
            defer { CATransaction.commit() }
            receiveHotkey?(true)
            #expect(hotkeyObserver.durations.last == Double(Float(0.73123456789)))
        }
        receiveHotkey?(false)
        try await wait { delegate.coordinator?.session?.state == .inactive }

        _ = delegate.toggleLauncher()
        try await wait { rootLayer()?.animation(forKey: "opacity") != nil }
        let directRoot = try #require(rootLayer())
        #expect(directRoot.animation(forKey: "opacity")?.duration == 5)
        let menuObserver = OpacityDurationObserver()
        directRoot.delegate = menuObserver
        let status = try #require(delegate.statusItemController)
        status.menu.performActionForItem(at: 0)
        #expect(menuObserver.durations.last == 5)
        try await services.stop()
    }

    @Test(arguments: [nil, false, true] as [Bool?])
    func menuBarVisibilityRestoresPreferenceAndUpdatesTheSameNativeItem(stored: Bool?) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        if let stored { defaults.set(stored, forKey: "showInMenuBar") }
        let services = AppServices(store: try AppDataStore(directoryURL: fixture.root),
                                   icons: AppIconRepository(cacheCostLimit: 0), directories: [], onError: { Issue.record($0) })
        let delegate = AppDelegate(
            defaults: defaults, makeServices: { services }, presentError: { Issue.record($0) },
            replyToTermination: { _ in }, makePlaceholder: nil
        )
        defer { delegate.statusItemController?.stop() }
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let item = try #require(delegate.statusItemController?.statusItem)
        #expect(item.isVisible == (stored ?? true))
        let shortcut = delegate.globalShortcut
        for visible in [false, true, false] {
            delegate.setMenuBarVisible(visible)
            #expect(delegate.statusItemController?.statusItem === item)
            #expect(item.isVisible == visible)
            #expect(delegate.globalShortcut === shortcut)
        }
        try await wait { services.isRunning }
        try await services.stop()
    }

    @Test
    func delayedNativeCompletionCannotCompleteSupersededShowOrHide() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let services = AppServices(store: try AppDataStore(directoryURL: fixture.root),
                                   icons: AppIconRepository(cacheCostLimit: 0), directories: [], onError: { Issue.record($0) })
        let placeholder = DeferredPlaceholder()
        let delegate = AppDelegate(
            defaults: defaults, makeServices: { services }, presentError: { Issue.record($0) },
            replyToTermination: { _ in }, makePlaceholder: { _ in placeholder }, installStatusItem: false
        )
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await wait { placeholder.requests == [true] }
        let session = try #require(delegate.coordinator?.session)
        #expect(placeholder.requests == [true])
        #expect(session.state == .preparing)
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(placeholder.requests == [true])

        _ = delegate.toggleLauncher()
        #expect(session.state == .dismissing)
        placeholder.completions[0](true)
        #expect(session.state == .dismissing)
        _ = delegate.toggleLauncher()
        #expect(placeholder.requests == [true, false, true])
        #expect(session.state == .preparing)
        placeholder.completions[1](true)
        #expect(session.state == .preparing)
        placeholder.isVisible = true
        placeholder.completions[2](false)
        #expect(session.state == .preparing)
        placeholder.completions[2](true)
        #expect(session.state == .visible)
        placeholder.completions[0](true)
        #expect(session.state == .visible)

        _ = delegate.toggleLauncher()
        #expect(session.state == .dismissing)
        placeholder.completions[2](true)
        #expect(session.state == .dismissing)
        placeholder.isVisible = false
        placeholder.completions[3](true)
        #expect(session.state == .inactive)
        try await wait { services.isRunning }
        try await services.stop()
    }

    private final class DeferredPlaceholder: LauncherPlaceholderPresenting {
        var isVisible = false
        var onDismiss: (@MainActor () -> Void)?
        var retainsFocusForOwnedInteraction: (@MainActor () -> Bool)?
        var requests: [Bool] = []
        var completions: [@MainActor (Bool) -> Void] = []

        func setVisible(_ visible: Bool, completion: @escaping @MainActor (Bool) -> Void) {
            requests.append(visible)
            completions.append(completion)
        }
        func stop() { isVisible = false }
    }

    private final class FocusablePlaceholder: LauncherPlaceholderPresenting {
        var isVisible = false
        var onDismiss: (@MainActor () -> Void)?
        var retainsFocusForOwnedInteraction: (@MainActor () -> Bool)?
        var requests: [Bool] = []

        func setVisible(_ visible: Bool, completion: @escaping @MainActor (Bool) -> Void) {
            requests.append(visible)
            isVisible = visible
            completion(true)
        }
        func stop() { isVisible = false }
    }

    private final class UnavailablePlaceholder: LauncherPlaceholderPresenting {
        var isVisible = false
        var onDismiss: (@MainActor () -> Void)?
        var retainsFocusForOwnedInteraction: (@MainActor () -> Bool)?
        var requests: [Bool] = []

        func setVisible(_ visible: Bool, completion: @escaping @MainActor (Bool) -> Void) {
            requests.append(visible)
            completion(false)
        }
        func stop() {}
    }

    private func wait(until condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Timed out waiting for the application lifecycle callback.")
    }

}

@MainActor
private final class OpacityDurationObserver: NSObject, CALayerDelegate {
    var durations: [CFTimeInterval] = []

    nonisolated func action(for layer: CALayer, forKey event: String) -> (any CAAction)? {
        MainActor.assumeIsolated {
            if event == "opacity" { durations.append(CATransaction.animationDuration()) }
            return nil
        }
    }
}
