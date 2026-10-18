import AppKit
import CoreML
import SwiftUI
import Vision
import XCTest
@testable import Launchpod

@MainActor
final class GeneralSettingsViewTests: XCTestCase {
    func testCompiledCatalogResolvesSettingsLabelsInEverySupportedLanguage() throws {
        let appBundle = Bundle(for: AppLanguagePreference.self)
        XCTAssertEqual(appBundle.bundleURL, Bundle.main.bundleURL)
        XCTAssertEqual(appBundle.bundleURL.pathExtension, "app")

        for (identifier, general, language, followSystem) in [
            ("en", "General", "Language", "Follow System"),
            ("zh-Hans", CatalogTestSupport.text("General", locale: "zh-Hans"), CatalogTestSupport.text("Language", locale: "zh-Hans"), CatalogTestSupport.text("Follow System", locale: "zh-Hans")),
            ("zh-Hant", CatalogTestSupport.text("General", locale: "zh-Hant"), CatalogTestSupport.text("Language", locale: "zh-Hant"), CatalogTestSupport.text("Follow System", locale: "zh-Hant")),
            ("fr", CatalogTestSupport.text("General", locale: "fr"), CatalogTestSupport.text("Language", locale: "fr"), CatalogTestSupport.text("Follow System", locale: "fr")),
            ("de", CatalogTestSupport.text("General", locale: "de"), CatalogTestSupport.text("Language", locale: "de"), CatalogTestSupport.text("Follow System", locale: "de")),
            ("ja", CatalogTestSupport.text("General", locale: "ja"), CatalogTestSupport.text("Language", locale: "ja"), CatalogTestSupport.text("Follow System", locale: "ja")),
            ("ko", CatalogTestSupport.text("General", locale: "ko"), CatalogTestSupport.text("Language", locale: "ko"), CatalogTestSupport.text("Follow System", locale: "ko")),
            ("es", "General", CatalogTestSupport.text("Language", locale: "es"), CatalogTestSupport.text("Follow System", locale: "es"))
        ] {
            let locale = Locale(identifier: identifier)
            let generalResource = LocalizedStringResource("General", locale: locale, bundle: .atURL(appBundle.bundleURL))
            let languageResource = LocalizedStringResource("Language", locale: locale, bundle: .atURL(appBundle.bundleURL))
            let systemResource = LocalizedStringResource("Follow System", locale: locale, bundle: .atURL(appBundle.bundleURL))

            XCTAssertEqual(String(localized: generalResource), general, identifier)
            XCTAssertEqual(String(localized: languageResource), language, identifier)
            XCTAssertEqual(String(localized: systemResource), followSystem, identifier)
        }
    }

    func testCompiledCatalogResolvesGeneralLabelsInEverySupportedLanguage() throws {
        let appBundle = Bundle(for: AppLanguagePreference.self)
        for (identifier, languageAndAppearance, menuBarAndDock, applicationIcon) in [
            ("en", "Language & Appearance", "Menu Bar & Dock", "Application Icon"),
            ("zh-Hans", CatalogTestSupport.text("Language & Appearance", locale: "zh-Hans"), CatalogTestSupport.text("Menu Bar & Dock", locale: "zh-Hans"), CatalogTestSupport.text("Application Icon", locale: "zh-Hans")),
            ("zh-Hant", CatalogTestSupport.text("Language & Appearance", locale: "zh-Hant"), CatalogTestSupport.text("Menu Bar & Dock", locale: "zh-Hant"), CatalogTestSupport.text("Application Icon", locale: "zh-Hant")),
            ("fr", CatalogTestSupport.text("Language & Appearance", locale: "fr"), CatalogTestSupport.text("Menu Bar & Dock", locale: "fr"), CatalogTestSupport.text("Application Icon", locale: "fr")),
            ("de", CatalogTestSupport.text("Language & Appearance", locale: "de"), CatalogTestSupport.text("Menu Bar & Dock", locale: "de"), CatalogTestSupport.text("Application Icon", locale: "de")),
            ("ja", CatalogTestSupport.text("Language & Appearance", locale: "ja"), CatalogTestSupport.text("Menu Bar & Dock", locale: "ja"), CatalogTestSupport.text("Application Icon", locale: "ja")),
            ("ko", CatalogTestSupport.text("Language & Appearance", locale: "ko"), CatalogTestSupport.text("Menu Bar & Dock", locale: "ko"), CatalogTestSupport.text("Application Icon", locale: "ko")),
            ("es", CatalogTestSupport.text("Language & Appearance", locale: "es"), CatalogTestSupport.text("Menu Bar & Dock", locale: "es"), CatalogTestSupport.text("Application Icon", locale: "es"))
        ] {
            let locale = Locale(identifier: identifier)
            for (key, expected) in [
                ("Language & Appearance", languageAndAppearance),
                ("Menu Bar & Dock", menuBarAndDock),
                ("Application Icon", applicationIcon)
            ] {
                let resource = LocalizedStringResource(String.LocalizationValue(key), locale: locale,
                                                       bundle: .atURL(appBundle.bundleURL))
                XCTAssertEqual(String(localized: resource), expected, "\(identifier): \(key)")
            }
        }
    }

