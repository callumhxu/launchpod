import Foundation
import XCTest
@testable import Launchpod

/// The main-actor owner of the saved Classical arrangement: loading, reconciling with the catalog,
/// committing finished edits and saving them.
final class ClassicalLayoutModelTests: XCTestCase {
    private let ids = (0..<12).map { _ in AppIdentity() }

    private func layout(_ pages: [[Int]]) throws -> ClassicalLayout {
        try ClassicalLayout(pages: pages.map { $0.map { ids[$0] } })
    }

    @MainActor
    func testExportedLayoutCanRestoreFoldersAndOrderAfterImportAndRestart() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        var original = try layout([[0, 1, 2]])
        _ = original.makeFolder(target: ids[0], dragged: ids[1], title: "Work")
        try await store.save(original)
        let model = ClassicalLayoutModel(store: store)
        await model.load()

        let exported = try await model.exportData()
        let replacement = try layout([[2, 1, 0]])
        try await model.importData(JSONEncoder().encode(replacement))
        XCTAssertEqual(model.layout, replacement)
        let importedReplacement = try await store.load()
        XCTAssertEqual(importedReplacement, replacement)

        try await model.importData(exported)
        XCTAssertEqual(model.layout, original)
        let restoredOriginal = try await store.load()
        XCTAssertEqual(restoredOriginal, original)
        let restarted = ClassicalLayoutModel(store: store)
        await restarted.load()
        XCTAssertEqual(restarted.layout, original)
    }

    @MainActor
    func testInvalidImportLeavesTheCurrentLayoutAndSavedFileUntouched() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let original = try layout([[0, 1]])
        try await store.save(original)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        let savedBytes = try Data(contentsOf: store.fileURL)
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: savedBytes) as? [String: Any])
        var pages = try XCTUnwrap(document["pages"] as? [[Any]])
        let firstItem = try XCTUnwrap(pages.first?.first)
        pages[0] = [firstItem, firstItem]
        document["pages"] = pages
        let invalid = try JSONSerialization.data(withJSONObject: document)

        do {
            try await model.importData(invalid)
            XCTFail("An import with one app in two slots must be rejected.")
        } catch {}

        XCTAssertEqual(model.layout, original)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), savedBytes)
        let persisted = try await store.load()
        XCTAssertEqual(persisted, original)
    }

    @MainActor
    func testFailedLayoutLoadPreservesDamagedPrimaryUntilExplicitRecovery() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let invalidPrimary = Data("invalid primary layout".utf8)
        try invalidPrimary.write(to: store.fileURL)
        let model = ClassicalLayoutModel(store: store)
        var errors: [Error] = []
        model.onError = { errors.append($0) }

        await model.load()
        XCTAssertEqual(errors.count, 1)
        XCTAssertFalse(model.isLoaded)
        XCTAssertNil(model.layout)
        let first = try record(ids[0], name: "Alpha", directory: "/Applications", online: true)
        let second = try record(ids[1], name: "Bravo", directory: "/Applications", online: true)
        let preview = model.pages(for: [second, first], capacity: 3)
        XCTAssertEqual(preview.flatMap { $0.compactMap(\.record?.id) }, [first.id, second.id])
        model.commit(try layout([[1, 0]]))
        model.commitFolderDrag(try layout([[1, 0]]))
        model.excludeDeleted(first.id)
        XCTAssertNil(model.renameFolder(ClassicalLayoutFolder.ID(), to: "Work"))
        await model.flush()

        XCTAssertNil(model.layout)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), invalidPrimary)
        let imported = try layout([[1, 0]])
        try await model.importData(JSONEncoder().encode(imported))
        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.layout, imported)
        let restored = try await store.load()
        XCTAssertEqual(restored, imported)
    }

    @MainActor
    func testResetRemovesTheSavedLayoutAndRebuildsTheSystemOrder() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(try layout([[1, 0]]))
        let model = ClassicalLayoutModel(store: store)
        await model.load()

        try await model.resetToSystemLayout()

        XCTAssertNil(model.layout)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        let cleared = try await store.load()
        XCTAssertNil(cleared)
        let safari = try systemRecord(ids[0], bundleID: "com.apple.Safari", name: "Safari")
        let calculator = try systemRecord(ids[1], bundleID: "com.apple.calculator", name: "Calculator")
        let pages = model.pages(for: [calculator, safari], capacity: 4)
        XCTAssertEqual(pages.map { $0.compactMap(\.record?.id) }, [[safari.id, calculator.id]])
        await model.flush()
        let rebuilt = try await store.load()
        XCTAssertEqual(rebuilt?.pages, [[.app(safari.id), .app(calculator.id)]])
    }

    @MainActor
    func testNewAppsWithEqualDockTitlesFollowCatalogOrderWithoutMovingSavedSlots() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let saved = try layout([[0]])
        try await store.save(saved)
        let existing = try record(ids[0], name: "Existing", directory: "/Applications", online: true)
        let firstNew = try record(ids[1], name: "App01", directory: "/Applications", online: true)
        let secondNew = try record(ids[2], name: "App1", directory: "/Applications", online: true)
        let model = ClassicalLayoutModel(store: store)
        await model.load()

        _ = model.pages(for: [firstNew, secondNew, existing], capacity: 3)

        XCTAssertEqual(model.layout?.pages, [[.app(existing.id), .app(firstNew.id), .app(secondNew.id)]],
                       "Equal Dock titles retain catalog order while the saved slot stays first")
    }

    @MainActor
    func testOfflineExternalAppKeepsItsSavedSlotAfterReloadAndReconnect() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let volume = try fixture.directory("ExternalVolume")
        let applications = volume.appending(path: "Applications", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        _ = try fixture.application("Studio.app", in: applications, identifier: "com.example.Studio")
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: applications))
        let catalog = ApplicationCatalog(directories: [directory], scanner: ApplicationScanner())
        let onlineUpdate = await catalog.refresh()
        let online = try XCTUnwrap(onlineUpdate.records.first)
        let order = [[ids[0], online.id, ids[2]]]
        let initial = try ClassicalLayout(pages: order)
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(initial)
        let first = try record(ids[0], name: "Calendar", directory: "/Applications", online: true)
        let last = try record(ids[2], name: "Notes", directory: "/Applications", online: true)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        XCTAssertEqual(model.pages(for: [last, online, first], capacity: 3).map { $0.compactMap(\.record?.id) }, order)

        try FileManager.default.removeItem(at: applications)
        let offlineUpdate = await catalog.refresh()
        let offline = try XCTUnwrap(offlineUpdate.records.first)
        XCTAssertEqual(offline.id, online.id)
        XCTAssertEqual(offline.source.isOnline, false)
        XCTAssertNil(offline.isMissing, "An offline volume leaves application absence unknown")
        let disconnected = model.pages(for: [last, first, offline], capacity: 3)
        XCTAssertEqual(disconnected.map { $0.compactMap(\.record?.id) }, order)
        XCTAssertEqual(disconnected[0][1].record?.source.isOnline, false)

        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        _ = try fixture.application("Studio.app", in: applications, identifier: "com.example.Studio")
        let restoredUpdate = await catalog.refresh()
        let restored = try XCTUnwrap(restoredUpdate.records.first)
        XCTAssertEqual(restored.id, online.id)
        let reloaded = ClassicalLayoutModel(store: store)
        await reloaded.load()
        let reconnected = reloaded.pages(for: [restored, last, first], capacity: 3)
        XCTAssertEqual(reconnected.map { $0.compactMap(\.record?.id) }, order)
        XCTAssertEqual(reconnected[0][1].record?.source.isOnline, true)
    }

    @MainActor
    func testConfirmedDeletionStaysExcludedThroughMissingObservationAndReloadUntilReinstalled() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(try layout([[0, 1, 2]]))
        let first = try record(ids[0], name: "Calendar", directory: "/Applications", online: true)
        let deleted = try record(ids[1], name: "Studio", directory: "/Applications", online: true)
        let last = try record(ids[2], name: "Notes", directory: "/Applications", online: true)
        let model = ClassicalLayoutModel(store: store)
        await model.load()

        model.excludeDeleted(deleted.id)
        XCTAssertEqual(model.pages(for: [first, deleted, last], capacity: 3).map { $0.compactMap(\.record?.id) },
                       [[first.id, last.id]], "A stale catalog snapshot cannot restore the just-deleted app")
        var missing = deleted
        missing.isMissing = true
        XCTAssertEqual(model.pages(for: [first, missing, last], capacity: 3).map { $0.compactMap(\.record?.id) },
                       [[first.id, last.id]])
        try await waitUntil {
            let saved = try await store.load()
            return saved?.excludedObservedAbsentIDs.contains(deleted.id) == true
        }

        let reloaded = ClassicalLayoutModel(store: store)
        await reloaded.load()
        XCTAssertEqual(reloaded.pages(for: [first, missing, last], capacity: 3).map { $0.compactMap(\.record?.id) },
                       [[first.id, last.id]], "A confirmed deletion must not return as a question-mark item after restart")
        var reinstalled = deleted
        reinstalled.isMissing = false
        XCTAssertEqual(reloaded.pages(for: [first, reinstalled, last], capacity: 3).map { $0.compactMap(\.record?.id) },
                       [[first.id, last.id, deleted.id]], "A newly observed installation can enter the layout again")
    }

    @MainActor
    func testDragCommitPreservesADeletedAppsExclusionThroughRefreshAndReload() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(try layout([[0, 1, 2, 3]]))
        let first = try record(ids[0], name: "Calendar", directory: "/Applications", online: true)
        let deleted = try record(ids[1], name: "Studio", directory: "/Applications", online: true)
        let last = try record(ids[2], name: "Notes", directory: "/Applications", online: true)
        let moved = try record(ids[3], name: "Maps", directory: "/Applications", online: true)
        let model = ClassicalLayoutModel(store: store)
        await model.load()

        model.excludeDeleted(deleted.id)
        model.commit(try ClassicalLayout(pages: [[moved.id, first.id, last.id]]))
        XCTAssertEqual(model.pages(for: [first, deleted, last, moved], capacity: 4).map { $0.compactMap(\.record?.id) },
                       [[moved.id, first.id, last.id]], "The drag must not restore a just-deleted app")
        var missing = deleted
        missing.isMissing = true
        XCTAssertEqual(model.pages(for: [first, missing, last, moved], capacity: 4).map { $0.compactMap(\.record?.id) },
                       [[moved.id, first.id, last.id]])
        try await waitUntil {
            let saved = try await store.load()
            return saved?.excludedObservedAbsentIDs.contains(deleted.id) == true
        }

        let reloaded = ClassicalLayoutModel(store: store)
        await reloaded.load()
        XCTAssertEqual(reloaded.pages(for: [first, missing, last, moved], capacity: 4).map { $0.compactMap(\.record?.id) },
                       [[moved.id, first.id, last.id]], "The saved drag order must retain the deletion exclusion")
        var reinstalled = deleted
        reinstalled.isMissing = false
        XCTAssertEqual(reloaded.pages(for: [first, reinstalled, last, moved], capacity: 4).map { $0.compactMap(\.record?.id) },
                       [[moved.id, first.id, last.id, deleted.id]])
    }

    /// Step 15: a drop's commit is saved only after loading, and `flush()` returns only once every
    /// save started so far has reached the store, so a quit can wait for the last drop.
    @MainActor
    func testFlushWaitsForEveryCommittedArrangementToBeSaved() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let writes = WriteLog()
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory),
                                         write: { data, url in
            Thread.sleep(forTimeInterval: 0.05)
            try data.write(to: url, options: .atomic)
            writes.append(url.lastPathComponent)
        })
        let model = ClassicalLayoutModel(store: store)
        model.commit(try layout([[0, 1]]))
        await model.flush()
        let unloaded = try await store.load()
        XCTAssertNil(unloaded, "Nothing is saved before the saved layout has loaded")

        await model.load()
        model.commit(try layout([[1, 0]]))
        model.commit(try layout([[1], [0]]))
        await model.flush()

        XCTAssertEqual(writes.primaryCount, 2)
        let saved = try await store.load()
        XCTAssertEqual(saved?.pages, try layout([[1], [0]]).pages, "The last committed drop is on disk")
    }

    @MainActor
    func testResetWaitsForPendingSaveWithoutAcceptingAConcurrentCatalogRewrite() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let writer = PausingLayoutWriter()
        defer { writer.release() }
        let store = ClassicalLayoutStore(
            directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory),
            write: { data, url in try writer.write(data, to: url) }
        )
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        let arranged = try layout([[0, 1]])
        model.commit(arranged)
        try await waitUntil { writer.isBlocked }

        var resetStarted = false
        let reset = Task { @MainActor in
            resetStarted = true
            try await model.resetToSystemLayout()
        }
        try await waitUntil { resetStarted }
        let records = try [record(ids[0], name: "Alpha", directory: "/Applications", online: true),
                           record(ids[1], name: "Bravo", directory: "/Applications", online: true),
                           record(ids[2], name: "Charlie", directory: "/Applications", online: true)]
        let visible = model.pages(for: records, capacity: 4)
        XCTAssertEqual(visible.flatMap { $0.compactMap(\.record?.id) }, [ids[0], ids[1], ids[2]])
        XCTAssertEqual(model.layout, arranged, "Catalog refresh must not queue a stale save during reset.")

        writer.release()
        try await reset.value
        await model.flush()
        XCTAssertNil(model.layout)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    // MARK: Folders

    private func slots(_ layout: ClassicalLayout?) -> [[ClassicalLayoutTestSlot]]? {
        layout.map { ClassicalLayoutTestSlot.pages(of: $0, ids: ids) }
    }

    /// Calendar 0, Studio 1, Notes 2 and Maps 3, the folder `Work` holding [[0, 1, 2]] before Maps.
    private func savedFolder(in store: ClassicalLayoutStore) async throws -> [AppRecord] {
        var arrangement = try layout([[0, 1, 2, 3]])
        let work = arrangement.makeFolder(target: ids[0], dragged: ids[1], title: "Work")
        arrangement.insert(ids[2], intoFolder: work, capacity: 4)
        try await store.save(arrangement)
        return try zip([0, 1, 2, 3], ["Calendar", "Studio", "Notes", "Maps"]).map {
            try record(ids[$0], name: $1, directory: "/Applications", online: true)
        }
    }

    @MainActor
    func testOfflineAppKeepsItsFolderSlot() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        var records = try await savedFolder(in: store)
        records[1] = try record(ids[1], name: "Studio", directory: "/Volumes/External/Applications", online: false)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        _ = model.pages(for: records, capacity: 4)
        XCTAssertEqual(slots(model.layout), [[.folder("Work", [[0, 1, 2]]), 3]],
                       "An app on an offline volume keeps its folder slot")
    }

    @MainActor
    func testConfirmedDeletionInsideAFolderStaysExcludedAfterReload() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let records = try await savedFolder(in: store)
        let model = ClassicalLayoutModel(store: store)
        await model.load()

        model.excludeDeleted(ids[1])
        _ = model.pages(for: records, capacity: 4)
        XCTAssertEqual(slots(model.layout), [[.folder("Work", [[0, 2]]), 3]],
                       "A stale catalog snapshot cannot restore the just-deleted app to its folder")
        var missing = records
        missing[1].isMissing = true
        _ = model.pages(for: missing, capacity: 4)
        try await waitUntil {
            let saved = try await store.load()
            return saved?.excludedObservedAbsentIDs.contains(self.ids[1]) == true
        }

        let reloaded = ClassicalLayoutModel(store: store)
        await reloaded.load()
        _ = reloaded.pages(for: missing, capacity: 4)
        XCTAssertEqual(slots(reloaded.layout), [[.folder("Work", [[0, 2]]), 3]],
                       "A confirmed deletion does not return to the folder after restart")
        var reinstalled = records
        reinstalled[1].isMissing = false
        _ = reloaded.pages(for: reinstalled, capacity: 4)
        XCTAssertEqual(slots(reloaded.layout), [[.folder("Work", [[0, 2]]), 3, 1]],
                       "A reinstalled app returns to the first free root slot, not its old folder")
    }

    @MainActor
    func testCommittedFolderArrangementDoesNotRestoreADeletedApp() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let records = try await savedFolder(in: store)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        _ = model.pages(for: records, capacity: 4)
        let stale = try XCTUnwrap(model.layout)

        model.excludeDeleted(ids[1])
        var dropped = stale
        dropped.move(ids[3], toRootPage: 0, index: 0)
        model.commit(dropped)
        XCTAssertEqual(slots(model.layout), [[3, .folder("Work", [[0, 2]])]],
                       "A drop prepared before the deletion must not put the app back into its folder")
        await model.flush()
        let saved = try await store.load()
        XCTAssertEqual(slots(saved), [[3, .folder("Work", [[0, 2]])]])
    }

    @MainActor
    func testFolderDragOutPersistsTheNewRootSlotAndRemainingMembership() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let records = try await savedFolder(in: store)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        _ = model.pages(for: records, capacity: 4)
        var dropped = try XCTUnwrap(model.layout)
        let folderID = try XCTUnwrap(dropped.folders.first?.id)

        dropped.move(ids[1], toRootPage: 0, index: 1)
        model.commitFolderDrag(dropped)

        XCTAssertEqual(slots(model.layout), [[.folder("Work", [[0, 2]]), 1, 3]],
                       "Dragging a member out leaves it at the root without restoring it to the folder")
        XCTAssertEqual(model.layout?.pages.first?[1], .app(ids[1]))
        XCTAssertEqual(model.layout?.folder(folderID)?.pages, [[ids[0], ids[2]]])
        await model.flush()
        let reloaded = ClassicalLayoutModel(store: store)
        await reloaded.load()
        XCTAssertEqual(slots(reloaded.layout), [[.folder("Work", [[0, 2]]), 1, 3]],
                       "The changed membership and root order survive a reload")
    }

    // MARK: Committing arrangements presented with folders as single slots

    /// Until folders have their own presentation, a folder is shown through one of its apps, so a
    /// committed arrangement names folder members instead of folders. Saving must never lose or
    /// reorder folder data.
    @MainActor
    private func committing(_ pages: [[Int]], saved expected: [[ClassicalLayoutTestSlot]],
                            _ message: String) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let records = try await savedFolder(in: store)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        _ = model.pages(for: records, capacity: 4)

        model.commit(try layout(pages))
        XCTAssertEqual(slots(model.layout), expected, message)
        await model.flush()
        let reloaded = ClassicalLayoutModel(store: store)
        await reloaded.load()
        XCTAssertEqual(slots(reloaded.layout), expected, "\(message) (after reload)")
    }

    @MainActor
    func testFolderShownByItsFirstAppMovesAsAWholeFolder() async throws {
        try await committing([[3, 0]], saved: [[3, .folder("Work", [[0, 1, 2]])]],
                             "The folder moves with the app that presents it")
    }

    @MainActor
    func testAnyFolderMemberStandsForItsFolderWithoutReorderingIt() async throws {
        try await committing([[3, 1]], saved: [[3, .folder("Work", [[0, 1, 2]])]],
                             "A later member names the folder's slot")
        try await committing([[2, 3, 0]], saved: [[.folder("Work", [[0, 1, 2]]), 3]],
                             "Only the first member names the slot; the folder's own order is kept")
    }

    @MainActor
    func testFolderMissingFromTheArrangementKeepsItsOldSlot() async throws {
        try await committing([[3]], saved: [[.folder("Work", [[0, 1, 2]]), 3]],
                             "A folder the arrangement does not mention is not lost")
    }

    @MainActor
    func testArrangementThatCannotBeCombinedWithTheFoldersIsReportedAndNotSaved() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let writes = WriteLog()
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory),
                                         write: { data, url in
            try data.write(to: url, options: .atomic)
            writes.append(url.lastPathComponent)
        })
        let records = try await savedFolder(in: store)
        let model = ClassicalLayoutModel(store: store)
        var errors: [Error] = []
        model.onError = { errors.append($0) }
        await model.load()
        _ = model.pages(for: records, capacity: 4)
        await model.flush()
        let before = model.layout
        let written = writes.primaryCount

        // A different folder claiming an app of the saved folder would place that app twice.
        var conflicting = try layout([[0, 3]])
        conflicting.makeFolder(target: ids[0], dragged: ids[3], title: "Games")
        model.commit(conflicting)
        await model.flush()

        XCTAssertEqual(errors.count, 1, "The rejected commit is reported")
        XCTAssertEqual(model.layout, before, "The layout is unchanged")
        XCTAssertEqual(writes.primaryCount, written, "Nothing is saved")
        let saved = try await store.load()
        XCTAssertEqual(slots(saved), [[.folder("Work", [[0, 1, 2]]), 3]])
    }

    /// Root pages show a folder as one item with its title and the applications the catalog knows,
    /// in folder order.
    @MainActor
    func testPagesPresentAFolderAsOneItem() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let records = try await savedFolder(in: store)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        let pages = model.pages(for: records, capacity: 4)
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.first?.count, 2)
        let folder = try XCTUnwrap(pages.first?.first?.folder)
        XCTAssertEqual(folder.title, "Work")
        XCTAssertEqual(folder.pages.map { $0.map(\.id) }, [[ids[0], ids[1], ids[2]]])
        XCTAssertEqual(pages.first?.last?.record?.id, ids[3])
        XCTAssertEqual(pages.first?.first?.records.map(\.id), [ids[0], ids[1], ids[2]])
    }

    /// A committed folder item keeps its saved title and pages, even when the presentation that
    /// produced it showed an older title or fewer applications.
    @MainActor
    func testCommittedFolderItemKeepsItsSavedContents() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let records = try await savedFolder(in: store)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        let shown = model.pages(for: records, capacity: 4)
        var folder = try XCTUnwrap(shown.first?.first?.folder)
        folder.title = "Older"
        folder.pages = [[records[0], records[2]]]
        model.commit(try ClassicalLayout(pages: [[ClassicalPageItem.app(records[3]).layoutItem,
                                                  ClassicalPageItem.folder(folder).layoutItem]]))
        XCTAssertEqual(slots(model.layout), [[3, .folder("Work", [[0, 1, 2]])]])
        await model.flush()
        let reloaded = ClassicalLayoutModel(store: store)
        await reloaded.load()
        XCTAssertEqual(slots(reloaded.layout), [[3, .folder("Work", [[0, 1, 2]])]])
    }

    /// A drag into a full five-row folder starts another folder page, and the page break and
    /// member order survive the model's commit and a fresh load from disk.
    @MainActor
    func testFolderDragOverflowPersistsThirtyFiveThenOne() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let members = (0..<36).map { _ in AppIdentity() }
        let folderID = ClassicalLayoutFolder.ID()
        let folder = ClassicalLayoutFolder(id: folderID, title: "Work", pages: [Array(members.prefix(35))])
        let saved = try ClassicalLayout(pages: [[.folder(folder), .app(members[35])]])
        try await store.save(saved)
        let model = ClassicalLayoutModel(store: store)
        await model.load()

        var dragged = saved
        XCTAssertTrue(dragged.insert(members[35], intoFolder: folderID, capacity: 35))
        model.commitFolderDrag(dragged)
        await model.flush()

        let diskLayout = try await store.load()
        let persisted = try XCTUnwrap(diskLayout?.folder(folderID))
        XCTAssertEqual(persisted.pages.map(\.count), [35, 1])
        XCTAssertEqual(persisted.identities, members)
        let reloaded = ClassicalLayoutModel(store: store)
        await reloaded.load()
        XCTAssertEqual(reloaded.layout?.folder(folderID)?.pages, persisted.pages)
        XCTAssertEqual(reloaded.layout?.pages.map(\.count), [1], "The drag changes only folder paging")
    }

    @MainActor
    func testRenamingAFolderSavesAnyNonEmptyTitle() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let records = try await savedFolder(in: store)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        _ = model.pages(for: records, capacity: 4)
        let id = try XCTUnwrap(model.layout?.folders.first?.id)
        model.renameFolder(id, to: "Projects")
        model.renameFolder(id, to: "")
        await model.flush()
        let reloaded = ClassicalLayoutModel(store: store)
        await reloaded.load()
        XCTAssertEqual(slots(reloaded.layout), [[.folder("Projects", [[0, 1, 2]]), 3]], "An empty title is not saved")

        _ = reloaded.pages(for: records, capacity: 4)
        reloaded.renameFolder(id, to: "   ")
        await reloaded.flush()
        let spaced = ClassicalLayoutModel(store: store)
        await spaced.load()
        XCTAssertEqual(slots(spaced.layout), [[.folder("   ", [[0, 1, 2]]), 3]], "A title of spaces is saved and reloads")
    }

    private func record(_ id: AppIdentity, name: String, directory: String, online: Bool) throws -> AppRecord {
        let directoryURL = URL(filePath: directory, directoryHint: .isDirectory)
        let bundleURL = directoryURL.appending(path: "\(name).app", directoryHint: .isDirectory)
        return AppRecord(
            id: id,
            metadata: try AppMetadata(bundleIdentifier: "com.example.\(name)", bundleURL: bundleURL,
                                      displayName: name, version: nil, buildVersion: nil, contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: directoryURL, isOnline: online)
        )
    }

    private func systemRecord(_ id: AppIdentity, bundleID: String, name: String) throws -> AppRecord {
        let directory = URL(filePath: "/Applications", directoryHint: .isDirectory)
        return AppRecord(
            id: id,
            metadata: try AppMetadata(bundleIdentifier: bundleID,
                                      bundleURL: directory.appending(path: "\(name).app", directoryHint: .isDirectory),
                                      displayName: name, version: nil, buildVersion: nil, contentModificationDate: nil),
            source: try AppSource(kind: .system, directoryURL: directory, isOnline: true)
        )
    }

    @MainActor
    private func waitUntil(_ condition: @escaping @MainActor () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        let fulfilled = try await condition()
        XCTAssertTrue(fulfilled, "Timed out waiting for the saved layout")
    }
}

/// The files the store wrote, in order.
private nonisolated final class WriteLog: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    func append(_ name: String) { lock.withLock { names.append(name) } }
    var primaryCount: Int { lock.withLock { names.filter { $0 == "layout.json" }.count } }
}

private nonisolated final class PausingLayoutWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let resume = DispatchSemaphore(value: 0)
    private var blocked = false
    private var released = false

    var isBlocked: Bool { lock.withLock { blocked } }

    func write(_ data: Data, to url: URL) throws {
        let shouldPause = lock.withLock { () -> Bool in
            guard url.lastPathComponent == "layout.json", !blocked else { return false }
            blocked = true
            return true
        }
        if shouldPause { resume.wait() }
        try data.write(to: url, options: .atomic)
    }

    func release() {
        let shouldResume = lock.withLock { () -> Bool in
            guard !released else { return false }
            released = true
            return true
        }
        if shouldResume { resume.signal() }
    }
}
