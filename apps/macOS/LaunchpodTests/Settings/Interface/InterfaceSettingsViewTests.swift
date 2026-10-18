import SwiftUI
import XCTest
@testable import Launchpod

@MainActor
final class InterfaceSettingsViewTests: XCTestCase {
    func testCompiledCatalogResolvesClassicalDockLabelsInEverySupportedLanguage() throws {
        let appBundle = Bundle(for: AppLanguagePreference.self)
        let caption = "Covers the Dock while Launchpod is shown full screen."
        for (identifier, section, toggle, description) in [
            ("en", "Classical", "Hide Dock", caption),
            ("zh-Hans", CatalogTestSupport.text("Classical", locale: "zh-Hans"), CatalogTestSupport.text("Hide Dock", locale: "zh-Hans"), CatalogTestSupport.text("Covers the Dock while Launchpod is shown full screen.", locale: "zh-Hans")),
            ("zh-Hant", CatalogTestSupport.text("Classical", locale: "zh-Hant"), CatalogTestSupport.text("Hide Dock", locale: "zh-Hant"), CatalogTestSupport.text("Covers the Dock while Launchpod is shown full screen.", locale: "zh-Hant")),
            ("fr", CatalogTestSupport.text("Classical", locale: "fr"), CatalogTestSupport.text("Hide Dock", locale: "fr"), CatalogTestSupport.text("Covers the Dock while Launchpod is shown full screen.", locale: "fr")),
            ("de", CatalogTestSupport.text("Classical", locale: "de"), CatalogTestSupport.text("Hide Dock", locale: "de"), CatalogTestSupport.text("Covers the Dock while Launchpod is shown full screen.", locale: "de")),
            ("ja", CatalogTestSupport.text("Classical", locale: "ja"), CatalogTestSupport.text("Hide Dock", locale: "ja"), CatalogTestSupport.text("Covers the Dock while Launchpod is shown full screen.", locale: "ja")),
            ("ko", CatalogTestSupport.text("Classical", locale: "ko"), CatalogTestSupport.text("Hide Dock", locale: "ko"), CatalogTestSupport.text("Covers the Dock while Launchpod is shown full screen.", locale: "ko")),
            ("es", CatalogTestSupport.text("Classical", locale: "es"), CatalogTestSupport.text("Hide Dock", locale: "es"), CatalogTestSupport.text("Covers the Dock while Launchpod is shown full screen.", locale: "es"))
        ] {
            let locale = Locale(identifier: identifier)
            for (key, expected) in [("Classical", section), ("Hide Dock", toggle), (caption, description)] {
                let resource = LocalizedStringResource(String.LocalizationValue(key), locale: locale,
                                                       bundle: .atURL(appBundle.bundleURL))
                XCTAssertEqual(String(localized: resource), expected, "\(identifier): \(key)")
            }
        }
    }

    func testGridLabelsAreLocalized() {
        let bundle = Bundle(for: AppLanguagePreference.self)
        for (key, expected) in [("Rows", CatalogTestSupport.text("Rows", locale: "zh-Hans")), ("Columns", CatalogTestSupport.text("Columns", locale: "zh-Hans")), ("Applies the next time Launchpod opens.", CatalogTestSupport.text("Applies the next time Launchpod opens.", locale: "zh-Hans"))] {
            let resource = LocalizedStringResource(String.LocalizationValue(key), locale: Locale(identifier: "zh-Hans"),
                                                   bundle: .atURL(bundle.bundleURL))
            XCTAssertEqual(String(localized: resource), expected)
        }
    }

    func testCompiledCatalogResolvesIconGridInEverySupportedLanguage() {
        let bundle = Bundle(for: AppLanguagePreference.self)
        for (identifier, expected) in [
            ("en", "Icon Grid"), ("zh-Hans", CatalogTestSupport.text("Icon Grid", locale: "zh-Hans")), ("zh-Hant", CatalogTestSupport.text("Icon Grid", locale: "zh-Hant")), ("fr", CatalogTestSupport.text("Icon Grid", locale: "fr")),
            ("de", CatalogTestSupport.text("Icon Grid", locale: "de")), ("ja", CatalogTestSupport.text("Icon Grid", locale: "ja")), ("ko", CatalogTestSupport.text("Icon Grid", locale: "ko")), ("es", CatalogTestSupport.text("Icon Grid", locale: "es"))
        ] {
            let resource = LocalizedStringResource("Icon Grid", locale: Locale(identifier: identifier),
                                                   bundle: .atURL(bundle.bundleURL))
            XCTAssertEqual(String(localized: resource), expected, identifier)
        }
    }

