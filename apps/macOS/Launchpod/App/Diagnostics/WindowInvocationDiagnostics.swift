#if DEBUG
import AppKit
import OSLog

/// Records invocation and focus evidence without changing window or application state.
@MainActor
final class WindowInvocationDiagnostics {
    enum Source: String, Sendable {
        case startup, dockReopen, statusButton, menuToggle, menuSettings
        case commandComma, globalHotkey, directLauncher, directSettings
    }

    struct Request: Equatable, Sendable {
        let id: UInt64
        let source: Source
    }

    struct Scope {
        let request: Request
        fileprivate let previous: Request?
        fileprivate let ownsRequest: Bool
    }

    struct ApplicationSnapshot {
        let isActive: Bool
        let isHidden: Bool
        let activationPolicy: Int
        let keyWindowNumber: Int?
        let mainWindowNumber: Int?
        let frontmostProcessID: Int32?
    }

    struct OrderingSnapshot {
        /// Zero-based position in the active Space; nil means absent or unavailable.
        let targetIndex: Int?
        let frontWindowNumbers: [Int]?
        /// Hit testing ignores transparent areas and windows that ignore mouse events.
        let windowAtCenter: Int
    }

    struct WindowSnapshot {
        let number: Int
        let role: String
        let isVisible: Bool
        let isKey: Bool
        let isMain: Bool
        let isMiniaturized: Bool
        let isOnActiveSpace: Bool
        let occlusionState: UInt
        let alpha: Double
        let level: Int
        let styleMask: UInt
        let collectionBehavior: UInt
        let frame: NSRect
        let screenFrame: NSRect?
        let firstResponderType: String?
        let ordering: OrderingSnapshot?
    }

    struct Entry {
        let runID: UUID
        let processID: Int32
        let uptime: TimeInterval
        let request: Request?
        let windowPresentationRequest: Request?
        let event: String
        let detail: String
        let application: ApplicationSnapshot
        let window: WindowSnapshot?
    }

    typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void
    static let shared = WindowInvocationDiagnostics()
    // Finite diagnostic checkpoints, not presentation timing or a polling interval.
    static let sampleDelays: [TimeInterval] = [0, 0.05, 0.25]
    var sink: (@MainActor (Entry) -> Void)?
    private(set) var currentRequest: Request?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Launchpod", category: "WindowInvocation")
    private let runID = UUID()
    private let schedule: Scheduler
    private var nextRequestID: UInt64 = 0
    private var nextSampleID: UInt64 = 0
    private var samples: [ObjectIdentifier: UInt64] = [:]
    private var observations: [ObjectIdentifier: Observation] = [:]
    private var applicationObservers: [NSObjectProtocol] = []

    private struct Observation {
        weak var window: NSWindow?
        var request: Request?
        let tokens: [NSObjectProtocol]
    }

