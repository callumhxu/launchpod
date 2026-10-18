import Testing
@testable import Launchpod

@MainActor
struct WindowModeEngineTests {
    @Test
    func startsInactiveInWindowMode() {
        let engine = WindowModeEngine()

        #expect(engine.mode == .window)
        #expect(engine.state == .inactive)
    }

    @Test
    func simultaneousInstancesKeepCallbacksAndResetIndependent() {
        let previous = WindowModeEngine()
        let previousOpening = previous.presentation.toggle()
        let replacement = WindowModeEngine()
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
