import Foundation

/// Saves the Classical layout to one current-format file in its mode-owned directory.
actor ClassicalLayoutStore {
    nonisolated let fileURL: URL
    private let directoryURL: URL
    private let write: @Sendable (Data, URL) throws -> Void

    init(directoryURL: URL,
         write: @escaping @Sendable (Data, URL) throws -> Void = { data, url in try data.write(to: url, options: .atomic) }) {
        self.directoryURL = directoryURL
        fileURL = directoryURL.appendingPathComponent("layout.json")
        self.write = write
    }

    /// Nil when the layout file is absent. An unreadable file is reported to the caller.
    func load() throws -> ClassicalLayout? {
        do {
            return try JSONDecoder().decode(ClassicalLayout.self, from: Data(contentsOf: fileURL))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    /// Saves the complete current-format layout atomically.
    func save(_ layout: ClassicalLayout) throws {
        let encoded = try JSONEncoder().encode(layout)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try write(encoded, fileURL)
    }

    /// Removes the saved layout when the user requests the system arrangement again.
    func removeSavedLayout() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
