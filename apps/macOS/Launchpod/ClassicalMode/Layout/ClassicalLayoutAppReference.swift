import Foundation

/// The bundle and location a layout identity stood for when the catalog last held it.
///
/// A layout slot refers to an app identity owned by the shared app data. When that data no longer
/// holds the identity but a catalog record has the same bundle identifier and location, the slot
/// belongs to that record's identity instead of being treated as an uninstalled application.
nonisolated struct ClassicalLayoutAppReference: Codable, Hashable, Sendable {
    let id: AppIdentity
    let bundleIdentifier: String
    let bundleURL: URL

    enum ValidationError: Error {
        case emptyBundleIdentifier
        case invalidBundleURL
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case bundleIdentifier
        case bundleURL
    }

    init(id: AppIdentity, bundleIdentifier: String, bundleURL: URL) throws {
        guard !bundleIdentifier.isEmpty else { throw ValidationError.emptyBundleIdentifier }
        guard let bundleURL = AppFileURL.normalized(bundleURL) else { throw ValidationError.invalidBundleURL }
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
    }

    /// Nil for a record without a known bundle identifier, which the catalog cannot match either.
    init?(record: AppRecord) {
        guard let bundleIdentifier = record.metadata.knownBundleIdentifier,
              let reference = try? Self(id: record.id, bundleIdentifier: bundleIdentifier,
                                        bundleURL: record.metadata.bundleURL) else { return nil }
        self = reference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: container.decode(AppIdentity.self, forKey: .id),
                      bundleIdentifier: container.decode(String.self, forKey: .bundleIdentifier),
                      bundleURL: container.decode(URL.self, forKey: .bundleURL))
    }

    /// The catalog identity that takes over each referenced identity `records` no longer holds.
    ///
    /// Matching uses the catalog's bundle-and-location rule. A reference matches only when exactly
    /// one record not in `held` qualifies, and a record claimed by more than one reference is left
    /// unmatched, so an ambiguous replacement never moves an application into a slot.
    static func replacements(for references: some Collection<Self>, in records: [AppRecord],
                             excluding held: Set<AppIdentity>) -> [AppIdentity: AppIdentity] {
        let known = Set(records.map(\.id))
        var candidates: [AppIdentity: AppIdentity] = [:]
        for reference in references where !known.contains(reference.id) {
            let matches = records.filter {
                !held.contains($0.id)
                    && $0.matchesBundleAndLocation(bundleIdentifier: reference.bundleIdentifier,
                                                   bundleURL: reference.bundleURL)
            }
            if matches.count == 1, let match = matches.first { candidates[reference.id] = match.id }
        }
        let claims = Dictionary(candidates.values.map { ($0, 1) }, uniquingKeysWith: +)
        return candidates.filter { claims[$0.value] == 1 }
    }
}
