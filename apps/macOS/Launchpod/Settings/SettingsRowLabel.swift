import SwiftUI

/// A settings row label with an icon, a title, and a secondary subtitle, centered vertically in its row.
///
/// Grouped forms align a label's icon with the first line of its title. Rows with a subtitle use this
/// label so the icon and the row's control are centered on the whole text block instead.
struct SettingsRowLabel: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Metrics.subtitleSpacing) {
                Text(title)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .labelStyle(CenteredIconLabelStyle())
        .settingsRowCentered()
    }

    // Matches the grouped form's own icon-to-title spacing and subtitle spacing.
    private enum Metrics {
        static let iconSpacing: CGFloat = 11
        static let subtitleSpacing: CGFloat = 2
    }

    private struct CenteredIconLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(alignment: .center, spacing: Metrics.iconSpacing) {
                configuration.icon
                configuration.title
            }
        }
    }
}

extension View {
    /// Centers a row's label or trailing control vertically on the row, rather than aligning it
    /// with the first text baseline.
    func settingsRowCentered() -> some View {
        alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
    }
}
