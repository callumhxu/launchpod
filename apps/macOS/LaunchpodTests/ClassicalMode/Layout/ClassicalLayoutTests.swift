import Foundation
import XCTest
@testable import Launchpod

/// The saved Classical arrangement and its rules.
final class ClassicalLayoutTests: XCTestCase {
    private let ids = (0..<12).map { _ in AppIdentity() }

    private func layout(_ pages: [[Int]]) throws -> ClassicalLayout {
        try ClassicalLayout(pages: pages.map { $0.map { ids[$0] } })
    }

    private func numbers(_ layout: ClassicalLayout) -> [[ClassicalLayoutTestSlot]] {
        ClassicalLayoutTestSlot.pages(of: layout, ids: ids)
    }

    func testFirstLayoutFillsPagesInOrder() {
        let reconciled = ClassicalLayout().reconciled(with: Array(ids.prefix(7)), capacity: 3)
        XCTAssertEqual(numbers(reconciled), [[0, 1, 2], [3, 4, 5], [6]])
    }

    func testRemovedApplicationsLeaveTheirPageWithoutPullingOthersAcross() throws {
        let reconciled = try layout([[0, 1, 2], [3, 4, 5]]).reconciled(with: [0, 2, 3, 4, 5].map { ids[$0] }, capacity: 3)
        XCTAssertEqual(numbers(reconciled), [[0, 2], [3, 4, 5]])
        let emptied = try layout([[0], [3, 4]]).reconciled(with: [3, 4].map { ids[$0] }, capacity: 3)
        XCTAssertEqual(numbers(emptied), [[3, 4]], "Empty pages disappear")
    }

    /// The first page with room, else a new page.
    func testNewApplicationsTakeTheFirstPageWithRoom() throws {
        let reconciled = try layout([[0, 1, 2], [3], [4, 5, 6]])
            .reconciled(with: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map { ids[$0] }, capacity: 3)
        XCTAssertEqual(numbers(reconciled), [[0, 1, 2], [3, 7, 8], [4, 5, 6], [9]])
    }

    /// A smaller grid splits pages into pages inserted after.
    func testSmallerCapacitySplitsPagesIntoFollowingPages() throws {
        let reconciled = try layout([[0, 1, 2, 3, 4], [5, 6]]).reconciled(with: Array(ids.prefix(7)), capacity: 2)
        XCTAssertEqual(numbers(reconciled), [[0, 1], [2, 3], [4], [5, 6]])
    }

    /// The last item moves to the start of the next page.
    func testOverflowCascadesToTheStartOfFollowingPages() throws {
        var arrangement = try layout([[0, 1, 2, 9], [3, 4, 5], [6]])
        arrangement.pushOverflow(from: 0, capacity: 3)
        XCTAssertEqual(numbers(arrangement), [[0, 1, 2], [9, 3, 4], [5, 6]])
        var last = try layout([[0, 1, 9]])
        last.pushOverflow(from: 0, capacity: 2)
        XCTAssertEqual(numbers(last), [[0, 1], [9]])
    }