    func testGridFieldsShowEachStepperValue() async throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        defaults.set(7, forKey: ClassicalGridPreference.columnsKey)
        defaults.set(5, forKey: ClassicalGridPreference.rowsKey)
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let host = NSHostingView(rootView: Host(defaults: defaults))
        let window = NativeAppTestSupport.makeKeyPanel(size: NSSize(width: 480, height: 420), contentView: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        // Columns and Rows each pair one editable number field with one stepper, in that order.
        let fields = editableFields(in: host)
        let steppers = steppers(in: host)
        XCTAssertEqual(fields.count, 2)
        XCTAssertEqual(steppers.count, 2)
        XCTAssertEqual(fields.map(\.stringValue), ["7", "5"])

        for stepper in steppers {
            stepper.integerValue += 1
            stepper.sendAction(stepper.action, to: stepper.target)
        }
        try await waitUntil { fields.map(\.stringValue) == ["8", "6"] }
        XCTAssertEqual(defaults.integer(forKey: ClassicalGridPreference.columnsKey), 8)
        XCTAssertEqual(defaults.integer(forKey: ClassicalGridPreference.rowsKey), 6)
    }

    func testClassicalDockToggleStoresThePreference() async throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let host = NSHostingView(rootView: Host(defaults: defaults))
        let window = NativeAppTestSupport.makeKeyPanel(size: NSSize(width: 480, height: 320), contentView: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        // The page has two switches; SwiftUI hosts them as native `NSSwitch` controls.
        let toggle = try XCTUnwrap(switches(in: host).first)
        XCTAssertEqual(switches(in: host).count, 2)
        XCTAssertEqual(toggle.state, .off)
        XCTAssertFalse(ClassicalDockPreference.hidesDock(in: defaults))
        toggle.performClick(nil)
        try await waitUntil { ClassicalDockPreference.hidesDock(in: defaults) }
        XCTAssertEqual(toggle.state, .on)
        toggle.performClick(nil)
        try await waitUntil { !ClassicalDockPreference.hidesDock(in: defaults) }
        XCTAssertEqual(toggle.state, .off)
    }