    func testApplicationIconSubtitleResolvesInEverySupportedLanguage() {
        let appBundle = Bundle(for: AppLanguagePreference.self)
        for (identifier, expected) in [
            ("en", "Choose the icon shown in the Dock."),
            ("zh-Hans", CatalogTestSupport.text("Choose the icon shown in the Dock.", locale: "zh-Hans")),
            ("zh-Hant", CatalogTestSupport.text("Choose the icon shown in the Dock.", locale: "zh-Hant")),
            ("fr", CatalogTestSupport.text("Choose the icon shown in the Dock.", locale: "fr")),
            ("de", CatalogTestSupport.text("Choose the icon shown in the Dock.", locale: "de")),
            ("ja", CatalogTestSupport.text("Choose the icon shown in the Dock.", locale: "ja")),
            ("ko", CatalogTestSupport.text("Choose the icon shown in the Dock.", locale: "ko")),
            ("es", CatalogTestSupport.text("Choose the icon shown in the Dock.", locale: "es"))
        ] {
            let resource = LocalizedStringResource(
                "Choose the icon shown in the Dock.",
                locale: Locale(identifier: identifier),
                bundle: .atURL(appBundle.bundleURL)
            )
            XCTAssertEqual(String(localized: resource), expected, identifier)
        }
    }

