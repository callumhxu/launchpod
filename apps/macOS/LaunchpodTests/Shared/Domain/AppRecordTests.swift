import Foundation
import Testing
@testable import Launchpod

struct AppRecordTests {
    @Test
    func sameBundleAtDifferentLocationsKeepsSeparateIdentities() throws {
        let first = try makeRecord(path: "/Applications/Example.app")
        let copy = try makeRecord(path: "/Volumes/External/Example.app")

        #expect(first.id != copy.id)
        #expect(!first.matchesBundleAndLocation(of: copy.metadata))
        #expect(!copy.matchesBundleAndLocation(of: first.metadata))
    }

    @Test
    func reinstallAtAKnownLocationCanRefreshMetadataWithoutChangingIdentity() throws {
        let original = try makeRecord(path: "/Applications/Example.app")
        let reinstalled = try AppMetadata(
            bundleIdentifier: "COM.EXAMPLE.EDITOR",
            bundleURL: URL(fileURLWithPath: "/Applications/Tools/../Example.app", isDirectory: true),
            displayName: "Editor 2", version: "2.0", buildVersion: "200"
        )
        let source = try AppSource(kind: .custom, directoryURL: URL(fileURLWithPath: "/Applications", isDirectory: true))

        #expect(original.matchesBundleAndLocation(of: reinstalled))
        let refreshed = try original.replacingMetadata(with: reinstalled, source: source)
        #expect(refreshed.id == original.id)
        #expect(refreshed.metadata == reinstalled)
        #expect(refreshed.source == source)
        #expect(original.metadata.displayName == "Editor")
    }

    @Test
    func explicitlyConfirmedMoveRetainsIdentityAndAcceptsTheNewSource() throws {
        let original = try makeRecord(path: "/Applications/Example.app")
        let movedMetadata = try AppMetadata(
            bundleIdentifier: "com.example.Editor",
            bundleURL: URL(fileURLWithPath: "/Users/example/Applications/Example.app", isDirectory: true),
            displayName: "Editor", version: "1.1"
        )
        let movedSource = try AppSource(
            kind: .user, directoryURL: URL(fileURLWithPath: "/Users/example/Applications", isDirectory: true)
        )

        #expect(!original.matchesBundleAndLocation(of: movedMetadata))
        let moved = try original.replacingMetadata(with: movedMetadata, source: movedSource)
        #expect(moved.id == original.id)
        #expect(moved.metadata.bundleURL.absoluteString == "file:///Users/example/Applications/Example.app/")
        #expect(moved.source == movedSource)
        #expect(moved.matchesBundleAndLocation(of: movedMetadata))
        #expect(!moved.matchesBundleAndLocation(of: original.metadata))
    }

