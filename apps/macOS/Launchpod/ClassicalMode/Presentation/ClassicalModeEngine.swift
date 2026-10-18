@MainActor
final class ClassicalModeEngine: LauncherModeEngine {
    let mode = LauncherMode.classical
    let presentation = LauncherPresentationState()

    func destroySession() {
        presentation.reset()
    }
}
