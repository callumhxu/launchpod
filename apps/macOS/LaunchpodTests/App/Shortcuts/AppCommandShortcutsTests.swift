import AppKit
import Testing
@testable import Launchpod

@Suite(.serialized)
@MainActor
struct AppCommandShortcutsTests {

    @Test func settingsCommandRunsOnceAndIsWithheldFromTheFocusedWindow() throws {
        var opens = 0
        let shortcuts = AppCommandShortcuts(
            commands: AppCommandShortcuts.launcherCommands(openSettings: { opens += 1 }, closeWindow: {}),
            isEligible: { true }
        )

        #expect(shortcuts.process(try event(",", modifiers: .command)))
        #expect(opens == 1)
        // Auto repeats stay consumed so the window never receives a stray comma.
        #expect(shortcuts.process(try event(",", modifiers: .command, isARepeat: true)))
        #expect(opens == 1)
        #expect(shortcuts.process(try event(",", modifiers: .command)))
        #expect(opens == 2)
    }

    @Test(arguments: [
        (",", NSEvent.ModifierFlags.command.union(.shift).rawValue),
        (",", NSEvent.ModifierFlags.command.union(.control).rawValue),
        ("，", NSEvent.ModifierFlags.command.union(.option).rawValue),
        (",", NSEvent.ModifierFlags().rawValue),
        ("q", NSEvent.ModifierFlags.command.rawValue),
        ("a", NSEvent.ModifierFlags.command.rawValue)
    ])
    func unmatchedKeystrokesArePassedThrough(key: String, modifiers: UInt) throws {
        var opens = 0
        let shortcuts = AppCommandShortcuts(
            commands: AppCommandShortcuts.launcherCommands(openSettings: { opens += 1 }, closeWindow: {}),
            isEligible: { true }
        )

        #expect(!shortcuts.process(try event(key, modifiers: .init(rawValue: modifiers))))
        #expect(opens == 0)
    }

    @Test func ineligibleFocusNeverClaimsTheShortcut() throws {
        var opens = 0
        let focus = Focus()
        let shortcuts = AppCommandShortcuts(
            commands: AppCommandShortcuts.launcherCommands(openSettings: { opens += 1 }, closeWindow: {}),
            isEligible: { focus.isEligible }
        )

        #expect(!shortcuts.process(try event(",", modifiers: .command)))
        #expect(opens == 0)
        focus.isEligible = true
        #expect(shortcuts.process(try event(",", modifiers: .command)))
        #expect(opens == 1)
    }

    @Test(arguments: [",", "\u{FF0C}"])
    func anInputMethodsOwnPunctuationStillMatchesTheShortcut(comma: String) throws {
        var opens = 0
        let shortcuts = AppCommandShortcuts(
            commands: AppCommandShortcuts.launcherCommands(openSettings: { opens += 1 }, closeWindow: {}),
            isEligible: { true }
        )

        // A Chinese input method sends ⌘, as the fullwidth comma.
        #expect(shortcuts.process(try event(comma, modifiers: .command)))
        #expect(opens == 1)
    }

    @Test(arguments: ["w", "W", "ｗ", "Ｗ"])
    func closeWindowIsServedWithoutAMenuBar(key: String) throws {
        var opens = 0
        var closes = 0
        let shortcuts = AppCommandShortcuts(
            commands: AppCommandShortcuts.launcherCommands(
                openSettings: { opens += 1 }, closeWindow: { closes += 1 }
            ),
            isEligible: { true }
        )

        #expect(shortcuts.process(try event(key, modifiers: .command)))
        #expect(closes == 1)
        #expect(opens == 0)
    }

    @Test(arguments: [("Ｗ", "w"), ("É", "é"), ("！", "!")])
    func commandDefinitionsAndEventsUseTheSameCharacterNormalization(commandKey: String, eventKey: String) throws {
        var actions = 0
        let shortcuts = AppCommandShortcuts(
            commands: [.init(key: commandKey, perform: { actions += 1 })],
            isEligible: { true }
        )

        #expect(shortcuts.process(try event(eventKey, modifiers: [.command, .capsLock, .function])))
        #expect(actions == 1)
        #expect(shortcuts.process(try event(eventKey, modifiers: .command, isARepeat: true)))
        #expect(actions == 1)
    }

    @Test func startIsRepeatableAndStopReleasesTheMonitor() throws {
        let shortcuts = AppCommandShortcuts(commands: [], isEligible: { true })
        shortcuts.start()
        shortcuts.start()
        shortcuts.stop()
        shortcuts.stop()
    }

    @MainActor
    private final class Focus {
        var isEligible = false
    }

    private func event(
        _ key: String, modifiers: NSEvent.ModifierFlags, isARepeat: Bool = false
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
            isARepeat: isARepeat, keyCode: 0
        ))
    }
}
