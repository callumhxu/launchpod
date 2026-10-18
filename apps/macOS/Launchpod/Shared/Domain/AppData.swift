import Foundation

/// Shared app identities and user customizations, independent of either mode's layout.
nonisolated struct AppData: Equatable, Codable, Sendable {
    let records: [AppRecord]
    let customizations: [AppCustomization]
    /// App directories with a completed online scan, including empty directories.
    let scannedDirectoryURLs: Set<URL>

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case records
        case customizations
        case scannedDirectoryURLs
    }

    enum ValidationError: Error {
        case duplicateRecordIdentity
        case duplicateCustomizationIdentity
    }

    /// Customizations may refer to apps absent from the records and remain user-owned data.
    init(
        records: [AppRecord] = [],
        customizations: [AppCustomization] = [],
        scannedDirectoryURLs: Set<URL> = []
    ) throws {
        guard Set(records.map(\.id)).count == records.count else {
            throw ValidationError.duplicateRecordIdentity
        }
        guard Set(customizations.map(\.appID)).count == customizations.count else {
            throw ValidationError.duplicateCustomizationIdentity
        }
        self.records = records
        self.customizations = customizations
        self.scannedDirectoryURLs = scannedDirectoryURLs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported AppData schema version: \(version)."
            )
        }
        try self.init(
            records: container.decode([AppRecord].self, forKey: .records),
            customizations: container.decode([AppCustomization].self, forKey: .customizations),
            scannedDirectoryURLs: Set(container.decode([URL].self, forKey: .scannedDirectoryURLs))
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(records, forKey: .records)
        try container.encode(customizations, forKey: .customizations)
        try container.encode(scannedDirectoryURLs.sorted { $0.absoluteString < $1.absoluteString },
                             forKey: .scannedDirectoryURLs)
    }
}
