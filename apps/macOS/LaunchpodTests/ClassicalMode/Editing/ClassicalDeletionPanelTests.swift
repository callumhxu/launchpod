import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalDeletionPanelTests: XCTestCase {
    /// A 20 pt square at the centre of the icon image.
    func testDeletionPanelPointsAtTheIconCentre() {
        XCTAssertEqual(ClassicalDeletionPanel.anchor(icon: CGRect(x: 35, y: 43, width: 96, height: 96)),
                       CGRect(x: 73, y: 81, width: 20, height: 20))
        XCTAssertEqual(ClassicalDeletionPanel.anchor(icon: CGRect(x: 0, y: 0, width: 75, height: 75)),
                       CGRect(x: 27, y: 27, width: 21, height: 21), "trunc(37.5) − 10 on each side")
    }

    func testDeletionMessageUsesTheDocksWording() {
        XCTAssertEqual(ClassicalDeletionPanel.message(for: "Pages", locale: Locale(identifier: "en")),
                       "Are you sure you want to delete the application “Pages”?")
        XCTAssertEqual(ClassicalDeletionPanel.message(for: "Pages", locale: Locale(identifier: "zh-Hans")),
                       CatalogTestSupport.format("Are you sure you want to delete the application “%@”?",
                                                 locale: "zh-Hans", argument: "Pages"))
    }

    /// 64 pt icon, message 304 pt wide, Cancel then the default action button.
    func testDeletionPanelLayoutAndKeys() throws {
        let record = try record("Pages")
        let panel = ClassicalDeletionPanel(record: record, icon: NSImage(size: CGSize(width: 64, height: 64)),
                                           message: "Are you sure?", cancelTitle: "Cancel", actionTitle: "Delete")
        let view = try XCTUnwrap(panel.popover.contentViewController?.view)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.frame.size, CGSize(width: 400, height: 84))
        XCTAssertEqual(panel.messageField.frame, CGRect(x: 82, y: 40, width: 308, height: 34), "The nib's frame, with the field's 2 pt alignment insets")
        XCTAssertEqual(panel.popover.behavior, .applicationDefined)
        XCTAssertEqual(panel.actionButton.keyEquivalent, "\r")
        XCTAssertLessThan(panel.cancelButton.frame.maxX, panel.actionButton.frame.minX)
        var results: [Bool] = []
        panel.onFinish = { results.append($0) }
        panel.handleKey(try key(keyCode: 0, characters: "a"))
        XCTAssertEqual(results, [], "Other keys do nothing")
        panel.handleKey(try key(keyCode: 53, characters: "\u{1b}"))
        panel.handleKey(try key(keyCode: 36, characters: "\r"))
        XCTAssertEqual(results, [false], "Escape cancels, once")

        let confirming = ClassicalDeletionPanel(record: record, icon: NSImage(), message: "", cancelTitle: "", actionTitle: "")
        confirming.onFinish = { results.append($0) }
        confirming.handleKey(try key(keyCode: 76, characters: "\u{3}"))
        XCTAssertEqual(results, [false, true], "Enter chooses the action")
    }

    private func key(keyCode: UInt16, characters: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                       isARepeat: false, keyCode: keyCode))
    }

    private func record(_ name: String) throws -> AppRecord {
        let url = URL(filePath: "/Applications/\(name).app", directoryHint: .isDirectory)
        return AppRecord(
            id: AppIdentity(),
            metadata: try AppMetadata(bundleIdentifier: "com.example.\(UUID().uuidString)", bundleURL: url,
                                      displayName: name, version: nil, buildVersion: nil, contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: url.deletingLastPathComponent())
        )
    }
}
