import AppKit
import SwiftUI

struct AboutSettingsView: View {
    let showIntroduction: @MainActor () -> Void
    @ObservedObject private var softwareUpdates: SoftwareUpdateController
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }

    init(
        applicationIcon: ApplicationIcon? = nil,
        softwareUpdates: SoftwareUpdateController? = nil,
        showIntroduction: @escaping @MainActor () -> Void = {}
    ) {
        _ = applicationIcon
        self.softwareUpdates = softwareUpdates ?? SoftwareUpdateController(infoDictionary: [:])
        self.showIntroduction = showIntroduction
    }

    var body: some View {
        Form {
            Section {
                ForEach(Self.links, id: \.accessibilityIdentifier) { link in
                    if let url = link.url {
                        Link(destination: url) {
                            LabeledContent {
                                HStack(spacing: Self.handleSpacing) {
                                    Text(verbatim: ExternalLink.handle(for: url))
                                    Image(systemName: "arrow.up.right")
                                }
                                .foregroundStyle(.secondary)
                            } label: {
                                Label {
                                    Text(verbatim: link.title)
                                } icon: {
                                    Image(link.logo)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: Self.logoSide, height: Self.logoSide)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(link.accessibilityIdentifier)
                    }
                }
            } header: {
                VStack {
                    Image(nsImage: resolvedIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    Text("Launchpod")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    Text("Version \(version)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            Section {
                LabeledContent {
                    Button("Check for Updates…") {
                        softwareUpdates.checkForUpdates()
                    }
                    .disabled(!softwareUpdates.canCheckForUpdates)
                    .accessibilityIdentifier("checkForUpdatesButton")
                } label: {
                    Label("Software Update", systemImage: "arrow.triangle.2.circlepath")
                }
                LabeledContent {
                    Button("Show Introduction", action: showIntroduction)
                        .accessibilityIdentifier("showIntroductionButton")
                } label: {
                    Label("Getting Started", systemImage: "play.rectangle")
                }
            }
        }
        .formStyle(.grouped)
    }

    private struct ExternalLink {
        let title: String
        let logo: String
        let accessibilityIdentifier: String

        /// The page configured under `title` in the bundle's `LaunchpodLinks`; `nil` hides the link.
        var url: URL? {
            let links = Bundle.main.object(forInfoDictionaryKey: "LaunchpodLinks") as? [String: String]
            guard let value = links?[title], !value.isEmpty else { return nil }
            return URL(string: value)
        }

        /// The account shown beside the link: the page path, with `@` added to a bare account name.
        static func handle(for url: URL) -> String {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return path.contains("/") || path.hasPrefix("@") ? path : "@" + path
        }
    }

    private static let logoSide: CGFloat = 16
    private static let handleSpacing: CGFloat = 4

    /// Project and social pages, opened in the default browser. Brand names are not localized.
    private static let links = [
        ExternalLink(title: "GitHub", logo: "GitHubLogo", accessibilityIdentifier: "githubLink"),
        ExternalLink(title: "X", logo: "XLogo", accessibilityIdentifier: "xLink"),
        ExternalLink(title: "YouTube", logo: "YouTubeLogo", accessibilityIdentifier: "youtubeLink"),
        ExternalLink(title: "TikTok", logo: "TikTokLogo", accessibilityIdentifier: "tiktokLink")
    ]

    private var resolvedIcon: NSImage {
        ApplicationIconPreviewImage.resolve(.colorTiles)
    }
}
