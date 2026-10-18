import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class HoldToQuitPromptTests: XCTestCase {
    func testPromptReportsClampedProgressWithoutTakingKeyboardFocusAndHides() throws {
        try NativeAppTestSupport.requireNativeWindowTests()
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let prompt = HoldToQuitPrompt()
        defer { prompt.hide() }
        let keyWindow = NSApplication.shared.keyWindow

        prompt.show(locale: Locale(identifier: "en"))

        let panel = try visiblePanel()
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(NSApplication.shared.keyWindow === keyWindow)
        let content = try XCTUnwrap(panel.contentView)
        let progress = try XCTUnwrap(descendants(content).compactMap { $0 as? NSProgressIndicator }.first)
        XCTAssertFalse(progress.isIndeterminate)
        XCTAssertEqual(progress.doubleValue, 0)
        for (input, expected) in [(-1.0, 0.0), (0.5, 0.5), (2.0, 1.0)] {
            prompt.update(progress: input)
            XCTAssertEqual(progress.doubleValue, expected)
        }

        prompt.hide()
        XCTAssertFalse(panel.isVisible)
        prompt.hide()
        prompt.update(progress: 0.2)
        XCTAssertFalse(panel.isVisible)
    }

    func testShowingAgainReplacesPreviousPanelAndUsesRequestedLocale() throws {
        try NativeAppTestSupport.requireNativeWindowTests()
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let prompt = HoldToQuitPrompt()
        defer { prompt.hide() }
        prompt.show(locale: Locale(identifier: "en"))
        let first = try visiblePanel()
        let english = labels(in: try XCTUnwrap(first.contentView))
        XCTAssertTrue(english.contains("Hold ⌘Q for 2 seconds to quit Launchpod"))

        prompt.show(locale: Locale(identifier: "zh-Hans"))

        let second = try visiblePanel()
        XCTAssertFalse(first.isVisible)
        XCTAssertFalse(first === second)
        let chinese = labels(in: try XCTUnwrap(second.contentView))
        XCTAssertEqual(chinese.count, english.count)
        XCTAssertNotEqual(chinese, english)
        XCTAssertTrue(chinese.contains { $0.contains("Launchpod") && $0.contains("⌘Q") })
        XCTAssertEqual(NSApplication.shared.windows.filter {
            $0.accessibilityIdentifier() == "holdToQuitPrompt" && $0.isVisible
        }.count, 1)
    }

    private func visiblePanel() throws -> NSWindow {
        try XCTUnwrap(NSApplication.shared.windows.first {
            $0.accessibilityIdentifier() == "holdToQuitPrompt" && $0.isVisible
        })
    }

    private func labels(in view: NSView) -> [String] {
        descendants(view).compactMap { ($0 as? NSTextField)?.stringValue }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
