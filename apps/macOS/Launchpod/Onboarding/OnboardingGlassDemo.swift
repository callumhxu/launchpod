import SwiftUI

/// A native material demonstration, separate from either launcher's presentation state.
struct OnboardingGlassDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: OnboardingParameters.sectionSpacing) {
            ZStack {
                LinearGradient(colors: [.indigo, .blue, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: OnboardingParameters.sectionSpacing) {
                    ForEach(OnboardingDemoState.App.allCases) { app in
                        OnboardingSampleTile(app: app)
                    }
                }
                .accessibilityHidden(true)
                if #available(macOS 26.0, *) {
                    GlassEffectContainer(spacing: OnboardingParameters.sectionSpacing) {
                        if isExpanded {
                            glassContent
                                .glassEffect(.regular, in: .rect(cornerRadius: OnboardingParameters.panelCornerRadius))
                                .glassEffectID("sample", in: glass)
                        } else {
                            Image(systemName: "square.grid.2x2")
                                .font(.largeTitle)
                                .padding(OnboardingParameters.pagePadding)
                                .glassEffect(.regular, in: .circle)
                                .glassEffectID("sample", in: glass)
                        }
                    }
                } else {
                    glassContent
                        .background(.regularMaterial, in: .rect(cornerRadius: OnboardingParameters.panelCornerRadius))
                }
            }
            .frame(height: OnboardingParameters.glassStageHeight)
            .clipShape(.rect(cornerRadius: OnboardingParameters.panelCornerRadius))
            if #available(macOS 26.0, *) {
                Button {
                    withAnimation(reduceMotion ? nil : OnboardingParameters.demonstration) {
                        isExpanded.toggle()
                    }
                } label: {
                    if isExpanded {
                        Text("Collapse Glass")
                    } else {
                        Text("Expand Glass")
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .accessibilityIdentifier("onboardingToggleGlass")
                Text("Expand and collapse the sample to see native Liquid Glass change shape.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Liquid Glass requires macOS 26 or later. This Mac shows the standard system material.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityIdentifier("onboardingGlassDemo")
    }

    private var glassContent: some View {
        VStack(spacing: OnboardingParameters.itemSpacing) {
            Image(systemName: "square.grid.2x2").font(.largeTitle)
            if #available(macOS 26.0, *) {
                Text("Liquid Glass").font(.title2.bold())
            } else {
                Text("System Material").font(.title2.bold())
            }
            Text("Light, depth, and motion.").font(.callout)
        }
        .padding(OnboardingParameters.pagePadding)
        .frame(width: OnboardingParameters.glassExpandedWidth)
    }
}
