import Foundation
import Testing
@testable import Launchpod

@MainActor
struct OnboardingModelTests {
    @Test
    func firstInstallStartsAtWelcomeAndNavigationIncludesTheFeatureShowcaseAndStaysWithinBounds() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let model = OnboardingModel(defaults: defaults)

        #expect(OnboardingModel.Step.allCases == [.welcome, .organize, .folders, .glass, .access])
        #expect(!model.hasCompleted)
        #expect(!model.isPresented)
        #expect(model.step == .welcome)
        model.begin()
        #expect(model.isPresented)
        model.back()
        #expect(model.step == .welcome)
        for expected in [OnboardingModel.Step.organize, .folders, .glass, .access, .access] {
            model.next()
            #expect(model.step == expected)
            #expect(!model.hasCompleted)
        }
        for expected in [OnboardingModel.Step.glass, .folders, .organize, .welcome, .welcome] {
            model.back()
            #expect(model.step == expected)
        }
        #expect(!OnboardingModel(defaults: defaults).hasCompleted)
    }

    @Test(arguments: OnboardingModel.Step.allCases)
    func finishingOrSkippingAnyStepPersistsCompletion(step: OnboardingModel.Step) throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let model = OnboardingModel(defaults: defaults)
        model.begin(at: step)

        model.finish()
        #expect(model.hasCompleted)
        #expect(!model.isPresented)
        #expect(OnboardingModel(defaults: defaults).hasCompleted)
        model.finish()
        #expect(OnboardingModel(defaults: defaults).hasCompleted)
    }

    @Test
    func replayStartsAtWelcomeAndKeepsTheFirstInstallCompletion() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let model = OnboardingModel(defaults: defaults)
        model.begin(at: .access)
        model.finish()

        model.begin()
        #expect(model.step == .welcome)
        #expect(model.isPresented)
        #expect(model.hasCompleted)
        model.next()
        model.back()
        #expect(OnboardingModel(defaults: defaults).hasCompleted)
        model.begin(at: .access)
        #expect(model.step == .access)
        #expect(model.hasCompleted)
        #expect(OnboardingModel(defaults: defaults).hasCompleted)
    }
}
