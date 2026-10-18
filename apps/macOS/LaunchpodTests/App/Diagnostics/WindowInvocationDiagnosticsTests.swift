#if DEBUG
import AppKit
import Testing
@testable import Launchpod

@MainActor
struct WindowInvocationDiagnosticsTests {
    @Test
    func originatingRequestsSurviveNestedCallsAndSeparateInvocationsHaveDistinctIDs() throws {
        var entries: [WindowInvocationDiagnostics.Entry] = []
        let diagnostics = WindowInvocationDiagnostics(sink: { entries.append($0) })
        let origin = diagnostics.begin(.statusButton)
        let delegated = diagnostics.ensureRequest(.directLauncher)
        diagnostics.record("launcher.request")
        diagnostics.end(delegated)
        #expect(diagnostics.currentRequest == origin.request)

        let nested = diagnostics.begin(.menuSettings)
        diagnostics.record("settings.request")
        diagnostics.end(nested)
        diagnostics.record("launcher.return")
        diagnostics.end(origin)
        #expect(diagnostics.currentRequest == nil)
        let next = diagnostics.ensureRequest(.directLauncher)
        diagnostics.end(next)

        #expect(entries.filter { $0.event == "invocation.begin" }.map(\.request?.source)
                == [.statusButton, .menuSettings, .directLauncher])
        #expect(entries.first { $0.event == "launcher.request" }?.request == origin.request)
        #expect(entries.first { $0.event == "launcher.return" }?.request == origin.request)
        #expect(entries.first { $0.event == "settings.request" }?.request == nested.request)
        #expect(Set([origin.request.id, nested.request.id, next.request.id]).count == 3)
        #expect(Set(entries.map(\.runID)).count == 1)
        #expect(entries.allSatisfy { $0.processID == ProcessInfo.processInfo.processIdentifier })
        #expect(entries.map(\.uptime) == entries.map(\.uptime).sorted())
    }

    @Test
    func snapshotsReadNativeStateWithoutChangingFocusOrIncludingWindowText() throws {
        let window = makeWindow()
        defer { window.close() }
        window.title = "private-document-title-8731"
        window.identifier = NSUserInterfaceItemIdentifier("private-window-identifier-8731")
        let field = NSTextField(string: "private-field-content-8731")
        window.contentView = field
        window.initialFirstResponder = field
        window.alphaValue = 0.63
        let application = NSApplication.shared
        let keyWindow = application.keyWindow
        let mainWindow = application.mainWindow
        let isActive = application.isActive
        let visible = window.isVisible
        let isKey = window.isKeyWindow
        let responder = window.firstResponder
        let level = window.level
        let frame = window.frame
        var entries: [WindowInvocationDiagnostics.Entry] = []
        let diagnostics = WindowInvocationDiagnostics(sink: { entries.append($0) })

        diagnostics.record("window.snapshot", window: window, includeOrdering: true)
        let entry = try #require(entries.last)
        let snapshot = try #require(entry.window)
        #expect(snapshot.number == window.windowNumber)
        #expect(snapshot.role == "other")
        #expect(snapshot.isVisible == visible)
        #expect(snapshot.isKey == isKey)
        #expect(snapshot.alpha == 0.63)
        #expect(snapshot.level == level.rawValue)
        #expect(snapshot.frame == frame)
        #expect(snapshot.ordering != nil)
        #expect(application.keyWindow === keyWindow)
        #expect(application.mainWindow === mainWindow)
        #expect(application.isActive == isActive)
        #expect(window.isVisible == visible)
        #expect(window.isKeyWindow == isKey)
        #expect(window.firstResponder === responder)
        #expect(window.level == level)
        #expect(window.frame == frame)
        let payload = String(reflecting: entry)
        #expect(!payload.contains(window.title))
        #expect(!payload.contains(try #require(window.identifier).rawValue))
        #expect(!payload.contains(field.stringValue))
    }

    @Test
    func deferredSamplesAreFiniteAndKeepTheOriginAfterTheInvocationReturns() throws {
        let window = makeWindow()
        defer { window.close() }
        var entries: [WindowInvocationDiagnostics.Entry] = []
        var callbacks: [@MainActor () -> Void] = []
        let diagnostics = WindowInvocationDiagnostics(
            sink: { entries.append($0) }, schedule: { _, action in callbacks.append(action) }
        )
        let scope = diagnostics.begin(.dockReopen)
        diagnostics.sampleAfterEventLoop(window: window, request: scope.request)
        diagnostics.end(scope)
        let later = diagnostics.begin(.directSettings)
        diagnostics.end(later)
        entries.removeAll()
        let scheduledCount = callbacks.count
        #expect(scheduledCount > 0)

        for callback in callbacks { callback() }
        #expect(entries.count == scheduledCount)
        #expect(entries.allSatisfy { $0.event == "window.deferred" && $0.request == scope.request })
        #expect(entries.allSatisfy { $0.window?.ordering != nil })
        #expect(callbacks.count == scheduledCount)
        for callback in callbacks { callback() }
        #expect(entries.count == scheduledCount)
        #expect(!window.isVisible)
        #expect(!window.isKeyWindow)
    }

    @Test
    func anotherWindowsInvocationExplainsFocusChangesButCannotRelabelDeferredSamples() throws {
        let launcher = makeWindow()
        let settings = makeWindow()
        defer { launcher.close(); settings.close() }
        var entries: [WindowInvocationDiagnostics.Entry] = []
        var callbacks: [@MainActor () -> Void] = []
        let diagnostics = WindowInvocationDiagnostics(
            sink: { entries.append($0) }, schedule: { _, action in callbacks.append(action) }
        )
        let original = diagnostics.begin(.statusButton)
        diagnostics.observe(window: launcher, request: original.request)
        diagnostics.sampleAfterEventLoop(window: launcher, request: original.request)
        diagnostics.end(original)
        let settingsInvocation = diagnostics.begin(.commandComma)
        diagnostics.observe(window: settings, request: settingsInvocation.request)
        entries.removeAll()

        diagnostics.record("launcher.focusChanged", window: launcher)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: launcher)
        let focusChange = try #require(entries.first { $0.event == "launcher.focusChanged" })
        let notification = try #require(entries.first { $0.event == "window.notification" })
        #expect(focusChange.request == settingsInvocation.request)
        #expect(notification.request == settingsInvocation.request)
        #expect(focusChange.windowPresentationRequest == original.request)
        #expect(notification.windowPresentationRequest == original.request)

        for callback in callbacks { callback() }
        let deferred = entries.filter { $0.event == "window.deferred" }
        #expect(!deferred.isEmpty)
        #expect(deferred.allSatisfy { $0.request == original.request })
        #expect(deferred.allSatisfy { $0.windowPresentationRequest == original.request })
        diagnostics.end(settingsInvocation)
        diagnostics.record("launcher.laterNotification", window: launcher)
        #expect(entries.last?.request == original.request)
        #expect(diagnostics.presentationRequest(for: launcher) == original.request)
        #expect(diagnostics.presentationRequest(for: settings) == settingsInvocation.request)
    }

    @Test
    func replacingOrCancellingSamplesDoesNotAffectAnotherWindowsPendingSamples() throws {
        let first = makeWindow()
        let second = makeWindow()
        defer { first.close(); second.close() }
        var entries: [WindowInvocationDiagnostics.Entry] = []
        var callbacks: [@MainActor () -> Void] = []
        let diagnostics = WindowInvocationDiagnostics(
            sink: { entries.append($0) }, schedule: { _, action in callbacks.append(action) }
        )
        let old = diagnostics.begin(.startup)
        diagnostics.sampleAfterEventLoop(window: first, request: old.request)
        diagnostics.end(old)
        let staleCallbacks = callbacks
        callbacks.removeAll()
        let replacement = diagnostics.begin(.globalHotkey)
        diagnostics.sampleAfterEventLoop(window: first, request: replacement.request)
        diagnostics.end(replacement)
        let replacementCallbacks = callbacks
        callbacks.removeAll()
        let sibling = diagnostics.begin(.menuSettings)
        diagnostics.sampleAfterEventLoop(window: second, request: sibling.request)
        diagnostics.end(sibling)
        let siblingCallbacks = callbacks
        callbacks.removeAll()
        entries.removeAll()

        for callback in staleCallbacks { callback() }
        #expect(entries.isEmpty)
        for callback in replacementCallbacks { callback() }
        #expect(entries.count == replacementCallbacks.count)
        #expect(entries.allSatisfy { $0.request == replacement.request })
        entries.removeAll()
        diagnostics.sampleAfterEventLoop(window: first, request: replacement.request)
        diagnostics.cancelSampling(for: first)
        for callback in callbacks { callback() }
        #expect(entries.isEmpty)
        for callback in siblingCallbacks { callback() }
        #expect(entries.count == siblingCallbacks.count)
        #expect(entries.allSatisfy { $0.request == sibling.request })
    }

    @Test
    func pendingSamplesDoNotRetainTheirWindowOrDiagnosticsOwner() {
        weak var baselineWindow: NSWindow?
        autoreleasepool {
            let window = makeWindow()
            baselineWindow = window
            window.close()
        }
        #expect(baselineWindow == nil)

        var entries: [WindowInvocationDiagnostics.Entry] = []
        var callbacks: [@MainActor () -> Void] = []
        var diagnostics: WindowInvocationDiagnostics? = WindowInvocationDiagnostics(
            sink: { entries.append($0) }, schedule: { _, action in callbacks.append(action) }
        )
        weak var releasedWindow: NSWindow?
        autoreleasepool {
            let window = makeWindow()
            releasedWindow = window
            diagnostics?.sampleAfterEventLoop(window: window)
            window.close()
        }
        #expect(releasedWindow == nil)
        for callback in callbacks { callback() }
        #expect(entries.isEmpty)

        let retainedWindow = makeWindow()
        defer { retainedWindow.close() }
        callbacks.removeAll()
        diagnostics?.sampleAfterEventLoop(window: retainedWindow)
        weak let releasedDiagnostics = diagnostics
        diagnostics = nil
        #expect(releasedDiagnostics == nil)
        for callback in callbacks { callback() }
        #expect(entries.isEmpty)
    }

    @Test
    func observingAgainUpdatesCorrelationWithoutDuplicatingAndStoppingCancelsAllWindowWork() throws {
        let window = makeWindow()
        defer { window.close() }
        var entries: [WindowInvocationDiagnostics.Entry] = []
        var callbacks: [@MainActor () -> Void] = []
        let diagnostics = WindowInvocationDiagnostics(
            sink: { entries.append($0) }, schedule: { _, action in callbacks.append(action) }
        )
        let first = diagnostics.begin(.startup)
        diagnostics.observe(window: window, request: first.request)
        diagnostics.end(first)
        let next = diagnostics.begin(.statusButton)
        diagnostics.observe(window: window, request: next.request)
        diagnostics.sampleAfterEventLoop(window: window, request: next.request)
        diagnostics.end(next)
        entries.removeAll()

        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
        #expect(entries.count == 1)
        #expect(entries.first?.event == "window.notification")
        #expect(entries.first?.request == next.request)
        diagnostics.stopObserving(window: window)
        diagnostics.stopObserving(window: window)
        entries.removeAll()
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
        NotificationCenter.default.post(name: NSApplication.didUnhideNotification, object: NSApplication.shared)
        for callback in callbacks { callback() }
        #expect(entries.isEmpty)
    }

    @Test
    func notificationObserversDoNotKeepTheDiagnosticsOwnerAlive() {
        let window = makeWindow()
        defer { window.close() }
        var entries: [WindowInvocationDiagnostics.Entry] = []
        var diagnostics: WindowInvocationDiagnostics? = WindowInvocationDiagnostics(sink: { entries.append($0) })
        diagnostics?.observe(window: window)
        weak let released = diagnostics
        diagnostics = nil
        #expect(released == nil)
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
        NotificationCenter.default.post(name: NSApplication.didUnhideNotification, object: NSApplication.shared)
        #expect(entries.isEmpty)
    }

    private func makeWindow() -> NSWindow {
        let window = NSPanel(contentRect: NSRect(x: 40, y: 60, width: 160, height: 120),
                             styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        return window
    }
}
#endif
