import SwiftUI

/// A recognizable sample icon; no installed app is opened by the introduction.
struct OnboardingSampleTile: View {
    let app: OnboardingDemoState.App

    var body: some View {
        VStack(spacing: OnboardingParameters.compactSpacing) {
            Image(systemName: symbol)
                .font(.system(size: OnboardingParameters.tileSymbolSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: OnboardingParameters.tileSize, height: OnboardingParameters.tileSize)
                .background(color.gradient, in: .rect(cornerRadius: OnboardingParameters.tileCornerRadius))
            Text(title).font(.caption)
        }
        .frame(width: OnboardingParameters.sampleItemWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var symbol: String {
        switch app {
        case .notes: "note.text"
        case .music: "music.note"
        case .photos: "photo"
        case .calendar: "calendar"
        }
    }

    private var color: Color {
        switch app {
        case .notes: .orange
        case .music: .pink
        case .photos: .purple
        case .calendar: .blue
        }
    }

    private var title: LocalizedStringKey {
        switch app {
        case .notes: "Notes"
        case .music: "Music"
        case .photos: "Photos"
        case .calendar: "Calendar"
        }
    }
}
