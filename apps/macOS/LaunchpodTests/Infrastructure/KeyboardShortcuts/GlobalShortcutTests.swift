import AppKit
import Testing
@testable import Launchpod

@MainActor
struct GlobalShortcutTests {
    @Test
    func heldKeysInvokeOnceAndRebindingInvalidatesOldCallbacks() throws {
        let first = try #require(ShortcutPreference.Binding(keyCode: 40, modifiers: [.control, .option], characters: "k"))
        let second = try #require(ShortcutPreference.Binding(keyCode: 37, modifiers: [.control, .option], characters: "l"))
        var callbacks: [@MainActor (Bool) -> Void] = []
        var registered: [ShortcutPreference.Binding] = []
        var cancellations = 0
        var actions = 0
        let shortcut = GlobalShortcut(register: { binding, receive in
            registered.append(binding)
            callbacks.append(receive)
            return { cancellations += 1 }
        }, action: { actions += 1 })

        shortcut.update(binding: nil)
        #expect(registered.isEmpty)
        shortcut.update(binding: first)
        shortcut.update(binding: first)
        #expect(registered == [first])
        let original = try #require(callbacks.first)
        for _ in 0..<100 { original(true) }
        #expect(actions == 1)
        original(false)
        original(true)
        #expect(actions == 2)

        shortcut.update(binding: second)
        #expect(registered == [first, second])
        #expect(cancellations == 1)
        let replacement = try #require(callbacks.last)
        replacement(true)
        #expect(actions == 3)
        original(false)
        replacement(true)
        #expect(actions == 3)
        original(true)
        #expect(actions == 3)
        replacement(false)
        replacement(true)
        #expect(actions == 4)
        shortcut.stop()
        shortcut.stop()
        #expect(cancellations == 2)
        #expect(shortcut.binding == nil)
        replacement(false)
        replacement(true)
        #expect(actions == 4)
    }

    @Test
    func failedRegistrationCanRetryTheSameBindingAndDisablingCancelsIt() throws {
        let binding = try #require(ShortcutPreference.Binding(keyCode: 40, modifiers: .command, characters: "k"))
        var attempts = 0
        var cancellations = 0
        let shortcut = GlobalShortcut(register: { _, _ in
            attempts += 1
            if attempts == 1 { throw NSError(domain: NSOSStatusErrorDomain, code: -9878) }
            return { cancellations += 1 }
        }, action: {})

        shortcut.update(binding: binding)
        #expect(shortcut.registrationError == -9878)
        #expect(shortcut.binding == binding)
        #expect(cancellations == 0)
        shortcut.update(binding: binding)
        #expect(attempts == 2)
        #expect(shortcut.registrationError == nil)
        shortcut.update(binding: nil)
        #expect(cancellations == 1)
        #expect(shortcut.binding == nil)
        #expect(shortcut.registrationError == nil)
    }

    @Test
    func releasingOwnerCancelsRegistrationAndRetainedCallbackCannotKeepItAlive() throws {
        let binding = try #require(ShortcutPreference.Binding(keyCode: 40, modifiers: .option, characters: "k"))
        var receive: (@MainActor (Bool) -> Void)?
        var cancellations = 0
        var actions = 0
        var shortcut: GlobalShortcut? = GlobalShortcut(register: { _, callback in
            receive = callback
            return { cancellations += 1 }
        }, action: { actions += 1 })
        weak let released = shortcut
        shortcut?.update(binding: binding)
        shortcut = nil
        #expect(released == nil)
        #expect(cancellations == 1)
        receive?(true)
        #expect(actions == 0)
    }
}
