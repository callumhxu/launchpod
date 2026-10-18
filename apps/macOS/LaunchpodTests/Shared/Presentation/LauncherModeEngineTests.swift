import Testing
@testable import Launchpod

@MainActor
struct LauncherModeEngineTests {
    @Test(arguments: LauncherMode.allCases)
    func lifecycleIsVisibleThroughModeBoundary(mode: LauncherMode) {
        let engine = makeEngine(mode: mode)
        let opening = engine.presentation.toggle()
        #expect(engine.state == .preparing)

        #expect(engine.presentation.complete(opening))
        #expect(engine.state == .visible)

        let closing = engine.presentation.toggle()
        #expect(engine.state == .dismissing)
        #expect(engine.presentation.complete(closing))
        #expect(engine.state == .inactive)
    }

    @Test
    func modesDoNotShareStateOrAcceptEachOthersCompletions() {
        let classical: any LauncherModeEngine = ClassicalModeEngine()
        let window: any LauncherModeEngine = WindowModeEngine()
        let classicalOpening = classical.presentation.toggle()
        #expect(window.state == .inactive)

        let windowOpening = window.presentation.toggle()
        #expect(!window.presentation.complete(classicalOpening))
        #expect(!classical.presentation.complete(windowOpening))
        #expect(classical.state == .preparing)
        #expect(window.state == .preparing)
        #expect(classical.presentation.complete(classicalOpening))
        #expect(classical.state == .visible)
        #expect(window.state == .preparing)

        classical.presentation.reset()
        #expect(!classical.presentation.complete(classicalOpening))
        #expect(window.presentation.complete(windowOpening))
        #expect(window.state == .visible)
        #expect(classical.state == .inactive)
    }

    @Test(arguments: LauncherMode.allCases)
    func destroyingSessionInvalidatesTransitionsWithoutAffectingAnotherEngine(mode: LauncherMode) {
        let engine = makeEngine(mode: mode)
        let other = makeEngine(mode: mode == .classical ? .window : .classical)
        let opening = engine.presentation.toggle()
        let otherOpening = other.presentation.toggle()

        engine.destroySession()
        engine.destroySession()
        #expect(engine.state == .inactive)
        #expect(!engine.presentation.complete(opening))
        #expect(other.state == .preparing)
        #expect(other.presentation.complete(otherOpening))
        #expect(other.state == .visible)
    }

    private func makeEngine(mode: LauncherMode) -> any LauncherModeEngine {
        switch mode {
        case .classical: ClassicalModeEngine()
        case .window: WindowModeEngine()
        }
    }
}
