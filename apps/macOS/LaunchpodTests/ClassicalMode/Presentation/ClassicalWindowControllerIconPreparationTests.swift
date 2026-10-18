import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalWindowControllerIconPreparationTests: XCTestCase {
    func testHiddenCatalogRefreshPreparesNewIconWithoutReopeningOrChangingShownLayout() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let first = try AppIconTestSupport.record(path: "/Applications/First.app",
                                                  identifier: "com.example.hidden-refresh.first")
        let installed = try AppIconTestSupport.record(path: "/Applications/Installed.app",
                                                      identifier: "com.example.hidden-refresh.installed")
        let records = MainActorBox([first])
        var requests: [AppIdentity] = []
        let desktopSize = try AppIconSize(pointSize: CGSize(width: 8, height: 8), backingScale: 1)
        let desktop = try AppIconTestSupport.icon(size: desktopSize).cgImage
        let controller = ClassicalWindowController(desktopImage: { _ in desktop },
                                                   presentError: { XCTFail("Unexpected presentation error: \($0)") },
                                                   hidesDock: { false })
        defer { controller.stop() }
        controller.pageContent = ClassicalPageContent(records: { records.value }, icon: { record, size in
            requests.append(record.id)
            return try AppIconTestSupport.icon(size: size).cgImage
        })

        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await waitUntil { shown && requests.contains(first.id) }
        let panel = try XCTUnwrap(controller.window as? ClassicalPanel)
        let springboard = try XCTUnwrap(panel.launcherContentView.springboard)
        let shownLayout = springboard.pages

        var hidden = false
        controller.setVisible(false) { hidden = $0 }
        try await waitUntil { hidden && !panel.isVisible }
        records.value.append(installed)
        controller.refreshApplications(invalidatingIcons: [installed.id])

        try await waitUntil { requests.contains(installed.id) }
        XCTAssertFalse(panel.isVisible, "Preparing an installed app should not reopen the launcher")
        XCTAssertEqual(springboard.pages, shownLayout,
                       "The hidden refresh should leave the last presented layout untouched")
    }

    func testHiddenInstallReconcilesSavedFolderAndOrderWithoutResettingUserPositions() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let first = try AppIconTestSupport.record(path: "/Applications/First.app", identifier: "com.example.layout.first")
        let memberA = try AppIconTestSupport.record(path: "/Applications/MemberA.app", identifier: "com.example.layout.a")
        let memberB = try AppIconTestSupport.record(path: "/Applications/MemberB.app", identifier: "com.example.layout.b")
        let last = try AppIconTestSupport.record(path: "/Applications/Last.app", identifier: "com.example.layout.last")
        let installed = try AppIconTestSupport.record(path: "/Applications/Installed.app", identifier: "com.example.layout.new")
        let folder = ClassicalLayoutFolder(title: "My Folder", pages: [[memberB.id, memberA.id]])
        let initial = try ClassicalLayout(pages: [[.app(last.id), .folder(folder)], [.app(first.id)]])
        try await store.save(initial)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        let catalog = MainActorBox([first, memberA, last, memberB])
        var requested: [AppIdentity] = []
        let desktopSize = try AppIconSize(pointSize: CGSize(width: 8, height: 8), backingScale: 1)
        let desktop = try AppIconTestSupport.icon(size: desktopSize).cgImage
        let controller = ClassicalWindowController(desktopImage: { _ in desktop },
                                                   presentError: { XCTFail("Unexpected presentation error: \($0)") },
                                                   hidesDock: { false })
        defer { controller.stop() }
        var content = ClassicalPageContent(records: { [] }, icon: { record, size in
            requested.append(record.id)
            return try AppIconTestSupport.icon(size: size).cgImage
        })
        content.pages = { capacity in model.pages(for: catalog.value, capacity: capacity) }
        controller.pageContent = content

        var shown = false
        controller.setVisible(true) { shown = $0 }
        try await waitUntil { shown && requested.contains(last.id) }
        let panel = try XCTUnwrap(controller.window as? ClassicalPanel)
        let springboard = try XCTUnwrap(panel.launcherContentView.springboard)
        let displayed = springboard.pages
        await model.flush()
        XCTAssertEqual(model.layout?.pages, initial.pages)

        var hidden = false
        controller.setVisible(false) { hidden = $0 }
        try await waitUntil { hidden && !panel.isVisible }
        catalog.value.append(installed)
        controller.refreshApplications(invalidatingIcons: [installed.id])
        try await waitUntil { requested.contains(installed.id) }
        await model.flush()

        let saved = try await store.load()
        let persisted = try XCTUnwrap(saved)
        XCTAssertEqual(persisted.pages, [[.app(last.id), .folder(folder), .app(installed.id)], [.app(first.id)]],
                       "A new app fills the first page with space while existing root slots stay in place")
        XCTAssertEqual(persisted.folder(folder.id)?.pages, [[memberB.id, memberA.id]],
                       "The user's folder membership and internal order survive reconciliation")
        XCTAssertEqual(springboard.pages, displayed, "Hidden icon preparation does not rebuild the visible layer model")
        XCTAssertFalse(panel.isVisible)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try XCTUnwrap(condition() ? true : nil, "Timed out waiting for hidden Classical icon preparation")
    }
}
