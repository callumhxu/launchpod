import AppKit
import Combine

@MainActor
final class LauncherStatusItemController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private(set) var statusItem: NSStatusItem?
    let menu = NSMenu()
    private(set) var isTrackingMenu = false
    private let languagePreference: AppLanguagePreference
    private let softwareUpdates: SoftwareUpdateController
    private var updateObservation: AnyCancellable?
    private let toggle: @MainActor () -> Void
    private let openSettings: @MainActor () -> Void
    private let restart: @MainActor () -> Void
    private let quit: @MainActor () -> Void
    private let showMenu: @MainActor (NSStatusItem, NSMenu) -> Void

    var isHandlingInteraction: Bool {
        if isTrackingMenu { return true }
        guard NSEvent.pressedMouseButtons != 0,
              let button = statusItem?.button, let window = button.window else { return false }
        let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return button.bounds.contains(button.convert(point, from: nil))
    }

    init(
        languagePreference: AppLanguagePreference,
        softwareUpdates: SoftwareUpdateController,
        toggle: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void,
        restart: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) },
        showMenu: @escaping @MainActor (NSStatusItem, NSMenu) -> Void = { item, menu in
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        }
    ) {
        self.languagePreference = languagePreference
        self.softwareUpdates = softwareUpdates
        self.toggle = toggle
        self.openSettings = openSettings
        self.restart = restart
        self.quit = quit
        self.showMenu = showMenu
        super.init()

        menu.delegate = self
        addItem(action: #selector(toggleLauncher), identifier: "toggleLauncher")
        menu.addItem(.separator())
        addItem(action: #selector(showSettings), identifier: "openSettings")
        addItem(action: #selector(checkForUpdates), identifier: "checkForUpdates")
        menu.addItem(.separator())
        addItem(action: #selector(restartLauncher), identifier: "restartLauncher")
        addItem(action: #selector(quitLauncher), identifier: "quitLauncher")
        refreshMenu()
        updateObservation = Publishers.CombineLatest(
            softwareUpdates.$canCheckForUpdates,
            softwareUpdates.$hasAvailableUpdate
        ).sink { [weak self] canCheckForUpdates, hasAvailableUpdate in
            self?.refreshUpdateMenuItem(canCheckForUpdates: canCheckForUpdates,
                                        hasAvailableUpdate: hasAvailableUpdate)
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Launchpod")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "Launchpod"
        statusItem.button?.setAccessibilityLabel("Launchpod")
        statusItem.button?.setAccessibilityIdentifier("launcherStatusItem")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.statusItem = statusItem
    }

    isolated deinit {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    func handleClick(_ event: NSEvent?) {
        #if DEBUG
        let scope = WindowInvocationDiagnostics.shared.begin(.statusButton)
        defer { WindowInvocationDiagnostics.shared.end(scope) }
        #endif
        guard let statusItem else { return }
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            #if DEBUG
            WindowInvocationDiagnostics.shared.record("statusButton.openMenu")
            #endif
            refreshMenu()
            isTrackingMenu = true
            defer { isTrackingMenu = false }
            showMenu(statusItem, menu)
        } else {
            toggle()
        }
    }

    func refreshMenu() {
        languagePreference.refreshSystemLanguages()
        let locale = languagePreference.locale
        menu.items[0].title = String(localized: LocalizedStringResource("Toggle Launchpod", locale: locale))
        menu.items[2].title = String(localized: LocalizedStringResource("Settings", locale: locale)) + "…"
        menu.items[3].title = String(localized: LocalizedStringResource("Check for Updates…", locale: locale))
        menu.items[5].title = String(localized: LocalizedStringResource("Restart Launchpod", locale: locale))
        menu.items[6].title = String(localized: LocalizedStringResource("Quit Launchpod", locale: locale))
        refreshUpdateMenuItem(canCheckForUpdates: softwareUpdates.canCheckForUpdates,
                              hasAvailableUpdate: softwareUpdates.hasAvailableUpdate)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(checkForUpdates) || softwareUpdates.canCheckForUpdates
    }

    private func refreshUpdateMenuItem(canCheckForUpdates: Bool, hasAvailableUpdate: Bool) {
        let item = menu.items[3]
        item.isEnabled = canCheckForUpdates
        item.image = hasAvailableUpdate
            ? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            : nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isTrackingMenu = true
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("statusMenu.willOpen")
        #endif
    }

    func menuDidClose(_ menu: NSMenu) {
        isTrackingMenu = false
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("statusMenu.didClose")
        #endif
    }

    func stop() {
        guard let statusItem else { return }
        menu.cancelTracking()
        isTrackingMenu = false
        statusItem.menu = nil
        statusItem.button?.target = nil
        statusItem.button?.action = nil
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func addItem(action: Selector, identifier: String) {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        item.target = self
        item.setAccessibilityIdentifier(identifier)
        menu.addItem(item)
    }

    @objc private func statusItemClicked(_ sender: Any?) { handleClick(NSApplication.shared.currentEvent) }
    @objc private func toggleLauncher(_ sender: Any?) {
        #if DEBUG
        let scope = WindowInvocationDiagnostics.shared.begin(.menuToggle)
        defer { WindowInvocationDiagnostics.shared.end(scope) }
        #endif
        toggle()
    }
    @objc private func showSettings(_ sender: Any?) {
        #if DEBUG
        let scope = WindowInvocationDiagnostics.shared.begin(.menuSettings)
        defer { WindowInvocationDiagnostics.shared.end(scope) }
        #endif
        openSettings()
    }
    @objc private func restartLauncher(_ sender: Any?) { restart() }
    @objc private func checkForUpdates(_ sender: Any?) { softwareUpdates.checkForUpdates() }
    @objc private func quitLauncher(_ sender: Any?) { quit() }
}
