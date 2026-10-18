import AppKit

/// Quits once ⌘Q has been held for two seconds.
///
/// Key-up delivery is not required: the hold is judged from the physical key
/// state, polled while the prompt is on screen.
/// Eligible ⌘Q events are consumed while monitoring, so the chord
/// never reaches the focused window, and quitting begins once the two-second
/// threshold is observed rather than waiting for the key to come back up. The key it
/// was holding is handed to `quit`, because it is still down at that point and
/// the caller must retain the receiving window while this local monitor consumes
/// its remaining events. It cannot consume events delivered to another process.
@MainActor
final class HoldToQuitController {
    static let holdDuration: TimeInterval = 2
    private static let keyStateCheckInterval: TimeInterval = 0.05
    private static let commandKeyCodes: [UInt16] = [54, 55]

    private(set) var isHolding = false
    private var heldKeyCode: UInt16?
    private var drainingKeyCode: UInt16?
    private var startedAt: TimeInterval?
    private var timer: Timer?
    private var monitor: Any?
    private var deactivateObserver: NSObjectProtocol?
    private var resignKeyObserver: NSObjectProtocol?
    private let isEligible: @MainActor () -> Bool
    private let now: @MainActor () -> TimeInterval
    private let isKeyPressed: @MainActor (UInt16) -> Bool
    private let showPrompt: @MainActor () -> Void
    private let updateProgress: @MainActor (Double) -> Void
    private let hidePrompt: @MainActor () -> Void
    /// Receives the key code that was held, which is still physically down.
    private let quit: @MainActor (UInt16) -> Void

    init(
        isEligible: @escaping @MainActor () -> Bool,
        now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        isKeyPressed: @escaping @MainActor (UInt16) -> Bool = {
            CGEventSource.keyState(.combinedSessionState, key: $0)
        },
        showPrompt: @escaping @MainActor () -> Void,
        updateProgress: @escaping @MainActor (Double) -> Void = { _ in },
        hidePrompt: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor (UInt16) -> Void
    ) {
        self.isEligible = isEligible
        self.now = now
        self.isKeyPressed = isKeyPressed
        self.showPrompt = showPrompt
        self.updateProgress = updateProgress
        self.hidePrompt = hidePrompt
        self.quit = quit
    }

    isolated deinit {
        timer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver) }
        if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
    }

    static func canHandleShortcut(in application: NSApplication) -> Bool {
        AppShortcutFocus.ownsCommandShortcuts(in: application)
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.process(event) ?? false }
            return consumed ? nil : event
        }
        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApplication.shared, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isHolding, !self.isEligible() else { return }
                self.cancel()
            }
        }
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    func stop() {
        cancel()
        endDraining()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver) }
        deactivateObserver = nil
        if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
        resignKeyObserver = nil
    }

    /// Consumes the whole ⌘Q chord, repeats included, so it cannot reach the
    /// focused window while the hold is being measured.
    @discardableResult
    func process(_ event: NSEvent) -> Bool {
        if let drainingKeyCode {
            return (event.type == .keyDown || event.type == .keyUp) && event.keyCode == drainingKeyCode
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let isQuitKeyDown = event.type == .keyDown && modifiers == .command
            && event.charactersIgnoringModifiers?.lowercased() == "q"
        guard isHolding || isQuitKeyDown else { return false }
        guard isEligible() else {
            cancel()
            return false
        }
        switch event.type {
        case .keyDown:
            guard isQuitKeyDown else {
                cancel()
                return false
            }
            if !event.isARepeat {
                cancel()
                isHolding = true
                heldKeyCode = event.keyCode
                startedAt = now()
                showPrompt()
                updateProgress(0)
                let timer = Timer(timeInterval: Self.keyStateCheckInterval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.checkHoldCompletion() }
                }
                self.timer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
            return true
        case .keyUp:
            guard event.keyCode == heldKeyCode else { return false }
            cancel()
            return true
        case .flagsChanged:
            if modifiers != .command { cancel() }
        default:
            cancel()
        }
        return false
    }

    /// Quits as soon as the two seconds are up; letting go early cancels.
    func checkHoldCompletion() {
        guard isHolding, let startedAt, let heldKeyCode else { return }
        guard isEligible() else {
            cancel()
            return
        }
        guard isKeyPressed(heldKeyCode),
              Self.commandKeyCodes.contains(where: { isKeyPressed($0) }) else {
            cancel()
            return
        }
        let elapsed = now() - startedAt
        guard elapsed >= Self.holdDuration else {
            updateProgress(elapsed / Self.holdDuration)
            return
        }
        let completedKeyCode = heldKeyCode
        beginDraining(keyCode: completedKeyCode)
        quit(completedKeyCode)
    }

    /// Consumes this key's remaining events without starting another hold.
    /// The caller ends draining after physical release or a canceled termination.
    func beginDraining(keyCode: UInt16) {
        cancel()
        drainingKeyCode = keyCode
    }

    func endDraining() {
        drainingKeyCode = nil
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        heldKeyCode = nil
        startedAt = nil
        guard isHolding else { return }
        isHolding = false
        hidePrompt()
    }
}
