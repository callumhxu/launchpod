import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalPageContentTests: XCTestCase {
    func testPagesBeforeTheSharedCatalogLoadsDoNotClearTheSavedArrangement() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let saved = try ClassicalLayout(pages: [[AppIdentity(), AppIdentity()]])
        let layoutStore = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await layoutStore.save(saved)
        let layout = ClassicalLayoutModel(store: layoutStore)
        await layout.load()
        let services = AppServices(
            store: try AppDataStore(directoryURL: fixture.root.appending(path: "Data", directoryHint: .isDirectory)),
            icons: AppIconRepository(cacheCostLimit: 0), directories: [],
            onError: { XCTFail("Unexpected application error: \($0)") }
        )

        XCTAssertNil(services.data)
        XCTAssertTrue(ClassicalPageContent(services: services, layout: layout).pages(3).isEmpty)
        XCTAssertEqual(layout.layout, saved)
        let persisted = try await layoutStore.load()
        XCTAssertEqual(persisted, saved)
    }

    func testRestoredOfflineApplicationOccupiesItsSavedSlotWithQuestionMark() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let first = try record("Calendar", directory: "/Applications", online: true)
        let external = try record("Studio", directory: "/Volumes/Studio/Applications", online: false)
        let last = try record("Notes", directory: "/Applications", online: true)
        let expected = [first.id, external.id, last.id]
        let dataStore = try AppDataStore(directoryURL: fixture.root.appending(path: "Data", directoryHint: .isDirectory))
        let layoutStore = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await dataStore.save(AppData(records: [last, external, first]))
        try await layoutStore.save(ClassicalLayout(pages: [expected]))

        let services = AppServices(store: dataStore, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [], onError: { XCTFail("Unexpected application error: \($0)") })
        try await services.start()
        try await AppIconTestSupport.wait { services.hasCurrentScan }
        XCTAssertTrue(services.availableRecords.isEmpty, "No directory was observed during restoration")
        let layout = ClassicalLayoutModel(store: layoutStore)
        await layout.load()
        let content = ClassicalPageContent(services: services, layout: layout)
        let pages = content.pages(3)
        XCTAssertEqual(pages.map { $0.compactMap(\.record?.id) }, [expected])
        XCTAssertEqual(pages[0][1].record?.source.isOnline, false)

        let page = ClassicalGridPage()
        let grid = ClassicalGridLayout(pageSize: CGSize(width: 300, height: 200), rows: 1, columns: 3)
        page.show(pages[0], grid: grid, frame: CGRect(x: 0, y: 0, width: 300, height: 200),
                  scale: 1, rightToLeft: false, icon: { _, _ in throw CancellationError() })
        XCTAssertNotNil(page.itemLayers[1].notFoundLayer, "The saved offline slot shows a question mark")
        XCTAssertNil(page.itemLayers[0].notFoundLayer)
        XCTAssertNil(page.itemLayers[2].notFoundLayer)
        try await services.stop()

        let reconnected = try record("Studio", id: external.id, directory: "/Volumes/Studio/Applications", online: true)
        try await dataStore.save(AppData(records: [last, reconnected, first]))
        let restarted = AppServices(store: dataStore, icons: AppIconRepository(cacheCostLimit: 0),
                                    directories: [], onError: { XCTFail("Unexpected application error: \($0)") })
        try await restarted.start()
        try await AppIconTestSupport.wait { restarted.hasCurrentScan }
        let restoredLayout = ClassicalLayoutModel(store: layoutStore)
        await restoredLayout.load()
        let restored = ClassicalPageContent(services: restarted, layout: restoredLayout).pages(3)
        XCTAssertEqual(restored.map { $0.compactMap(\.record?.id) }, [expected])
        page.show(restored[0], grid: grid, frame: page.layer.frame,
                  scale: 1, rightToLeft: false, icon: { _, _ in throw CancellationError() })
        XCTAssertNil(page.itemLayers[1].notFoundLayer, "The question mark clears when the app is online again")
        try await restarted.stop()
    }

    func testRestoredCacheDoesNotSeedInitialLayoutBeforeCurrentDiscovery() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        _ = try fixture.application("Safari.app", in: apps, identifier: "com.apple.Safari",
                                    values: ["CFBundleDisplayName": "Safari"])
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let initialScan = await ApplicationCatalog(directories: [directory], scanner: ApplicationScanner()).refresh()
        let cached = try XCTUnwrap(initialScan.records.first)
        let dataStore = try AppDataStore(directoryURL: fixture.root.appending(path: "Data", directoryHint: .isDirectory))
        try await dataStore.save(AppData(records: [cached]))
        _ = try fixture.application("Store.app", in: apps, identifier: "com.apple.AppStore",
                                    values: ["CFBundleDisplayName": "Store"])
        _ = try fixture.application("Terminal.app", in: apps, identifier: "com.apple.Terminal",
                                    values: ["CFBundleDisplayName": "Terminal"])

        let scanner = PausingFirstScanScanner()
        defer { Task { await scanner.resume() } }
        let services = AppServices(store: dataStore, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], scanner: scanner,
                                   onError: { XCTFail("Unexpected application error: \($0)") })
        defer { Task { try? await services.stop() } }
        let layoutStore = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let layout = ClassicalLayoutModel(store: layoutStore)
        await layout.load()
        try await services.start()
        try await AppIconTestSupport.wait { await scanner.isPaused }
        let content = ClassicalPageContent(services: services, layout: layout)

        XCTAssertEqual(services.data?.records.map(\.id), [cached.id])
        XCTAssertFalse(services.hasCurrentScan)
        XCTAssertTrue(content.pages(3).isEmpty)
        XCTAssertNil(layout.layout)
        let beforeScan = try await layoutStore.load()
        XCTAssertNil(beforeScan)

        await scanner.resume()
        try await AppIconTestSupport.wait { services.hasCurrentScan && services.data?.records.count == 3 }
        let pages = content.pages(3)
        XCTAssertEqual(pages.first?.first?.record?.metadata.bundleIdentifier, "com.apple.AppStore")
        XCTAssertEqual(pages.first?.dropFirst().first?.record?.metadata.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(pages.first?.last?.folder?.records.map(\.metadata.bundleIdentifier), ["com.apple.Terminal"])
        XCTAssertEqual(layout.layout?.folders.first?.id, .defaultOther)
        try await services.stop()
    }

    func testRestoredCacheCannotEraseASavedLayoutBeforeCurrentDiscovery() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        _ = try fixture.application("Safari.app", in: apps, identifier: "com.apple.Safari")
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let initialScan = await ApplicationCatalog(directories: [directory], scanner: ApplicationScanner()).refresh()
        let cached = try XCTUnwrap(initialScan.records.first)
        let dataStore = try AppDataStore(directoryURL: fixture.root.appending(path: "Data", directoryHint: .isDirectory))
        try await dataStore.save(AppData(records: [cached]))
        let saved = try ClassicalLayout(pages: [[cached.id, AppIdentity()]])
        let layoutStore = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await layoutStore.save(saved)

        let scanner = PausingFirstScanScanner()
        defer { Task { await scanner.resume() } }
        let services = AppServices(store: dataStore, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], scanner: scanner,
                                   onError: { XCTFail("Unexpected application error: \($0)") })
        defer { Task { try? await services.stop() } }
        let layout = ClassicalLayoutModel(store: layoutStore)
        await layout.load()
        try await services.start()
        try await AppIconTestSupport.wait { await scanner.isPaused }

        XCTAssertFalse(services.hasCurrentScan)
        XCTAssertTrue(ClassicalPageContent(services: services, layout: layout).pages(3).isEmpty)
        await layout.flush()
        XCTAssertEqual(layout.layout, saved)
        let onDisk = try await layoutStore.load()
        XCTAssertEqual(onDisk, saved)
        await scanner.resume()
        try await AppIconTestSupport.wait { services.hasCurrentScan }
        try await services.stop()
    }

    private func record(_ name: String, id: AppIdentity = AppIdentity(), directory: String, online: Bool) throws -> AppRecord {
        let directoryURL = URL(filePath: directory, directoryHint: .isDirectory)
        let bundleURL = directoryURL.appending(path: "\(name).app", directoryHint: .isDirectory)
        return AppRecord(
            id: id,
            metadata: try AppMetadata(bundleIdentifier: "com.example.\(name)", bundleURL: bundleURL,
                                      displayName: name, version: nil, buildVersion: nil, contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: directoryURL, isOnline: online)
        )
    }
}
