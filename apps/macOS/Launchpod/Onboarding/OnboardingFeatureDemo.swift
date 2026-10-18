import SwiftUI

/// An illustrative sample whose state never changes the user's apps or layout.
struct OnboardingFeatureDemo: View {
    let isInteractive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var illustration
    @State private var sample = OnboardingDemoState()
    @State private var didReorder = false

    var body: some View {
        VStack(spacing: OnboardingParameters.sectionSpacing) {
            VStack(spacing: OnboardingParameters.sectionSpacing) {
                HStack(spacing: OnboardingParameters.compactSpacing) {
                    Image(systemName: "magnifyingglass")
                    if sample.query.isEmpty {
                        Text("Search Apps")
                    } else {
                        Text("Notes")
                    }
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(OnboardingParameters.itemSpacing)
                .background(.background, in: .rect(cornerRadius: OnboardingParameters.tileCornerRadius))

                HStack(spacing: OnboardingParameters.itemSpacing) {
                    ForEach(sample.visibleApps) { app in
                        sampleTile(app)
                            .matchedGeometryEffect(id: app, in: illustration)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: OnboardingParameters.demoRowHeight)
                .accessibilityIdentifier("onboardingSampleApps")
            }
            .padding(OnboardingParameters.sectionSpacing)
            .background(.quinary, in: .rect(cornerRadius: OnboardingParameters.panelCornerRadius))

            if isInteractive {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboardingDemoDescription")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: OnboardingParameters.itemSpacing) { controls }
                    VStack(spacing: OnboardingParameters.itemSpacing) { controls }
                }
            }
        }
        .accessibilityIdentifier("onboardingFeatureDemo")
    }

    @ViewBuilder private var controls: some View {
        Button("Try Search") { animate { sample.searchForNotes() } }
            .accessibilityIdentifier("onboardingTrySearch")
        Button("Try Reordering") {
            animate {
                sample.reset()
                sample.move(.calendar, before: .notes)
                didReorder = true
            }
        }
        .accessibilityIdentifier("onboardingTryReorder")
        Button("Reset Demo") { animate { sample.reset(); didReorder = false } }
            .accessibilityIdentifier("onboardingResetDemo")
    }

    @ViewBuilder private func sampleTile(_ app: OnboardingDemoState.App) -> some View {
        if isInteractive && sample.query.isEmpty {
            OnboardingSampleTile(app: app)
                .draggable(app.rawValue)
                .dropDestination(for: String.self) { items, _ in
                    guard let value = items.first, let source = OnboardingDemoState.App(rawValue: value),
                          source != app else { return false }
                    animate { sample.move(source, before: app); didReorder = true }
                    return true
                }
        } else {
            OnboardingSampleTile(app: app)
        }
    }

    private func animate(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : OnboardingParameters.demonstration, change)
    }

    private var description: LocalizedStringKey {
        if !sample.query.isEmpty {
            "Searching narrows the apps shown. This illustration searches for Notes."
        } else if didReorder {
            "The sample order has changed. Your own app layout stays untouched."
        } else {
            "Drag a sample app onto another position, or use Try Reordering."
        }
    }
}
