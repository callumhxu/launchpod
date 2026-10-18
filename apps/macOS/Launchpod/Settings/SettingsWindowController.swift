import AppKit
import Observation
import SwiftUI

/// Owns the reusable settings panel and presents it without requesting app activation.
/// The panel stays at the ordinary window level, allowing other apps to cover it
/// when the user switches away.
@MainActor
final class SettingsWindowController: NSWindowController {
    private static let contentSize = NSSize(width: 480, height: 480)
    private let languagePreference: AppLanguagePreference
    private let tabController: NSTabViewController

    var isVisible: Bool { window?.isVisible == true }

    init(
        languagePreference: AppLanguagePreference,
        shortcutPreference: ShortcutPreference,
        globalShortcut: GlobalShortcut,
        applicationIconPreference: ApplicationIconPreference,
        launchAtLogin: LaunchAtLoginModel,
        softwareUpdates: SoftwareUpdateController? = nil,
        directoryPreference: AppDirectoryPreference? = nil,
        showIntroduction: @escaping @MainActor () -> Void = {},
        classicalLayout: ClassicalLayoutModel? = nil,
        onLayoutChanged: @escaping @MainActor @Sendable () -> Void = {},
        onDirectoriesChanged: @escaping @MainActor @Sendable ([ApplicationScan.Directory]) -> Void = { _ in },
        dockStore: any DockPersistentAppsStore = InMemoryDockPersistentAppsStore.forCurrentProcess()
    ) {
        self.languagePreference = languagePreference
        let softwareUpdates = softwareUpdates ?? SoftwareUpdateController(infoDictionary: [:])
        let keepInDock = KeepInDockModel(store: dockStore)
        let directoryPreference = directoryPreference ?? AppDirectoryPreference()
        let tabController = NSTabViewController()
        self.tabController = tabController
        let panel = SettingsPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.identifier = AppShortcutFocus.settingsWindowIdentifier
        panel.toolbarStyle = .preference
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        // Keep the panel available even when its application is inactive.
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        // Deliberately an ordinary level: `orderFrontRegardless()` brings the
        // panel to the front of its level even when its application is inactive.
        // Other apps can cover it when the user switches away.
        tabController.tabStyle = .toolbar
        tabController.canPropagateSelectedChildViewControllerTitle = false
        for page in SettingsView.Page.allCases {
            let controller = SettingsPageController(content: SettingsContent(
                page: page,
                languagePreference: languagePreference,
                shortcutPreference: shortcutPreference,
                globalShortcut: globalShortcut,
                directoryPreference: directoryPreference,
                applicationIconPreference: applicationIconPreference,
                launchAtLogin: launchAtLogin,
                classicalLayout: classicalLayout,
                onLayoutChanged: onLayoutChanged,
                onDirectoriesChanged: onDirectoriesChanged,
                keepInDock: keepInDock,
                softwareUpdates: softwareUpdates,
                showIntroduction: showIntroduction
            ))
            let item = NSTabViewItem(viewController: controller)
            item.identifier = page.rawValue
            item.image = NSImage(systemSymbolName: page.systemImage, accessibilityDescription: nil)
            tabController.addTabViewItem(item)
        }
        tabController.view.setFrameSize(Self.contentSize)
        panel.contentViewController = tabController
        panel.center()
        super.init(window: panel)
        observeLanguage()
    }

    required init?(coder: NSCoder) { nil }

    isolated deinit {
        #if DEBUG
        if let window { WindowInvocationDiagnostics.shared.stopObserving(window: window) }
        #endif
        window?.close()
    }

    /// Reuses the one panel, and takes keyboard focus without activating.
    func show(page selectedPage: SettingsView.Page? = nil) {
        #if DEBUG
        let scope = WindowInvocationDiagnostics.shared.ensureRequest(.directSettings)
        defer { WindowInvocationDiagnostics.shared.end(scope) }
        #endif
        guard let window else { return }
        #if DEBUG
        let diagnostics = WindowInvocationDiagnostics.shared
        diagnostics.observe(window: window, request: scope.request)
        diagnostics.record("settings.show", window: window)
        defer { diagnostics.sampleAfterEventLoop(window: window, request: scope.request) }
        #endif
        languagePreference.refreshSystemLanguages()
        if let selectedPage,
           let index = SettingsView.Page.allCases.firstIndex(of: selectedPage) {
            tabController.selectedTabViewItemIndex = index
        } else if !window.isVisible {
            tabController.selectedTabViewItemIndex = 0
        }
        window.title = String(localized: LocalizedStringResource("Settings", locale: languagePreference.locale))
        #if DEBUG
        diagnostics.record("settings.beforeOrderFront", window: window, includeOrdering: true)
        #endif
        window.orderFrontRegardless()
        window.toolbar?.displayMode = .iconAndLabel
        #if DEBUG
        diagnostics.record("settings.afterOrderFront.beforeMakeKey", window: window, includeOrdering: true)
        #endif
        window.makeKey()
        #if DEBUG
        diagnostics.record("settings.afterMakeKey", window: window, includeOrdering: true)
        #endif
    }

