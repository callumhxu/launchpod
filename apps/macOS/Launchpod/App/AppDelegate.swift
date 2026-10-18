import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    #if DEBUG
    /// Prevents the background unit-test host from presenting UI or starting application services.
    var suppressesTestHostPresentation = false
    #endif
    private(set) var services: AppServices?
    /// The saved Classical arrangement, loaded before the catalog starts.
    private(set) var classicalLayout: ClassicalLayoutModel?
    private(set) var coordinator: LauncherCoordinator?
    private(set) var launcherPlaceholder: (any LauncherPlaceholderPresenting)?
    private(set) var statusItemController: LauncherStatusItemController?
    let languagePreference: AppLanguagePreference
    let directoryPreference: AppDirectoryPreference
    let shortcutPreference: ShortcutPreference
    let applicationIconPreference: ApplicationIconPreference
    let softwareUpdates = SoftwareUpdateController()
    private(set) lazy var globalShortcut = GlobalShortcut(register: globalShortcutRegister) { [weak self] in
        #if DEBUG
        let scope = WindowInvocationDiagnostics.shared.begin(.globalHotkey)
        defer { WindowInvocationDiagnostics.shared.end(scope) }
        #endif
        self?.toggleLauncher(suppressSlowMotion: true)
    }
    private(set) var settingsWindow: SettingsWindowController?
    let onboarding: OnboardingModel
    private(set) var onboardingWindow: OnboardingWindowController?
    /// Handles commands received by our panels without relying on the active app's menu bar.
    private(set) lazy var commandShortcuts = AppCommandShortcuts(
        commands: AppCommandShortcuts.launcherCommands(
            openSettings: { [weak self] in
                #if DEBUG
                let scope = WindowInvocationDiagnostics.shared.begin(.commandComma)
                defer { WindowInvocationDiagnostics.shared.end(scope) }
                #endif
                self?.openSettings()
            }
        )
    )
    private var startupTask: Task<Void, Never>?
    private var directoryUpdateTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let makeServices: @MainActor () throws -> AppServices
    private let makeClassicalLayout: @MainActor () -> ClassicalLayoutModel
    private let presentError: @MainActor (any Error) -> Void
    private let replyToTermination: @MainActor (Bool) -> Void
    private let makePlaceholder: (@MainActor (AppLanguagePreference) -> any LauncherPlaceholderPresenting)?
    private let globalShortcutRegister: GlobalShortcut.Register?
    private let installStatusItem: Bool
    private let requestTermination: @MainActor () -> Void
    private let relaunch: @MainActor () async throws -> Void
    private let confirmQuit: @MainActor (AppLanguagePreference) -> Bool
    private let presentSettings: (@MainActor (AppDelegate) -> Void)?
    private let presentOnboarding: (@MainActor (AppDelegate) -> Void)?
    private var restartRequested = false
    private var isConfirmingQuit = false
    /// The key code of a hold that completed while still physically down.
    private var heldQuitKeyCode: UInt16?
    private var restoreHeldQuitInterface: (@MainActor () -> Void)?
    private let isKeyPressed: @MainActor (UInt16) -> Bool
    private let holdToQuitPrompt = HoldToQuitPrompt()
    private(set) lazy var holdToQuitController = HoldToQuitController(
        isEligible: { [weak self] in
            guard let self else { return false }
            return self.terminationTask == nil && !self.isConfirmingQuit && !self.restartRequested
                && HoldToQuitController.canHandleShortcut(in: .shared)
        },
        isKeyPressed: { [weak self] keyCode in self?.isKeyPressed(keyCode) ?? false },
        showPrompt: { [weak self] in
            guard let self else { return }
            self.holdToQuitPrompt.show(locale: self.languagePreference.locale)
        },
        updateProgress: { [weak self] fraction in
            self?.holdToQuitPrompt.update(progress: fraction)
        },
        hidePrompt: { [weak self] in self?.holdToQuitPrompt.hide() },
        quit: { [weak self] keyCode in self?.quitAfterHoldingShortcut(keyCode: keyCode) }
    )

    isolated deinit {
        launcherPlaceholder?.stop()
        statusItemController?.stop()
        settingsWindow?.stop()
        onboardingWindow?.stop()
    }

    override convenience init() {
        self.init(
            defaults: .standard,
            makeServices: Self.makeServices,
            makeClassicalLayout: Self.makeClassicalLayout,
            presentError: { NSApplication.shared.presentError($0) },
            replyToTermination: { NSApplication.shared.reply(toApplicationShouldTerminate: $0) },
            makePlaceholder: { languagePreference in
                if UserDefaults.standard.string(forKey: "launcherMode") == LauncherMode.window.rawValue {
                    return LauncherPlaceholderWindowController(languagePreference: languagePreference)
                }
                return ClassicalWindowController()
            },
            presentOnboarding: { $0.openOnboarding() }
        )
    }

    init(
        defaults: UserDefaults,
        makeServices: @escaping @MainActor () throws -> AppServices,
        makeClassicalLayout: @escaping @MainActor () -> ClassicalLayoutModel = { ClassicalLayoutModel(store: nil) },
        presentError: @escaping @MainActor (any Error) -> Void,
        replyToTermination: @escaping @MainActor (Bool) -> Void,
        makePlaceholder: (@MainActor (AppLanguagePreference) -> any LauncherPlaceholderPresenting)? = {
            LauncherPlaceholderWindowController(languagePreference: $0)
        },
        globalShortcutRegister: GlobalShortcut.Register? = nil,
        installStatusItem: Bool = true,
        requestTermination: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) },
        relaunch: @escaping @MainActor () async throws -> Void = AppDelegate.relaunchApplication,
        confirmQuit: @escaping @MainActor (AppLanguagePreference) -> Bool = {
            QuitConfirmation.confirm(locale: $0.locale)
        },
        presentSettings: (@MainActor (AppDelegate) -> Void)? = nil,
        presentOnboarding: (@MainActor (AppDelegate) -> Void)? = nil,
        applicationIconApplier: any ApplicationIconApplying = ApplicationIconApplierFactory.make(
            isIsolated: DockMutationPolicy.isIsolated,
            system: SystemApplicationIconApplier()
        ),
        isKeyPressed: @escaping @MainActor (UInt16) -> Bool = {
            CGEventSource.keyState(.combinedSessionState, key: $0)
        }
    ) {
        self.defaults = defaults
        onboarding = OnboardingModel(defaults: defaults)
        languagePreference = AppLanguagePreference(defaults: defaults)
        directoryPreference = AppDirectoryPreference(defaults: defaults)
        shortcutPreference = ShortcutPreference(defaults: defaults)
        applicationIconPreference = ApplicationIconPreference(
            defaults: ApplicationIconDefaultsFactory.make(
                isIsolated: DockMutationPolicy.isIsolated,
                fallback: defaults
            ),
            applier: applicationIconApplier
        )
        self.makeServices = makeServices
        self.makeClassicalLayout = makeClassicalLayout
        self.presentError = presentError
        self.replyToTermination = replyToTermination
        self.makePlaceholder = makePlaceholder
        self.globalShortcutRegister = globalShortcutRegister
        self.installStatusItem = installStatusItem
        self.requestTermination = requestTermination
        self.relaunch = relaunch
        self.confirmQuit = confirmQuit
        self.presentSettings = presentSettings
        self.presentOnboarding = presentOnboarding
        self.isKeyPressed = isKeyPressed
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        guard !suppressesTestHostPresentation else { return }
        let scope = WindowInvocationDiagnostics.shared.begin(.startup)
        defer { WindowInvocationDiagnostics.shared.end(scope) }
        #endif
        guard services == nil else { return }
        // A crash or forced quit while the Classical launcher showed an auto-hiding Dock left auto-hide off.
        ClassicalDockReveal().recoverAfterUnexpectedExit()
        // Before settings or the launcher read them, carry over a grid set with `defaults write com.apple.dock`.
        ClassicalGridPreference.importDockSettingsIfNeeded(into: defaults)
        do {
            let services = try makeServices()
            self.services = services
            let layout = makeClassicalLayout()
            layout.onError = { [weak self] in self?.presentError($0) }
            classicalLayout = layout
            services.onApplicationsChanged = { [weak self] affectedIDs in
                guard let self, self.terminationTask == nil else { return }
                (self.launcherPlaceholder as? ClassicalWindowController)?.refreshApplications(invalidatingIcons: affectedIDs)
            }
            let defaults = self.defaults
            let mode = defaults.string(forKey: "launcherMode").flatMap(LauncherMode.init(rawValue:)) ?? .classical
            coordinator = LauncherCoordinator(mode: mode, launcher: services.launcher) {
                defaults.set($0.rawValue, forKey: "launcherMode")
            }
            globalShortcut.update(binding: shortcutPreference.selection)
            holdToQuitController.start()
            commandShortcuts.start()
            if installStatusItem {
                statusItemController = LauncherStatusItemController(
                    languagePreference: languagePreference,
                    softwareUpdates: softwareUpdates,
                    toggle: { [weak self] in self?.toggleLauncher() },
                    openSettings: { [weak self] in self?.openSettings() },
                    restart: { [weak self] in self?.restartApplication() }
                )
                setMenuBarVisible(defaults.object(forKey: "showInMenuBar") as? Bool ?? true)
            }
            startServices()
            if !onboarding.hasCompleted, let presentOnboarding {
                onboarding.begin()
                presentOnboarding(self)
            } else {
                showLauncher()
            }
        } catch {
            presentError(error)
        }
    }

    @discardableResult
    func toggleLauncher(suppressSlowMotion: Bool = false) -> LauncherPresentationState.Transition? {
        #if DEBUG
        let scope = WindowInvocationDiagnostics.shared.ensureRequest(.directLauncher)
        defer { WindowInvocationDiagnostics.shared.end(scope) }
        WindowInvocationDiagnostics.shared.record("launcher.toggle", detail: "terminating=\(terminationTask != nil) phase=\(String(describing: coordinator?.session?.presentation.phase))")
        #endif
        guard terminationTask == nil else { return nil }
        if onboarding.isPresented {
            onboardingWindow?.show()
            return nil
        }
        guard let transition = coordinator?.toggle() else { return nil }
        present(transition, suppressSlowMotion: suppressSlowMotion)
        return transition
    }

    @discardableResult
    func showLauncher() -> LauncherPresentationState.Transition? {
        #if DEBUG
        let scope = WindowInvocationDiagnostics.shared.ensureRequest(.directLauncher)
        defer { WindowInvocationDiagnostics.shared.end(scope) }
        WindowInvocationDiagnostics.shared.record("launcher.show", detail: "terminating=\(terminationTask != nil) phase=\(String(describing: coordinator?.session?.presentation.phase))")
        #endif
        guard terminationTask == nil, !onboarding.isPresented else { return nil }
        guard
              let transition = coordinator?.sessionForSelectedMode()?.presentation.requestVisibility(true) else { return nil }
        present(transition)
        return transition
    }

    private func present(_ transition: LauncherPresentationState.Transition, suppressSlowMotion: Bool = false) {
        #if DEBUG
        let request = WindowInvocationDiagnostics.shared.currentRequest
        WindowInvocationDiagnostics.shared.record("launcher.present", request: request, detail: "targetVisible=\(transition.targetIsVisible)")
        #endif
        if launcherPlaceholder == nil, let makePlaceholder {
            launcherPlaceholder = makePlaceholder(languagePreference)
            (launcherPlaceholder as? ClassicalWindowController)?.pageContent = services.flatMap { services in
                classicalLayout.map { ClassicalPageContent(services: services, layout: $0) }
            }
            (launcherPlaceholder as? ClassicalWindowController)?.locale = { [weak self] in
                self?.languagePreference.locale ?? .current
            }
            (launcherPlaceholder as? ClassicalWindowController)?.openSettings = { [weak self] in
                self?.openSettings()
            }
            (launcherPlaceholder as? ClassicalWindowController)?.showsMenuBarItem = { [weak self] in
                guard let self else { return true }
                return self.defaults.object(forKey: "showInMenuBar") as? Bool ?? true
            }
            (launcherPlaceholder as? ClassicalWindowController)?.onDismissRequested = { [weak self] in
                guard let self,
                      let dismissal = self.coordinator?.session?.presentation.requestVisibility(false) else { return }
                self.present(dismissal)
            }
            launcherPlaceholder?.onDismiss = { [weak self] in
                self?.launcherPlaceholderDidDismiss()
            }
            launcherPlaceholder?.retainsFocusForOwnedInteraction = { [weak self] in
                self?.statusItemController?.isHandlingInteraction == true
            }
        }
        if let launcherPlaceholder {
            let completion: @MainActor (Bool) -> Void = { [weak self] completed in
                #if DEBUG
                WindowInvocationDiagnostics.shared.record("launcher.completion", window: (self?.launcherPlaceholder as? NSWindowController)?.window,
                                                          request: request, detail: "completed=\(completed) targetVisible=\(transition.targetIsVisible)")
                #endif
                guard completed else { return }
                self?.coordinator?.complete(transition)
                #if DEBUG
                WindowInvocationDiagnostics.shared.record("launcher.coordinatorCompleted", request: request,
                                                          detail: "phase=\(String(describing: self?.coordinator?.session?.presentation.phase))")
                #endif
            }
            if suppressSlowMotion, let classical = launcherPlaceholder as? ClassicalWindowController {
                classical.setVisible(transition.targetIsVisible, suppressSlowMotion: true, completion: completion)
            } else {
                launcherPlaceholder.setVisible(transition.targetIsVisible, completion: completion)
            }
        }
    }

    private func launcherPlaceholderDidDismiss() {
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.onDismiss", window: (launcherPlaceholder as? NSWindowController)?.window,
                                                  detail: "phase=\(String(describing: coordinator?.session?.presentation.phase))")
        #endif
        guard launcherPlaceholder?.isVisible == false,
              let transition = coordinator?.session?.presentation.requestVisibility(false) else { return }
        coordinator?.complete(transition)
    }

    func setMenuBarVisible(_ visible: Bool) {
        statusItemController?.statusItem?.isVisible = visible
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        #if DEBUG
        let scope = WindowInvocationDiagnostics.shared.begin(.dockReopen)
        defer { WindowInvocationDiagnostics.shared.end(scope) }
        WindowInvocationDiagnostics.shared.record("application.reopen", detail: "hasVisibleWindows=\(flag)")
        #endif
        toggleLauncher()
        return false
    }

    /// Reuses one settings panel for the menu item and for ⌘,.
    func openSettings(page: SettingsView.Page? = nil) {
        #if DEBUG
        guard !suppressesTestHostPresentation else { return }
        let scope = WindowInvocationDiagnostics.shared.ensureRequest(.directSettings)
        defer { WindowInvocationDiagnostics.shared.end(scope) }
        WindowInvocationDiagnostics.shared.record("settings.open", detail: "terminating=\(terminationTask != nil) customPresenter=\(presentSettings != nil)")
        #endif
        guard terminationTask == nil else { return }
        if let presentSettings {
            presentSettings(self)
            return
        }
        let settingsWindow = settingsWindow ?? SettingsWindowController(
            languagePreference: languagePreference,
            shortcutPreference: shortcutPreference,
            globalShortcut: globalShortcut,
            applicationIconPreference: applicationIconPreference,
            launchAtLogin: LaunchAtLoginModel(),
            softwareUpdates: softwareUpdates,
            directoryPreference: directoryPreference,
            showIntroduction: { [weak self] in self?.openOnboarding() },
            classicalLayout: classicalLayout,
            onLayoutChanged: { [weak self] in
                (self?.launcherPlaceholder as? ClassicalWindowController)?.refreshApplications(invalidatingIcons: [])
            },
            onDirectoriesChanged: { [weak self] _ in
                guard let self else { return }
                let previous = self.directoryUpdateTask
                self.directoryUpdateTask = Task { @MainActor [weak self] in
                    await previous?.value
                    guard let self else { return }
                    await self.startupTask?.value
                    do { try await self.services?.updateDirectories(self.directoryPreference.directories) }
                    catch { self.presentError(error) }
                }
            }
        )
        self.settingsWindow = settingsWindow
        settingsWindow.show(page: page)
    }

    func openOnboarding() {
        #if DEBUG
        guard !suppressesTestHostPresentation else { return }
        #endif
        guard terminationTask == nil else { return }
        if let dismissal = coordinator?.session?.presentation.requestVisibility(false) {
            present(dismissal)
        }
        if onboardingWindow == nil {
            onboarding.begin()
            onboardingWindow = OnboardingWindowController(
                model: onboarding, languagePreference: languagePreference,
                onFinish: { [weak self] in self?.finishOnboarding() },
                openSettings: { [weak self] in self?.openSettings() }
            )
        }
        onboardingWindow?.show()
    }

    func finishOnboarding() {
        guard onboarding.isPresented else { return }
        onboarding.finish()
        onboardingWindow?.stop()
        onboardingWindow = nil
        showLauncher()
    }

    func restartApplication() {
        guard terminationTask == nil, !restartRequested, !isConfirmingQuit else { return }
        restartRequested = true
        requestTermination()
    }

    func quitAfterHoldingShortcut(keyCode: UInt16) {
        guard terminationTask == nil, !restartRequested, !isConfirmingQuit, heldQuitKeyCode == nil else { return }
        heldQuitKeyCode = keyCode
        holdToQuitController.beginDraining(keyCode: keyCode)
        restoreHeldQuitInterface = hideInterfaceForHeldQuit()
        requestTermination()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        guard !isConfirmingQuit else { return .terminateCancel }
        let heldKeyCode = heldQuitKeyCode
        heldQuitKeyCode = nil
        let restoreInterface = restoreHeldQuitInterface
        restoreHeldQuitInterface = nil
        let skipConfirmation = heldKeyCode != nil
        holdToQuitController.cancel()
        if !restartRequested && !skipConfirmation {
            isConfirmingQuit = true
            let confirmed = confirmQuit(languagePreference)
            isConfirmingQuit = false
            guard confirmed else { return .terminateCancel }
        }
        guard services != nil || restartRequested || heldKeyCode != nil else { return .terminateNow }
        startupTask?.cancel()
        terminationTask = Task {
            await startupTask?.value
            await directoryUpdateTask?.value
            do {
                if let heldKeyCode { await absorbHeldShortcut(keyCode: heldKeyCode) }
                try await services?.stop()
                if restartRequested {
                    globalShortcut.stop()
                    // The new instance loads the layout at startup; finish this process's writes first.
                    await classicalLayout?.flush()
                    try await relaunch()
                }
                globalShortcut.stop()
                statusItemController?.stop()
                statusItemController = nil
                settingsWindow?.stop()
                settingsWindow = nil
                onboardingWindow?.stop()
                onboardingWindow = nil
                launcherPlaceholder?.stop()
                launcherPlaceholder = nil
                coordinator?.stop()
                holdToQuitController.stop()
                commandShortcuts.stop()
                await classicalLayout?.flush()
                replyToTermination(true)
            } catch {
                restartRequested = false
                terminationTask = nil
                holdToQuitController.endDraining()
                restoreInterface?()
                presentError(error)
                replyToTermination(false)
                globalShortcut.update(binding: shortcutPreference.selection)
                startServices()
            }
        }
        return .terminateLater
    }

    /// Hides the interface while retaining the panels receiving this app's key events.
    /// The returned action restores the prior presentation if saving fails.
    private func hideInterfaceForHeldQuit() -> @MainActor () -> Void {
        holdToQuitPrompt.hide()
        let launcherWindow = (launcherPlaceholder as? NSWindowController)?.window
        let windows = [launcherWindow, settingsWindow?.window, onboardingWindow?.window].compactMap { $0 }.map {
            (window: $0, alpha: $0.alphaValue, isVisible: $0.isVisible, isKey: $0.isKeyWindow)
        }
        let menuBarVisible = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        for state in windows { state.window.alphaValue = 0 }
        setMenuBarVisible(false)
        return { [weak self] in
            for state in windows {
                if state.isVisible {
                    state.window.orderFrontRegardless()
                } else {
                    state.window.orderOut(nil)
                }
                state.window.alphaValue = state.alpha
            }
            windows.first(where: { $0.isKey })?.window.makeKey()
            if let launcherWindow,
               let transition = self?.coordinator?.session?.presentation.requestVisibility(launcherWindow.isVisible) {
                self?.coordinator?.complete(transition)
            }
            self?.setMenuBarVisible(menuBarVisible)
        }
    }

    /// Waits for physical release while the local monitor consumes this app's Q events.
    private func absorbHeldShortcut(keyCode: UInt16) async {
        while isKeyPressed(keyCode) {
            try? await Task.sleep(for: .milliseconds(30))
        }
        holdToQuitController.endDraining()
    }

    private func startServices() {
        guard terminationTask == nil, let services else { return }
        let layout = classicalLayout
        startupTask = Task {
            do {
                await layout?.load()
                try await services.updateDirectories(directoryPreference.directories)
                try await services.start()
            } catch is CancellationError {
                return
            } catch {
                presentError(error)
            }
        }
    }

    private static func makeClassicalLayout() -> ClassicalLayoutModel {
        let directory = URL.applicationSupportDirectory.appending(path: "Launchpod/Classical", directoryHint: .isDirectory)
        return ClassicalLayoutModel(store: ClassicalLayoutStore(directoryURL: directory))
    }

    private static func makeServices() throws -> AppServices {
        let directory = URL.applicationSupportDirectory.appending(path: "Launchpod", directoryHint: .isDirectory)
        return AppServices(
            store: try AppDataStore(directoryURL: directory),
            icons: AppIconRepository(cacheCostLimit: 64 * 1024 * 1024),
            onError: { NSApplication.shared.presentError($0) }
        )
    }

    private static func relaunchApplication() async throws {
        let applicationURL = Bundle.main.bundleURL
        guard applicationURL.pathExtension == "app" else {
            throw CocoaError(.executableNotLoadable)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        _ = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }
}
