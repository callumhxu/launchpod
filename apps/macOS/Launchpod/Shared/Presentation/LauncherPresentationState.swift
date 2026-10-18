import Foundation

@MainActor
final class LauncherPresentationState {
    enum Phase: Equatable, Sendable {
        case inactive
        case preparing
        case visible
        case dismissing
    }

    struct Transition: Equatable, Sendable {
        fileprivate let id = UUID()
        let targetIsVisible: Bool
    }

    private(set) var phase = Phase.inactive
    /// Identifies the latest visibility request or reset, independently of completion.
    private(set) var visibilityRequestRevision = UUID()
    private var pendingTransition: Transition?

    var targetIsVisible: Bool {
        phase == .preparing || phase == .visible
    }

    func requestVisibility(_ visible: Bool) -> Transition? {
        guard visible != targetIsVisible else { return nil }
        return beginTransition(to: visible)
    }

    func toggle() -> Transition {
        beginTransition(to: !targetIsVisible)
    }

    @discardableResult
    func complete(_ transition: Transition) -> Bool {
        guard pendingTransition == transition else { return false }
        pendingTransition = nil
        phase = transition.targetIsVisible ? .visible : .inactive
        return true
    }

    func reset() {
        pendingTransition = nil
        visibilityRequestRevision = UUID()
        phase = .inactive
    }

    private func beginTransition(to visible: Bool) -> Transition {
        let transition = Transition(targetIsVisible: visible)
        visibilityRequestRevision = transition.id
        pendingTransition = transition
        phase = visible ? .preparing : .dismissing
        return transition
    }
}
