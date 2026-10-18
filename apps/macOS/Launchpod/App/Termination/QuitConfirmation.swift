import AppKit

@MainActor
enum QuitConfirmation {
    static func makeAlert(locale: Locale) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: LocalizedStringResource("Quit Launchpod?", locale: locale))
        alert.informativeText = String(localized: LocalizedStringResource(
            "After quitting, keyboard shortcuts and the menu bar will be unavailable. Open Launchpod again to use it.",
            locale: locale
        ))
        let cancel = alert.addButton(withTitle: String(localized: LocalizedStringResource("Cancel", locale: locale)))
        cancel.keyEquivalent = "\r"
        cancel.keyEquivalentModifierMask = []
        let quit = alert.addButton(withTitle: String(localized: LocalizedStringResource("Quit", locale: locale)))
        quit.keyEquivalent = ""
        alert.window.defaultButtonCell = cancel.cell as? NSButtonCell
        return alert
    }

    static func confirm(locale: Locale) -> Bool {
        let alert = makeAlert(locale: locale)
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak alert] event in
            let handled = MainActor.assumeIsolated {
                guard let alert, event.window === alert.window,
                      ["\r", "\u{1b}"].contains(event.charactersIgnoringModifiers ?? ""),
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
                alert.buttons[0].performClick(nil)
                return true
            }
            return handled ? nil : event
        }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        NSApplication.shared.activate()
        return alert.runModal() == .alertSecondButtonReturn
    }
}
