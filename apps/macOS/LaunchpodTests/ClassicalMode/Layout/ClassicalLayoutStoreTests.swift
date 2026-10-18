import Foundation
import XCTest
@testable import Launchpod

/// Saving and validating the Classical layout's single authoritative file.
final class ClassicalLayoutStoreTests: XCTestCase {
    private let ids = (0..<5).map { _ in AppIdentity() }

    private func layout(_ pages: [[Int]]) throws -> ClassicalLayout {
        try ClassicalLayout(pages: pages.map { $0.map { ids[$0] } })
    }

    func testSuccessiveAtomicSavesKeepOnlyTheLatestPrimaryFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClassicalLayoutStore(directoryURL: directory)
        let missing = try await store.load()
        XCTAssertNil(missing)
        let latest = try layout([[1, 0]])

        try await store.save(try layout([[0, 1]]))
        try await store.save(latest)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, latest)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["layout.json"])
    }

    func testFoldersSaveInOrderWithSchemaVersionOne() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClassicalLayoutStore(directoryURL: directory)
        var saved = try layout([[0, 1, 2], [3, 4]])
        let work = saved.makeFolder(target: ids[1], dragged: ids[0], title: "Work")
        saved.insert(ids[3], intoFolder: work, capacity: 2)
        saved.renameFolder(work, to: "Utilities")
        var rearranged = try XCTUnwrap(saved.folder(work))
        rearranged.pages = [[ids[1]], [ids[0], ids[3]]]
        saved = try ClassicalLayout(pages: saved.pages.map { $0.map { $0.folder?.id == work ? .folder(rearranged) : $0 } })

        try await store.save(saved)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, saved)
        XCTAssertEqual(loaded.map { ClassicalLayoutTestSlot.pages(of: $0, ids: ids) },
                       [[.folder("Utilities", [[1], [0, 3]]), 2], [4]], "The saved order is kept exactly")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
        XCTAssertEqual(json?["schemaVersion"] as? Int, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["layout.json"])
    }

    func testCorruptPrimaryThrowsWithoutReplacingItsContents() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClassicalLayoutStore(directoryURL: directory)
        let corrupt = Data("broken primary".utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try corrupt.write(to: store.fileURL)

        do {
            _ = try await store.load()
            XCTFail("A corrupt primary layout must fail to load.")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["layout.json"])
    }

    func testInterruptedAtomicWritePreservesTheLastSuccessfulLayout() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalStore = ClassicalLayoutStore(directoryURL: directory)
        let original = try layout([[0, 1]])
        try await originalStore.save(original)
        let originalBytes = try Data(contentsOf: originalStore.fileURL)
        let interrupted = ClassicalLayoutStore(directoryURL: directory) { _, _ in throw WriteInterruption.stopped }

        do {
            try await interrupted.save(try layout([[1, 0]]))
            XCTFail("The injected write interruption must be reported.")
        } catch is WriteInterruption {}

        XCTAssertEqual(try Data(contentsOf: originalStore.fileURL), originalBytes)
        let loaded = try await originalStore.load()
        XCTAssertEqual(loaded, original)
    }

    func testInvalidApplicationReferencesMakeThePrimaryUnreadable() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClassicalLayoutStore(directoryURL: directory)
        let records = try (0..<2).map { index in
            let bundleURL = URL(filePath: "/Applications/App\(index).app", directoryHint: .isDirectory)
            return AppRecord(id: ids[index],
                             metadata: try AppMetadata(bundleIdentifier: "com.example.App\(index)", bundleURL: bundleURL,
                                                       displayName: "App\(index)"),
                             source: try AppSource(kind: .custom, directoryURL: bundleURL.deletingLastPathComponent()))
        }
        var saved = try layout([[0, 1]])
        saved.rememberApplications(records)
        try await store.save(saved)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        var references = try XCTUnwrap(json["appReferences"] as? [[String: Any]])
        references[1]["id"] = references[0]["id"]
        json["appReferences"] = references
        let invalid = try JSONSerialization.data(withJSONObject: json)
        try invalid.write(to: store.fileURL)

        do {
            _ = try await store.load()
            XCTFail("Duplicate application references must make the primary unreadable.")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: store.fileURL), invalid)
    }

    func testRemovingSavedLayoutDeletesOnlyThePrimaryAndIsIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClassicalLayoutStore(directoryURL: directory)
        try await store.save(try layout([[0, 1]]))
        let unrelated = directory.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: unrelated)

        try await store.removeSavedLayout()
        try await store.removeSavedLayout()

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["keep.txt"])
    }

    private enum WriteInterruption: Error { case stopped }
}
