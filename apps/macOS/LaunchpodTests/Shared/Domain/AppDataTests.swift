import Foundation
import Testing
@testable import Launchpod

struct AppDataTests {
    @Test
    func currentModelsRoundTripWithIdentityUnknownObservationsAndOrphanedChoicesIntact() throws {
        let metadata = try AppMetadata(
            bundleIdentifier: "com.example.Editor", bundleURL: URL(fileURLWithPath: "/Applications/Editor.app"),
            displayName: "Editor", version: "1.2", buildVersion: "34", categoryIdentifier: "public.app-category.productivity",
            contentModificationDate: Date(timeIntervalSinceReferenceDate: 1234), isApplication: true,
            isUIElement: false, isBackgroundOnly: nil
        )
        let source = try AppSource(
            kind: .custom, directoryURL: URL(fileURLWithPath: "/Applications"),
            isOnline: nil, volumeUUIDString: "observed-volume"
        )
        let record = AppRecord(metadata: metadata, source: source, isMissing: true, bookmarkData: Data([0, 1, 254, 255]))
        let choices = [
            AppCustomization(appID: record.id, isHidden: true, customName: "  \u{6587}\u{7a3f}\nEditor  "),
            AppCustomization(appID: AppIdentity(), customName: "Absent application")
        ]
        let original = try AppData(records: [record], customizations: choices,
                                   scannedDirectoryURLs: [source.directoryURL])

        let encoded = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(AppData.self, from: encoded)
        #expect(restored == original)
        #expect(restored.records.first?.id == record.id)
        #expect(restored.customizations == choices)
        #expect(restored.scannedDirectoryURLs == [source.directoryURL])
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
    }

    @Test(arguments: [
        #"{"schemaVersion":1,"records":[],"customizations":[],"scannedDirectoryURLs":[]}"#,
        #"{"schemaVersion":1,"records":[],"customizations":[],"scannedDirectoryURLs":[],"unknownField":{"value":true}}"#
    ])
    func validEmptyCurrentFormatAcceptsUnknownFields(json: String) throws {
        let restored = try JSONDecoder().decode(AppData.self, from: Data(json.utf8))
        let empty = try AppData()
        #expect(restored == empty)
        #expect(restored.scannedDirectoryURLs.isEmpty)
    }

    @Test(arguments: [
        #"{"records":[],"customizations":[],"scannedDirectoryURLs":[]}"#,
        #"{"schemaVersion":0,"records":[],"customizations":[],"scannedDirectoryURLs":[]}"#,
        #"{"schemaVersion":2,"records":[],"customizations":[],"scannedDirectoryURLs":[]}"#,
        #"{"schemaVersion":"1","records":[],"customizations":[],"scannedDirectoryURLs":[]}"#,
        #"{"schemaVersion":true,"records":[],"customizations":[],"scannedDirectoryURLs":[]}"#,
        #"{"schemaVersion":1.5,"records":[],"customizations":[],"scannedDirectoryURLs":[]}"#,
        #"{"schemaVersion":1,"customizations":[],"scannedDirectoryURLs":[]}"#,
        #"{"schemaVersion":1,"records":[],"scannedDirectoryURLs":[]}"#,
        #"{"schemaVersion":1,"records":[],"customizations":[]}"#,
        #"{"schemaVersion":1,"records":null,"customizations":[],"scannedDirectoryURLs":[]}"#,
        #"{"schemaVersion":1,"records":[],"customizations":{},"scannedDirectoryURLs":[]}"#,
        #"{"schemaVersion":1,"records":[],"customizations":[],"scannedDirectoryURLs":null}"#
    ])
    func invalidCurrentEnvelopeIsRejectedInsteadOfResettingItsContents(json: String) {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(AppData.self, from: Data(json.utf8)) }
    }

    @Test
    func duplicatePersistentIdentitiesAreRejectedButDistinctCopiesRemainSeparate() throws {
        let metadata = try AppMetadata(
            bundleIdentifier: "com.example.Editor", bundleURL: URL(fileURLWithPath: "/Applications/Editor.app"),
            displayName: "Editor"
        )
        let source = try AppSource(kind: .system, directoryURL: URL(fileURLWithPath: "/Applications"))
        let record = AppRecord(metadata: metadata, source: source)
        let duplicateCopy = AppRecord(metadata: metadata, source: source)
        let customization = AppCustomization(appID: record.id, customName: "Retained")

        #expect(throws: (any Error).self) { try AppData(records: [record, record]) }
        #expect(throws: (any Error).self) { try AppData(customizations: [customization, customization]) }
        let separateCopies = try AppData(records: [record, duplicateCopy], customizations: [customization])
        #expect(try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(separateCopies)) == separateCopies)

        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(separateCopies)) as? [String: Any])
        let records = try #require(object["records"] as? [Any])
        object["records"] = [records[0], records[0]]
        let duplicateRecords = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(AppData.self, from: duplicateRecords) }
        object["records"] = records
        let customizations = try #require(object["customizations"] as? [Any])
        object["customizations"] = [customizations[0], customizations[0]]
        let duplicateCustomizations = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(AppData.self, from: duplicateCustomizations) }
    }
}