    init(
        sink: (@MainActor (Entry) -> Void)? = nil,
        schedule: @escaping Scheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
        }
    ) {
        self.sink = sink
        self.schedule = schedule
    }

    isolated deinit {
        for observation in observations.values {
            for token in observation.tokens { NotificationCenter.default.removeObserver(token) }
        }
        for token in applicationObservers { NotificationCenter.default.removeObserver(token) }
    }

    func begin(_ source: Source) -> Scope {
        nextRequestID += 1
        let request = Request(id: nextRequestID, source: source)
        let scope = Scope(request: request, previous: currentRequest, ownsRequest: true)
        currentRequest = request
        record("invocation.begin", request: request)
        return scope
    }

    /// Keeps an originating callback's request while allowing direct method invocations.
    func ensureRequest(_ source: Source) -> Scope {
        guard let currentRequest else { return begin(source) }
        return Scope(request: currentRequest, previous: currentRequest, ownsRequest: false)
    }

    func end(_ scope: Scope) {
        guard scope.ownsRequest else { return }
        record("invocation.return", request: scope.request)
        currentRequest = scope.previous
    }

    func request(for window: NSWindow?) -> Request? {
        currentRequest ?? presentationRequest(for: window)
    }

    func presentationRequest(for window: NSWindow?) -> Request? {
        guard let window else { return nil }
        return observations[ObjectIdentifier(window)]?.request
    }

    func record(
        _ event: String, window: NSWindow? = nil, request: Request? = nil,
        detail: String = "", includeOrdering: Bool = false
    ) {
        let app = NSApplication.shared
        let entry = Entry(
            runID: runID, processID: ProcessInfo.processInfo.processIdentifier,
            uptime: ProcessInfo.processInfo.systemUptime,
            request: request ?? self.request(for: window), windowPresentationRequest: presentationRequest(for: window),
            event: event, detail: detail,
            application: ApplicationSnapshot(
                isActive: app.isActive, isHidden: app.isHidden, activationPolicy: app.activationPolicy().rawValue,
                keyWindowNumber: app.keyWindow?.windowNumber, mainWindowNumber: app.mainWindow?.windowNumber,
                frontmostProcessID: NSWorkspace.shared.frontmostApplication?.processIdentifier
            ),
            window: window.map { snapshot($0, includeOrdering: includeOrdering) }
        )
        let windowFields = logFields(for: entry.window)
        logger.notice("""
        run=\(entry.runID.uuidString, privacy: .public) pid=\(entry.processID) t=\(entry.uptime) \
        request=\(entry.request?.id ?? 0) source=\(entry.request?.source.rawValue ?? "none", privacy: .public) \
        windowRequest=\(entry.windowPresentationRequest?.id ?? 0) windowSource=\(entry.windowPresentationRequest?.source.rawValue ?? "none", privacy: .public) \
        event=\(entry.event, privacy: .public) detail=\(entry.detail, privacy: .public) \
        appActive=\(entry.application.isActive) appHidden=\(entry.application.isHidden) policy=\(entry.application.activationPolicy) \
        appKey=\(entry.application.keyWindowNumber ?? -1) appMain=\(entry.application.mainWindowNumber ?? -1) \
        frontPID=\(entry.application.frontmostProcessID ?? -1) \(windowFields, privacy: .public)
        """)
        sink?(entry)
    }

    func observe(window: NSWindow, request: Request? = nil) {
        let identity = ObjectIdentifier(window)
        if observations[identity] != nil {
            observations[identity]?.request = request ?? currentRequest
            return
        }
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
            NSWindow.didChangeOcclusionStateNotification, NSWindow.didChangeScreenNotification,
            NSWindow.willCloseNotification
        ]
        let tokens = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    self.record("window.notification", window: window, detail: name.rawValue)
                }
            }
        }
        observations[identity] = Observation(window: window, request: request ?? currentRequest, tokens: tokens)
        startObservingApplicationIfNeeded()
    }

    func stopObserving(window: NSWindow) {
        cancelSampling(for: window)
        if let observation = observations.removeValue(forKey: ObjectIdentifier(window)) {
            for token in observation.tokens { NotificationCenter.default.removeObserver(token) }
        }
        if observations.isEmpty {
            for token in applicationObservers { NotificationCenter.default.removeObserver(token) }
            applicationObservers.removeAll()
        }
    }

    /// Replaces earlier pending samples for this window, without retaining it.
    func sampleAfterEventLoop(window: NSWindow, request: Request? = nil) {
        nextSampleID += 1
        let generation = nextSampleID
        let identity = ObjectIdentifier(window)
        let request = request ?? self.request(for: window)
        samples[identity] = generation
        for (index, delay) in Self.sampleDelays.enumerated() {
            schedule(delay) { [weak self, weak window] in
                guard let self, self.samples[identity] == generation else { return }
                guard let window else {
                    self.samples.removeValue(forKey: identity)
                    return
                }
                self.record("window.deferred", window: window, request: request,
                            detail: "checkpoint=\(index) scheduledDelay=\(delay)", includeOrdering: true)
                if index == Self.sampleDelays.count - 1 { self.samples.removeValue(forKey: identity) }
            }
        }
    }

    func cancelSampling(for window: NSWindow) {
        samples.removeValue(forKey: ObjectIdentifier(window))
    }

    private func startObservingApplicationIfNeeded() {
        guard applicationObservers.isEmpty else { return }
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            NSApplication.didHideNotification, NSApplication.didUnhideNotification
        ]
        applicationObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: NSApplication.shared, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for observation in self.observations.values {
                        guard let window = observation.window else { continue }
                        self.record("application.notification", window: window, detail: name.rawValue)
                    }
                }
            }
        }
    }

    private func snapshot(_ window: NSWindow, includeOrdering: Bool) -> WindowSnapshot {
        let role: String
        switch window.identifier {
        case AppShortcutFocus.launcherWindowIdentifier: role = "launcher"
        case AppShortcutFocus.settingsWindowIdentifier: role = "settings"
        default: role = "other"
        }
        return WindowSnapshot(
            number: window.windowNumber, role: role, isVisible: window.isVisible,
            isKey: window.isKeyWindow, isMain: window.isMainWindow, isMiniaturized: window.isMiniaturized,
            isOnActiveSpace: window.isOnActiveSpace, occlusionState: window.occlusionState.rawValue,
            alpha: Double(window.alphaValue), level: window.level.rawValue,
            styleMask: window.styleMask.rawValue, collectionBehavior: window.collectionBehavior.rawValue,
            frame: window.frame, screenFrame: window.screen?.frame,
            firstResponderType: window.firstResponder.map { String(reflecting: type(of: $0)) },
            ordering: includeOrdering ? orderingSnapshot(window) : nil
        )
    }

    private func logFields(for window: WindowSnapshot?) -> String {
        guard let window else { return "window=none" }
        var fields = "window=\(window.number) role=\(window.role) visible=\(window.isVisible) key=\(window.isKey) main=\(window.isMain)"
        fields += " mini=\(window.isMiniaturized) activeSpace=\(window.isOnActiveSpace) occlusion=\(window.occlusionState) alpha=\(window.alpha)"
        fields += " level=\(window.level) style=\(window.styleMask) collection=\(window.collectionBehavior) frame=\(NSStringFromRect(window.frame))"
        fields += " screen=\(window.screenFrame.map { NSStringFromRect($0) } ?? "none") responderType=\(window.firstResponderType ?? "none")"
        if let ordering = window.ordering {
            fields += " targetRank=\(ordering.targetIndex.map(String.init) ?? "absent-or-unavailable")"
            fields += " frontWindows=\(ordering.frontWindowNumbers.map { $0.map(String.init).joined(separator: ",") } ?? "unavailable")"
            fields += " centerHitWindow=\(ordering.windowAtCenter)"
        }
        return fields
    }

    private func orderingSnapshot(_ window: NSWindow) -> OrderingSnapshot {
        let numbers = NSWindow.windowNumbers(options: .allApplications)?.map(\.intValue)
        return OrderingSnapshot(
            targetIndex: numbers?.firstIndex(of: window.windowNumber),
            frontWindowNumbers: numbers.map { Array($0.prefix(8)) },
            windowAtCenter: NSWindow.windowNumber(
                at: NSPoint(x: window.frame.midX, y: window.frame.midY), belowWindowWithWindowNumber: 0
            )
        )
    }
}
#endif
