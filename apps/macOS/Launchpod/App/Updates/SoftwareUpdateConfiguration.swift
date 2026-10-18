import Foundation

/// The externally supplied values required to use Launchpod's signed update feed.
struct SoftwareUpdateConfiguration: Equatable, Sendable {
    static let feedURLInfoKey = "SUFeedURL"
    static let publicEDKeyInfoKey = "SUPublicEDKey"

    let feedURL: URL
    let publicEDKey: String

    init?(infoDictionary: [String: Any]) {
        guard
            let feedValue = Self.nonemptyString(
                infoDictionary[Self.feedURLInfoKey]
            ),
            let feedURL = URL(string: feedValue),
            feedURL.scheme?.lowercased() == "https",
            feedURL.host != nil,
            let publicEDKey = Self.nonemptyString(
                infoDictionary[Self.publicEDKeyInfoKey]
            )
        else { return nil }

        self.feedURL = feedURL
        self.publicEDKey = publicEDKey
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
