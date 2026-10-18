import AppKit
import Testing
@testable import Launchpod

@MainActor
struct ShortcutPreferenceTests {
    @Test
    func unsetSelectionRoundTripsAUserBindingAndCanBeCleared() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let preference = ShortcutPreference(defaults: defaults)
        #expect(preference.selection == nil)
        let binding = try #require(ShortcutPreference.Binding(
            keyCode: 40, modifiers: [.command, .option, .shift, .capsLock], characters: "K"
        ))
        #expect(binding.modifiers == [.command, .option, .shift])

        preference.selection = binding
        #expect(ShortcutPreference(defaults: defaults).selection == binding)
        preference.selection = nil
        #expect(defaults.object(forKey: ShortcutPreference.preferenceKey) == nil)
        #expect(ShortcutPreference(defaults: defaults).selection == nil)
    }

    @Test
    func rejectsUnmodifiedAndNonPrintableBindingsButAllowsModifiedSpace() {
        #expect(ShortcutPreference.Binding(keyCode: 40, modifiers: [], characters: "k") == nil)
        #expect(ShortcutPreference.Binding(keyCode: 40, modifiers: .shift, characters: "K") == nil)
        for characters in ["", "\n", "\t", "\u{1B}", "\u{F700}", "\u{F704}"] {
            #expect(ShortcutPreference.Binding(keyCode: 40, modifiers: .command, characters: characters) == nil)
        }
        #expect(ShortcutPreference.Binding(keyCode: 49, modifiers: .control, characters: " ") != nil)
    }

    @Test
    func malformedStoredValuesDoNotProduceARegistrationBinding() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let invalid: [[String: Any]] = [
            [:],
            ["keyCode": -1, "modifiers": NSEvent.ModifierFlags.command.rawValue, "characters": "k"],
            ["keyCode": 65536, "modifiers": NSEvent.ModifierFlags.command.rawValue, "characters": "k"],
            ["keyCode": "40", "modifiers": NSEvent.ModifierFlags.command.rawValue, "characters": "k"],
            ["keyCode": 40, "modifiers": 0, "characters": "k"],
            ["keyCode": 40, "modifiers": NSEvent.ModifierFlags.command.rawValue, "characters": ""]
        ]
        for value in invalid {
            defaults.set(value, forKey: ShortcutPreference.preferenceKey)
            #expect(ShortcutPreference(defaults: defaults).selection == nil)
        }
    }
}