    func testExistingSettingsViewUpdatesAfterEachAppLanguageChange() async throws {
        try NativeAppTestSupport.requireNativeWindowTests()
        let preference = try makePreference(preferredLanguages: ["fr-CA"])
        let window = try makeWindow(preference: preference)
        defer { window.close() }
        let host = try XCTUnwrap(window.contentView)

        for (selection, heading, label, autonym, appearanceLabel, automaticLabel) in [
            (AppLanguage.english, "General", "Language", "English", "Appearance", "Auto"),
            (.simplifiedChinese, CatalogTestSupport.text("General", locale: "zh-Hans"), CatalogTestSupport.text("Language", locale: "zh-Hans"), CatalogTestSupport.text("Simplified Chinese", locale: "zh-Hans"), CatalogTestSupport.text("Appearance", locale: "zh-Hans"), CatalogTestSupport.text("Auto", locale: "zh-Hans")),
            (.traditionalChinese, CatalogTestSupport.text("General", locale: "zh-Hant"), CatalogTestSupport.text("Language", locale: "zh-Hant"), CatalogTestSupport.text("Traditional Chinese", locale: "zh-Hant"), CatalogTestSupport.text("Appearance", locale: "zh-Hant"), CatalogTestSupport.text("Auto", locale: "zh-Hant")),
            (.french, CatalogTestSupport.text("General", locale: "fr"), CatalogTestSupport.text("Language", locale: "fr"), CatalogTestSupport.text("French", locale: "fr"), CatalogTestSupport.text("Appearance", locale: "fr"), CatalogTestSupport.text("Auto", locale: "fr")),
            (.german, CatalogTestSupport.text("General", locale: "de"), CatalogTestSupport.text("Language", locale: "de"), CatalogTestSupport.text("German", locale: "de"), CatalogTestSupport.text("Appearance", locale: "de"), CatalogTestSupport.text("Auto", locale: "de")),
            (.japanese, CatalogTestSupport.text("General", locale: "ja"), CatalogTestSupport.text("Language", locale: "ja"), CatalogTestSupport.text("Japanese", locale: "ja"), CatalogTestSupport.text("Appearance", locale: "ja"), CatalogTestSupport.text("Auto", locale: "ja")),
            (.korean, CatalogTestSupport.text("General", locale: "ko"), CatalogTestSupport.text("Language", locale: "ko"), CatalogTestSupport.text("Korean", locale: "ko"), CatalogTestSupport.text("Appearance", locale: "ko"), CatalogTestSupport.text("Auto", locale: "ko")),
            (.spanish, "General", CatalogTestSupport.text("Language", locale: "es"), CatalogTestSupport.text("Spanish", locale: "es"), CatalogTestSupport.text("Appearance", locale: "es"), CatalogTestSupport.text("Auto", locale: "es")),
            (.english, "General", "Language", "English", "Appearance", "Auto"),
            (.system, CatalogTestSupport.text("General", locale: "fr"), CatalogTestSupport.text("Language", locale: "fr"), CatalogTestSupport.text("Follow System", locale: "fr"), CatalogTestSupport.text("Appearance", locale: "fr"), CatalogTestSupport.text("Auto", locale: "fr"))
        ] {
            preference.selection = selection
            let rendered = try await renderedText(
                in: host, locale: preference.locale, attachmentName: "Settings-\(selection.rawValue)"
            )

            XCTAssertFalse(rendered.localizedCaseInsensitiveContains(heading), "Redundant \(heading) heading: \(rendered)")
            XCTAssertTrue(rendered.contains(label), "Missing \(label): \(rendered)")
            XCTAssertTrue(rendered.contains(autonym), "Missing selected language \(autonym): \(rendered)")
            XCTAssertTrue(rendered.contains(appearanceLabel), "Missing \(appearanceLabel): \(rendered)")
            XCTAssertTrue(rendered.contains(automaticLabel), "Missing \(automaticLabel): \(rendered)")
            for otherLabel in ["Language", CatalogTestSupport.text("Language", locale: "zh-Hans"), CatalogTestSupport.text("Language", locale: "zh-Hant"), CatalogTestSupport.text("Language", locale: "fr"), CatalogTestSupport.text("Language", locale: "de"), CatalogTestSupport.text("Language", locale: "ja"), CatalogTestSupport.text("Language", locale: "ko"), CatalogTestSupport.text("Language", locale: "es")] where otherLabel != label {
                XCTAssertFalse(rendered.contains(otherLabel), "Stale language after \(selection): \(rendered)")
            }
        }
    }

    func testRestoredLanguageRendersItsAutonymInThePicker() async throws {
        try NativeAppTestSupport.requireNativeWindowTests()
        let preference = try makePreference(storedLanguage: .french)
        let window = try makeWindow(preference: preference)
        defer { window.close() }
        let host = try XCTUnwrap(window.contentView)
        let rendered = try await renderedText(
            in: host, locale: preference.locale, attachmentName: "Settings-restored-fr"
        )
        XCTAssertEqual(preference.selection, .french)
        XCTAssertFalse(rendered.localizedCaseInsensitiveContains(CatalogTestSupport.text("General", locale: "fr")), rendered)
        XCTAssertTrue(rendered.contains(CatalogTestSupport.text("Language", locale: "fr")), rendered)
        XCTAssertTrue(rendered.contains(CatalogTestSupport.text("French", locale: "fr")), rendered)
        XCTAssertTrue(rendered.contains(CatalogTestSupport.text("Appearance", locale: "fr")), rendered)
        XCTAssertTrue(rendered.contains(CatalogTestSupport.text("Auto", locale: "fr")), rendered)
    }

