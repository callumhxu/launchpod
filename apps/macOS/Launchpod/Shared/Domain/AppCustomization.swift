import Foundation

/// User-owned values retained independently of an app's discovery record.
nonisolated struct AppCustomization: Equatable, Codable, Sendable {
    let appID: AppIdentity
    var isHidden: Bool
    var customName: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case appID
        case isHidden
        case customName
    }

    init(appID: AppIdentity, isHidden: Bool = false, customName: String? = nil) {
        self.appID = appID
        self.isHidden = isHidden
        self.customName = customName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported AppCustomization schema version: \(version)."
            )
        }
        appID = try container.decode(AppIdentity.self, forKey: .appID)
        isHidden = try container.decode(Bool.self, forKey: .isHidden)
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(appID, forKey: .appID)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encodeIfPresent(customName, forKey: .customName)
    }
}
