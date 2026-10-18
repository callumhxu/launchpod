import Foundation
import XCTest
@testable import Launchpod

/// A saved Classical layout follows its applications when the shared app data replaced their
/// identities, for example after the app data was lost while the layout was kept.
final class ClassicalLayoutModelIdentityReplacementTests: XCTestCase {
    /// One application as the catalog describes it, independent of the identity it is given.
    private struct App {
        var bundleID: String
        var name: String
        var directory = "/Applications"
        var category: String?
        var isMissing: Bool?
        var isOnline = true

        func record(_ id: AppIdentity) throws -> AppRecord {
            let directoryURL = URL(filePath: directory, directoryHint: .isDirectory)
            return AppRecord(
                id: id,
                metadata: try AppMetadata(bundleIdentifier: bundleID,
                                          bundleURL: directoryURL.appending(path: "\(name).app", directoryHint: .isDirectory),
                                          displayName: name, version: nil, buildVersion: nil,
                                          categoryIdentifier: category, contentModificationDate: nil),
                source: try AppSource(kind: .custom, directoryURL: URL(filePath: "/Applications", directoryHint: .isDirectory),
                                      isOnline: isOnline),
                isMissing: isMissing
            )
        }
    }

    private func records(_ apps: [App], _ ids: [AppIdentity]) throws -> [AppRecord] {
        try zip(apps, ids).map { try $0.record($1) }
    }

    private func slots(_ layout: ClassicalLayout?, _ ids: [AppIdentity]) -> [[ClassicalLayoutTestSlot]]? {
        layout.map { ClassicalLayoutTestSlot.pages(of: $0, ids: ids) }
    }

