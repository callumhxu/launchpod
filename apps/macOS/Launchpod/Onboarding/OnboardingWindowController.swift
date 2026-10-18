import AppKit
import Observation
import SwiftUI

/// Owns the optional introduction window independently of either launcher mode.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let languagePreference: AppLanguagePreference
    private let onFinish: @MainActor () -> Void

    init(model: OnboardingModel, languagePreference: AppLanguagePreference,
         onFinish: @escaping @MainActor () -> Void,
         openSettings: @escaping @MainActor () -> Void) {
        self.languagePreference = languagePreference
        self.onFinish = onFinish
        let panel = IntroductionPanel(
            contentRect: NSRect(origin: .zero, size: OnboardingParameters.windowSize),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.identifier = AppShortcutFocus.onboardingWindowIdentifier
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentMinSize = OnboardingParameters.minimumWindowSize
        panel.contentView = IntroductionHostingView(rootView: IntroductionContent(
            model: model, languagePreference: languagePreference,
            finish: onFinish, openSettings: openSettings
        ))
        panel.center()
        super.init(window: panel)
        panel.delegate = self
        observeLanguage()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        languagePreference.refreshSystemLanguages()
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onFinish()
        return false
    }

    func stop() {
        window?.delegate = nil
        window?.close()
        window = nil
    }

    private func observeLanguage() {
        withObservationTracking {
            window?.title = String(localized: LocalizedStringResource(
                "Welcome to Launchpod", locale: languagePreference.locale
            ))
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeLanguage() }
        }
    }

    private final class IntroductionPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private final class IntroductionHostingView: NSHostingView<IntroductionContent> {
        override var acceptsFirstResponder: Bool { true }
        override var needsPanelToBecomeKey: Bool { true }
    }

    private struct IntroductionContent: View {
        let model: OnboardingModel
        let languagePreference: AppLanguagePreference
        let finish: @MainActor () -> Void
        let openSettings: @MainActor () -> Void

        var body: some View {
            OnboardingView(model: model, finish: finish, openSettings: openSettings)
                .environment(\.locale, languagePreference.locale)
        }
    }
}
