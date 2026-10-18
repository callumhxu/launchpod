import Foundation
import Testing
@testable import Launchpod

struct LaunchpodAppVisibilityTests {
    @Test
    func presentationExcludesCopiesAndExactRunningPathButKeepsNamesakes() throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let runningURL = try fixture.application("Running.app", identifier: nil)
        let installed = try record(bundleID: "app.joyx.launchpod", path: "/Applications/Launchpod.app")
        let copied = try record(bundleID: "APP.JOYX.LAUNCHPOD",
                                path: "/Volumes/Other/Applications/Launchpod.app")
        let runningWithoutID = try record(bundleID: nil, path: runningURL.path)
        let namesake = try record(bundleID: "com.example.launchpod", path: "/Applications/Launchpod Clone.app",
                                  name: "Launchpod")
        let unrelated = try record(bundleID: "com.example.notes", path: "/Applications/Notes.app")

        let presented = LaunchpodAppVisibility.presentationRecords(
            from: [installed, copied, runningWithoutID, namesake, unrelated], applicationURL: runningURL
        )

        #expect(presented.map(\.id) == [namesake.id, unrelated.id])
    }

    private func record(bundleID: String?, path: String, name: String? = nil) throws -> AppRecord {
        let bundleURL = URL(filePath: path, directoryHint: .isDirectory)
        let directoryURL = bundleURL.deletingLastPathComponent()
        return AppRecord(id: AppIdentity(),
                         metadata: try AppMetadata(bundleIdentifier: bundleID, bundleURL: bundleURL,
                                                   displayName: name ?? bundleURL.deletingPathExtension().lastPathComponent),
                         source: try AppSource(kind: .custom, directoryURL: directoryURL, isOnline: true))
    }
}
