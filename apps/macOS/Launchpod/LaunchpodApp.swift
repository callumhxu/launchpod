//
//  LaunchpodApp.swift
//  Launchpod
//
//  Created by Callum on 9/20/26.
//

import AppKit
import SwiftUI

@main
struct LaunchpodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private var languagePreference: AppLanguagePreference { appDelegate.languagePreference }
    @AppStorage(AppAppearance.preferenceKey) private var appearance = AppAppearance.automatic
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    #if DEBUG
    /// Observes the delegate owned by SwiftUI without extending its lifetime.
    static private(set) weak var testHostDelegate: AppDelegate?

    init() {
        Self.testHostDelegate = appDelegate
        appDelegate.suppressesTestHostPresentation = Self.isBackgroundUnitTestHost
    }

    private static var isBackgroundUnitTestHost: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LAUNCHPOD_NATIVE_WINDOW_TESTS"] != "1" else { return false }
        return environment["LAUNCHPOD_UNIT_TEST_HOST"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, languagePreference.locale)
        }
        .defaultLaunchBehavior(.suppressed)
        .onChange(of: showInMenuBar, initial: true) {
            appDelegate.setMenuBarVisible(showInMenuBar)
        }
        .onChange(of: appearance, initial: true) {
            NSApplication.shared.appearance = appearance.nsAppearance
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                languagePreference.refreshSystemLanguages()
            }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button {
                    appDelegate.openSettings()
                } label: {
                    Text(verbatim: String(
                        localized: LocalizedStringResource("Settings", locale: languagePreference.locale)
                    ) + "…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