    func stop() {
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("settings.stop", window: window)
        if let window { WindowInvocationDiagnostics.shared.stopObserving(window: window) }
        #endif
        window?.close()
        window = nil
    }

    private func observeLanguage() {
        withObservationTracking {
            let locale = languagePreference.locale
            window?.title = String(localized: LocalizedStringResource("Settings", locale: locale))
            for (page, item) in zip(SettingsView.Page.allCases, tabController.tabViewItems) {
                item.label = page.title(locale: locale)
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeLanguage()
            }
        }
    }

    private final class SettingsPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    /// A non-activating panel only routes keys to views that ask for them.
    private final class SettingsHostingView: NSHostingView<SettingsContent> {
        override var acceptsFirstResponder: Bool { true }
        override var needsPanelToBecomeKey: Bool { true }
    }

    private final class SettingsPageController: NSViewController {
        private let content: SettingsContent

        init(content: SettingsContent) {
            self.content = content
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            let hostingView = SettingsHostingView(rootView: content)
            // Constrain resizing to the content's minimum and maximum sizes.
            hostingView.sizingOptions = [.minSize, .maxSize]
            view = hostingView
        }
    }

    /// Binds the shared preferences through `UserDefaults`.
    private struct SettingsContent: View {
        let page: SettingsView.Page
        let languagePreference: AppLanguagePreference
        let shortcutPreference: ShortcutPreference
        let globalShortcut: GlobalShortcut
        let directoryPreference: AppDirectoryPreference
        let applicationIconPreference: ApplicationIconPreference
        let launchAtLogin: LaunchAtLoginModel
        let classicalLayout: ClassicalLayoutModel?
        let onLayoutChanged: @MainActor @Sendable () -> Void
        let onDirectoriesChanged: @MainActor @Sendable ([ApplicationScan.Directory]) -> Void
        let keepInDock: KeepInDockModel
        let softwareUpdates: SoftwareUpdateController
        let showIntroduction: @MainActor () -> Void
        @AppStorage(AppAppearance.preferenceKey) private var appearance = AppAppearance.automatic
        @AppStorage("showInMenuBar") private var showInMenuBar = true
        @AppStorage(ClassicalDockPreference.key) private var classicalHidesDock = false
        @AppStorage(ClassicalFolderGlassPreference.key)
        private var classicalFolderLiquidGlass = ClassicalFolderGlassPreference.defaultValue
        @AppStorage(ClassicalGridPreference.rowsKey) private var classicalRows = ClassicalSpringboardGeometry.defaultRows
        @AppStorage(ClassicalGridPreference.columnsKey) private var classicalColumns = ClassicalSpringboardGeometry.defaultColumns

        var body: some View {
            SettingsView(
                page: page,
                languagePreference: languagePreference,
                directoryPreference: directoryPreference,
                appearance: $appearance,
                showInMenuBar: $showInMenuBar,
                classicalHidesDock: $classicalHidesDock,
                classicalFolderLiquidGlass: $classicalFolderLiquidGlass,
                classicalRows: $classicalRows,
                classicalColumns: $classicalColumns,
                shortcutPreference: shortcutPreference,
                globalShortcut: globalShortcut,
                applicationIconPreference: applicationIconPreference,
                launchAtLogin: launchAtLogin,
                classicalLayout: classicalLayout,
                onLayoutChanged: onLayoutChanged,
                onDirectoriesChanged: onDirectoriesChanged,
                keepInDock: keepInDock,
                softwareUpdates: softwareUpdates,
                showIntroduction: showIntroduction
            )
                .environment(\.locale, languagePreference.locale)
        }
    }
}
