import AppKit

/// Owns the selected mode and its lazily created presentation session.
@MainActor
final class LauncherCoordinator {
    private(set) var mode: LauncherMode
    private(set) var session: (any LauncherModeEngine)?
    private(set) var pendingMode: LauncherMode?

    private let launcher: WorkspaceApplicationLauncher
    private let onModeChange: @MainActor (LauncherMode) -> Void

    isolated deinit {
        stop()
    }

    init(
        mode: LauncherMode = .classical,
        launcher: WorkspaceApplicationLauncher? = nil,
        onModeChange: @escaping @MainActor (LauncherMode) -> Void = { _ in }
    ) {
        self.mode = mode
        self.launcher = launcher ?? WorkspaceApplicationLauncher()
        self.onModeChange = onModeChange
    }

    /// Returns the current session, or creates one without requesting visibility.
    /// A pending mode switch must finish dismissing before a session is available.
    func sessionForSelectedMode() -> (any LauncherModeEngine)? {
        guard pendingMode == nil else { return nil }
        if let session { return session }

        let newSession: any LauncherModeEngine
        switch mode {
        case .classical:
            newSession = ClassicalModeEngine()
        case .window:
            newSession = WindowModeEngine()
        }
        session = newSession
        return newSession
    }

    /// Toggles the selected session's visibility request without completing presentation.
    /// A pending mode switch keeps its dismissal request until completion.
    @discardableResult
    func toggle() -> LauncherPresentationState.Transition? {
        sessionForSelectedMode()?.presentation.toggle()
    }

    /// Defers selection until the old session's dismissal completes, if needed.
    /// The caller must drive any returned transition using its presentation surface.
    @discardableResult
    func selectMode(_ mode: LauncherMode) -> LauncherPresentationState.Transition? {
        guard pendingMode != nil || mode != self.mode else { return nil }
        pendingMode = mode

        guard let session, session.state != .inactive else {
            finishModeSwitch()
            return nil
        }
        return session.presentation.requestVisibility(false)
    }

    /// Requests dismissal after a successful launch only if its session has no newer visibility request.
    /// The caller must drive the returned transition and report its actual completion.
    func launch(_ metadata: AppMetadata) async throws -> (
        application: NSRunningApplication,
        dismissal: LauncherPresentationState.Transition?
    ) {
        weak let launchingSession = session
        let visibilityRequestRevision = launchingSession?.presentation.visibilityRequestRevision
        let application = try await launcher.launch(metadata)
        guard let launchingSession, launchingSession === session,
              launchingSession.presentation.visibilityRequestRevision == visibilityRequestRevision else {
            return (application, nil)
        }
        return (application, launchingSession.presentation.requestVisibility(false))
    }

    /// Accepts only the current session's outstanding transition.
    @discardableResult
    func complete(_ transition: LauncherPresentationState.Transition) -> Bool {
        guard let session, session.presentation.complete(transition) else { return false }
        if pendingMode != nil, session.state == .inactive {
            finishModeSwitch()
        }
        return true
    }

    /// Releases the session and cancels an uncommitted selection during shutdown.
    func stop() {
        pendingMode = nil
        destroySession()
    }

    private func finishModeSwitch() {
        guard let nextMode = pendingMode else { return }
        destroySession()
        pendingMode = nil
        guard mode != nextMode else { return }
        mode = nextMode
        onModeChange(nextMode)
    }

    private func destroySession() {
        session?.destroySession()
        session = nil
    }
}
