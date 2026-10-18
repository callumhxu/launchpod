import AppKit
import Testing
@testable import Launchpod

@Suite(.serialized)
@MainActor
struct SettingsWindowControllerTests {

    @Test func theSettingsPanelCanBeShownAndFocusedWithoutActivatingTheApp() throws {
        let controller = try makeController()
        defer { controller.stop() }
        let panel = try #require(controller.window as? NSPanel)

        // Everything an ordinary window cannot do while the app is inactive.
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.becomesKeyOnlyIfNeeded)
        // An ordinary level: shown in front by `orderFrontRegardless()`, but
        // not pinned above every other app afterwards.
        #expect(panel.level == .normal)
        let content = try #require(panel.contentView)
        #expect(visibleViews(in: content).contains { $0.needsPanelToBecomeKey })
        #expect(panel.identifier == AppShortcutFocus.settingsWindowIdentifier)
        #expect(!controller.isVisible)
    }

    @Test func theSettingsPanelCanMoveAndCloseButCannotResize() throws {
        let controller = try makeController()
        defer { controller.stop() }
        let panel = try #require(controller.window)

        controller.show()
        panel.contentView?.layoutSubtreeIfNeeded()

        #expect(panel.isMovable)
        #expect(panel.styleMask.contains(.closable))
        #expect(!panel.styleMask.contains(.resizable))
        #expect(!panel.isZoomable)
        #expect(panel.standardWindowButton(.zoomButton)?.isEnabled != true)
    }

    @Test func theSettingsPanelStartsAtTheFixedContentSize() throws {
        let controller = try makeController()
        defer { controller.stop() }
        let panel = try #require(controller.window)

        panel.contentView?.layoutSubtreeIfNeeded()

        #expect(panel.contentLayoutRect.size == NSSize(width: 480, height: 480))
    }

    @Test func showingReusesTheOnePanelAndStopReleasesIt() throws {
        let controller = try makeController()
        let panel = try #require(controller.window)

        controller.show()
        #expect(controller.isVisible)
        controller.show()
        #expect(controller.window === panel)
        #expect(controller.isVisible)

        controller.stop()
        #expect(!controller.isVisible)
        #expect(controller.window == nil)
        controller.stop()
    }

    @Test func theSettingsPanelOwnsTheAppsCommandShortcuts() throws {
        let controller = try makeController()
        defer { controller.stop() }
        let panel = try #require(controller.window)

        // ⌘, and ⌘Q have no menu bar to come from while the app is inactive.
        #expect(AppShortcutFocus.ownsCommandShortcuts(focusedWindow: panel, hasModalPresentation: false))
    }

    @Test func theNativeSettingsHeaderRendersInEnglishAndChinese() async throws {
        for (language, title, labels) in [
            (AppLanguage.english, "Settings", ["General", "Interface", "Apps", "Shortcuts", "Advanced", "About"]),
            (.simplifiedChinese, CatalogTestSupport.text("Settings", locale: "zh-Hans"), [CatalogTestSupport.text("General", locale: "zh-Hans"), CatalogTestSupport.text("Interface", locale: "zh-Hans"), CatalogTestSupport.text("Apps", locale: "zh-Hans"), CatalogTestSupport.text("Shortcuts", locale: "zh-Hans"), CatalogTestSupport.text("Advanced", locale: "zh-Hans"), CatalogTestSupport.text("About", locale: "zh-Hans")])
        ] {
            let controller = try makeController(language: language)
            defer { controller.stop() }
            let panel = try #require(controller.window)
            controller.show()
            try await Task.sleep(for: .milliseconds(150))
            let frameView = try #require(panel.contentView?.superview)
            let bitmap = try NativeAppTestSupport.capture(frameView)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            Attachment.record(png, named: "Settings-\(language.rawValue)-native-header.png")
            Attachment.record(viewDescription(frameView), named: "Settings-\(language.rawValue)-native-views.txt")
            #expect(panel.title == title)
            #expect(panel.accessibilityTitle() == title)
            #expect(panel.titleVisibility == .visible)
            try expectHeaderGeometry(in: panel, title: title, labels: labels)
        }
    }

    @Test func nativeToolbarTabsShowTheirPagesAndKeepTheLocalizedSettingsTitle() async throws {
        for (language, title, labels) in [
            (AppLanguage.english, "Settings", ["General", "Interface", "Apps", "Shortcuts", "Advanced", "About"]),
            (.simplifiedChinese, CatalogTestSupport.text("Settings", locale: "zh-Hans"), [CatalogTestSupport.text("General", locale: "zh-Hans"), CatalogTestSupport.text("Interface", locale: "zh-Hans"), CatalogTestSupport.text("Apps", locale: "zh-Hans"), CatalogTestSupport.text("Shortcuts", locale: "zh-Hans"), CatalogTestSupport.text("Advanced", locale: "zh-Hans"), CatalogTestSupport.text("About", locale: "zh-Hans")]),
            (.traditionalChinese, CatalogTestSupport.text("Settings", locale: "zh-Hant"), [CatalogTestSupport.text("General", locale: "zh-Hant"), CatalogTestSupport.text("Interface", locale: "zh-Hant"), CatalogTestSupport.text("Apps", locale: "zh-Hant"), CatalogTestSupport.text("Shortcuts", locale: "zh-Hant"), CatalogTestSupport.text("Advanced", locale: "zh-Hant"), CatalogTestSupport.text("About", locale: "zh-Hant")]),
            (.french, CatalogTestSupport.text("Settings", locale: "fr"), [CatalogTestSupport.text("General", locale: "fr"), "Interface", "Apps", CatalogTestSupport.text("Shortcuts", locale: "fr"), CatalogTestSupport.text("Advanced", locale: "fr"), CatalogTestSupport.text("About", locale: "fr")]),
            (.german, CatalogTestSupport.text("Settings", locale: "de"), [CatalogTestSupport.text("General", locale: "de"), CatalogTestSupport.text("Interface", locale: "de"), "Apps", CatalogTestSupport.text("Shortcuts", locale: "de"), CatalogTestSupport.text("Advanced", locale: "de"), CatalogTestSupport.text("About", locale: "de")]),
            (.japanese, CatalogTestSupport.text("Settings", locale: "ja"), [CatalogTestSupport.text("General", locale: "ja"), CatalogTestSupport.text("Interface", locale: "ja"), CatalogTestSupport.text("Apps", locale: "ja"), CatalogTestSupport.text("Shortcuts", locale: "ja"), CatalogTestSupport.text("Advanced", locale: "ja"), CatalogTestSupport.text("About", locale: "ja")]),
            (.korean, CatalogTestSupport.text("Settings", locale: "ko"), [CatalogTestSupport.text("General", locale: "ko"), CatalogTestSupport.text("Interface", locale: "ko"), CatalogTestSupport.text("Apps", locale: "ko"), CatalogTestSupport.text("Shortcuts", locale: "ko"), CatalogTestSupport.text("Advanced", locale: "ko"), CatalogTestSupport.text("About", locale: "ko")]),
            (.spanish, CatalogTestSupport.text("Settings", locale: "es"), ["General", CatalogTestSupport.text("Interface", locale: "es"), "Apps", CatalogTestSupport.text("Shortcuts", locale: "es"), CatalogTestSupport.text("Advanced", locale: "es"), CatalogTestSupport.text("About", locale: "es")])
        ] {
            let controller = try makeController(language: language)
            defer { controller.stop() }
            let panel = try #require(controller.window)
            controller.show()
            try await settle(panel)
            let toolbar = try #require(panel.toolbar)
            #expect(toolbar.visibleItems?.map(\.label) == labels)
            #expect(toolbar.displayMode == .iconAndLabel)

            for (index, label) in labels.enumerated() {
                let item = try #require(toolbar.items.first { $0.label == label })
                #expect(item.image != nil, "\(label) must retain its native tab icon")
                try select(item)
                try await settle(panel)
                try expectPage(index, in: panel)
                #expect(panel.title == title, "\(label) must not replace the Settings title")
                #expect(panel.titleVisibility == .visible)
                _ = try titleField(in: panel, title: title)
                #expect(toolbar.selectedItemIdentifier == item.itemIdentifier)
                #expect(panel.contentLayoutRect.width == 480, "Settings must retain its original fixed content width")
                #expect(panel.frame.height > panel.frame.width, "Settings must remain portrait on every page")
                try expectHeaderGeometry(in: panel, title: title, labels: labels)
                let frameView = try #require(panel.contentView?.superview)
                let bitmap = try NativeAppTestSupport.capture(frameView)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                Attachment.record(png, named: "Settings-\(language.rawValue)-page-\(index).png")
            }
        }
    }

    @Test func showingAgainPreservesTheTabAndReopeningReturnsToGeneral() async throws {
        let controller = try makeController()
        defer { controller.stop() }
        let panel = try #require(controller.window)
        controller.show()
        try await settle(panel)
        let toolbar = try #require(panel.toolbar)

        for (index, label) in ["General", "Interface", "Apps", "Shortcuts", "Advanced", "About"].enumerated().dropFirst() {
            let item = try #require(toolbar.items.first { $0.label == label })
            try select(item)
            try await settle(panel)
            controller.show()
            try await settle(panel)
            try expectPage(index, in: panel)
            #expect(toolbar.selectedItemIdentifier == item.itemIdentifier)

            panel.close()
            controller.show()
            try await settle(panel)
            #expect(controller.window === panel)
            try expectPage(0, in: panel)
            #expect(!panel.styleMask.contains(.resizable))
            #expect(!panel.isZoomable)
        }
    }

    @Test func changingTheLanguageUpdatesTheOpenNativeHeaderWithoutChangingItsPage() async throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let preference = AppLanguagePreference(defaults: defaults, preferredLanguages: { ["en-US"] })
        let controller = try makeController(languagePreference: preference)
        defer { controller.stop() }
        let panel = try #require(controller.window)
        controller.show()
        try await settle(panel)
        let toolbar = try #require(panel.toolbar)
        try select(#require(toolbar.items.first { $0.label == "Shortcuts" }))
        try await settle(panel)

        preference.selection = .simplifiedChinese
        try await settle(panel)

        #expect(controller.window === panel)
        #expect(panel.title == CatalogTestSupport.text("Settings", locale: "zh-Hans"))
        #expect(toolbar.visibleItems?.map(\.label) == [CatalogTestSupport.text("General", locale: "zh-Hans"), CatalogTestSupport.text("Interface", locale: "zh-Hans"), CatalogTestSupport.text("Apps", locale: "zh-Hans"), CatalogTestSupport.text("Shortcuts", locale: "zh-Hans"), CatalogTestSupport.text("Advanced", locale: "zh-Hans"), CatalogTestSupport.text("About", locale: "zh-Hans")])
        _ = try titleField(in: panel, title: CatalogTestSupport.text("Settings", locale: "zh-Hans"))
        try expectPage(3, in: panel)
    }

    private func select(_ item: NSToolbarItem) throws {
        let action = try #require(item.action)
        #expect(NSApplication.shared.sendAction(action, to: item.target, from: item))
    }

    private func expectHeaderGeometry(in panel: NSWindow, title: String, labels: [String]) throws {
        let frameView = try #require(panel.contentView?.superview)
        let titleView = try titleField(in: panel, title: title)
        let titleFrame = panel.convertToScreen(titleView.convert(titleView.bounds, to: nil))
        let close = try #require(panel.standardWindowButton(.closeButton))
        let closeFrame = panel.convertToScreen(close.convert(close.bounds, to: nil))
        #expect(titleFrame.minY < closeFrame.maxY && titleFrame.maxY > closeFrame.minY)
        let views = visibleViews(in: frameView)
        var previousFrame: NSRect?
        for label in labels {
            let tab = try #require(views.first { $0.accessibilityRole() == .button && $0.accessibilityTitle() == label })
            let frame = panel.convertToScreen(tab.convert(tab.bounds, to: nil))
            #expect(frame.width > 0 && frame.height > 0)
            #expect(panel.frame.contains(frame), "\(label) must remain visible inside the window")
            #expect(frame.maxY < min(titleFrame.minY, closeFrame.minY), "\(label) must have space below the title row")
            #expect(visibleViews(in: tab).contains { ($0 as? NSButton)?.image != nil }, "\(label) must render its icon")
            if let previousFrame {
                #expect(abs(frame.midY - previousFrame.midY) <= 1, "Tabs must share one row")
                #expect(frame.minX >= previousFrame.maxX, "Tabs must retain their order without overlapping")
            }
            previousFrame = frame
        }
    }

    private func titleField(in panel: NSWindow, title: String) throws -> NSTextField {
        let frameView = try #require(panel.contentView?.superview)
        return try #require(visibleViews(in: frameView).compactMap { $0 as? NSTextField }.first {
            $0.stringValue == title && $0.bounds.width > 0 && $0.bounds.height > 0
        }, "The native title field must visibly render \(title)")
    }

    private func expectPage(_ index: Int, in panel: NSWindow) throws {
        let tabs = try #require(panel.contentViewController as? NSTabViewController)
        #expect(tabs.selectedTabViewItemIndex == index)
        let content = try #require(tabs.tabView.selectedTabViewItem?.view)
        #expect(content.window === panel)
        let views = visibleViews(in: content)
        #expect(views.contains { $0 is DockApplicationIconView } == (index == 0))
        #expect(views.contains { $0 is ShortcutRecorder.RecorderButton } == (index == 3))
        #expect(views.contains { $0.needsPanelToBecomeKey })
    }

    private func settle(_ panel: NSWindow) async throws {
        try await Task.sleep(for: .milliseconds(150))
        panel.contentView?.superview?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
    }

    private func viewDescription(_ view: NSView, depth: Int = 0) -> String {
        let details = "\(String(repeating: "  ", count: depth))\(type(of: view)) frame=\(view.frame) hidden=\(view.isHiddenOrHasHiddenAncestor) role=\(view.accessibilityRole()?.rawValue ?? "") title=\(view.accessibilityTitle() ?? "") label=\(view.accessibilityLabel() ?? "")"
        return ([details] + view.subviews.map { viewDescription($0, depth: depth + 1) }).joined(separator: "\n")
    }

    private func visibleViews(in view: NSView) -> [NSView] {
        guard !view.isHiddenOrHasHiddenAncestor else { return [] }
        return [view] + view.subviews.flatMap { visibleViews(in: $0) }
    }

    private func makeController(
        language: AppLanguage = .english,
        languagePreference: AppLanguagePreference? = nil
    ) throws -> SettingsWindowController {
        _ = NSApplication.shared
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        defaults.set(language.rawValue, forKey: AppLanguagePreference.preferenceKey)
        return SettingsWindowController(
            languagePreference: languagePreference ?? AppLanguagePreference(defaults: defaults, preferredLanguages: { ["en-US"] }),
            shortcutPreference: ShortcutPreference(defaults: defaults),
            globalShortcut: GlobalShortcut(register: { _, _ in {} }, action: {}),
            applicationIconPreference: ApplicationIconPreference(
                defaults: defaults, applier: NoopApplicationIconApplier()
            ),
            launchAtLogin: LaunchAtLoginModel(service: InMemoryLaunchAtLoginService()),
            directoryPreference: AppDirectoryPreference(defaults: defaults),
            dockStore: InMemoryDockPersistentAppsStore()
        )
    }

    private struct NoopApplicationIconApplier: ApplicationIconApplying {
        func apply(_ icon: ApplicationIcon) throws { }
    }

    private struct InMemoryLaunchAtLoginService: LaunchAtLoginServicing {
        var status: LaunchAtLoginStatus { .notRegistered }
        func register() throws { }
        func unregister() throws { }
    }
}