    func testLiquidGlassToggleDefaultsOnAndPersistsExplicitOffAcrossSettingsViews() async throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }

        XCTAssertNil(defaults.object(forKey: ClassicalFolderGlassPreference.key))
        let firstHost = NSHostingView(rootView: Host(defaults: defaults))
        let firstWindow = NativeAppTestSupport.makeKeyPanel(size: NSSize(width: 480, height: 420), contentView: firstHost)
        try await Task.sleep(for: .milliseconds(150))
        firstHost.layoutSubtreeIfNeeded()
        let firstSwitches = switches(in: firstHost)
        XCTAssertEqual(firstSwitches.count, 2)
        let firstToggle = try XCTUnwrap(firstSwitches.last)
        XCTAssertEqual(firstToggle.state, .on, "Native Liquid Glass is enabled by default")
        firstToggle.performClick(nil)
        try await waitUntil { defaults.object(forKey: ClassicalFolderGlassPreference.key) as? Bool == false }
        firstWindow.close()

        let secondHost = NSHostingView(rootView: Host(defaults: defaults))
        let secondWindow = NativeAppTestSupport.makeKeyPanel(size: NSSize(width: 480, height: 420), contentView: secondHost)
        defer { secondWindow.close() }
        try await Task.sleep(for: .milliseconds(150))
        secondHost.layoutSubtreeIfNeeded()
        let secondToggle = try XCTUnwrap(switches(in: secondHost).last)
        XCTAssertEqual(secondToggle.state, .off, "The stored choice is restored")
        secondToggle.performClick(nil)
        try await waitUntil { defaults.bool(forKey: ClassicalFolderGlassPreference.key) }
        XCTAssertEqual(secondToggle.state, .on)
    }

    func testGridSteppersStoreRowsAndColumnsWithinLaunchpadsRange() async throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let host = NSHostingView(rootView: Host(defaults: defaults))
        let window = NativeAppTestSupport.makeKeyPanel(size: NSSize(width: 480, height: 420), contentView: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let steppers = steppers(in: host)
        XCTAssertEqual(steppers.count, 2)
        // SwiftUI hosts each `Stepper` as an `NSStepper` whose action reports one step up or down.
        func increment(_ stepper: NSStepper) {
            stepper.integerValue += 1
            stepper.sendAction(stepper.action, to: stepper.target)
        }
        let columns = try XCTUnwrap(steppers.first)
        increment(columns)
        try await waitUntil { defaults.integer(forKey: ClassicalGridPreference.columnsKey) == 8 }
        let rows = try XCTUnwrap(steppers.last)
        defaults.set(100, forKey: ClassicalGridPreference.rowsKey)
        try await Task.sleep(for: .milliseconds(100))
        increment(rows)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(defaults.integer(forKey: ClassicalGridPreference.rowsKey), 100, "The Dock's upper bound of 100 holds")
    }

    func testEachGridStepperOwnsOneDimensionAndStopsAtTheRangeBounds() async throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let range = ClassicalGridPreference.range
        let keys = [ClassicalGridPreference.columnsKey, ClassicalGridPreference.rowsKey]
        for key in keys { defaults.set(range.lowerBound, forKey: key) }
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let host = NSHostingView(rootView: Host(defaults: defaults))
        let window = NativeAppTestSupport.makeKeyPanel(size: NSSize(width: 480, height: 420), contentView: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let steppers = steppers(in: host)
        XCTAssertEqual(steppers.count, 2, "Columns and Rows each have their own stepper")
        XCTAssertEqual(switches(in: host).count, 2, "Hide Dock and Liquid Glass are separate switches")
        func step(_ stepper: NSStepper, by delta: Int) {
            stepper.integerValue += delta
            stepper.sendAction(stepper.action, to: stepper.target)
        }
        func values() -> [Int] { keys.map { defaults.integer(forKey: $0) } }

        var steppedKeys: [String] = []
        for stepper in steppers {
            let before = values()
            step(stepper, by: -1)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(values(), before, "Stepping below \(range.lowerBound) changes nothing")
            step(stepper, by: 1)
            try await waitUntil { values() != before }
            let changed = zip(keys, zip(before, values())).filter { $0.1.0 != $0.1.1 }
            XCTAssertEqual(changed.count, 1, "One stepper changes exactly one dimension: \(changed)")
            if let (key, (old, new)) = changed.first {
                XCTAssertEqual(new, old + 1)
                steppedKeys.append(key)
            }
        }
        XCTAssertEqual(Set(steppedKeys), Set(keys), "The two steppers bind Columns and Rows, not the same value")

        for key in keys { defaults.set(range.upperBound, forKey: key) }
        try await Task.sleep(for: .milliseconds(100))
        for stepper in steppers {
            step(stepper, by: 1)
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(values(), [range.upperBound, range.upperBound], "Stepping above \(range.upperBound) changes nothing")
    }

    private func steppers(in view: NSView) -> [NSStepper] {
        (view as? NSStepper).map { [$0] } ?? view.subviews.flatMap { steppers(in: $0) }
    }

    private func editableFields(in view: NSView) -> [NSTextField] {
        if let field = view as? NSTextField, field.isEditable { return [field] }
        return view.subviews.flatMap { editableFields(in: $0) }
    }

    private func switches(in view: NSView) -> [NSSwitch] {
        (view as? NSSwitch).map { [$0] } ?? view.subviews.flatMap { switches(in: $0) }
    }

    private struct Host: View {
        @AppStorage private var hidesDock: Bool
        @AppStorage private var liquidGlass: Bool
        @AppStorage private var rows: Int
        @AppStorage private var columns: Int

        init(defaults: UserDefaults) {
            _hidesDock = AppStorage(wrappedValue: false, ClassicalDockPreference.key, store: defaults)
            _liquidGlass = AppStorage(wrappedValue: true, ClassicalFolderGlassPreference.key, store: defaults)
            _rows = AppStorage(wrappedValue: ClassicalSpringboardGeometry.defaultRows, ClassicalGridPreference.rowsKey, store: defaults)
            _columns = AppStorage(wrappedValue: ClassicalSpringboardGeometry.defaultColumns, ClassicalGridPreference.columnsKey,
                                  store: defaults)
        }

        var body: some View {
            InterfaceSettingsView(classicalHidesDock: $hidesDock, classicalFolderLiquidGlass: $liquidGlass,
                                  classicalRows: $rows, classicalColumns: $columns)
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Timed out waiting for the stored preference.")
    }
}
