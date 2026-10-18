import AppKit
import Carbon
import Observation

/// Owns one global registration and delivers one action per press and release cycle.
@MainActor
@Observable
final class GlobalShortcut {
    typealias Register = @MainActor (
        ShortcutPreference.Binding,
        @escaping @MainActor (Bool) -> Void
    ) throws -> @MainActor () -> Void

    private(set) var binding: ShortcutPreference.Binding?
    private(set) var registrationError: OSStatus?

    private let register: Register
    private let action: @MainActor () -> Void
    @ObservationIgnored private var cancelRegistration: (@MainActor () -> Void)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var isPressed = false

    isolated deinit {
        cancelRegistration?()
    }

    init(register: Register? = nil, action: @escaping @MainActor () -> Void) {
        self.register = register ?? { binding, receive in
            let registration = try NativeShortcutRegistration(binding: binding, receive: receive)
            return { registration.stop() }
        }
        self.action = action
    }

    func update(binding: ShortcutPreference.Binding?) {
        guard self.binding != binding || registrationError != nil else { return }
        stop()
        self.binding = binding
        guard let binding else { return }
        let currentGeneration = generation
        do {
            cancelRegistration = try register(binding) { [weak self] pressed in
                guard let self, self.generation == currentGeneration else { return }
                if pressed {
                    guard !self.isPressed else { return }
                    self.isPressed = true
                    self.action()
                } else {
                    self.isPressed = false
                }
            }
        } catch {
            registrationError = OSStatus((error as NSError).code)
        }
    }

    func stop() {
        generation = UUID()
        cancelRegistration?()
        cancelRegistration = nil
        isPressed = false
        binding = nil
        registrationError = nil
    }
}

@MainActor
private final class NativeShortcutRegistration {
    private static var nextIdentifier: UInt32 = 0
    private nonisolated let eventIdentifier: UInt32
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let receive: @MainActor (Bool) -> Void
    private var isActive = false

    isolated deinit {
        stop()
    }

    init(binding: ShortcutPreference.Binding, receive: @escaping @MainActor (Bool) -> Void) throws {
        Self.nextIdentifier &+= 1
        eventIdentifier = Self.nextIdentifier
        self.receive = receive
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let installation = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                              EventParamType(typeEventHotKeyID), nil,
                                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr else { return status }
                let registration = Unmanaged<NativeShortcutRegistration>.fromOpaque(context).takeUnretainedValue()
                guard identifier.signature == 0x4C504F44,
                      identifier.id == registration.eventIdentifier else { return OSStatus(eventNotHandledErr) }
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                DispatchQueue.main.async { [weak registration] in
                    guard let registration, registration.isActive else { return }
                    registration.receive(pressed)
                }
                return noErr
            },
            events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard installation == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(installation)) }
        var modifiers: UInt32 = 0
        if binding.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if binding.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if binding.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if binding.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let identifier = EventHotKeyID(signature: 0x4C504F44, id: eventIdentifier)
        let status = RegisterEventHotKey(UInt32(binding.keyCode), modifiers, identifier,
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        guard status == noErr else {
            stop()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        isActive = true
    }

    func stop() {
        isActive = false
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
