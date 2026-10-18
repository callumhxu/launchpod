import Foundation
import Testing
@testable import Launchpod

@MainActor
struct AppServicesSelfExclusionTests {
    @Test
    func discoveryAndRestartKeepSelfRecordsInDataButOutOfSharedPresentation() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let installed = try fixture.application("Launchpod.app", in: apps, identifier: "app.joyx.launchpod")
        let copy = try fixture.application("Launchpod Copy.app", in: apps, identifier: "APP.JOYX.LAUNCHPOD")
        let namesake = try fixture.application("Namesake.app", in: apps, identifier: "com.example.launchpod")
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let store = try AppDataStore(directoryURL: fixture.root.appending(path: "Storage", directoryHint: .isDirectory))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { Issue.record($0) })

        try await services.start()
        try await wait { services.hasCurrentScan && services.data?.records.count == 3 }
        #expect(Set(services.data?.records.map(\.metadata.bundleURL) ?? []) == [installed, copy, namesake])
        #expect(services.presentationRecords.map(\.metadata.bundleURL) == [namesake])

        try await services.stop()
        #expect(Set(try #require(try await store.load()?.records.map(\.metadata.bundleURL)))
                == [installed, copy, namesake])
        try await services.start()
        try await wait { services.hasCurrentScan && services.data?.records.count == 3 }
        #expect(services.presentationRecords.map(\.metadata.bundleURL) == [namesake])
        try await services.stop()
    }

    private func wait(until condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Timed out waiting for discovery")
    }
}
