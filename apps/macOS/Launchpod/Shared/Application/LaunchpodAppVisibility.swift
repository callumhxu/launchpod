import Foundation

/// Omits Launchpod installations from launcher presentation without changing saved app records.
nonisolated enum LaunchpodAppVisibility {
    static func presentationRecords(from records: [AppRecord],
                                    applicationURL: URL = Bundle.main.bundleURL) -> [AppRecord] {
        let currentURL = applicationURL.resolvingSymlinksInPath().standardizedFileURL
        return records.filter { record in
            if let bundleID = record.metadata.knownBundleIdentifier,
               bundleID.caseInsensitiveCompare("app.joyx.launchpod") == .orderedSame {
                return false
            }
            return record.metadata.bundleURL.resolvingSymlinksInPath().standardizedFileURL != currentURL
        }
    }
}
