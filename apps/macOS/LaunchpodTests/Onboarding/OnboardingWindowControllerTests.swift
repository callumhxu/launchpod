import AppKit
import Testing
@testable import Launchpod

@MainActor
struct OnboardingWindowControllerTests {
    @Test
    func nativeCloseFinishesTheOptionalIntroductionThroughItsOwner() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let model = OnboardingModel(defaults: defaults)
        model.begin()
        var completions = 0
        let controller = OnboardingWindowController(
            model: model, languagePreference: AppLanguagePreference(defaults: defaults),
            onFinish: {
                completions += 1
                model.finish()
            },
            openSettings: { Issue.record("Closing the introduction must not open Settings.") }
        )
        defer { controller.stop() }
        let window = try #require(controller.window)
        #expect(!window.isVisible)
        #expect(window.identifier == AppShortcutFocus.onboardingWindowIdentifier)

        #expect(!controller.windowShouldClose(window))
        #expect(completions == 1)
        #expect(!model.isPresented)
        #expect(OnboardingModel(defaults: defaults).hasCompleted)
        #expect(!window.isVisible)
    }

    @Test
    func stoppingTheControllerDoesNotCompleteAnUnfinishedIntroduction() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let model = OnboardingModel(defaults: defaults)
        model.begin()
        let controller = OnboardingWindowController(
            model: model, languagePreference: AppLanguagePreference(defaults: defaults),
            onFinish: { Issue.record("Stopping the window must not mark onboarding complete.") },
            openSettings: {}
        )
        let window = try #require(controller.window)
        #expect(!window.isVisible)

        controller.stop()
        controller.stop()
        #expect(controller.window == nil)
        #expect(window.delegate == nil)
        #expect(!window.isVisible)
        #expect(!model.hasCompleted)
        #expect(!OnboardingModel(defaults: defaults).hasCompleted)
    }
}
