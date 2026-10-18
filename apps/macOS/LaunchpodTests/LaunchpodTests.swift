//
//  LaunchpodTests.swift
//  LaunchpodTests
//
//  Created by Callum on 9/20/26.
//

import Testing
import AppKit
@testable import Launchpod

// Run with parallel testing disabled: these tests mutate the real app and standard defaults.
@Suite(.serialized)
@MainActor
struct LaunchpodTests {

    @Test func appTargetUsesOrdinaryApplicationSupportInDebugAndRelease() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectFile = testsDirectory.deletingLastPathComponent()
            .appending(path: "Launchpod.xcodeproj/project.pbxproj")
        let project = try String(contentsOf: projectFile, encoding: .utf8)

        for configuration in ["Debug", "Release"] {
            let marker = "/* \(configuration) configuration for PBXNativeTarget \"Launchpod\" */ = {"
            let start = try #require(project.range(of: marker)?.lowerBound)
            let remainder = project[start...]
            let end = try #require(remainder.range(of: "\n\t\t\t};")?.upperBound)
            let buildConfiguration = remainder[..<end]
            #expect(buildConfiguration.contains("ENABLE_APP_SANDBOX = NO;"),
                    "\(configuration) must use the ordinary Application Support directory that owns the saved layout.")
            #expect(!buildConfiguration.contains("ENABLE_APP_SANDBOX = YES;"))
            #expect(!buildConfiguration.contains("ENABLE_USER_SELECTED_FILES"),
                    "File access is not provided by an App Sandbox entitlement when the app target is unsandboxed.")
        }
    }

    @Test func runnerRequestedIsolationProtectsTheApplicationDefaultsAndSavedLayout() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let prefix = environment["LAUNCHPOD_EXPECTED_TEST_BUNDLE_PREFIX"],
              let home = environment["LAUNCHPOD_EXPECTED_TEST_HOME"] else { return }
        let identifier = try #require(Bundle.main.bundleIdentifier)
        #expect(identifier.hasPrefix(prefix))
        #expect(identifier != "app.joyx.launchpod")
        #expect(Bundle(for: AppDelegate.self).bundleURL == Bundle.main.bundleURL)
        let expectedHome = URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL
        let support = URL.applicationSupportDirectory.standardizedFileURL
        #expect(support.path.hasPrefix(expectedHome.path + "/"))
        #expect(DockMutationPolicy.isIsolated)
        Attachment.record("Bundle: \(identifier)\nApplication support: \(support.path)",
                          named: "test-host-storage-isolation.txt")
    }

    @Test func appearanceOwnerUpdatesOwnedWindowsEvenAfterTheLauncherCloses() async throws {
        let application = NSApplication.shared
        let delegate = try NativeAppTestSupport.appDelegate()
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        defer { delegate.settingsWindow?.window?.close() }
        let defaults = UserDefaults.standard
        let domain = try #require(Bundle.main.bundleIdentifier)
        let originalValue = defaults.persistentDomain(forName: domain)?[AppAppearance.preferenceKey]
        let originalAppearance = application.appearance
        let originalGlobalStyle = defaults.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? NSObject
        defer {
            application.appearance = originalAppearance
            if let originalValue {
                defaults.set(originalValue, forKey: AppAppearance.preferenceKey)
            } else {
                defaults.removeObject(forKey: AppAppearance.preferenceKey)
            }
        }

        let launcherWindow = try await showLauncher(delegate)
        let settingsWindow = try await NativeAppTestSupport.openSettings()
        try await expectFocused(settingsWindow)
        #expect(try await showLauncher(delegate) === launcherWindow)
        #expect(settingsWindow.isVisible)
        application.appearance = nil
        let systemAppearance = try #require(application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]))
        try await expectAppearanceOwner(updates: [launcherWindow, settingsWindow], systemAppearance: systemAppearance)

        launcherWindow.cancelOperation(nil)
        try await expectHidden(launcherWindow)
        #expect(settingsWindow.isVisible)
        try await expectAppearanceOwner(updates: [settingsWindow], systemAppearance: systemAppearance)
        #expect(!delegate.applicationShouldHandleReopen(application, hasVisibleWindows: true))
        try await expectFocused(launcherWindow)
        #expect((delegate.launcherPlaceholder as? NSWindowController)?.window === launcherWindow)
        #expect(launcherWindow.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == systemAppearance)
        let currentGlobalStyle = defaults.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? NSObject
        #expect(currentGlobalStyle == originalGlobalStyle)
    }

    @Test func nativeSettingsCommandAndCommandCommaReuseTheSameOwnedPanel() async throws {
        let application = NSApplication.shared
        let delegate = try NativeAppTestSupport.appDelegate()
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        defer { delegate.settingsWindow?.window?.close() }
        let menuItem = try #require(settingsMenuItem(in: application.mainMenu))
        #expect(menuItem.title == "Settings…")
        #expect(menuItem.keyEquivalent == ",")
        #expect(menuItem.keyEquivalentModifierMask.intersection([.command, .control, .option, .shift]) == .command)
        let menu = try #require(menuItem.menu)
        let index = try #require(menu.items.firstIndex(of: menuItem))
        menu.performActionForItem(at: index)
        let controller = try #require(delegate.settingsWindow)
        let settingsWindow = try #require(controller.window)
        try await expectFocused(settingsWindow)

        let panel = try #require(settingsWindow as? NSPanel)
        #expect(panel.identifier == AppShortcutFocus.settingsWindowIdentifier)
        #expect(panel.level == .normal)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.isVisible)

        settingsWindow.performClose(nil)
        #expect(!settingsWindow.isVisible)
        let launcherWindow = try await showLauncher(delegate)
        try sendCommandComma(to: launcherWindow)
        try await expectFocused(settingsWindow)
        try await expectHidden(launcherWindow)
        #expect(delegate.settingsWindow === controller)
        #expect(controller.window === settingsWindow)

        try sendCommandComma(to: settingsWindow)
        try await expectFocused(settingsWindow)
        menu.performActionForItem(at: index)
        let reopened = try await NativeAppTestSupport.openSettings()
        try await expectFocused(settingsWindow)
        #expect(reopened === settingsWindow)
        #expect(delegate.settingsWindow === controller)
        let settingsWindows = application.windows.filter {
            $0.isVisible && $0.identifier == AppShortcutFocus.settingsWindowIdentifier
        }
        #expect(settingsWindows.count == 1)
        // The suppressed main scene is untouched by opening settings.
        #expect(!application.windows.contains { $0.isVisible && $0.canBecomeMain })
    }

    private func settingsMenuItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.title == "Settings…" { return item }
            if let match = settingsMenuItem(in: item.submenu) { return match }
        }
        return nil
    }

    private func expectAppearanceOwner(updates windows: [NSWindow], systemAppearance: NSAppearance.Name) async throws {
        for value in [AppAppearance.light, .dark, .automatic] {
            UserDefaults.standard.set(value.rawValue, forKey: AppAppearance.preferenceKey)
            let expected = value.nsAppearance?.name ?? systemAppearance
            let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
            while (NSApplication.shared.appearance?.name != value.nsAppearance?.name
                   || windows.contains { $0.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) != expected }),
                  ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(NSApplication.shared.appearance?.name == value.nsAppearance?.name)
            for window in windows {
                #expect(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
            }
        }
    }

    private func showLauncher(_ delegate: AppDelegate) async throws -> NSWindow {
        delegate.showLauncher()
        let controller = try #require(delegate.launcherPlaceholder as? NSWindowController)
        let window = try #require(controller.window)
        try await expectFocused(window)
        #expect(window.firstResponder === window.initialFirstResponder)
        #expect(window.initialFirstResponder != nil)
        return window
    }

    private func expectHidden(_ window: NSWindow) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while window.isVisible, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!window.isVisible)
    }

    private func expectFocused(_ window: NSWindow) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (!window.isVisible || !window.isKeyWindow), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(window.isVisible)
        #expect(window.isKeyWindow)
    }

    private func sendCommandComma(to window: NSWindow) throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: ",", charactersIgnoringModifiers: ",",
            isARepeat: false, keyCode: 43
        ))
        NSApplication.shared.sendEvent(event)
    }

}