    func testNativeAppearanceStorageBindingRendersAndRestoresTheSelectedValue() async throws {
        try NativeAppTestSupport.requireNativeWindowTests()
        let defaults = try makeDefaults()
        let preference = AppLanguagePreference(defaults: defaults, preferredLanguages: { ["en-US"] })
        var binding: Binding<AppAppearance>?
        let window = try makeWindow(preference: preference, appearanceDefaults: defaults) { binding = $0 }
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        let appearance = try XCTUnwrap(binding)
        XCTAssertEqual(appearance.wrappedValue, .automatic)

        for (value, title) in [(AppAppearance.light, "Light"), (.dark, "Dark"), (.automatic, "Auto")] {
            appearance.wrappedValue = value
            let rendered = try await renderedText(
                in: XCTUnwrap(window.contentView), locale: Locale(identifier: "en"),
                attachmentName: "Settings-appearance-\(value.rawValue)"
            )
            XCTAssertTrue(rendered.contains(title), rendered)
            XCTAssertEqual(defaults.string(forKey: AppAppearance.preferenceKey), value.rawValue)

            var restoredBinding: Binding<AppAppearance>?
            let restoredWindow = try makeWindow(preference: preference, appearanceDefaults: defaults) { restoredBinding = $0 }
            defer { restoredWindow.close() }
            let restoredText = try await renderedText(
                in: XCTUnwrap(restoredWindow.contentView), locale: Locale(identifier: "en"),
                attachmentName: "Settings-appearance-restored-\(value.rawValue)"
            )
            XCTAssertEqual(restoredBinding?.wrappedValue, value)
            XCTAssertTrue(restoredText.contains(title), restoredText)
        }
    }

    func testSmallSettingsContentKeepsFrenchLabelsVisible() async throws {
        try NativeAppTestSupport.requireNativeWindowTests()
        let preference = try makePreference(storedLanguage: .french)
        let window = try makeWindow(preference: preference, size: NSSize(width: 360, height: 420))
        defer { window.close() }
        let host = try XCTUnwrap(window.contentView)
        let rendered = try await renderedText(
            in: host, locale: preference.locale, attachmentName: "Settings-small-360x420-fr"
        )

        XCTAssertFalse(rendered.localizedCaseInsensitiveContains(CatalogTestSupport.text("General", locale: "fr")), rendered)
        XCTAssertTrue(rendered.contains(CatalogTestSupport.text("Language", locale: "fr")), rendered)
        XCTAssertTrue(rendered.contains(CatalogTestSupport.text("French", locale: "fr")), rendered)
        XCTAssertTrue(rendered.contains(CatalogTestSupport.text("Appearance", locale: "fr")), rendered)
        XCTAssertTrue(rendered.contains(CatalogTestSupport.text("Auto", locale: "fr")), rendered)
    }

    func testMissingAndInvalidNativeAppearanceStorageUsesAuto() async throws {
        try NativeAppTestSupport.requireNativeWindowTests()
        for storedValue in [nil, "sepia", 42] as [Any?] {
            let defaults = try makeDefaults()
            defaults.set(storedValue, forKey: AppAppearance.preferenceKey)
            let preference = AppLanguagePreference(defaults: defaults, preferredLanguages: { ["en-US"] })
            var binding: Binding<AppAppearance>?
            let window = try makeWindow(preference: preference, appearanceDefaults: defaults) { binding = $0 }
            defer { window.close() }
            let rendered = try await renderedText(
                in: XCTUnwrap(window.contentView), locale: Locale(identifier: "en"),
                attachmentName: "Settings-appearance-invalid-\(String(describing: storedValue))"
            )
            XCTAssertEqual(binding?.wrappedValue, .automatic)
            XCTAssertTrue(rendered.contains("Auto"), rendered)
        }
    }

