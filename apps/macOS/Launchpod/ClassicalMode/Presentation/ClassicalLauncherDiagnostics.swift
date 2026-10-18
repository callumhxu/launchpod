import AppKit

/// The Classical launcher window's invocation and focus records for `WindowInvocationDiagnostics`.
/// Debug builds only; every call does nothing in release builds.
@MainActor
enum ClassicalLauncherDiagnostics {
    /// Starts recording a visibility request; call the returned function when it has been handled.
    static func beginVisibilityRequest(_ visible: Bool, window: NSWindow?) -> @MainActor () -> Void {
        #if DEBUG
        let diagnostics = WindowInvocationDiagnostics.shared
        let scope = diagnostics.ensureRequest(.directLauncher)
        if let window { diagnostics.observe(window: window, request: scope.request) }
        diagnostics.record("launcher.setVisible", window: window, detail: "targetVisible=\(visible)")
        return { diagnostics.end(scope) }
        #else
        return {}
        #endif
    }

    /// The window was ordered front and made key for a new presentation.
    static func didMakeKey(_ window: NSWindow) {
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.afterMakeKey", window: window, includeOrdering: true)
        WindowInvocationDiagnostics.shared.sampleAfterEventLoop(window: window)
        #endif
    }

    static func didAcquireFocus(_ window: NSWindow) {
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.focusAcquired", window: window)
        #endif
    }

    static func didOrderOut(_ window: NSWindow?) {
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.afterOrderOut", window: window, includeOrdering: true)
        #endif
    }

    static func didStop(_ window: NSWindow?) {
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.stop", window: window)
        stopObserving(window)
        #endif
    }

    static func stopObserving(_ window: NSWindow?) {
        #if DEBUG
        if let window { WindowInvocationDiagnostics.shared.stopObserving(window: window) }
        #endif
    }
}
