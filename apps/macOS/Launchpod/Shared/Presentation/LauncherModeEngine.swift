@MainActor
protocol LauncherModeEngine: AnyObject {
    var mode: LauncherMode { get }
    var presentation: LauncherPresentationState { get }

    /// Releases transient session state and invalidates unfinished transitions.
    func destroySession()
}

extension LauncherModeEngine {
    var state: LauncherPresentationState.Phase { presentation.phase }
}
