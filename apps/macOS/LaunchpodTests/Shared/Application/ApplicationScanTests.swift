import Foundation
import Testing
@testable import Launchpod

struct ApplicationScanTests {
    @Test
    func fileIdentityFollowsARealMoveButDoesNotIdentifyACopy() throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let app = try fixture.application("Editor.app")
        let original = try #require(try identity(at: app))
        let copy = fixture.root.appendingPathComponent("Copy.app", isDirectory: true)
        try FileManager.default.copyItem(at: app, to: copy)
        let copied = try #require(try identity(at: copy))
        let moved = fixture.root.appendingPathComponent("Moved.app", isDirectory: true)
        try FileManager.default.moveItem(at: app, to: moved)

        #expect(try identity(at: moved) == original)
        #expect(copied != original)
    }

    @Test
    func unavailableResourceIdentifiersDoNotCreateSyntheticIdentity() {
        #expect(ApplicationScan.FileIdentity(resourceValues: URLResourceValues()) == nil)
    }

    private func identity(at url: URL) throws -> ApplicationScan.FileIdentity? {
        ApplicationScan.FileIdentity(resourceValues: try url.resourceValues(forKeys: [
            .volumeIdentifierKey, .fileResourceIdentifierKey
        ]))
    }
}
