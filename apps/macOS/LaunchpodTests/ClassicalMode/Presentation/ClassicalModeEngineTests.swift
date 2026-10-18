import Testing
@testable import Launchpod

@MainActor
struct ClassicalModeEngineTests {
    @Test
    func startsInactiveInClassicalMode() {
        let engine = ClassicalModeEngine()

        #expect(engine.mode == .classical)
        #expect(engine.state == .inactive)
    }

    @Test
    func simultaneousInstancesKeepCallbacksAndResetIndependent() {
        let previous = ClassicalModeEngine()
        let previousOpening = previous.presentation.toggle()
        let replacement = ClassicalModeEngine()
        #expect(replacement.state == .inactive)
        let replacementOpening = replacement.presentation.toggle()

        #expect(!replacement.presentation.complete(previousOpening))
        #expect(!previous.presentation.complete(replacementOpening))
        #expect(previous.state == .preparing)
        #expect(replacement.state == .preparing)
        #expect(previous.presentation.complete(previousOpening))
        #expect(previous.state == .visible)
        #expect(replacement.state == .preparing)

        previous.presentation.reset()
        #expect(previous.state == .inactive)
        #expect(replacement.presentation.complete(replacementOpening))
        #expect(replacement.state == .visible)
        #expect(previous.state == .inactive)
    }
}
