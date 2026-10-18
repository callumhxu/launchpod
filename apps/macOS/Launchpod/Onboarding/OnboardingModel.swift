import Foundation
import Observation

@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome, organize, folders, glass, access
    }

    static let completionKey = "hasCompletedOnboarding"
    private(set) var step: Step = .welcome
    private(set) var hasCompleted: Bool
    private(set) var isPresented = false
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        hasCompleted = defaults.bool(forKey: Self.completionKey)
    }

    func begin(at step: Step = .welcome) {
        self.step = step
        isPresented = true
    }

    func next() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Finishing or skipping the optional introduction prevents automatic presentation next launch.
    func finish() {
        hasCompleted = true
        isPresented = false
        defaults.set(true, forKey: Self.completionKey)
    }
}
