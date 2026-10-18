import Testing
@testable import Launchpod

@MainActor
struct LauncherPresentationStateTests {
    @Test
    func repeatedRequestsDoNotRestartTransitions() throws {
        let state = LauncherPresentationState()
        #expect(state.phase == .inactive)
        #expect(!state.targetIsVisible)
        #expect(state.requestVisibility(false) == nil)

        let opening = try #require(state.requestVisibility(true))
        #expect(opening.targetIsVisible)
        #expect(state.phase == .preparing)
        #expect(state.targetIsVisible)
        #expect(state.requestVisibility(true) == nil)
        #expect(state.complete(opening))
        #expect(state.phase == .visible)
        #expect(state.targetIsVisible)
        #expect(state.requestVisibility(true) == nil)

        let closing = try #require(state.requestVisibility(false))
        #expect(!closing.targetIsVisible)
        #expect(state.phase == .dismissing)
        #expect(!state.targetIsVisible)
        #expect(state.requestVisibility(false) == nil)
        #expect(state.complete(closing))
        #expect(state.phase == .inactive)
        #expect(!state.targetIsVisible)
        #expect(state.requestVisibility(false) == nil)
    }

    @Test(arguments: [true, false])
    func invocationReversesAnUnfinishedTransition(firstTargetIsVisible: Bool) {
        let state = LauncherPresentationState()
        if !firstTargetIsVisible {
            #expect(state.complete(state.toggle()))
        }
        let first = state.toggle()
        #expect(first.targetIsVisible == firstTargetIsVisible)
        let reversed = state.toggle()
        let expectedPhase: LauncherPresentationState.Phase = firstTargetIsVisible ? .dismissing : .preparing
        let completedPhase: LauncherPresentationState.Phase = firstTargetIsVisible ? .inactive : .visible

        #expect(reversed.targetIsVisible == !firstTargetIsVisible)
        #expect(state.targetIsVisible == !firstTargetIsVisible)
        #expect(state.phase == expectedPhase)
        #expect(!state.complete(first))
        #expect(state.phase == expectedPhase)
        #expect(state.complete(reversed))
        #expect(state.phase == completedPhase)
        #expect(!state.complete(first))
        #expect(state.phase == completedPhase)
    }

    @Test(arguments: [true, false])
    func oldCallbacksCannotCompleteANewTransitionWithTheSameTarget(targetIsVisible: Bool) {
        let state = LauncherPresentationState()
        if !targetIsVisible {
            #expect(state.complete(state.toggle()))
        }
        let first = state.toggle()
        let reversed = state.toggle()
        let latest = state.toggle()
        let expectedPhase: LauncherPresentationState.Phase = targetIsVisible ? .preparing : .dismissing
        let completedPhase: LauncherPresentationState.Phase = targetIsVisible ? .visible : .inactive

        #expect(first.targetIsVisible == targetIsVisible)
        #expect(latest.targetIsVisible == targetIsVisible)
        for stale in [first, reversed] {
            #expect(!state.complete(stale))
            #expect(state.phase == expectedPhase)
            #expect(state.targetIsVisible == targetIsVisible)
        }
        #expect(state.complete(latest))
        for stale in [first, reversed] {
            #expect(!state.complete(stale))
            #expect(state.phase == completedPhase)
        }
    }

    @Test
    func duplicateCompletionsCannotConsumeLaterTransitions() {
        let state = LauncherPresentationState()
        let opening = state.toggle()

        #expect(state.complete(opening))
        #expect(!state.complete(opening))
        #expect(state.phase == .visible)

        let closing = state.toggle()
        #expect(!state.complete(opening))
        #expect(state.phase == .dismissing)
        #expect(state.complete(closing))
        #expect(!state.complete(closing))
        #expect(state.phase == .inactive)

        let reopened = state.toggle()
        #expect(!state.complete(opening))
        #expect(!state.complete(closing))
        #expect(state.phase == .preparing)
        #expect(state.complete(reopened))
        #expect(state.phase == .visible)
    }

    @Test(arguments: [true, false])
    func resetInvalidatesInFlightCallbacksBeforeReopening(targetIsVisible: Bool) {
        let state = LauncherPresentationState()
        if !targetIsVisible {
            #expect(state.complete(state.toggle()))
        }
        let inFlight = state.toggle()
        #expect(inFlight.targetIsVisible == targetIsVisible)
        state.reset()
        state.reset()

        #expect(state.phase == .inactive)
        #expect(!state.targetIsVisible)
        #expect(!state.complete(inFlight))
        #expect(state.phase == .inactive)
        let reopened = state.toggle()
        #expect(reopened.targetIsVisible)
        #expect(!state.complete(inFlight))
        #expect(state.phase == .preparing)
        #expect(state.complete(reopened))
        #expect(state.phase == .visible)
    }

    @Test(arguments: [100, 101])
    func rapidTogglesAcceptOnlyTheLastCompletion(invocationCount: Int) throws {
        let state = LauncherPresentationState()
        let transitions = (0..<invocationCount).map { _ in state.toggle() }
        let latest = try #require(transitions.last)
        let targetIsVisible = invocationCount % 2 == 1
        let expectedPhase: LauncherPresentationState.Phase = targetIsVisible ? .preparing : .dismissing
        let completedPhase: LauncherPresentationState.Phase = targetIsVisible ? .visible : .inactive

        #expect(latest.targetIsVisible == targetIsVisible)
        for transition in transitions.dropLast().reversed() {
            #expect(!state.complete(transition))
            #expect(state.phase == expectedPhase)
        }
        #expect(state.complete(latest))
        #expect(state.phase == completedPhase)
    }
}
