import AppKit
import SwiftUI

struct OnboardingView: View {
    let model: OnboardingModel
    let finish: () -> Void
    let openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Launchpod").font(.headline)
                Spacer()
                Text("Step \(stepNumber) of \(OnboardingModel.Step.allCases.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("onboardingProgress")
            }
            .padding(OnboardingParameters.pagePadding)

            ScrollView {
                VStack(spacing: OnboardingParameters.sectionSpacing) {
                    page
                }
                .frame(maxWidth: OnboardingParameters.contentWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, OnboardingParameters.pagePadding)
                .padding(.vertical, OnboardingParameters.itemSpacing)
                .id(model.step)
                .transition(.opacity)
            }
            .animation(reduceMotion ? nil : OnboardingParameters.transition, value: model.step)

            Divider()
            footer
                .padding(OnboardingParameters.pagePadding)
        }
        .accessibilityIdentifier("onboardingView")
    }

    @ViewBuilder private var page: some View {
        switch model.step {
        case .welcome:
            Image("ApplicationIconColorTiles")
                .resizable()
                .scaledToFit()
                .frame(width: OnboardingParameters.heroIconSize,
                       height: OnboardingParameters.heroIconSize)
                .accessibilityHidden(true)
            heading("Welcome to Launchpod", subtitle: "Your apps, ready when you are.")
            OnboardingFeatureDemo(isInteractive: false)
            Text("Browse your apps in Classical mode, search by name, and keep them together in folders.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .organize:
            heading("Find it. Open it. Make it yours.",
                    subtitle: "Search by name and drag apps into the order you want in Classical mode.")
            OnboardingFeatureDemo(isInteractive: true)
        case .folders:
            heading("A Place for Every App",
                    subtitle: "Drag one app onto another to create a folder in Classical mode.")
            OnboardingFolderDemo()
        case .glass:
            heading("Made for Your Mac", subtitle: "Explore native materials and fluid transitions.")
            OnboardingGlassDemo()
        case .access:
            Image(systemName: "keyboard")
                .font(.system(size: OnboardingParameters.heroIconSize, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            heading("Always Within Reach", subtitle: "Choose how you open Launchpod.")
            VStack(alignment: .leading, spacing: OnboardingParameters.sectionSpacing) {
                Label("Set a keyboard shortcut in Settings → Shortcuts.", systemImage: "command")
                Label("Choose menu bar and Dock options in Settings → General.", systemImage: "dock.rectangle")
            }
            .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings…", action: openSettings)
                .controlSize(.large)
                .accessibilityIdentifier("onboardingOpenSettings")
            Text("You can do this now or change it later.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func heading(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: OnboardingParameters.itemSpacing) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: OnboardingParameters.itemSpacing) {
            if model.step != .welcome {
                Button("Back") { model.back() }
                    .accessibilityIdentifier("onboardingBack")
            }
            Spacer()
            if model.step != .access {
                Button("Skip Introduction", action: finish)
                    .accessibilityIdentifier("onboardingSkip")
                Button("Continue") { model.next() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboardingContinue")
            } else {
                Button("Get Started", action: finish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboardingFinish")
            }
        }
        .controlSize(.large)
    }

    private var stepNumber: Int { model.step.rawValue + 1 }
}