    @Test
    func samePathWithAnotherKnownBundleCannotInheritIdentity() throws {
        let original = try makeRecord(path: "/Applications/Example.app")
        let replacement = try AppMetadata(
            bundleIdentifier: "com.other.Editor", bundleURL: original.metadata.bundleURL, displayName: "Other Editor"
        )

        #expect(!original.matchesBundleAndLocation(of: replacement))
        #expect(throws: AppRecord.UpdateError.self) {
            try original.replacingMetadata(with: replacement, source: original.source)
        }
        let separate = AppRecord(metadata: replacement, source: original.source)
        #expect(separate.id != original.id)
    }

    @Test(arguments: [nil, ""] as [String?])
    func missingBundleIdentifiersNeverEstablishAutomaticContinuity(bundleIdentifier: String?) throws {
        let known = try makeRecord(path: "/Applications/Example.app")
        let unidentified = try AppMetadata(
            bundleIdentifier: bundleIdentifier, bundleURL: known.metadata.bundleURL, displayName: "Editor"
        )
        let record = AppRecord(metadata: unidentified, source: known.source)

        #expect(!known.matchesBundleAndLocation(of: unidentified))
        #expect(!record.matchesBundleAndLocation(of: known.metadata))
        #expect(!record.matchesBundleAndLocation(of: unidentified))
        let explicitlyUpdated = try record.replacingMetadata(with: known.metadata, source: known.source)
        #expect(explicitlyUpdated.id == record.id)
        #expect(explicitlyUpdated.matchesBundleAndLocation(of: known.metadata))
    }

    @Test
    func pathCaseDoesNotImplyAFileSystemEquivalence() throws {
        let original = try makeRecord(path: "/Applications/Example.app")
        let other = try makeRecord(path: "/Applications/example.app")

        #expect(!original.matchesBundleAndLocation(of: other.metadata))
    }

    @Test
    func moveAndVersionRefreshPreserveObservationsUntilTheCallerReplacesOrClearsThem() throws {
        var original = try makeRecord(path: "/Applications/Example.app")
        original.isMissing = true
        original.bookmarkData = Data([0, 1, 2, 255])
        let movedMetadata = try AppMetadata(
            bundleIdentifier: "com.example.Editor",
            bundleURL: URL(fileURLWithPath: "/Volumes/External/Example.app", isDirectory: true),
            displayName: "Editor", version: "2.0"
        )
        let movedSource = try AppSource(
            kind: .custom, directoryURL: URL(fileURLWithPath: "/Volumes/External", isDirectory: true), isOnline: true
        )
        let moved = try original.replacingMetadata(with: movedMetadata, source: movedSource)

        #expect(moved.id == original.id)
        #expect(moved.isMissing == true)
        #expect(moved.bookmarkData == Data([0, 1, 2, 255]))
        let versionUpdate = try AppMetadata(
            bundleIdentifier: "com.example.Editor", bundleURL: moved.metadata.bundleURL,
            displayName: "Editor", version: "3.0"
        )
        var refreshed = try moved.replacingMetadata(with: versionUpdate, source: movedSource)
        #expect(refreshed.isMissing == true)
        #expect(refreshed.bookmarkData == original.bookmarkData)
        #expect(refreshed.matchesBundleAndLocation(of: versionUpdate))

        refreshed.isMissing = false
        refreshed.bookmarkData = Data([255, 0, 23])
        let restored = try JSONDecoder().decode(AppRecord.self, from: JSONEncoder().encode(refreshed))
        #expect(restored.isMissing == false)
        #expect(restored.bookmarkData == Data([255, 0, 23]))
        #expect(restored.id == original.id)
        refreshed.isMissing = nil
        refreshed.bookmarkData = nil
        let cleared = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(refreshed)) as? [String: Any])
        #expect(cleared["isMissing"] == nil)
        #expect(cleared["bookmarkData"] == nil)
        #expect(refreshed.id == original.id)
    }

    @Test
    func recentlyAddedStateSurvivesMetadataRefreshAndPersistence() throws {
        var record = try makeRecord(path: "/Applications/Example.app")
        #expect(record.isRecentlyAdded == nil)
        record.isRecentlyAdded = true
        let refreshedMetadata = try AppMetadata(
            bundleIdentifier: "com.example.Editor", bundleURL: record.metadata.bundleURL,
            displayName: "Editor Updated", version: "2.0"
        )
        let refreshed = try record.replacingMetadata(with: refreshedMetadata, source: record.source)
        #expect(refreshed.isRecentlyAdded == true)

        let persisted = try JSONEncoder().encode(refreshed)
        #expect(try JSONDecoder().decode(AppRecord.self, from: persisted).isRecentlyAdded == true)
        var cleared = refreshed
        cleared.isRecentlyAdded = false
        #expect(try JSONDecoder().decode(AppRecord.self, from: JSONEncoder().encode(cleared)).isRecentlyAdded == false)
    }

    @Test
    func missingAppAndOfflineSourceDoNotAuthorizeAnotherBundleToInheritIdentity() throws {
        let known = try makeRecord(path: "/Applications/Example.app")
        let offline = try AppSource(kind: .system, directoryURL: known.source.directoryURL, isOnline: false)
        let missing = AppRecord(id: known.id, metadata: known.metadata, source: offline, isMissing: true)
        let replacement = try AppMetadata(
            bundleIdentifier: "com.other.Editor", bundleURL: known.metadata.bundleURL, displayName: "Other"
        )

        #expect(!missing.matchesBundleAndLocation(of: replacement))
        #expect(throws: AppRecord.UpdateError.self) {
            try missing.replacingMetadata(with: replacement, source: offline)
        }
    }

    @Test
    func recordsAndUserDataCanBeConstructedAndPersistedOffTheMainActor() async throws {
        let (record, restoredRecord, customization, restoredCustomization) = try await Task.detached {
            let metadata = try AppMetadata(
                bundleIdentifier: "com.example.Editor",
                bundleURL: URL(fileURLWithPath: "/Applications/Example.app", isDirectory: true),
                displayName: "Editor", categoryIdentifier: "public.app-category.developer-tools",
                contentModificationDate: Date(timeIntervalSinceReferenceDate: 123456.25),
                isApplication: true, isUIElement: false, isBackgroundOnly: false
            )
            let source = try AppSource(
                kind: .system, directoryURL: URL(fileURLWithPath: "/Applications", isDirectory: true),
                isOnline: true, volumeUUIDString: "d80d927e-0000-4444-aaaa-0123456789ab"
            )
            let record = AppRecord(metadata: metadata, source: source, isMissing: false, bookmarkData: Data([0, 255]))
            let customization = AppCustomization(appID: record.id, isHidden: true, customName: "Mine")
            let restoredRecord = try JSONDecoder().decode(AppRecord.self, from: JSONEncoder().encode(record))
            let restoredCustomization = try JSONDecoder().decode(
                AppCustomization.self, from: JSONEncoder().encode(customization)
            )
            return (record, restoredRecord, customization, restoredCustomization)
        }.value

        #expect(restoredRecord == record)
        #expect(restoredCustomization == customization)
        #expect(restoredCustomization.appID == restoredRecord.id)
    }

    @Test
    func currentVersionOneFixtureRestoresTheCompleteSharedRecord() throws {
        let fixture = Data(Self.recordJSON.utf8)
        let record = try JSONDecoder().decode(AppRecord.self, from: fixture)

        #expect(record.id.rawValue.uuidString == "41B4AC56-38CE-4C82-880F-A92032C13A20")
        #expect(record.metadata.bundleIdentifier == "com.example.Editor")
        #expect(record.metadata.displayName == "Editor")
        #expect(record.metadata.version == "1.0")
        #expect(record.source.kind == .system)
        #expect(record.metadata.categoryIdentifier == "public.app-category.developer-tools")
        #expect(record.metadata.contentModificationDate == Date(timeIntervalSinceReferenceDate: 123456.25))
        #expect(record.metadata.isApplication == true)
        #expect(record.metadata.isUIElement == false)
        #expect(record.metadata.isBackgroundOnly == false)
        #expect(record.source.isOnline == true)
        #expect(record.source.volumeUUIDString == "d80d927e-0000-4444-aaaa-0123456789ab")
        #expect(record.isMissing == false)
        #expect(record.bookmarkData == Data([0, 1, 2, 255]))
        #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? NSDictionary
            == JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
    }

    @Test(arguments: ["null", "false", "true"])
    func recordFixtureDistinguishesMissingObservationsAndPreservesOpaqueBookmarkBytes(state: String) throws {
        var fixture = try #require(JSONSerialization.jsonObject(with: Data(Self.recordJSON.utf8)) as? [String: Any])
        fixture["isMissing"] = try JSONSerialization.jsonObject(with: Data(state.utf8), options: .fragmentsAllowed)
        let record = try JSONDecoder().decode(AppRecord.self, from: JSONSerialization.data(withJSONObject: fixture))
        let expectedState: Bool? = state == "null" ? nil : state == "true"
        let data = try JSONEncoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let restored = try JSONDecoder().decode(AppRecord.self, from: data)

        #expect(record.isMissing == expectedState)
        #expect(record.bookmarkData == Data([0, 1, 2, 255]))
        #expect(restored == record)
        #expect(object["isMissing"] as? Bool == expectedState)
        #expect(object["bookmarkData"] as? String == "AAEC/w==")
        if expectedState == nil {
            #expect(object["isMissing"] == nil)
        }
    }

    @Test(arguments: [false, true])
    func optionalRecordObservationsCanBeOmittedOrNull(explicitNull: Bool) throws {
        var fixture = try #require(JSONSerialization.jsonObject(with: Data(Self.recordJSON.utf8)) as? [String: Any])
        for key in ["isMissing", "bookmarkData"] {
            if explicitNull {
                fixture[key] = NSNull()
            } else {
                fixture.removeValue(forKey: key)
            }
        }
        let record = try JSONDecoder().decode(AppRecord.self, from: JSONSerialization.data(withJSONObject: fixture))

        #expect(record.isMissing == nil)
        #expect(record.bookmarkData == nil)
        fixture.removeValue(forKey: "isMissing")
        fixture.removeValue(forKey: "bookmarkData")
        #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? NSDictionary
            == fixture as NSDictionary)
    }

    @Test(arguments: [("isMissing", #""false""#), ("isMissing", "0"), ("bookmarkData", "7"), ("bookmarkData", #""not base64!""#)])
    func malformedRecordObservationsFailInsteadOfBecomingUnknown(field: String, jsonValue: String) throws {
        var object = try #require(JSONSerialization.jsonObject(with: Data(Self.recordJSON.utf8)) as? [String: Any])
        object[field] = try JSONSerialization.jsonObject(with: Data(jsonValue.utf8), options: .fragmentsAllowed)
        let fixture = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppRecord.self, from: fixture)
        }
    }

    @Test
    func recordIgnoresAdditionalKeysButKeepsRequiredData() throws {
        var object = try #require(JSONSerialization.jsonObject(with: Data(Self.recordJSON.utf8)) as? [String: Any])
        object["futureField"] = ["value": true]
        let record = try JSONDecoder().decode(AppRecord.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(record.id.rawValue.uuidString == "41B4AC56-38CE-4C82-880F-A92032C13A20")
        #expect(record.metadata.displayName == "Editor")
    }

    @Test(arguments: ["schemaVersion", "id", "metadata", "source"])
    func missingRequiredRecordFieldsFailInsteadOfCreatingNewIdentity(key: String) throws {
        var object = try #require(JSONSerialization.jsonObject(with: Data(Self.recordJSON.utf8)) as? [String: Any])
        object.removeValue(forKey: key)
        let fixture = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppRecord.self, from: fixture)
        }
    }

    @Test(arguments: ["0", "2", "-1", "1.5", "null", "true", #""1""#])
    func unsupportedOrMalformedRecordVersionsFail(version: String) {
        let fixture = Self.recordJSON.replacingOccurrences(of: #""schemaVersion":1"#, with: "\"schemaVersion\":\(version)")

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppRecord.self, from: Data(fixture.utf8))
        }
    }

    private func makeRecord(path: String) throws -> AppRecord {
        let metadata = try AppMetadata(
            bundleIdentifier: "com.example.Editor",
            bundleURL: URL(fileURLWithPath: path, isDirectory: true), displayName: "Editor", version: "1.0"
        )
        let source = try AppSource(kind: .system, directoryURL: URL(fileURLWithPath: "/Applications", isDirectory: true))
        return AppRecord(metadata: metadata, source: source)
    }

    private static let recordJSON = #"{"schemaVersion":1,"id":"41B4AC56-38CE-4C82-880F-A92032C13A20","metadata":{"bundleIdentifier":"com.example.Editor","bundleURL":"file:///Applications/Example.app/","displayName":"Editor","version":"1.0","buildVersion":"100","categoryIdentifier":"public.app-category.developer-tools","contentModificationDate":123456.25,"isApplication":true,"isUIElement":false,"isBackgroundOnly":false},"source":{"kind":"system","directoryURL":"file:///Applications/","isOnline":true,"volumeUUIDString":"d80d927e-0000-4444-aaaa-0123456789ab"},"isMissing":false,"bookmarkData":"AAEC/w=="}"#
}