    func testProductionSettingsBodyReturnsToAutoAndUpdatesWithoutTheLauncher() async throws {
        try NativeAppTestSupport.requireNativeWindowTests()
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let delegate = try NativeAppTestSupport.appDelegate()
        let application = NSApplication.shared
        let defaults = UserDefaults.standard
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let originalValue = defaults.persistentDomain(forName: domain)?[AppAppearance.preferenceKey]
        let originalAppearance = application.appearance
        defer {
            application.appearance = originalAppearance
            if let originalValue {
                defaults.set(originalValue, forKey: AppAppearance.preferenceKey)
            } else {
                defaults.removeObject(forKey: AppAppearance.preferenceKey)
            }
        }
        delegate.showLauncher()
        let launcher = try XCTUnwrap(delegate.launcherPlaceholder as? NSWindowController)
        let launcherWindow = try XCTUnwrap(launcher.window)
        // The Classical launcher shows only the desktop picture, which does not follow the app appearance.
        let launcherFollowsAppearance = launcher is LauncherPlaceholderWindowController
        let settingsWindow = try await NativeAppTestSupport.openSettings()
        defer { settingsWindow.close() }
        delegate.showLauncher()
        try await NativeAppTestSupport.waitUntil(description: "launcher becomes visible") { launcherWindow.isVisible }
        XCTAssertTrue(settingsWindow.isVisible)
        let windows: [WindowRole: NSWindow] = launcherFollowsAppearance
            ? [.launcher: launcherWindow, .settings: settingsWindow] : [.settings: settingsWindow]
        let appearanceRoles: [WindowRole] = launcherFollowsAppearance ? [.launcher, .settings] : [.settings]
        application.appearance = nil
        let systemAppearance = try XCTUnwrap(application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]))
        defaults.set("light", forKey: AppAppearance.preferenceKey)
        let light = try await captureWindowContents(windows, name: "appearance-light")
        defaults.set("dark", forKey: AppAppearance.preferenceKey)
        let dark = try await captureWindowContents(windows, name: "appearance-dark")
        for source in [AppAppearance.dark, .light] {
            defaults.set(source.rawValue, forKey: AppAppearance.preferenceKey)
            _ = try await captureWindowContents(windows, name: "appearance-before-auto-\(source.rawValue)")
            defaults.set("automatic", forKey: AppAppearance.preferenceKey)
            let automatic = try await captureWindowContents(windows, name: "appearance-\(source.rawValue)-to-auto")
            try assertBodyRenderings(automatic, for: appearanceRoles, match: systemAppearance, light: light, dark: dark)
        }

        if launcherFollowsAppearance {
            launcherWindow.performClose(nil)
        } else {
            // Borderless: no close button for performClose; a native close ends the presentation.
            launcherWindow.close()
        }
        settingsWindow.makeKey()
        XCTAssertFalse(launcherWindow.isVisible)
        XCTAssertTrue(settingsWindow.isVisible)
        for value in [AppAppearance.light, .dark, .automatic] {
            defaults.set(value.rawValue, forKey: AppAppearance.preferenceKey)
            let rendered = try await captureWindowContents(
                [.settings: settingsWindow], name: "appearance-settings-only-\(value.rawValue)"
            )
            try assertBodyRenderings(rendered, for: [.settings], match: value.nsAppearance?.name ?? systemAppearance, light: light, dark: dark)
        }
        XCTAssertFalse(delegate.applicationShouldHandleReopen(application, hasVisibleWindows: true))
        try await NativeAppTestSupport.waitUntil(description: "launcher becomes visible") { launcherWindow.isVisible }
        XCTAssertTrue(launcher.window === launcherWindow)
    }

    func testProductionSettingsWindowIsFixedSizeAndRestoresPosition() async throws {
        try NativeAppTestSupport.requireNativeWindowTests()
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let window = try await NativeAppTestSupport.openSettings()
        defer { window.close() }
        let screen = try XCTUnwrap(window.screen)
        let contentView = try XCTUnwrap(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        func findDockIcon(in view: NSView) -> DockApplicationIconView? {
            if let icon = view as? DockApplicationIconView { return icon }
            return view.subviews.lazy.compactMap(findDockIcon(in:)).first
        }
        let icon = try XCTUnwrap(findDockIcon(in: contentView))
        XCTAssertEqual(icon.bounds.width, 48, accuracy: 1)
        XCTAssertEqual(icon.bounds.height, 48, accuracy: 1)
        let iconGeometry = """
            Dock icon frame: \(icon.frame)
            Dock icon bounds: \(icon.bounds)
            Dock icon alignment insets: \(icon.alignmentRectInsets)
            Dock icon alignment rect: \(icon.alignmentRect(forFrame: icon.frame))
            Dock icon screen frame: \(window.convertToScreen(icon.convert(icon.bounds, to: nil)))
            Dock icon accessibility frame: \(icon.accessibilityFrame())
            """
        let geometry = XCTAttachment(string: """
            Settings frame: \(window.frame)
            Settings content layout: \(window.contentLayoutRect)
            Settings content bounds: \(contentView.bounds)
            Settings content minimum: \(window.contentMinSize)
            Settings content maximum: \(window.contentMaxSize)
            Screen visible frame: \(screen.visibleFrame)
            Frame center offset from visible center: \(window.frame.midX - screen.visibleFrame.midX), \(window.frame.midY - screen.visibleFrame.midY)
            Settings window title: \(window.title)
            \(iconGeometry)
            """)
        geometry.name = "Native-settings-window-geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
        XCTAssertLessThanOrEqual(window.frame.width, screen.visibleFrame.width + 1)
        XCTAssertLessThanOrEqual(window.frame.height, screen.visibleFrame.height + 1)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isZoomable)
        XCTAssertGreaterThanOrEqual(window.contentLayoutRect.width, 360)
        XCTAssertLessThanOrEqual(window.contentLayoutRect.width, 520)
        XCTAssertGreaterThanOrEqual(window.contentLayoutRect.height, 420)
        XCTAssertLessThanOrEqual(window.contentLayoutRect.height, 760)
        let originalOrigin = window.frame.origin
        let originalSize = window.frame.size
        window.close()
        let reopenedWindow = try await NativeAppTestSupport.openSettings()
        defer { reopenedWindow.close() }
        XCTAssertTrue(reopenedWindow === window)
        XCTAssertEqual(reopenedWindow.frame.size, originalSize)
        XCTAssertEqual(reopenedWindow.frame.origin.x, originalOrigin.x, accuracy: 1)
        XCTAssertEqual(reopenedWindow.frame.origin.y, originalOrigin.y, accuracy: 1)
    }

    private func makePreference(
        storedLanguage: AppLanguage? = nil, preferredLanguages: [String] = ["en-US"]
    ) throws -> AppLanguagePreference {
        let defaults = try makeDefaults()
        if let storedLanguage {
            defaults.set(storedLanguage.rawValue, forKey: AppLanguagePreference.preferenceKey)
        }
        return AppLanguagePreference(defaults: defaults, preferredLanguages: { preferredLanguages })
    }

    private func makeDefaults() throws -> UserDefaults {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        addTeardownBlock { try preferences.cleanup() }
        return defaults
    }

    private func makeWindow(
        preference: AppLanguagePreference, size: NSSize = NSSize(width: 480, height: 640),
        appearanceDefaults: UserDefaults? = nil,
        keepInDock: KeepInDockModel? = nil,
        appearanceBinding: @escaping (Binding<AppAppearance>) -> Void = { _ in }
    ) throws -> NSWindow {
        let defaults = try appearanceDefaults ?? makeDefaults()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsHost(
            preference: preference, defaults: defaults,
            keepInDock: keepInDock ?? KeepInDockModel(store: InMemoryDockPersistentAppsStore()),
            applicationIconPreference: ApplicationIconPreference(
                defaults: defaults, applier: NoopApplicationIconApplier()
            ),
            appearanceBinding: appearanceBinding
        ))
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func renderedText(in host: NSView, locale: Locale, attachmentName: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(150))
        let bitmap = try capturedBitmap(in: host, name: attachmentName)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        let localeIdentifier = locale.identifier
        let context = "Settings OCR phase=\(attachmentName), requested locale=\(localeIdentifier), bitmap=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh), region=(0, 0.5, 1, 0.5)"
        do {
            let text = try await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = [localeIdentifier]
                // Use the advertised CPU devices for screenshot recognition in the isolated test process.
                for (stage, devices) in try request.supportedComputeStageDevices {
                    guard let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) else {
                        throw NSError(domain: "LaunchpodTests.SettingsOCR", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "No CPU device for OCR stage \(stage)"])
                    }
                    request.setComputeDevice(cpu, for: stage)
                }
                // Both settings rows occupy the upper half; exclude the empty form area from text segmentation.
                request.regionOfInterest = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
                try VNImageRequestHandler(data: png, options: [:]).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }.value
            let transcript = XCTAttachment(string: "\(context)\nRecognized text:\n\(text)")
            transcript.name = "\(attachmentName)-recognized-text"
            transcript.lifetime = .keepAlways
            add(transcript)
            return text
        } catch {
            let diagnostic = "\(context)\nVision request failed before text assertions: \(error)\n\(NativeAppTestSupport.captureFailureSnapshot())"
            let attachment = XCTAttachment(string: diagnostic)
            attachment.name = "\(attachmentName)-OCR-error"
            attachment.lifetime = .keepAlways
            add(attachment)
            throw NSError(domain: "LaunchpodTests.SettingsOCR", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: diagnostic, NSUnderlyingErrorKey: error])
        }
    }

    private enum WindowRole: String {
        case launcher, settings
    }

    private func captureWindowContents(
        _ windows: [WindowRole: NSWindow], name: String
    ) async throws -> [WindowRole: [Double]] {
        try await Task.sleep(for: .milliseconds(500))
        var renderings: [WindowRole: [Double]] = [:]
        for (role, window) in windows {
            let bitmap = try capturedBitmap(
                in: XCTUnwrap(window.contentView), name: "\(name)-\(role.rawValue)"
            )
            let xRange = role == .launcher ? 0..<bitmap.pixelsWide : bitmap.pixelsWide / 4..<bitmap.pixelsWide * 3 / 4
            let yRange = role == .launcher ? 0..<bitmap.pixelsHigh : bitmap.pixelsHigh * 2 / 5..<bitmap.pixelsHigh * 3 / 5
            var luminance: [Double] = []
            for y in stride(from: yRange.lowerBound, to: yRange.upperBound, by: 6) {
                for x in stride(from: xRange.lowerBound, to: xRange.upperBound, by: 6) {
                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    luminance.append((color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722) * color.alphaComponent)
                }
            }
            renderings[role] = luminance
        }
        return renderings
    }

    private func assertBodyRenderings(
        _ actual: [WindowRole: [Double]], for roles: [WindowRole], match appearance: NSAppearance.Name,
        light: [WindowRole: [Double]], dark: [WindowRole: [Double]]
    ) throws {
        for role in roles {
            let pixels = try XCTUnwrap(actual[role], "Missing \(role.rawValue) rendering")
            let lightPixels = try XCTUnwrap(light[role], "Missing \(role.rawValue) light baseline")
            let darkPixels = try XCTUnwrap(dark[role], "Missing \(role.rawValue) dark baseline")
            let lightDistance = distance(pixels, lightPixels)
            let darkDistance = distance(pixels, darkPixels)
            XCTAssertGreaterThan(distance(lightPixels, darkPixels), 0.00001)
            let expectedDistance = appearance == .aqua ? lightDistance : darkDistance
            let otherDistance = appearance == .aqua ? darkDistance : lightDistance
            XCTAssertLessThan(expectedDistance, otherDistance, "\(role.rawValue) body distance to light=\(lightDistance), dark=\(darkDistance)")
        }
    }

    private func distance(_ first: [Double], _ second: [Double]) -> Double {
        guard first.count == second.count, !first.isEmpty else { return .infinity }
        return zip(first, second).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(first.count)
    }

    private func capturedBitmap(in view: NSView, name: String) throws -> NSBitmapImageRep {
        let bitmap = try NativeAppTestSupport.capture(view)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return bitmap
    }

    private struct SettingsHost: View {
        let preference: AppLanguagePreference
        @AppStorage private var appearance: AppAppearance
        @State private var showInMenuBar = true
        /// Never the user's Dock.
        let keepInDock: KeepInDockModel
        let applicationIconPreference: ApplicationIconPreference
        let appearanceBinding: (Binding<AppAppearance>) -> Void

        init(
            preference: AppLanguagePreference, defaults: UserDefaults, keepInDock: KeepInDockModel,
            applicationIconPreference: ApplicationIconPreference,
            appearanceBinding: @escaping (Binding<AppAppearance>) -> Void
        ) {
            self.preference = preference
            self.keepInDock = keepInDock
            self.applicationIconPreference = applicationIconPreference
            _appearance = AppStorage(
                wrappedValue: .automatic, AppAppearance.preferenceKey, store: defaults
            )
            self.appearanceBinding = appearanceBinding
        }

        var body: some View {
            GeneralSettingsView(languagePreference: preference, appearance: $appearance, showInMenuBar: $showInMenuBar,
                                keepInDock: keepInDock, applicationIconPreference: applicationIconPreference)
                .environment(\.locale, preference.locale)
                .onAppear { appearanceBinding($appearance) }
        }
    }

    private struct NoopApplicationIconApplier: ApplicationIconApplying {
        func apply(_ icon: ApplicationIcon) throws { }
    }
}
