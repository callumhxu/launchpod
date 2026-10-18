import AppKit
import Testing
@testable import Launchpod

@MainActor
struct HoldToQuitControllerTests {
    @Test
    func twoSecondHoldQuitsWithoutWaitingForTheKeyToComeUp() throws {
        let inputs = Inputs(time: 10)
        var actions: [String] = []
        var progress: [Double] = []
        let controller = HoldToQuitController(
            isEligible: { true }, now: { inputs.time }, isKeyPressed: { _ in true },
            showPrompt: { actions.append("show") }, updateProgress: { progress.append($0) },
            hidePrompt: { actions.append("hide") }, quit: { _ in actions.append("quit") }
        )
        defer { controller.stop() }

        #expect(controller.process(try event(.keyDown)))
        #expect(controller.isHolding)
        #expect(actions == ["show"])
        inputs.time = 11
        controller.checkHoldCompletion()
        #expect(actions == ["show"])
        #expect(progress == [0, 0.5])

        // The key is still physically down: the hold completes on time anyway.
        inputs.time = 12
        controller.checkHoldCompletion()
        #expect(actions == ["show", "hide", "quit"])
        #expect(!controller.isHolding)

        // Nothing is left running to quit a second time.
        inputs.time = 20
        controller.checkHoldCompletion()
        #expect(actions == ["show", "hide", "quit"])
    }

    @Test
    func theCompletedChordStaysConsumedWhenEligibilityAndCommandAreLost() throws {
        let inputs = Inputs()
        var quitKeys: [UInt16] = []
        let controller = HoldToQuitController(
            isEligible: { inputs.isEligible }, now: { inputs.time }, isKeyPressed: { _ in inputs.isPressed },
            showPrompt: {}, hidePrompt: {}, quit: {
                quitKeys.append($0)
                inputs.isEligible = false
            }
        )
        defer { controller.stop() }
        #expect(controller.process(try event(.keyDown)))
        inputs.time = 2
        controller.checkHoldCompletion()
        #expect(quitKeys == [12])
        #expect(!controller.isHolding)
        controller.cancel()

        // Repeats of the still-held key must not reach the focused window, and
        // must not quit again.
        #expect(controller.process(try event(.keyDown, repeatKey: true)))
        _ = controller.process(try event(.flagsChanged, modifiers: []))
        #expect(controller.process(try event(.keyDown, modifiers: [], repeatKey: true)))
        #expect(!controller.process(try event(.keyDown, modifiers: [], keyCode: 0, characters: "a")))
        #expect(controller.process(try event(.keyDown, modifiers: [], repeatKey: true)))
        inputs.time = 20
        controller.checkHoldCompletion()
        #expect(quitKeys == [12])

        inputs.isPressed = false
        #expect(controller.process(try event(.keyUp, modifiers: [])))
        controller.endDraining()
        #expect(!controller.process(try event(.keyDown, modifiers: [], repeatKey: true)))
        #expect(quitKeys == [12])
    }

    @Test(arguments: [NSEvent.EventType.keyUp, .flagsChanged])
    func releasingEitherKeyCancelsAndTheNextHoldStartsFromZero(release: NSEvent.EventType) throws {
        let inputs = Inputs()
        var prompts = 0
        var hides = 0
        var quits = 0
        let controller = HoldToQuitController(
            isEligible: { true }, now: { inputs.time }, isKeyPressed: { _ in true },
            showPrompt: { prompts += 1 }, hidePrompt: { hides += 1 }, quit: { _ in quits += 1 }
        )
        defer { controller.stop() }

        #expect(controller.process(try event(.keyDown)))
        inputs.time = 1.99
        _ = controller.process(try event(release, modifiers: release == .flagsChanged ? [] : [.command]))
        #expect(!controller.isHolding)
        inputs.time = 10
        controller.checkHoldCompletion()
        #expect(quits == 0)
        #expect(prompts == 1)
        #expect(hides == 1)

        #expect(controller.process(try event(.keyDown)))
        inputs.time = 11.99
        controller.checkHoldCompletion()
        #expect(quits == 0)
        inputs.time = 12
        controller.checkHoldCompletion()
        #expect(quits == 1)
        #expect(prompts == 2)
    }

    @Test(arguments: [false, true])
    func physicallyReleasingEitherKeyCancelsWithoutAnyEvent(releaseCommand: Bool) throws {
        let inputs = Inputs()
        var hides = 0
        let controller = HoldToQuitController(
            isEligible: { true }, now: { inputs.time },
            isKeyPressed: { keyCode in (keyCode == 12) == releaseCommand ? true : inputs.isPressed },
            showPrompt: {}, hidePrompt: { hides += 1 },
            quit: { _ in Issue.record("A released key cannot complete the hold.") }
        )
        defer { controller.stop() }

        // AppKit delivers no key up while Command is down, so only the polled
        // key state can end the hold.
        #expect(controller.process(try event(.keyDown)))
        inputs.isPressed = false
        inputs.time = 2
        controller.checkHoldCompletion()
        #expect(!controller.isHolding)
        #expect(hides == 1)
        inputs.time = 6
        controller.checkHoldCompletion()
        #expect(hides == 1)
    }

