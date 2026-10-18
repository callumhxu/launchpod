import Foundation

/// One observation of an app directory, including whether absence can be trusted.
nonisolated struct ApplicationScan: Sendable {
    struct Directory: Identifiable, Equatable, Sendable {
        let id: UUID
        let source: AppSource

        init(id: UUID = UUID(), source: AppSource) {
            self.id = id
            self.source = source
        }
    }

    /// Opaque identifiers are copied, compared through Foundation, and never persisted.
    struct FileIdentity: Equatable, @unchecked Sendable {
        private let volume: NSObject
        private let file: NSObject

        init?(resourceValues: URLResourceValues) {
            guard let volume = resourceValues.volumeIdentifier,
                  let file = resourceValues.fileResourceIdentifier,
                  let volumeCopy = volume.copy(with: nil) as? NSObject,
                  let fileCopy = file.copy(with: nil) as? NSObject,
                  !(volumeCopy is NSNull), !(fileCopy is NSNull) else { return nil }
            self.volume = volumeCopy
            self.file = fileCopy
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.volume.isEqual(rhs.volume) && lhs.file.isEqual(rhs.file)
        }
    }

    struct Observation: Sendable {
        let metadata: AppMetadata
        let discoveredURL: URL
        let fileIdentity: FileIdentity?
        let isAlias: Bool
        let isSymbolicLink: Bool
    }

    struct Issue: Error, Equatable, Sendable {
        let url: URL
        let domain: String
        let code: Int

        init(url: URL, error: any Error) {
            self.url = url
            let error = error as NSError
            domain = error.domain
            code = error.code
        }
    }

    let directory: Directory
    let source: AppSource
    let applications: [Observation]
    let isComplete: Bool
    let issues: [Issue]
    /// Includes actual targets of links, whose changes do not notify the link directory.
    let monitoredURLs: [URL]
    /// Directory listing observations retained until all app directories in a refresh are scanned.
    var listedDirectoryModificationDates: [URL: Date?] = [:]
}

nonisolated protocol ApplicationScanning: Sendable {
    func scan(_ directory: ApplicationScan.Directory) async -> ApplicationScan
    /// Whether the listed directories still match their observations after other app directories
    /// have been scanned. A change makes absence across the refresh uncertain.
    func isCurrent(_ scan: ApplicationScan) async -> Bool
    /// `true` confirms absence, `false` confirms existence, and `nil` means absence could not be determined.
    /// Existence alone does not confirm an application or its identity.
    func isMissing(at url: URL) async -> Bool?
}