    func testCodingRoundTripsAndRejectsDuplicates() throws {
        let arrangement = try layout([[0, 1], [2]])
        let data = try JSONEncoder().encode(arrangement)
        XCTAssertEqual(try JSONDecoder().decode(ClassicalLayout.self, from: data), arrangement)
        XCTAssertThrowsError(try ClassicalLayout(pages: [[ids[0]], [ids[0]]]))
        let future = Data(#"{"schemaVersion":2,"pages":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ClassicalLayout.self, from: future))
    }

    func testCurrentSchemaRejectsAnIncompleteFlatLayoutDocument() throws {
        let data = try JSONEncoder().encode(try layout([[0, 1]]))
        let complete = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let requiredKeys = ["schemaVersion", "pages", "excludedIDs", "excludedObservedAbsentIDs", "appReferences"]

        for key in requiredKeys {
            var incomplete = complete
            incomplete[key] = nil
            let encoded = try JSONSerialization.data(withJSONObject: incomplete)
            XCTAssertThrowsError(try JSONDecoder().decode(ClassicalLayout.self, from: encoded),
                                 "The current schemaVersion 1 document requires \(key).")
        }
    }

    // MARK: Folders

    private func folderID(at page: Int, _ index: Int, in layout: ClassicalLayout) throws -> ClassicalLayoutFolder.ID {
        guard case let .folder(folder) = layout.pages[page][index] else {
            XCTFail("No folder at root slot \(page), \(index)")
            throw CocoaError(.coderValueNotFound)
        }
        return folder.id
    }

    /// The new folder holds the target, then the dragged app, in the target's slot; the dragged
    /// app's old slot closes.
    func testMakeFolderReplacesTheTargetWithTargetThenDragged() throws {
        var after = try layout([[0, 1, 2, 3]])
        let id = after.makeFolder(target: ids[1], dragged: ids[3], title: "Utilities")
        XCTAssertEqual(numbers(after), [[0, .folder("Utilities", [[1, 3]]), 2]])
        XCTAssertEqual(try folderID(at: 0, 1, in: after), id, "The returned ID names the new folder")

        var before = try layout([[0, 1, 2, 3]])
        before.makeFolder(target: ids[2], dragged: ids[0], title: "Utilities")
        XCTAssertEqual(numbers(before), [[1, .folder("Utilities", [[2, 0]]), 3]])
    }

    func testMakeFolderTakesTheDraggedAppFromAnotherPage() throws {
        var kept = try layout([[0, 1], [2, 3]])
        kept.makeFolder(target: ids[1], dragged: ids[3], title: "Games")
        XCTAssertEqual(numbers(kept), [[0, .folder("Games", [[1, 3]])], [2]])

        var emptied = try layout([[0, 1], [2]])
        emptied.makeFolder(target: ids[0], dragged: ids[2], title: "Games")
        XCTAssertEqual(numbers(emptied), [[.folder("Games", [[0, 2]]), 1]],
                       "A page the dragged app leaves empty disappears, as empty pages do elsewhere")
    }

    /// The app joins the end of the folder's last page; folder pages hold rows × columns items, like root pages.
    func testInsertAppendsToTheFoldersLastPageAndOpensANewPageWhenFull() throws {
        var arrangement = try layout([[0, 1, 2, 3], [4]])
        let id = arrangement.makeFolder(target: ids[1], dragged: ids[3], title: "Work")
        arrangement.insert(ids[0], intoFolder: id, capacity: 3)
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[1, 3, 0]]), 2], [4]])
        arrangement.insert(ids[4], intoFolder: id, capacity: 3)
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[1, 3, 0], [4]]), 2]],
                       "A full last page gets a new folder page; the emptied root page disappears")
        arrangement.insert(ids[2], intoFolder: id, capacity: 3)
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[1, 3, 0], [4, 2]])]])
    }

    func testMoveTakesAFolderMemberBackToTheRoot() throws {
        var arrangement = try layout([[0, 1, 2, 3]])
        let id = arrangement.makeFolder(target: ids[1], dragged: ids[3], title: "Work")
        arrangement.insert(ids[0], intoFolder: id, capacity: 4)
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[1, 3, 0]]), 2]])
        arrangement.move(ids[3], toRootPage: 0, index: 2)
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[1, 0]]), 2, 3]])
    }

    /// Whether a folder dragged down to one app dissolves is the drag's decision; the model keeps
    /// a single-app folder.
    func testSingleAppFolderStays() throws {
        var arrangement = try layout([[0, 1, 2]])
        let id = arrangement.makeFolder(target: ids[0], dragged: ids[1], title: "Work")
        arrangement.move(ids[1], toRootPage: 0, index: 2)
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[0]]), 2, 1]])
        XCTAssertEqual(try folderID(at: 0, 0, in: arrangement), id)
        let decoded = try JSONDecoder().decode(ClassicalLayout.self, from: JSONEncoder().encode(arrangement))
        XCTAssertEqual(decoded, arrangement, "A single-app folder is valid saved data")
    }

    /// A folder with no apps is deleted together with its pages.
    func testMovingTheLastAppOutRemovesTheFolder() throws {
        var arrangement = try layout([[0, 1, 2]])
        arrangement.makeFolder(target: ids[1], dragged: ids[2], title: "Work")
        arrangement.move(ids[2], toRootPage: 0, index: 0)
        arrangement.move(ids[1], toRootPage: 0, index: 0)
        XCTAssertEqual(numbers(arrangement), [[1, 2, 0]])
        XCTAssertTrue(arrangement.folders.isEmpty)
    }

    /// Dissolving: the last app moves to the folder's slot on the root page.
    func testDissolvePutsTheRemainingAppInTheFoldersSlot() throws {
        var arrangement = try layout([[0, 1, 2, 3]])
        let id = arrangement.makeFolder(target: ids[1], dragged: ids[3], title: "Work")
        arrangement.move(ids[3], toRootPage: 0, index: 3)
        XCTAssertEqual(numbers(arrangement), [[0, .folder("Work", [[1]]), 2, 3]])
        arrangement.dissolve(id)
        XCTAssertEqual(numbers(arrangement), [[0, 1, 2, 3]])
    }

    /// Only an empty title is ignored; a title of whitespace is saved, and there is no duplicate-name check.
    func testRenameIgnoresOnlyEmptyTitlesAndAllowsDuplicates() throws {
        var arrangement = try layout([[0, 1, 2, 3]])
        let first = arrangement.makeFolder(target: ids[0], dragged: ids[1], title: "Utilities")
        let second = arrangement.makeFolder(target: ids[2], dragged: ids[3], title: "Games")
        arrangement.renameFolder(first, to: "Work")
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[0, 1]]), .folder("Games", [[2, 3]])]])
        XCTAssertFalse(arrangement.renameFolder(first, to: ""))
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[0, 1]]), .folder("Games", [[2, 3]])]],
                       "An empty title keeps the old name")
        XCTAssertTrue(arrangement.renameFolder(first, to: "  \n\t "))
        XCTAssertEqual(numbers(arrangement), [[.folder("  \n\t ", [[0, 1]]), .folder("Games", [[2, 3]])]])
        arrangement.renameFolder(second, to: "  \n\t ")
        XCTAssertEqual(numbers(arrangement), [[.folder("  \n\t ", [[0, 1]]), .folder("  \n\t ", [[2, 3]])]])
    }

    /// Dissolving a folder that still holds several apps puts all of them, in page order, where the
    /// folder was; a root page that becomes overfull is left for the caller's overflow step.
    func testDissolveWithSeveralAppsKeepsTheirOrderInTheFoldersSlot() throws {
        var arrangement = try layout([[0, 1, 2, 3], [4]])
        let id = arrangement.makeFolder(target: ids[1], dragged: ids[3], title: "Work")
        arrangement.insert(ids[4], intoFolder: id, capacity: 2)
        XCTAssertEqual(numbers(arrangement), [[0, .folder("Work", [[1, 3], [4]]), 2]])
        XCTAssertTrue(arrangement.dissolve(id))
        XCTAssertEqual(numbers(arrangement), [[0, 1, 3, 4, 2]])
        XCTAssertTrue(arrangement.folders.isEmpty)
        arrangement.pushOverflow(from: 0, capacity: 3)
        XCTAssertEqual(numbers(arrangement), [[0, 1, 3], [4, 2]])
        XCTAssertFalse(arrangement.dissolve(id), "A folder that no longer exists cannot be dissolved")
    }

    func testInsertingFromAnotherFolderKeepsTheSourceFolderWithItsRemainingApp() throws {
        var arrangement = try layout([[0, 1, 2, 3]])
        let work = arrangement.makeFolder(target: ids[0], dragged: ids[1], title: "Work")
        let games = arrangement.makeFolder(target: ids[2], dragged: ids[3], title: "Games")
        XCTAssertTrue(arrangement.insert(ids[1], intoFolder: games, capacity: 4))
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[0]]), .folder("Games", [[2, 3, 1]])]])
        XCTAssertTrue(arrangement.insert(ids[0], intoFolder: games, capacity: 4))
        XCTAssertEqual(numbers(arrangement), [[.folder("Games", [[2, 3, 1, 0]])]],
                       "The folder its last app left disappears")
        XCTAssertNil(arrangement.folder(work))
    }

    /// A folder page over capacity passes its last app to the start of the folder's next page,
    /// cascading like root pages.
    func testFolderOverflowCascadesToTheStartOfTheFoldersFollowingPages() throws {
        let folder = ClassicalLayoutFolder(title: "Work", pages: [[ids[0], ids[1], ids[3]], [ids[4]]])
        var arrangement = try ClassicalLayout(pages: [[.folder(folder), .app(ids[2])]])
        arrangement.pushOverflow(inFolder: folder.id, from: 0, capacity: 2)
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[0, 1], [3, 4]]), 2]])

        let full = ClassicalLayoutFolder(title: "Work", pages: [[ids[2], ids[0], ids[1]], [ids[3], ids[4]]])
        var cascading = try ClassicalLayout(pages: [[.folder(full)]])
        cascading.pushOverflow(inFolder: full.id, from: 0, capacity: 2)
        XCTAssertEqual(numbers(cascading), [[.folder("Work", [[2, 0], [1, 3], [4]])]],
                       "Overflow creates a new folder page when the last one is full")
    }

    func testMakeFolderWithAnAppFromAFolderItEmptiesRemovesThatFolder() throws {
        var arrangement = try layout([[0, 1, 2]])
        let work = arrangement.makeFolder(target: ids[0], dragged: ids[1], title: "Work")
        arrangement.move(ids[1], toRootPage: 0, index: 2)
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[0]]), 2, 1]])
        arrangement.makeFolder(target: ids[2], dragged: ids[0], title: "Games")
        XCTAssertEqual(numbers(arrangement), [[.folder("Games", [[2, 0]]), 1]])
        XCTAssertNil(arrangement.folder(work))
    }

    func testAFolderMembersRootPositionIsItsFoldersSlot() throws {
        var arrangement = try layout([[0, 1, 2, 3, 4]])
        let id = arrangement.makeFolder(target: ids[1], dragged: ids[3], title: "Work")
        arrangement.insert(ids[4], intoFolder: id, capacity: 2)
        XCTAssertEqual(arrangement.position(ofFolder: id)?.page, 0)
        XCTAssertEqual(arrangement.position(ofFolder: id)?.index, 1)
        XCTAssertEqual(arrangement.position(of: ids[4])?.page, 0, "A member on a later folder page is still in the folder's slot")
        XCTAssertEqual(arrangement.position(of: ids[4])?.index, 1)
        XCTAssertEqual(arrangement.position(of: ids[0])?.index, 0)
        XCTAssertNil(arrangement.position(of: ids[5]), "An unplaced app has no position")
    }

    // MARK: Folders and the catalog

    func testAppsInFoldersArePlacedAndNewAppsGoOnlyToTheFirstFreeRootSlot() throws {
        var arrangement = try layout([[0, 1, 2], [3]])
        arrangement.makeFolder(target: ids[0], dragged: ids[1], title: "Work")
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[0, 1]]), 2], [3]])
        let reconciled = arrangement.reconciled(with: [0, 1, 2, 3, 4, 5, 6].map { ids[$0] }, capacity: 3)
        XCTAssertEqual(numbers(reconciled), [[.folder("Work", [[0, 1]]), 2, 4], [3, 5, 6]],
                       "Folder members are not duplicated; new apps fill root pages, never the folder")
    }

    func testRemovedAppsLeaveFoldersAndAnEmptiedFolderDisappearsWithItsPages() throws {
        var arrangement = try layout([[0, 1, 2], [3, 4]])
        let id = arrangement.makeFolder(target: ids[0], dragged: ids[1], title: "Work")
        arrangement.insert(ids[2], intoFolder: id, capacity: 2)
        arrangement.makeFolder(target: ids[3], dragged: ids[4], title: "Games")
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[0, 1], [2]])], [.folder("Games", [[3, 4]])]])

        let oneLeft = arrangement.reconciled(with: [0, 1, 2, 3].map { ids[$0] }, capacity: 2)
        XCTAssertEqual(numbers(oneLeft), [[.folder("Work", [[0, 1], [2]])], [.folder("Games", [[3]])]],
                       "A folder with one app left stays")
        let pageEmptied = arrangement.reconciled(with: [0, 1, 3, 4].map { ids[$0] }, capacity: 2)
        XCTAssertEqual(numbers(pageEmptied), [[.folder("Work", [[0, 1]])], [.folder("Games", [[3, 4]])]],
                       "An emptied folder page disappears")
        let folderEmptied = arrangement.reconciled(with: [0, 1, 2].map { ids[$0] }, capacity: 2)
        XCTAssertEqual(numbers(folderEmptied), [[.folder("Work", [[0, 1], [2]])]],
                       "An emptied folder disappears, and so does the root page it leaves empty")
    }

    /// A returning app goes to the next available root space, not its old folder.
    func testReturningAppGoesToTheRootNotItsOldFolder() throws {
        var arrangement = try layout([[0, 1, 2]])
        arrangement.makeFolder(target: ids[0], dragged: ids[1], title: "Work")
        let gone = arrangement.reconciled(with: [0, 2].map { ids[$0] }, capacity: 3)
        XCTAssertEqual(numbers(gone), [[.folder("Work", [[0]]), 2]])
        let back = gone.reconciled(with: [0, 1, 2].map { ids[$0] }, capacity: 3)
        XCTAssertEqual(numbers(back), [[.folder("Work", [[0]]), 2, 1]])
    }

    func testSmallerCapacitySplitsFolderPagesLikeRootPages() throws {
        var arrangement = try layout([[0, 1, 2, 3, 4, 5]])
        let id = arrangement.makeFolder(target: ids[0], dragged: ids[1], title: "Work")
        for index in 2...4 { arrangement.insert(ids[index], intoFolder: id, capacity: 4) }
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[0, 1, 2, 3], [4]]), 5]])
        let reconciled = arrangement.reconciled(with: Array(ids.prefix(6)), capacity: 3)
        XCTAssertEqual(numbers(reconciled), [[.folder("Work", [[0, 1, 2], [3], [4]]), 5]],
                       "A folder page over capacity keeps its first items; the rest form pages right after it")
    }

    func testConfirmedDeletionRemovesAnAppFromItsFolder() throws {
        var arrangement = try layout([[0, 1, 2], [3]])
        arrangement.makeFolder(target: ids[0], dragged: ids[1], title: "Work")
        arrangement.makeFolder(target: ids[2], dragged: ids[3], title: "Games")
        arrangement.excludeDeleted(ids[1])
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[0]]), .folder("Games", [[2, 3]])]])
        arrangement.excludeDeleted(ids[0])
        XCTAssertEqual(numbers(arrangement), [[.folder("Games", [[2, 3]])]])
        let reconciled = arrangement.reconciled(with: Array(ids.prefix(4)), capacity: 3)
        XCTAssertEqual(numbers(reconciled), [[.folder("Games", [[2, 3]])]],
                       "A stale catalog snapshot does not restore deleted folder members")
    }

    // MARK: Saved folder data

    func testFoldersRoundTripThroughCoding() throws {
        var arrangement = try layout([[0, 1, 2, 3], [4]])
        let id = arrangement.makeFolder(target: ids[1], dragged: ids[3], title: "Work")
        arrangement.insert(ids[4], intoFolder: id, capacity: 2)
        let data = try JSONEncoder().encode(arrangement)
        let decoded = try JSONDecoder().decode(ClassicalLayout.self, from: data)
        XCTAssertEqual(decoded, arrangement)
        XCTAssertEqual(numbers(decoded), [[0, .folder("Work", [[1, 3], [4]]), 2]])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
    }

    /// Saved data with two folders, `Work` [[0, 1]] and `Games` [[2, 3]], followed by app 4 on the root page.
    private func savedFolders() throws -> Data {
        var arrangement = try layout([[0, 1, 2, 3, 4]])
        arrangement.makeFolder(target: ids[0], dragged: ids[1], title: "Work")
        arrangement.makeFolder(target: ids[2], dragged: ids[3], title: "Games")
        XCTAssertEqual(numbers(arrangement), [[.folder("Work", [[0, 1]]), .folder("Games", [[2, 3]]), 4]])
        return try JSONEncoder().encode(arrangement)
    }

    /// Re-encodes `data` after changing the saved folders (dictionaries holding `title` and `pages`) in order.
    private func editingFolders(_ data: Data, _ edit: (inout [String: Any], Int) -> Void) throws -> Data {
        var count = 0
        func visit(_ value: Any) -> Any {
            if var dictionary = value as? [String: Any] {
                dictionary = dictionary.mapValues(visit)
                if dictionary["title"] != nil, dictionary["pages"] != nil {
                    edit(&dictionary, count)
                    count += 1
                }
                return dictionary
            }
            if let array = value as? [Any] { return array.map(visit) }
            return value
        }
        let edited = visit(try JSONSerialization.jsonObject(with: data))
        XCTAssertEqual(count, 2, "Both saved folders were found")
        return try JSONSerialization.data(withJSONObject: edited)
    }

    private func decode(_ data: Data) throws -> ClassicalLayout {
        try JSONDecoder().decode(ClassicalLayout.self, from: data)
    }

    private func uuid(_ index: Int) -> String { ids[index].rawValue.uuidString }

    func testDecodingRejectsAnAppSavedTwiceAcrossRootAndFolders() throws {
        let data = try savedFolders()
        XCTAssertNoThrow(try decode(editingFolders(data) { _, _ in }), "The unedited data is valid")
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains(uuid(4)) && text.contains(uuid(0)))
        let rootAndFolder = Data(text.replacingOccurrences(of: uuid(4), with: uuid(0)).utf8)
        XCTAssertThrowsError(try decode(rootAndFolder), "An app in a folder and on a root page")
        let twoFolders = Data(text.replacingOccurrences(of: uuid(3), with: uuid(1)).utf8)
        XCTAssertThrowsError(try decode(twoFolders), "An app in two folders")
    }

    func testDecodingRejectsDuplicateFolderIDs() throws {
        var firstID: Any?
        let data = try editingFolders(savedFolders()) { folder, index in
            if index == 0 { firstID = folder["id"] } else { folder["id"] = firstID }
        }
        XCTAssertNotNil(firstID)
        XCTAssertThrowsError(try decode(data))
    }

    func testDecodingRejectsEmptyTitlesPagesAndFolders() throws {
        let saved = try savedFolders()
        XCTAssertThrowsError(try decode(editingFolders(saved) { folder, index in
            if index == 0 { folder["title"] = "" }
        }), "Empty title")
        XCTAssertThrowsError(try decode(editingFolders(saved) { folder, index in
            if index == 0, var pages = folder["pages"] as? [Any] { pages.append([Any]()); folder["pages"] = pages }
        }), "Empty folder page")
        XCTAssertThrowsError(try decode(editingFolders(saved) { folder, index in
            if index == 0 { folder["pages"] = [Any]() }
        }), "Folder without apps")
    }

    // MARK: Application references

    /// App `index` as the catalog holds it: `com.example.App<index>` at `/Applications/App<index>.app`
    /// unless `path` names another location.
    private func record(_ index: Int, id: AppIdentity? = nil, path: String? = nil,
                        online: Bool = true, isMissing: Bool? = nil) throws -> AppRecord {
        let bundleURL = URL(filePath: path ?? "/Applications/App\(index).app", directoryHint: .isDirectory)
        return AppRecord(
            id: id ?? ids[index],
            metadata: try AppMetadata(bundleIdentifier: "com.example.App\(index)", bundleURL: bundleURL,
                                      displayName: "App\(index)"),
            source: try AppSource(kind: .custom, directoryURL: bundleURL.deletingLastPathComponent(), isOnline: online),
            isMissing: isMissing
        )
    }

    func testApplicationReferencesRoundTripAsAnArraySortedByIdentity() throws {
        var arrangement = try layout([[0, 1, 2]])
        arrangement.makeFolder(target: ids[0], dragged: ids[1], title: "Work")
        let records = try (0...2).map { try record($0) }
        arrangement.rememberApplications(records)
        XCTAssertEqual(Set(arrangement.appReferences.keys), Set(ids.prefix(3)))

        let data = try JSONEncoder().encode(arrangement)
        XCTAssertEqual(try decode(data), arrangement)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        let saved = try XCTUnwrap(json["appReferences"] as? [[String: Any]])
        let savedIDs = saved.compactMap { $0["id"] as? String }
        XCTAssertEqual(savedIDs, ids.prefix(3).map(\.rawValue.uuidString).sorted())
        let first = try XCTUnwrap(saved.first { $0["id"] as? String == uuid(1) })
        XCTAssertEqual(first["bundleIdentifier"] as? String, "com.example.App1")
    }

    func testDecodingRejectsDuplicateOrInvalidApplicationReferences() throws {
        var arrangement = try layout([[0, 1]])
        arrangement.rememberApplications([try record(0), try record(1)])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(arrangement)) as? [String: Any])
        let references = try XCTUnwrap(json["appReferences"] as? [[String: Any]])
        XCTAssertEqual(references.count, 2)
        func decoding(_ edit: (inout [[String: Any]]) -> Void) throws -> ClassicalLayout {
            var edited = json
            var list = references
            edit(&list)
            edited["appReferences"] = list
            return try decode(JSONSerialization.data(withJSONObject: edited))
        }
        XCTAssertNoThrow(try decoding { _ in }, "The unedited data is valid")
        XCTAssertThrowsError(try decoding { $0[1]["id"] = $0[0]["id"] }, "Two references for one identity")
        XCTAssertThrowsError(try decoding { $0[0]["bundleIdentifier"] = "" }, "Empty bundle identifier")
        XCTAssertThrowsError(try decoding { $0[0]["bundleURL"] = "https://example.com/App0.app" }, "Not a local file")
    }

    func testReplacedIdentitiesKeepRootFolderExclusionAndTemplateState() throws {
        var arrangement = try layout([[0, 1, 2, 3], [4]])
        arrangement.makeFolder(target: ids[1], dragged: ids[2], title: "Work")
        arrangement.excludeDeleted(ids[5])
        arrangement.excludeDeleted(ids[6])
        let old = try (0...6).map { try record($0) }
        arrangement.observeExcluded(old.filter { $0.id != ids[6] })
        XCTAssertEqual(arrangement.excludedObservedAbsentIDs, [ids[6]])
        arrangement.markAutomaticTemplate(records: [])
        arrangement.rememberApplications(old)
        let saved = numbers(arrangement)

        // The same seven applications at the same locations, under identities 7 through 11 and two new ones.
        let replacements = [ids[7], ids[8], ids[9], ids[10], ids[11], AppIdentity(), AppIdentity()]
        let current = try (0...6).map { try record($0, id: replacements[$0]) }
        var adopted = arrangement
        adopted.adoptReplacedIdentities(from: current)

        XCTAssertEqual(ClassicalLayoutTestSlot.pages(of: adopted, ids: replacements), saved)
        XCTAssertEqual(adopted.excludedIDs, [replacements[5], replacements[6]])
        XCTAssertEqual(adopted.excludedObservedAbsentIDs, [replacements[6]])
        XCTAssertEqual(adopted.automaticTemplateBundleIDs, [:], "An automatic layout stays automatic")
        XCTAssertEqual(Set(adopted.appReferences.keys), Set(replacements))
        XCTAssertEqual(adopted.appReferences[replacements[1]]?.bundleIdentifier, "com.example.App1")
    }

    func testReplacedTemplateIdentityKeepsItsTemplateBundleIdentifier() throws {
        let safari = AppRecord(
            id: ids[0],
            metadata: try AppMetadata(bundleIdentifier: "com.apple.Safari",
                                      bundleURL: URL(filePath: "/Applications/Safari.app", directoryHint: .isDirectory),
                                      displayName: "Safari"),
            source: try AppSource(kind: .system, directoryURL: URL(filePath: "/Applications", directoryHint: .isDirectory),
                                  isOnline: true)
        )
        var arrangement = try layout([[0]])
        arrangement.markAutomaticTemplate(records: [safari])
        arrangement.rememberApplications([safari])
        let replaced = AppRecord(id: ids[1], metadata: safari.metadata, source: safari.source)

        arrangement.adoptReplacedIdentities(from: [replaced])

        XCTAssertEqual(numbers(arrangement), [[1]])
        XCTAssertEqual(arrangement.automaticTemplateBundleIDs, [ids[1]: "com.apple.Safari"])
    }

    func testAmbiguousOrUnmatchedIdentitiesAreLeftForReconciliation() throws {
        var arrangement = try layout([[0, 1, 2]])
        arrangement.rememberApplications([try record(0), try record(1),
                                          try record(2, path: "/Applications/Shared.app")])
        // App 0 has two candidate copies at its location; app 1 is gone; app 2 now has another bundle there.
        let copies = [try record(0, id: ids[3]), try record(0, id: ids[4])]
        let other = AppRecord(id: ids[5], metadata: try AppMetadata(
            bundleIdentifier: "com.example.Other",
            bundleURL: URL(filePath: "/Applications/Shared.app", directoryHint: .isDirectory), displayName: "Other"
        ), source: try record(5).source)
        var adopted = arrangement
        adopted.adoptReplacedIdentities(from: copies + [other])
        XCTAssertEqual(adopted, arrangement, "Nothing is replaced without exactly one matching application")

        let reconciled = adopted.reconciled(with: [ids[3], ids[4], ids[5]], capacity: 4)
        XCTAssertEqual(numbers(reconciled), [[3, 4, 5]], "Unmatched identities leave and the catalog apps arrive as new")
    }

    func testRememberingApplicationsFollowsMovesAndForgetsIdentitiesNoLongerHeld() throws {
        var arrangement = try layout([[0, 1, 2]])
        arrangement.excludeDeleted(ids[3])
        arrangement.rememberApplications([try record(0), try record(1), try record(2), try record(3), try record(4)])
        XCTAssertEqual(Set(arrangement.appReferences.keys), [ids[0], ids[1], ids[2], ids[3]],
                       "Held and excluded applications are remembered; an application outside the layout is not")

        arrangement.remove(ids[2])
        let moved = try record(0, path: "/Applications/Tools/App0.app")
        arrangement.rememberApplications([moved])
        XCTAssertEqual(arrangement.appReferences[ids[0]]?.bundleURL, moved.metadata.bundleURL)
        XCTAssertEqual(arrangement.appReferences[ids[1]]?.bundleURL, try record(1).metadata.bundleURL,
                       "An application absent from this catalog keeps its reference")
        XCTAssertNil(arrangement.appReferences[ids[2]], "A removed application's reference is forgotten")
        XCTAssertNotNil(arrangement.appReferences[ids[3]])
    }
}
