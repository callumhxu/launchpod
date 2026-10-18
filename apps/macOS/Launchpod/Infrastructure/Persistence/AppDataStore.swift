import Foundation

/// Saves shared app data to one current-format file.
/// The caller owns one store per directory; separate instances or processes are not coordinated.
actor AppDataStore {
    nonisolated enum ValidationError: Error {
        case invalidDirectoryURL
    }

    nonisolated let fileURL: URL

    private let directoryURL: URL
    private let write: @Sendable (Data, URL) throws -> Void

    /// The directory contains only shared app data; preferences and mode state have separate owners.
    /// Its URL must identify an absolute local file path.
    /// A supplied writer must preserve the destination on failure, as an atomic write does.
    init(
        directoryURL: URL,
        write: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) throws {
        guard let directoryURL = AppFileURL.normalized(directoryURL) else {
            throw ValidationError.invalidDirectoryURL
        }
        self.directoryURL = directoryURL
        fileURL = directoryURL.appendingPathComponent("app-data.json")
        self.write = write
    }

    /// Reads the current-format file. Nil means it is absent, never corrupt or unreadable.
    func load() throws -> AppData? {
        do {
            return try JSONDecoder().decode(AppData.self, from: Data(contentsOf: fileURL))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    /// Saves the complete current-format file atomically.
    func save(_ data: AppData) throws {
        let encoded = try JSONEncoder().encode(data)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try write(encoded, fileURL)
    }
}
