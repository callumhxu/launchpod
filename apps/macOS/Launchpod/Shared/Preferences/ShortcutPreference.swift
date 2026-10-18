import AppKit
import Observation

@MainActor
@Observable
final class ShortcutPreference {
    struct Binding: Equatable {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
        let characters: String

        init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String) {
            let normalized = modifiers.intersection([.command, .option, .control, .shift])
            guard !normalized.intersection([.command, .option, .control]).isEmpty,
                  !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
                  }) else { return nil }
            self.keyCode = keyCode
            self.modifiers = normalized
            self.characters = characters
        }
    }

    static let preferenceKey = "launcherShortcut"

    var selection: Binding? {
        didSet {
            guard selection != oldValue else { return }
            guard let selection else {
                defaults.removeObject(forKey: Self.preferenceKey)
                return
            }
            defaults.set([
                "keyCode": Int(selection.keyCode),
                "modifiers": selection.modifiers.rawValue,
                "characters": selection.characters
            ], forKey: Self.preferenceKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let stored = defaults.dictionary(forKey: Self.preferenceKey),
              let keyCode = stored["keyCode"] as? Int,
              let code = UInt16(exactly: keyCode),
              let modifiers = stored["modifiers"] as? UInt,
              let characters = stored["characters"] as? String else {
            selection = nil
            return
        }
        selection = Binding(keyCode: code, modifiers: .init(rawValue: modifiers), characters: characters)
    }
}
