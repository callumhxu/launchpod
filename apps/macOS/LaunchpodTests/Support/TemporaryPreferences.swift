import Foundation

/// Real defaults backed by a private temporary directory rather than the user's preferences folder.
struct TemporaryPreferences {
    let directoryURL: URL
    let domain: String
    let defaults: UserDefaults

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchpodTestPreferences-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        // An absolute domain path keeps Foundation and CFPreferences writes in this directory.
        let domain = directory.appendingPathComponent("preferences").path
        guard let defaults = UserDefaults(suiteName: domain) else {
            try FileManager.default.removeItem(at: directory)
            throw CocoaError(.fileReadUnknown)
        }
        directoryURL = directory
        self.domain = domain
        self.defaults = defaults
    }

    /// Flushes the domain before deleting only the temporary directory this fixture created.
    func cleanup() throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        defaults.removePersistentDomain(forName: domain)
        guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.removeItem(at: directoryURL)
    }
}
