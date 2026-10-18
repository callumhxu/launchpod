import Foundation

/// One app copy's stable identity and replaceable discovery values.
nonisolated struct AppRecord: Identifiable, Equatable, Codable, Sendable {
    let id: AppIdentity
    let metadata: AppMetadata
    let source: AppSource

    /// Whether the app is missing at its recorded location; nil means unknown.
    /// App absence and source availability are independent observations.
    var isMissing: Bool?

    /// Whether this app copy is marked recently added; nil means unobserved.
    var isRecentlyAdded: Bool?

    /// Opaque relocation data retained independently of refreshed metadata.
    var bookmarkData: Data?

    enum UpdateError: Error {
        case bundleIdentifierMismatch
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case metadata
        case source
        case isMissing
        case isRecentlyAdded
        case bookmarkData
    }

    init(
        id: AppIdentity = AppIdentity(),
        metadata: AppMetadata,
        source: AppSource,
        isMissing: Bool? = nil,
        isRecentlyAdded: Bool? = nil,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.metadata = metadata
        self.source = source
        self.isMissing = isMissing
        self.isRecentlyAdded = isRecentlyAdded
        self.bookmarkData = bookmarkData
    }

    /// Matches a repeated observation or same-location reinstall candidate.
    /// Missing identifiers and a bundle ID shared by different paths do not match.
    func matchesBundleAndLocation(of metadata: AppMetadata) -> Bool {
        matchesBundleAndLocation(bundleIdentifier: metadata.knownBundleIdentifier, bundleURL: metadata.bundleURL)
    }

    /// The same rule for a saved bundle identifier and location that is not a full observation.
    func matchesBundleAndLocation(bundleIdentifier: String?, bundleURL: URL) -> Bool {
        guard let previousIdentifier = self.metadata.knownBundleIdentifier,
              let newIdentifier = bundleIdentifier, !newIdentifier.isEmpty else { return false }
        return previousIdentifier.caseInsensitiveCompare(newIdentifier) == .orderedSame
            && self.metadata.bundleURL == bundleURL
    }

    /// The caller must establish continuity, including confirmation of a move.
    /// This operation preserves the key; it does not discover moves or choose copies.
    func replacingMetadata(with metadata: AppMetadata, source: AppSource) throws -> AppRecord {
        if let previousIdentifier = self.metadata.knownBundleIdentifier,
           let newIdentifier = metadata.knownBundleIdentifier,
           previousIdentifier.caseInsensitiveCompare(newIdentifier) != .orderedSame {
            throw UpdateError.bundleIdentifierMismatch
        }
        return AppRecord(
            id: id,
            metadata: metadata,
            source: source,
            isMissing: isMissing,
            isRecentlyAdded: isRecentlyAdded,
            bookmarkData: bookmarkData
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported AppRecord schema version: \(version)."
            )
        }
        id = try container.decode(AppIdentity.self, forKey: .id)
        metadata = try container.decode(AppMetadata.self, forKey: .metadata)
        source = try container.decode(AppSource.self, forKey: .source)
        isMissing = try container.decodeIfPresent(Bool.self, forKey: .isMissing)
        isRecentlyAdded = try container.decodeIfPresent(Bool.self, forKey: .isRecentlyAdded)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(isMissing, forKey: .isMissing)
        try container.encodeIfPresent(isRecentlyAdded, forKey: .isRecentlyAdded)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
    }
}