    @Test
    func losingEligibilityAndStoppingCancelThePendingQuit() throws {
        let inputs = Inputs()
        var quits = 0
        let controller = HoldToQuitController(
            isEligible: { inputs.isEligible }, now: { inputs.time }, isKeyPressed: { _ in true },
            showPrompt: {}, hidePrompt: {}, quit: { _ in quits += 1 }
        )
        #expect(controller.process(try event(.keyDown)))
        inputs.time = 1
        controller.checkHoldCompletion()
        inputs.isEligible = false
        inputs.time = 3
        controller.checkHoldCompletion()
        #expect(!controller.isHolding)
        #expect(quits == 0)
        #expect(!controller.process(try event(.keyDown)))

        inputs.isEligible = true
        #expect(controller.process(try event(.keyDown)))
        controller.stop()
        inputs.time = 20
        controller.checkHoldCompletion()
        #expect(!controller.isHolding)
        #expect(quits == 0)
    }

    @Test
    func unrelatedKeysAndModifiedQuitDoNotStartAHold() throws {
        let controller = HoldToQuitController(
            isEligible: { true }, now: { 0 }, isKeyPressed: { _ in true },
            showPrompt: { Issue.record("Unrelated shortcuts must not show the quit prompt.") },
            hidePrompt: {}, quit: { _ in Issue.record("Unrelated shortcuts must not quit.") }
        )
        defer { controller.stop() }
        #expect(!controller.process(try event(.keyDown, modifiers: [])))
        #expect(!controller.process(try event(.keyDown, modifiers: [.command, .shift])))
        #expect(!controller.process(try event(.keyDown, keyCode: 0, characters: "a")))
        #expect(!controller.isHolding)
    }

    @Test
    func aFreshKeyDownRestartsTheHoldFromZero() throws {
        let inputs = Inputs()
        var quits = 0
        let controller = HoldToQuitController(
            isEligible: { true }, now: { inputs.time }, isKeyPressed: { _ in true },
            showPrompt: {}, hidePrompt: {}, quit: { _ in quits += 1 }
        )
        defer { controller.stop() }
        #expect(controller.process(try event(.keyDown)))
        inputs.time = 1.9
        #expect(controller.process(try event(.keyDown)))
        inputs.time = 2
        controller.checkHoldCompletion()
        #expect(quits == 0)
        #expect(controller.isHolding)
        inputs.time = 3.9
        controller.checkHoldCompletion()
        #expect(quits == 1)
    }

    @Test(arguments: [
        ("a", NSEvent.ModifierFlags.command.rawValue),
        ("q", NSEvent.ModifierFlags.command.union(.shift).rawValue),
        ("q", NSEvent.ModifierFlags.command.union(.option).rawValue),
        ("q", NSEvent.ModifierFlags.command.union(.control).rawValue),
        ("q", NSEvent.ModifierFlags().rawValue)
    ])
    func anotherKeystrokeCancelsAnActiveHold(characters: String, modifiers: UInt) throws {
        let inputs = Inputs()
        var hides = 0
        var quits = 0
        let controller = HoldToQuitController(
            isEligible: { true }, now: { inputs.time }, isKeyPressed: { _ in true },
            showPrompt: {}, hidePrompt: { hides += 1 }, quit: { _ in quits += 1 }
        )
        defer { controller.stop() }
        #expect(controller.process(try event(.keyDown)))
        inputs.time = 1

        #expect(!controller.process(try event(
            .keyDown, modifiers: .init(rawValue: modifiers), characters: characters
        )))

        #expect(!controller.isHolding)
        #expect(hides == 1)
        inputs.time = 3
        controller.checkHoldCompletion()
        #expect(quits == 0)
    }

    @Test
    func aRepeatWithoutAnInitialPressIsConsumedButNeverQuits() throws {
        let inputs = Inputs()
        let controller = HoldToQuitController(
            isEligible: { true }, now: { inputs.time }, isKeyPressed: { _ in true },
            showPrompt: { Issue.record("A repeat must not begin a new hold.") },
            hidePrompt: {}, quit: { _ in Issue.record("A repeat alone must not quit.") }
        )
        defer { controller.stop() }
        #expect(controller.process(try event(.keyDown, repeatKey: true)))
        inputs.time = 10
        controller.checkHoldCompletion()
        #expect(!controller.isHolding)
        #expect(!controller.process(try event(.keyUp)))
    }

    @Test
    func mouseInteractionCancelsThePendingQuit() throws {
        let inputs = Inputs()
        var hides = 0
        let controller = HoldToQuitController(
            isEligible: { true }, now: { inputs.time }, isKeyPressed: { _ in true },
            showPrompt: {}, hidePrompt: { hides += 1 },
            quit: { _ in Issue.record("A canceled hold cannot quit.") }
        )
        defer { controller.stop() }
        #expect(controller.process(try event(.keyDown)))
        inputs.time = 1
        controller.checkHoldCompletion()
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: inputs.time,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        #expect(!controller.process(click))
        #expect(!controller.isHolding)
        #expect(hides == 1)
        inputs.time = 10
        controller.checkHoldCompletion()
    }

    @MainActor
    private final class Inputs {
        var time: TimeInterval
        var isEligible = true
        var isPressed = true

        init(time: TimeInterval = 0) {
            self.time = time
        }
    }

    private func event(
        _ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags = [.command],
        repeatKey: Bool = false, keyCode: UInt16 = 12, characters: String = "q"
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: repeatKey, keyCode: keyCode
        ))
    }
}