    private func store(in fixture: ApplicationDiscoveryTestDirectory,
                       writes: WriteCount? = nil) -> ClassicalLayoutStore {
        ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory)) { data, url in
            try data.write(to: url, options: .atomic)
            if url.lastPathComponent == "layout.json" { writes?.increment() }
        }
    }

    /// The first run arranges the apps under one set of identities; the next run's catalog holds the
    /// same apps under entirely new identities. The first-launch folders, every position and the
    /// automatic-layout state survive, and the saved file refers only to the new identities.
    @MainActor
    func testFullIdentityReplacementKeepsFoldersPositionsAndTheAutomaticLayout() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = store(in: fixture)
        let apps = [
            App(bundleID: "com.apple.Safari", name: "Safari"),
            App(bundleID: "com.apple.Terminal", name: "Terminal", directory: "/System/Applications/Utilities"),
            App(bundleID: "com.example.Chess", name: "Chess", category: "public.app-category.games", isMissing: false),
            App(bundleID: "com.example.Tool", name: "Tool", directory: "/Applications/Utilities"),
            App(bundleID: "com.example.Editor", name: "Editor")
        ]
        let before = apps.map { _ in AppIdentity() }
        let first = ClassicalLayoutModel(store: store)
        await first.load()
        _ = first.pages(for: try records(apps, before), capacity: 35)
        await first.flush()
        let firstSaved = try await store.load()
        let arranged = try XCTUnwrap(firstSaved)
        XCTAssertNotNil(arranged.folder(.defaultOther), "The first launch groups the utilities")
        XCTAssertNotNil(arranged.folder(.defaultGames), "The first launch groups the game")
        let markers = try XCTUnwrap(arranged.automaticTemplateBundleIDs)
        XCTAssertFalse(markers.isEmpty)

        let after = apps.map { _ in AppIdentity() }
        let restarted = ClassicalLayoutModel(store: store)
        await restarted.load()
        let pages = restarted.pages(for: try records(apps, after), capacity: 35)
        await restarted.flush()

        let expected = slots(arranged, before)
        XCTAssertEqual(slots(restarted.layout, after), expected)
        XCTAssertEqual(pages.flatMap { $0.flatMap(\.records) }.count, apps.count, "Every application is presented")
        XCTAssertEqual(restarted.layout?.folder(.defaultOther)?.usesDefaultTitle, true)
        let replaced = Dictionary(uniqueKeysWithValues: zip(before, after))
        XCTAssertEqual(restarted.layout?.automaticTemplateBundleIDs,
                       Dictionary(uniqueKeysWithValues: markers.map { (replaced[$0.key]!, $0.value) }),
                       "The layout is still the automatic first-launch layout")
        let saved = try await store.load()
        let persisted = try XCTUnwrap(saved)
        XCTAssertEqual(persisted, restarted.layout)
        XCTAssertEqual(slots(persisted, after), expected)
        XCTAssertTrue(Set(persisted.identities).isDisjoint(with: before))
        XCTAssertEqual(Set(persisted.appReferences.keys), Set(after))
    }

    /// A user folder and root positions carry over; an application the catalog no longer has leaves,
    /// while offline and missing applications the catalog still holds keep their slots.
    @MainActor
    func testReplacedIdentitiesKeepUserFoldersWhileRemovedAppsLeaveAndUnavailableAppsStay() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = store(in: fixture)
        var apps = [
            App(bundleID: "com.example.Editor", name: "Editor"),
            App(bundleID: "com.example.Tool", name: "Tool"),
            App(bundleID: "com.example.Viewer", name: "Viewer"),
            App(bundleID: "com.example.Removed", name: "Removed"),
            App(bundleID: "com.example.Offline", name: "Offline", directory: "/Volumes/External/Applications"),
            App(bundleID: "com.example.Missing", name: "Missing")
        ]
        let before = apps.map { _ in AppIdentity() }
        let work = ClassicalLayoutFolder(title: "Work", pages: [[before[2], before[1]]])
        let saved = try ClassicalLayout(pages: [[.app(before[0]), .folder(work), .app(before[3])],
                                                [.app(before[4]), .app(before[5])]])
        try await store.save(saved)
        let first = ClassicalLayoutModel(store: store)
        await first.load()
        _ = first.pages(for: try records(apps, before), capacity: 3)
        await first.flush()

        // Editor, Tool and Viewer get new identities; Removed is gone; the other two keep theirs.
        apps[4].isOnline = false
        apps[5].isMissing = true
        let after = [AppIdentity(), AppIdentity(), AppIdentity(), AppIdentity(), before[4], before[5]]
        let current = try records(Array(apps[0...2]) + Array(apps[4...5]),
                                  Array(after[0...2]) + Array(after[4...5]))
        let restarted = ClassicalLayoutModel(store: store)
        await restarted.load()
        _ = restarted.pages(for: current, capacity: 3)
        await restarted.flush()

        let expected: [[ClassicalLayoutTestSlot]] = [[0, .folder("Work", [[2, 1]])], [4, 5]]
        XCTAssertEqual(slots(restarted.layout, after), expected)
        XCTAssertNil(restarted.layout?.automaticTemplateBundleIDs, "A user arrangement stays a user arrangement")
        XCTAssertEqual(restarted.layout?.folder(work.id)?.title, "Work")
        let persisted = try await store.load()
        XCTAssertEqual(slots(persisted, after), expected)
        XCTAssertNil(persisted?.appReferences[before[3]], "The removed application is forgotten")
    }

    /// A deletion the user confirmed stays in effect for the application's new identity.
    @MainActor
    func testConfirmedDeletionCarriesOverToTheReplacementIdentity() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = store(in: fixture)
        let apps = [App(bundleID: "com.example.Editor", name: "Editor"),
                    App(bundleID: "com.example.Deleted", name: "Deleted")]
        let before = [AppIdentity(), AppIdentity()]
        try await store.save(try ClassicalLayout(pages: [before]))
        let first = ClassicalLayoutModel(store: store)
        await first.load()
        _ = first.pages(for: try records(apps, before), capacity: 4)
        first.excludeDeleted(before[1])
        // The catalog has not yet observed the deletion.
        _ = first.pages(for: try records(apps, before), capacity: 4)
        await first.flush()

        let after = [AppIdentity(), AppIdentity()]
        let restarted = ClassicalLayoutModel(store: store)
        await restarted.load()
        let pages = restarted.pages(for: try records(apps, after), capacity: 4)
        await restarted.flush()

        XCTAssertEqual(pages.flatMap { $0.flatMap(\.records) }.map(\.id), [after[0]],
                       "The deleted application does not return under its new identity")
        XCTAssertEqual(restarted.layout?.excludedIDs, [after[1]])
        let persisted = try await store.load()
        XCTAssertEqual(persisted?.excludedIDs, [after[1]])
    }

    /// Two catalog applications at the saved bundle and location make the replacement ambiguous, so
    /// the saved slot is not given to either; both arrive as new applications.
    @MainActor
    func testAmbiguousReplacementIsNotApplied() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = store(in: fixture)
        let editor = App(bundleID: "com.example.Editor", name: "Editor")
        let viewer = App(bundleID: "com.example.Viewer", name: "Viewer")
        let before = [AppIdentity(), AppIdentity()]
        try await store.save(try ClassicalLayout(pages: [[before[1], before[0]]]))
        let first = ClassicalLayoutModel(store: store)
        await first.load()
        _ = first.pages(for: try records([editor, viewer], before), capacity: 4)
        await first.flush()

        let copies = [AppIdentity(), AppIdentity()]
        let restarted = ClassicalLayoutModel(store: store)
        await restarted.load()
        _ = restarted.pages(for: try records([viewer, editor, editor], [before[1]] + copies), capacity: 4)

        let layout = try XCTUnwrap(restarted.layout)
        XCTAssertEqual(layout.pages.first?.first, .app(before[1]), "The unchanged application keeps its slot")
        XCTAssertFalse(layout.identities.contains(before[0]))
        XCTAssertEqual(Set(layout.identities.dropFirst()), Set(copies))
    }

    /// References are saved by the first presentation, follow an application that moved, and are
    /// dropped for an application that left the layout. An unchanged catalog saves nothing.
    @MainActor
    func testReferencesAreSavedOnceThenFollowMovesAndForgetRemovedApps() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let writes = WriteCount()
        let store = store(in: fixture, writes: writes)
        var apps = [App(bundleID: "com.example.Editor", name: "Editor"),
                    App(bundleID: "com.example.Viewer", name: "Viewer")]
        let ids = [AppIdentity(), AppIdentity()]
        try await store.save(try ClassicalLayout(pages: [ids]))
        let baseline = writes.value
        let model = ClassicalLayoutModel(store: store)
        await model.load()

        _ = model.pages(for: try records(apps, ids), capacity: 4)
        await model.flush()
        XCTAssertEqual(writes.value, baseline + 1, "The first presentation saves the references once")
        let initial = try await store.load()
        XCTAssertEqual(initial?.appReferences[ids[0]]?.bundleURL, try apps[0].record(ids[0]).metadata.bundleURL)
        _ = model.pages(for: try records(apps, ids), capacity: 4)
        await model.flush()
        XCTAssertEqual(writes.value, baseline + 1, "An unchanged catalog does not save again")

        apps[0].directory = "/Applications/Tools"
        _ = model.pages(for: [try apps[0].record(ids[0])], capacity: 4)
        await model.flush()
        let saved = try await store.load()
        let persisted = try XCTUnwrap(saved)
        XCTAssertEqual(persisted.identities, [ids[0]])
        XCTAssertEqual(persisted.appReferences[ids[0]]?.bundleURL, try apps[0].record(ids[0]).metadata.bundleURL)
        XCTAssertEqual(Set(persisted.appReferences.keys), [ids[0]])
    }
}

/// The number of primary layout files the store wrote.
private nonisolated final class WriteCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
