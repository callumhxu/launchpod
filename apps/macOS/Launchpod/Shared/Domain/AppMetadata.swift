import Foundation

/// Scanned values that may change without changing an app's stable identity.
nonisolated struct AppMetadata: Equatable, Codable, Sendable {
    let bundleIdentifier: String?
    let bundleURL: URL
    let displayName: String
    let version: String?
    let buildVersion: String?
    let categoryIdentifier: String?
    let contentModificationDate: Date?

    // Raw application and launch-role observations; unavailable values remain nil, not false.
    let isApplication: Bool?
    let isUIElement: Bool?
    let isBackgroundOnly: Bool?
    /// The observed beta status; nil means unknown or the resource key was unavailable.
    /// A missing Boolean resource value is recorded as false when the key is available.
    let isBeta: Bool?
    let isStoreApp: Bool?

    enum ValidationError: Error {
        case invalidBundleURL
    }

    init(
        bundleIdentifier: String?,
        bundleURL: URL,
        displayName: String,
        version: String? = nil,
        buildVersion: String? = nil,
        categoryIdentifier: String? = nil,
        contentModificationDate: Date? = nil,
        isApplication: Bool? = nil,
        isUIElement: Bool? = nil,
        isBackgroundOnly: Bool? = nil,
        isBeta: Bool? = nil,
        isStoreApp: Bool? = nil
    ) throws {
        guard let bundleURL = AppFileURL.normalized(bundleURL) else {
            throw ValidationError.invalidBundleURL
        }
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.displayName = displayName
        self.version = version
        self.buildVersion = buildVersion
        self.categoryIdentifier = categoryIdentifier
        self.contentModificationDate = contentModificationDate
        self.isApplication = isApplication
        self.isUIElement = isUIElement
        self.isBackgroundOnly = isBackgroundOnly
        self.isBeta = isBeta
        self.isStoreApp = isStoreApp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            bundleIdentifier: container.decodeIfPresent(String.self, forKey: .bundleIdentifier),
            bundleURL: container.decode(URL.self, forKey: .bundleURL),
            displayName: container.decode(String.self, forKey: .displayName),
            version: container.decodeIfPresent(String.self, forKey: .version),
            buildVersion: container.decodeIfPresent(String.self, forKey: .buildVersion),
            categoryIdentifier: container.decodeIfPresent(String.self, forKey: .categoryIdentifier),
            contentModificationDate: container.decodeIfPresent(Date.self, forKey: .contentModificationDate),
            isApplication: container.decodeIfPresent(Bool.self, forKey: .isApplication),
            isUIElement: container.decodeIfPresent(Bool.self, forKey: .isUIElement),
            isBackgroundOnly: container.decodeIfPresent(Bool.self, forKey: .isBackgroundOnly),
            isBeta: container.decodeIfPresent(Bool.self, forKey: .isBeta),
            isStoreApp: container.decodeIfPresent(Bool.self, forKey: .isStoreApp)
        )
    }

    var knownBundleIdentifier: String? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        return bundleIdentifier
    }
}

/// Shared lexical validation for app bundle and discovery source directories.
nonisolated enum AppFileURL {
    static func normalized(_ url: URL) -> URL? {
        guard url.isFileURL,
              let components = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: false),
              components.path.hasPrefix("/"),
              !components.path.contains("\0"),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              components.host == nil || components.host == "" || components.host == "localhost"
        else { return nil }

        // This is lexical normalization, not evidence of file or symlink identity.
        return url.absoluteURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            return URL(filePath: String(cString: path), directoryHint: .isDirectory).standardized
        }
    }
}
