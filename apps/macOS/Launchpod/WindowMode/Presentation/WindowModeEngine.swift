@MainActor
final class WindowModeEngine: LauncherModeEngine {
    let mode = LauncherMode.window
    let presentation = LauncherPresentationState()

    func destroySession() {
        presentation.reset()
    }
}
