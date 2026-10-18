import Foundation
import Testing
@testable import Launchpod

struct AppCustomizationTests {
    @Test
    func persistedOverridesRemainUsableAfterAnExplicitMoveAndReinstall() throws {
        let original = try makeRecord(path: "/Applications/Example.app")
        let saved = AppCustomization(appID: original.id, isHidden: true, customName: "My Editor")
        let restored = try JSONDecoder().decode(AppCustomization.self, from: JSONEncoder().encode(saved))
        let customizations = [restored.appID: restored]
        let movedMetadata = try AppMetadata(
            bundleIdentifier: "com.example.Editor",
            bundleURL: URL(fileURLWithPath: "/Volumes/External/Example.app", isDirectory: true),
            displayName: "Updated Editor", version: "2.0"
        )
        let movedSource = try AppSource(
            kind: .custom, directoryURL: URL(fileURLWithPath: "/Volumes/External", isDirectory: true)
        )

        let moved = try original.replacingMetadata(with: movedMetadata, source: movedSource)
        let movedOverrides = try #require(customizations[moved.id])
        #expect(movedOverrides.isHidden)
        #expect(movedOverrides.customName == "My Editor")
        #expect(moved.metadata.displayName == "Updated Editor")

        let restoredRecord = try JSONDecoder().decode(AppRecord.self, from: JSONEncoder().encode(moved))
        #expect(restoredRecord.matchesBundleAndLocation(of: movedMetadata))
        let reinstalled = try restoredRecord.replacingMetadata(with: movedMetadata, source: movedSource)
        #expect(customizations[reinstalled.id] == saved)
    }

    @Test
    func duplicateCopiesHaveIndependentUserDataAndClearingOneOverrideKeepsTheOther() throws {
        let first = try makeRecord(path: "/Applications/Example.app")
        let copy = try makeRecord(path: "/Volumes/External/Example.app")
        var firstOverrides = AppCustomization(appID: first.id, isHidden: true, customName: "Work")
        let copyOverrides = AppCustomization(appID: copy.id, isHidden: false, customName: "Personal")

        #expect(firstOverrides.appID != copyOverrides.appID)
        firstOverrides.customName = nil
        #expect(firstOverrides.isHidden)
        #expect(copyOverrides.customName == "Personal")
        #expect(!copyOverrides.isHidden)
        firstOverrides.isHidden = false
        #expect(firstOverrides.appID == first.id)
    }

    @Test(arguments: [nil, false, true] as [Bool?])
    func sourceAvailabilityChangesDoNotChangeAppObservationsOrUserChoices(isMissing: Bool?) throws {
        let initial = try makeRecord(path: "/Volumes/External/Example.app")
        let onlineSource = try AppSource(
            kind: .custom, directoryURL: URL(fileURLWithPath: "/Volumes/External", isDirectory: true), isOnline: true
        )
        var record = AppRecord(id: initial.id, metadata: initial.metadata, source: onlineSource, isMissing: isMissing)
        let saved = AppCustomization(appID: record.id, isHidden: true, customName: "My external editor")
        let restored = try JSONDecoder().decode(AppCustomization.self, from: JSONEncoder().encode(saved))
        let customizations = [restored.appID: restored]

        for isOnline in [false, true, nil] as [Bool?] {
            let source = try AppSource(
                kind: .custom, directoryURL: URL(fileURLWithPath: "/Volumes/External", isDirectory: true),
                isOnline: isOnline
            )
            record = try record.replacingMetadata(with: record.metadata, source: source)

            #expect(record.source.isOnline == isOnline)
            #expect(record.isMissing == isMissing)
            #expect(record.id == saved.appID)
            #expect(record.matchesBundleAndLocation(of: record.metadata))
            #expect(customizations[record.id] == saved)
        }
    }

    @Test
    func userDataCanBeRestoredWithoutADiscoveryRecord() throws {
        let fixture = Data(Self.customizationJSON.utf8)
        let customization = try JSONDecoder().decode(AppCustomization.self, from: fixture)

        #expect(customization.appID.rawValue.uuidString == "41B4AC56-38CE-4C82-880F-A92032C13A20")
        #expect(customization.isHidden)
        #expect(customization.customName == "  \u{6587}\u{7a3f} Editor  ")
        #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(customization)) as? NSDictionary
            == JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
    }

    @Test(arguments: ["", "  ", "  My Editor  ", "\u{6587}\u{7a3f}\nEditor"])
    func customNamesArePreservedVerbatimRatherThanTreatedAsDiscoveryNames(name: String) throws {
        let customization = AppCustomization(appID: AppIdentity(), customName: name)
        let restored = try JSONDecoder().decode(AppCustomization.self, from: JSONEncoder().encode(customization))

        #expect(restored.customName == name)
        #expect(!restored.isHidden)
    }

    @Test(arguments: [
        #"{"schemaVersion":1,"appID":"41B4AC56-38CE-4C82-880F-A92032C13A20","isHidden":false}"#,
        #"{"schemaVersion":1,"appID":"41B4AC56-38CE-4C82-880F-A92032C13A20","isHidden":false,"customName":null,"futureField":true}"#
    ])
    func noNameOverrideIsDistinctFromAnEmptyName(json: String) throws {
        let customization = try JSONDecoder().decode(AppCustomization.self, from: Data(json.utf8))

        #expect(customization.customName == nil)
        #expect(!customization.isHidden)
    }

    @Test(arguments: ["schemaVersion", "appID", "isHidden"])
    func missingRequiredCustomizationFieldsCannotResetUserChoices(key: String) throws {
        var object = try #require(JSONSerialization.jsonObject(with: Data(Self.customizationJSON.utf8)) as? [String: Any])
        object.removeValue(forKey: key)
        let fixture = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppCustomization.self, from: fixture)
        }
    }

    @Test(arguments: ["0", "2", "-1", "1.5", "null", "true", #""1""#])
    func unsupportedOrMalformedCustomizationVersionsFail(version: String) {
        let fixture = Self.customizationJSON.replacingOccurrences(of: #""schemaVersion":1"#, with: "\"schemaVersion\":\(version)")

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppCustomization.self, from: Data(fixture.utf8))
        }
    }

    @Test(arguments: [
        #"{"schemaVersion":1,"appID":"not-a-uuid","isHidden":true}"#,
        #"{"schemaVersion":1,"appID":"41B4AC56-38CE-4C82-880F-A92032C13A20","isHidden":null}"#,
        #"{"schemaVersion":1,"appID":"41B4AC56-38CE-4C82-880F-A92032C13A20","isHidden":"true"}"#,
        #"{"schemaVersion":1,"appID":"41B4AC56-38CE-4C82-880F-A92032C13A20","isHidden":true,"customName":5}"#
    ])
    func malformedCustomizationDoesNotSilentlyDiscardUserData(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppCustomization.self, from: Data(json.utf8))
        }
    }

    private func makeRecord(path: String) throws -> AppRecord {
        let metadata = try AppMetadata(
            bundleIdentifier: "com.example.Editor",
            bundleURL: URL(fileURLWithPath: path, isDirectory: true), displayName: "Editor"
        )
        let source = try AppSource(kind: .system, directoryURL: URL(fileURLWithPath: "/Applications", isDirectory: true))
        return AppRecord(metadata: metadata, source: source)
    }

    private static let customizationJSON = #"{"schemaVersion":1,"appID":"41B4AC56-38CE-4C82-880F-A92032C13A20","isHidden":true,"customName":"  \u6587\u7a3f Editor  "}"#
}
