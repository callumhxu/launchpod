import Foundation
import XCTest
@testable import Launchpod

/// Classical presentation keeps the selected Siri visible without discarding saved layout data.
final class ClassicalLayoutModelSiriTests: XCTestCase {
    private func record(_ bundleID: String?, name: String, category: String? = nil,
                        directoryPath: String = "/Applications", isBeta: Bool? = nil,
                        isMissing: Bool? = nil, isStoreApp: Bool? = nil, isUIElement: Bool? = nil,
                        sourceDirectoryPath: String? = nil, isOnline: Bool? = true) throws -> AppRecord {
        let directory = URL(filePath: directoryPath, directoryHint: .isDirectory)
        let sourceDirectory = URL(filePath: sourceDirectoryPath ?? directoryPath, directoryHint: .isDirectory)
        return AppRecord(
            id: AppIdentity(),
            metadata: try AppMetadata(bundleIdentifier: bundleID,
                                      bundleURL: directory.appending(path: "\(name).app", directoryHint: .isDirectory),
                                      displayName: name, version: nil, buildVersion: nil,
                                      categoryIdentifier: category,
                                      contentModificationDate: nil, isUIElement: isUIElement,
                                      isBeta: isBeta, isStoreApp: isStoreApp),
            source: try AppSource(kind: .custom, directoryURL: sourceDirectory, isOnline: isOnline),
            isMissing: isMissing
        )
    }

    @MainActor
    func testFreshLayoutShowsOnlyColorfulSiriAtItsTemplatePosition() throws {
        let home = try record("com.apple.Home", name: "Home")
        let siriLauncher = try record("com.apple.siri.launcher", name: "Siri",
                                      directoryPath: "/System/Applications", isMissing: false,
                                      isUIElement: true)
        let continuity = try record("com.apple.ScreenContinuity", name: "iPhone Mirroring")
        let siriAI = try record("com.apple.campo", name: "Siri AI",
                                directoryPath: "/System/Applications", isUIElement: true)
        let model = ClassicalLayoutModel(store: nil)

        let pages = model.pages(for: [siriAI, continuity, siriLauncher, home], capacity: 35)

        XCTAssertEqual(pages.flatMap { $0.compactMap(\.record?.id) },
                       [home.id, siriLauncher.id, continuity.id],
                       "Only the template Siri launcher appears, between Home and iPhone Mirroring")
    }

    @MainActor
    func testUnknownSiriLauncherAvailabilityStillHidesGraySiri() throws {
        let siriLauncher = try record("com.apple.siri.launcher", name: "Siri",
                                      directoryPath: "/System/Applications", isUIElement: true)
        let siriAI = try record("com.apple.campo", name: "Siri AI",
                                directoryPath: "/System/Applications", isUIElement: true)
        let model = ClassicalLayoutModel(store: nil)

        let pages = model.pages(for: [siriAI, siriLauncher], capacity: 35)

        XCTAssertEqual(pages.flatMap { $0.compactMap(\.record?.id) }, [siriLauncher.id],
                       "Unknown missing status during startup must not display duplicate Siri apps")
    }

    @MainActor
    func testUnavailableSiriLauncherLeavesGraySiriVisible() throws {
        let siriAI = try record("com.apple.campo", name: "Siri AI",
                                directoryPath: "/System/Applications", isUIElement: true)
        for (isMissing, isOnline) in [(true, true), (false, false)] {
            let siriLauncher = try record("com.apple.siri.launcher", name: "Siri",
                                          directoryPath: "/System/Applications", isMissing: isMissing,
                                          isUIElement: true, isOnline: isOnline)
            let model = ClassicalLayoutModel(store: nil)

            let pages = model.pages(for: [siriAI, siriLauncher], capacity: 35)

            XCTAssertTrue(pages.flatMap { $0.compactMap(\.record?.id) }.contains(siriAI.id),
                          "A missing or offline launcher cannot hide the available gray Siri app")
        }
    }

    @MainActor
    func testSavedGraySiriRemainsStoredButIsHiddenWhenColorfulSiriIsAvailable() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let siriLauncher = try record("com.apple.siri.launcher", name: "Siri",
                                      directoryPath: "/System/Applications", isMissing: false,
                                      isUIElement: true)
        let siriAI = try record("com.apple.campo", name: "Siri AI",
                                directoryPath: "/System/Applications", isUIElement: true)
        let saved = try ClassicalLayout(pages: [[.app(siriAI.id), .app(siriLauncher.id)]])
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(saved)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        // The first presentation records where each held application is; the arrangement is unchanged.
        var expected = saved
        expected.rememberApplications([siriAI, siriLauncher])

        let pages = model.pages(for: [siriAI, siriLauncher], capacity: 35)
        await model.flush()

        XCTAssertEqual(pages.flatMap { $0.compactMap(\.record?.id) }, [siriLauncher.id])
        XCTAssertEqual(model.layout, expected, "Presentation filtering must keep the saved layout as user data")
        let persisted = try await store.load()
        XCTAssertEqual(persisted, expected)
    }

    @MainActor
    func testEditingVisibleSiriDoesNotDiscardSavedGraySiri() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let siriLauncher = try record("com.apple.siri.launcher", name: "Siri",
                                      directoryPath: "/System/Applications", isMissing: false,
                                      isUIElement: true)
        let siriAI = try record("com.apple.campo", name: "Siri AI",
                                directoryPath: "/System/Applications", isUIElement: true)
        let saved = try ClassicalLayout(pages: [[.app(siriAI.id), .app(siriLauncher.id)]])
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(saved)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        _ = model.pages(for: [siriAI, siriLauncher], capacity: 35)

        model.commit(try ClassicalLayout(pages: [[.app(siriLauncher.id)]]))
        await model.flush()

        XCTAssertEqual(Set(model.layout?.identities ?? []), Set([siriAI.id, siriLauncher.id]),
                       "A visible-page edit must not delete a hidden system app from saved user data")
        let persisted = try await store.load()
        XCTAssertEqual(Set(persisted?.identities ?? []), Set([siriAI.id, siriLauncher.id]))
        let pages = model.pages(for: [siriAI, siriLauncher], capacity: 35)
        XCTAssertEqual(pages.flatMap { $0.compactMap(\.record?.id) }, [siriLauncher.id])
    }

    @MainActor
    func testFolderDragKeepsHiddenGraySiriInSavedFolder() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let siriLauncher = try record("com.apple.siri.launcher", name: "Siri",
                                      directoryPath: "/System/Applications", isMissing: false,
                                      isUIElement: true)
        let siriAI = try record("com.apple.campo", name: "Siri AI",
                                directoryPath: "/System/Applications", isUIElement: true)
        let folder = ClassicalLayoutFolder(title: "Utilities", pages: [[siriAI.id]])
        let saved = try ClassicalLayout(pages: [[.folder(folder), .app(siriLauncher.id)]])
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(saved)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        _ = model.pages(for: [siriAI, siriLauncher], capacity: 35)

        model.commitFolderDrag(try ClassicalLayout(pages: [[.app(siriLauncher.id)]]))
        await model.flush()

        XCTAssertEqual(model.layout?.folder(folder.id)?.pages, [[siriAI.id]])
        let persisted = try await store.load()
        XCTAssertEqual(persisted?.folder(folder.id)?.pages, [[siriAI.id]])
    }
}
