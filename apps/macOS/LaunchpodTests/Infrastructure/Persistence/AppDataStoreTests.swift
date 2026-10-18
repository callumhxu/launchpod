import Foundation
import Testing
@testable import Launchpod

struct AppDataStoreTests {
    @Test(arguments: ["https://example.invalid/storage", "file://remote-host/storage", "file:///tmp/storage?query=1"])
    func invalidStorageLocationsAreRejectedBeforeFileAccess(location: String) throws {
        let url = try #require(URL(string: location))
        #expect(throws: AppDataStore.ValidationError.self) { try AppDataStore(directoryURL: url) }
    }

    @Test
    func missingFileReturnsNoSavedDataWithoutCreatingFiles() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let absentDirectory = directory.appendingPathComponent("absent", isDirectory: true)
        let store = try AppDataStore(directoryURL: absentDirectory)

        #expect(try await store.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: absentDirectory.path))
    }

    @Test
    func savedUserChoicesSurviveAStoreRecreation() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AppDataStore(directoryURL: directory.appendingPathComponent("nested"))
        let original = try data(named: "  \u{6587}\u{7a3f}\nEditor  ")

        try await store.save(original)
        let restored = try #require(await AppDataStore(directoryURL: store.fileURL.deletingLastPathComponent()).load())

        #expect(restored == original)
        #expect(try JSONDecoder().decode(AppData.self, from: Data(contentsOf: store.fileURL)) == original)
    }

    @Test
    func successiveAtomicSavesKeepOnlyTheLatestPrimaryFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AppDataStore(directoryURL: directory)
        let latest = try data(named: "Latest")

        try await store.save(data(named: "Previous"))
        try await store.save(latest)

        #expect(try await store.load() == latest)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["app-data.json"])
    }

    @Test
    func corruptPrimaryThrowsWithoutReplacingItsContents() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AppDataStore(directoryURL: directory)
        let corrupt = Data("broken primary".utf8)
        try corrupt.write(to: store.fileURL)

        await #expect(throws: (any Error).self) { try await store.load() }
        #expect(try Data(contentsOf: store.fileURL) == corrupt)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["app-data.json"])
    }

    @Test(arguments: [
        #"{"schemaVersion":2,"records":[],"customizations":[],"scannedDirectoryURLs":[]}"#,
        #"{"schemaVersion":1,"records":[],"customizations":[{"schemaVersion":1,"appID":"invalid","isHidden":true}],"scannedDirectoryURLs":[]}"#
    ])
    func parseableJSONMustPassCurrentModelValidationBeforeItCanBeLoaded(json: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AppDataStore(directoryURL: directory)
        let invalid = Data(json.utf8)
        try invalid.write(to: store.fileURL)

        await #expect(throws: (any Error).self) { try await store.load() }
        #expect(try Data(contentsOf: store.fileURL) == invalid)
    }

    @Test
    func anInterruptedAtomicWritePreservesTheLastSuccessfulSave() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalStore = try AppDataStore(directoryURL: directory)
        let original = try data(named: "Last completed save")
        try await originalStore.save(original)
        let originalBytes = try Data(contentsOf: originalStore.fileURL)
        let interruptedStore = try AppDataStore(directoryURL: directory) { _, _ in
            throw WriteInterruption.stopped
        }

        await #expect(throws: WriteInterruption.self) {
            try await interruptedStore.save(data(named: "Not committed"))
        }
        #expect(try Data(contentsOf: originalStore.fileURL) == originalBytes)
        #expect(try await AppDataStore(directoryURL: directory).load() == original)
    }

    @Test
    func encodingFailureLeavesTheSuccessfulPrimaryByteForByteIntact() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AppDataStore(directoryURL: directory)
        let latest = try data(named: "Latest")
        try await store.save(latest)
        let primaryBytes = try Data(contentsOf: store.fileURL)
        let metadata = try AppMetadata(
            bundleIdentifier: "com.example.Editor", bundleURL: URL(fileURLWithPath: "/Applications/Editor.app"),
            displayName: "Editor", contentModificationDate: Date(timeIntervalSinceReferenceDate: .infinity)
        )
        let source = try AppSource(kind: .system, directoryURL: URL(fileURLWithPath: "/Applications"))
        let unencodable = try AppData(records: [AppRecord(metadata: metadata, source: source)])

        await #expect(throws: EncodingError.self) { try await store.save(unencodable) }
        #expect(try Data(contentsOf: store.fileURL) == primaryBytes)
        #expect(try await store.load() == latest)
    }

    @Test
    func concurrentSavesThroughOneStoreProduceOneCompleteRequestedSnapshot() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AppDataStore(directoryURL: directory)
        let requested = try (0..<12).map { try data(named: "Requested save \($0)") }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for snapshot in requested {
                group.addTask { try await store.save(snapshot) }
            }
            try await group.waitForAll()
        }

        let primary = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: store.fileURL))
        #expect(requested.contains(primary))
        #expect(try await store.load() == primary)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["app-data.json"])
    }

    @Test
    func separatelyOwnedDirectoriesDoNotShareSaves() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try AppDataStore(directoryURL: directory.appendingPathComponent("first"))
        let second = try AppDataStore(directoryURL: directory.appendingPathComponent("second"))
        let firstData = try data(named: "First")
        let secondData = try data(named: "Second")
        try await first.save(firstData)
        try await second.save(secondData)

        #expect(try await first.load() == firstData)
        #expect(try await second.load() == secondData)
        #expect(first.fileURL != second.fileURL)
    }

    private enum WriteInterruption: Error { case stopped }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Launchpod-AppDataStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func data(named name: String) throws -> AppData {
        let metadata = try AppMetadata(
            bundleIdentifier: "com.example.Editor", bundleURL: URL(fileURLWithPath: "/Applications/Editor.app"),
            displayName: "Editor", version: "1.2", isApplication: true
        )
        let source = try AppSource(
            kind: .custom, directoryURL: URL(fileURLWithPath: "/Applications"), isOnline: nil
        )
        let record = AppRecord(metadata: metadata, source: source, isMissing: false, bookmarkData: Data([0, 1, 255]))
        return try AppData(
            records: [record], customizations: [AppCustomization(appID: record.id, isHidden: true, customName: name)]
        )
    }
}
