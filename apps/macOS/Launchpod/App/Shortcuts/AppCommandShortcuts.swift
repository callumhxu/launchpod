import AppKit

/// Dispatches the application's own ⌘ commands while it stays inactive.
///
/// `AppShortcutFocus` explains why the menu bar cannot do this for a launcher
/// that never activates the application. Commands are declared as data so a new
/// shortcut only needs one entry.
@MainActor
final class AppCommandShortcuts {
    struct Command {
        let key: String
        let modifiers: NSEvent.ModifierFlags
        let perform: @MainActor () -> Void

        init(
            key: String,
            modifiers: NSEvent.ModifierFlags = .command,
            perform: @escaping @MainActor () -> Void
        ) {
            self.key = AppCommandShortcuts.normalizedKey(key)
            self.modifiers = modifiers.intersection([.command, .control, .option, .shift])
            self.perform = perform
        }
    }

    private let commands: [Command]
    private let isEligible: @MainActor () -> Bool
    private var monitor: Any?

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    init(
        commands: [Command],
        isEligible: @escaping @MainActor () -> Bool = { AppShortcutFocus.ownsCommandShortcuts(in: .shared) }
    ) {
        self.commands = commands
        self.isEligible = isEligible
    }

    /// The commands the app answers for itself, in place of the menu bar.
    static func launcherCommands(
        openSettings: @escaping @MainActor () -> Void,
        closeWindow: @escaping @MainActor () -> Void = {
            AppShortcutFocus.focusedWindow(in: .shared)?.performClose(nil)
        }
    ) -> [Command] {
        [Command(key: ",", perform: openSettings), Command(key: "w", perform: closeWindow)]
    }

    /// An input method reports a shortcut's key in its own punctuation: a Chinese
    /// one sends ⌘, as the fullwidth comma "，" (U+FF0C), which is not equal to
    /// ",". Folding fullwidth forms to halfwidth makes both forms compare equally.
    static func normalizedKey(_ characters: String) -> String {
        if characters.utf8.allSatisfy({ $0 < 0x80 }) { return characters.lowercased() }
        return (characters.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? characters).lowercased()
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.process(event) ?? false }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Consumes a matching command so the focused window never sees it, and
    /// swallows its auto repeats without performing the command again.
    @discardableResult
    func process(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let characters = event.charactersIgnoringModifiers else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard commands.contains(where: { $0.modifiers == modifiers }) else { return false }
        let key = Self.normalizedKey(characters)
        guard let command = commands.first(where: { $0.key == key && $0.modifiers == modifiers }),
              isEligible() else { return false }
        if !event.isARepeat { command.perform() }
        return true
    }
}
