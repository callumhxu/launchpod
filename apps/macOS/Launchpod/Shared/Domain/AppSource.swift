import Foundation

/// Discovery provenance supplied by the scanner, not app ownership or trust.
nonisolated struct AppSource: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case system = "system"
        case user = "user"
        case custom = "custom"
    }

    let kind: Kind
    let directoryURL: URL

    /// Last known availability of the app directory; nil means unknown.
    let isOnline: Bool?
    let volumeUUIDString: String?

    enum ValidationError: Error {
        case invalidDirectoryURL
    }

    init(
        kind: Kind,
        directoryURL: URL,
        isOnline: Bool? = nil,
        volumeUUIDString: String? = nil
    ) throws {
        guard let directoryURL = AppFileURL.normalized(directoryURL) else {
            throw ValidationError.invalidDirectoryURL
        }
        self.kind = kind
        self.directoryURL = directoryURL
        self.isOnline = isOnline
        self.volumeUUIDString = volumeUUIDString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(Kind.self, forKey: .kind),
            directoryURL: container.decode(URL.self, forKey: .directoryURL),
            isOnline: container.decodeIfPresent(Bool.self, forKey: .isOnline),
            volumeUUIDString: container.decodeIfPresent(String.self, forKey: .volumeUUIDString)
        )
    }
}
