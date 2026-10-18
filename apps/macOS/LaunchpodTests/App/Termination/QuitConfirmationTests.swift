import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class QuitConfirmationTests: XCTestCase {
    func testNativeAlertExplainsLostAccessAndMakesCancelTheDefault() {
        _ = NSApplication.shared
        let alert = QuitConfirmation.makeAlert(locale: Locale(identifier: "en"))
        XCTAssertEqual(alert.alertStyle, .warning)
        XCTAssertEqual(alert.messageText, "Quit Launchpod?")
        XCTAssertEqual(alert.informativeText,
                       "After quitting, keyboard shortcuts and the menu bar will be unavailable. Open Launchpod again to use it.")
        XCTAssertEqual(alert.buttons.map(\.title), ["Cancel", "Quit"])
        XCTAssertEqual(alert.buttons[0].keyEquivalent, "\r")
        XCTAssertTrue(alert.buttons[0].keyEquivalentModifierMask.isEmpty)
        XCTAssertEqual(alert.buttons[1].keyEquivalent, "")
    }

    func testOnlyQuitAcceptsTheActualModalConfirmation() throws {
        _ = NSApplication.shared
        for (characters, keyCode) in [("\r", UInt16(36)), ("\u{1b}", UInt16(53)), ("", UInt16(0))] {
            var timedOut = false
            var sentInput = false
            DispatchQueue.main.async {
                guard let window = NSApplication.shared.modalWindow else { return }
                if characters.isEmpty {
                    guard let content = window.contentView, let quit = self.quitButton(in: content) else { return }
                    sentInput = true
                    quit.performClick(nil)
                    return
                }
                guard let event = NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: characters,
                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
                      ) else { return }
                sentInput = true
                NSApplication.shared.postEvent(event, atStart: true)
            }
            let watchdog = DispatchWorkItem {
                MainActor.assumeIsolated {
                    timedOut = true
                    NSApplication.shared.abortModal()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: watchdog)

            let confirmed = QuitConfirmation.confirm(locale: Locale(identifier: "en"))
            watchdog.cancel()

            XCTAssertEqual(confirmed, characters.isEmpty)
            XCTAssertTrue(sentInput)
            XCTAssertFalse(timedOut, "The confirmation did not respond to key code \(keyCode).")
        }
    }

    private func quitButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.title == "Quit" { return button }
        for child in view.subviews {
            if let button = quitButton(in: child) { return button }
        }
        return nil
    }
}
