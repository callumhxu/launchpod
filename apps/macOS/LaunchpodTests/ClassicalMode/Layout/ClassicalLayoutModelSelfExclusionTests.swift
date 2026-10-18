import Foundation
import XCTest
@testable import Launchpod

final class ClassicalLayoutModelSelfExclusionTests: XCTestCase {
    @MainActor
    func testSavedRootAndFolderPositionsSurvivePresentationEditAndReload() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let rootSelf = try record(bundleID: "app.joyx.launchpod", path: "/Applications/Launchpod.app")
        let folderSelf = try record(bundleID: "app.joyx.launchpod", path: "/Volumes/Other/Launchpod.app")
        let secondFolderSelf = try record(bundleID: "app.joyx.launchpod", path: "/Volumes/Copy/Launchpod.app")
        let first = try record(bundleID: "com.example.first", path: "/Applications/First.app")
        let second = try record(bundleID: "com.example.second", path: "/Applications/Second.app")
        let third = try record(bundleID: "com.example.third", path: "/Applications/Third.app")
        let folder = ClassicalLayoutFolder(id: .init(), title: "Work",
                                           pages: [[folderSelf.id, second.id, secondFolderSelf.id, third.id]])
        let saved = try ClassicalLayout(pages: [[.app(rootSelf.id), .app(first.id), .folder(folder)]])
        try await store.save(saved)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        let hidden = Set([rootSelf.id, folderSelf.id, secondFolderSelf.id])
        let records = [rootSelf, folderSelf, secondFolderSelf, first, second, third]

        let visible = model.pages(for: records, hiding: hidden, capacity: 8)
        XCTAssertEqual(visible.flatMap { $0.flatMap(\.records) }.map(\.id), [first.id, second.id, third.id])
        var expected = saved
        expected.rememberApplications(records)
        XCTAssertEqual(model.layout, expected, "A refresh keeps the complete user arrangement")

        let edited = try ClassicalLayout(pages: [visible.flatMap { $0.map(\.layoutItem) }.reversed()])
        model.commit(edited)
        let refreshed = model.pages(for: records, hiding: hidden, capacity: 8)
        XCTAssertEqual(refreshed.flatMap { $0.flatMap(\.records) }.map(\.id), [second.id, third.id, first.id])
        var dragged = try ClassicalLayout(pages: [refreshed.flatMap { $0.map(\.layoutItem) }])
        dragged.move(second.id, toRootPage: 0, index: 1)
        model.commitFolderDrag(dragged)
        await model.flush()
        let reloaded = ClassicalLayoutModel(store: store)
        await reloaded.load()
        let reloadedPages = reloaded.pages(for: records, hiding: hidden, capacity: 8)

        XCTAssertEqual(reloadedPages.flatMap { $0.flatMap(\.records) }.map(\.id), [third.id, second.id, first.id])
        XCTAssertEqual(Set(reloaded.layout?.identities ?? []),
                       [rootSelf.id, folderSelf.id, secondFolderSelf.id, first.id, second.id, third.id])
        XCTAssertEqual(reloaded.layout?.folder(folder.id)?.pages,
                       [[folderSelf.id, secondFolderSelf.id, third.id]],
                       "Both hidden copies keep their folder order when a visible app is dragged out")
        XCTAssertEqual(reloaded.layout?.pages.first?.compactMap(\.app), [rootSelf.id, second.id, first.id])
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
