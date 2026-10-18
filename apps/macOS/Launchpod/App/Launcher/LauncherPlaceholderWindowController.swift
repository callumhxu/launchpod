import AppKit
import SwiftUI

@MainActor
protocol LauncherPlaceholderPresenting: AnyObject {
    var isVisible: Bool { get }
    var onDismiss: (@MainActor () -> Void)? { get set }
    var retainsFocusForOwnedInteraction: (@MainActor () -> Bool)? { get set }
    /// Completes showing only after keyboard focus is acquired, and hiding after ordering out.
    /// A superseded or stopped presentation reports false.
    func setVisible(_ visible: Bool, completion: @escaping @MainActor (Bool) -> Void)
    func stop()
}

@MainActor
final class LauncherPlaceholderWindowController: NSWindowController, NSWindowDelegate, LauncherPlaceholderPresenting {
    var onDismiss: (@MainActor () -> Void)?
    var retainsFocusForOwnedInteraction: (@MainActor () -> Bool)?
    private static let contentSize = NSSize(width: 480, height: 320)
    private var showCompletion: (@MainActor (Bool) -> Void)?
    private var isChangingVisibility = false

    var isVisible: Bool { window?.isVisible == true }

    init(languagePreference: AppLanguagePreference) {
        let window = PlaceholderPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.title = "Launchpod"
        window.identifier = AppShortcutFocus.launcherWindowIdentifier
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.contentView = PlaceholderHostingView(rootView: PlaceholderContent(languagePreference: languagePreference))
        window.initialFirstResponder = window.contentView
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    isolated deinit {
        #if DEBUG
        if let window { WindowInvocationDiagnostics.shared.stopObserving(window: window) }
        #endif
        window?.delegate = nil
        window?.close()
    }

    func setVisible(_ visible: Bool, completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        #if DEBUG
        let scope = WindowInvocationDiagnostics.shared.ensureRequest(.directLauncher)
        defer { WindowInvocationDiagnostics.shared.end(scope) }
        if showCompletion != nil {
            WindowInvocationDiagnostics.shared.record("launcher.superseded", window: window,
                                                      request: WindowInvocationDiagnostics.shared.presentationRequest(for: window),
                                                      detail: "completed=false")
        }
        #endif
        let superseded = showCompletion
        showCompletion = nil
        superseded?(false)
        guard let window else {
            #if DEBUG
            WindowInvocationDiagnostics.shared.record("launcher.missingWindow", detail: "completed=false")
            #endif
            completion(false)
            return
        }
        #if DEBUG
        let diagnostics = WindowInvocationDiagnostics.shared
        diagnostics.observe(window: window, request: scope.request)
        diagnostics.record("launcher.setVisible", window: window, detail: "targetVisible=\(visible)")
        defer { diagnostics.sampleAfterEventLoop(window: window, request: scope.request) }
        #endif
        isChangingVisibility = true
        defer { isChangingVisibility = false }
        if visible {
            showCompletion = completion
            #if DEBUG
            diagnostics.record("launcher.beforeOrderFront", window: window, includeOrdering: true)
            #endif
            window.orderFrontRegardless()
            #if DEBUG
            diagnostics.record("launcher.afterOrderFront.beforeMakeKey", window: window, includeOrdering: true)
            #endif
            window.makeKey()
            #if DEBUG
            diagnostics.record("launcher.afterMakeKey", window: window, includeOrdering: true)
            #endif
            finishShowingIfFocused()
        } else {
            #if DEBUG
            diagnostics.record("launcher.beforeOrderOut", window: window, includeOrdering: true)
            #endif
            window.orderOut(nil)
            #if DEBUG
            diagnostics.record("launcher.afterOrderOut", window: window, detail: "completed=\(!window.isVisible)", includeOrdering: true)
            #endif
            completion(!window.isVisible)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.didBecomeKey", window: window)
        #endif
        finishShowingIfFocused()
    }

    private func finishShowingIfFocused() {
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.checkFocus", window: window,
                                                  detail: "pending=\(showCompletion != nil) initialResponderPresent=\(window?.initialFirstResponder != nil)")
        #endif
        guard showCompletion != nil, let window, window.isVisible, window.isKeyWindow,
              let responder = window.initialFirstResponder,
              window.makeFirstResponder(responder), window.firstResponder === responder else {
            #if DEBUG
            WindowInvocationDiagnostics.shared.record("launcher.focusCheckIncomplete", window: window,
                                                      detail: "pending=\(showCompletion != nil)")
            #endif
            return
        }
        let completion = showCompletion
        showCompletion = nil
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.focusAcquired", window: window, detail: "completed=true")
        #endif
        completion?(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isChangingVisibility, isVisible, window?.isKeyWindow != true,
              retainsFocusForOwnedInteraction?() != true else {
            #if DEBUG
            let reason = isChangingVisibility ? "changingVisibility" : !isVisible ? "notVisible"
                : window?.isKeyWindow == true ? "stillKey" : "ownedInteraction"
            WindowInvocationDiagnostics.shared.record("launcher.resignKeyIgnored", window: window, detail: reason)
            #endif
            return
        }
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.dismissReason", window: window, detail: "resignedKey")
        #endif
        dismiss()
    }

    func windowWillClose(_ notification: Notification) {
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.willClose", window: window, detail: "changingVisibility=\(isChangingVisibility)")
        #endif
        guard !isChangingVisibility else { return }
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.dismissReason", window: window, detail: "close")
        #endif
        dismiss()
    }

    private func dismiss() {
        isChangingVisibility = true
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.dismiss.beforeOrderOut", window: window, includeOrdering: true)
        #endif
        window?.orderOut(nil)
        isChangingVisibility = false
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.dismiss.afterOrderOut", window: window, includeOrdering: true)
        if let window { WindowInvocationDiagnostics.shared.sampleAfterEventLoop(window: window) }
        #endif
        let completion = showCompletion
        showCompletion = nil
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.dismissCompletion", window: window,
                                                  detail: "pending=\(completion != nil) completed=false onDismiss=\(onDismiss != nil)")
        #endif
        completion?(false)
        onDismiss?()
    }

    func stop() {
        #if DEBUG
        WindowInvocationDiagnostics.shared.record("launcher.stop", window: window, detail: "pending=\(showCompletion != nil) completed=false")
        if let window { WindowInvocationDiagnostics.shared.stopObserving(window: window) }
        #endif
        onDismiss = nil
        retainsFocusForOwnedInteraction = nil
        let completion = showCompletion
        showCompletion = nil
        completion?(false)
        window?.delegate = nil
        window?.close()
        window = nil
    }

    private final class PlaceholderPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        override func cancelOperation(_ sender: Any?) {
            performClose(sender)
        }
    }

    private final class PlaceholderHostingView: NSHostingView<PlaceholderContent> {
        override var acceptsFirstResponder: Bool { true }
        override var needsPanelToBecomeKey: Bool { true }
    }

    private struct PlaceholderContent: View {
        let languagePreference: AppLanguagePreference

        var body: some View {
            VStack {
                Text(verbatim: "Launchpod")
                    .font(.title)
                Text("The launcher interface is not available yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("launcherPlaceholderMessage")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .environment(\.locale, languagePreference.locale)
        }
    }
}
