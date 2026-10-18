import Foundation
import XCTest
@testable import Launchpod

@MainActor
final class TemporaryPreferencesTests: XCTestCase {
    func testPreferenceModelsRoundTripThroughARealTemporaryPropertyList() throws {
        let preferences = try TemporaryPreferences()
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let preference = AppLanguagePreference(defaults: preferences.defaults, preferredLanguages: { ["en-US"] })
        preference.selection = .french

        XCTAssertTrue(preferences.defaults.synchronize())
        let fileURL = URL(fileURLWithPath: preferences.domain).appendingPathExtension("plist")
        XCTAssertTrue(fileURL.path.hasPrefix(preferences.directoryURL.path + "/"))
        let contents = try Data(contentsOf: fileURL)
        let propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: contents, format: nil) as? [String: Any]
        )
        XCTAssertEqual(propertyList[AppLanguagePreference.preferenceKey] as? String, "fr")

        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: preferences.domain))
        let restored = AppLanguagePreference(defaults: reopenedDefaults, preferredLanguages: { ["ja-JP"] })
        XCTAssertEqual(restored.selection, .french)
        XCTAssertEqual(restored.resolvedLanguage, .french)

        try preferences.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferences.directoryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testIndependentFixturesDoNotShareValuesOrDeleteEachOthersFiles() throws {
        let first = try TemporaryPreferences()
        defer { XCTAssertNoThrow(try first.cleanup()) }
        let second = try TemporaryPreferences()
        defer { XCTAssertNoThrow(try second.cleanup()) }
        XCTAssertNotEqual(first.domain, second.domain)

        first.defaults.set("first", forKey: "fixtureValue")
        second.defaults.set("second", forKey: "fixtureValue")
        XCTAssertTrue(first.defaults.synchronize())
        XCTAssertTrue(second.defaults.synchronize())
        XCTAssertEqual(first.defaults.string(forKey: "fixtureValue"), "first")
        XCTAssertEqual(second.defaults.string(forKey: "fixtureValue"), "second")

        try first.cleanup()
        XCTAssertEqual(second.defaults.string(forKey: "fixtureValue"), "second")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.directoryURL.path))
        try second.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.directoryURL.path))
    }

    func testCoreFoundationAndFoundationShareTheTemporaryDomainWithoutHomePreferenceFiles() throws {
        let homePreferencesURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
        let existingFiles = try preferenceFileNames(in: homePreferencesURL)
        let preferences = try TemporaryPreferences()
        defer { XCTAssertNoThrow(try preferences.cleanup()) }

        preferences.defaults.set(["first", "second"], forKey: "orderedValues")
        XCTAssertTrue(preferences.defaults.synchronize())
        XCTAssertEqual(
            CFPreferencesCopyAppValue("orderedValues" as CFString, preferences.domain as CFString) as? [String],
            ["first", "second"]
        )
        CFPreferencesSetAppValue("cfValue" as CFString, "preserved" as CFString, preferences.domain as CFString)
        XCTAssertTrue(CFPreferencesAppSynchronize(preferences.domain as CFString))
        XCTAssertEqual(preferences.defaults.string(forKey: "cfValue"), "preserved")

        try preferences.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferences.directoryURL.path))
        let remainingFiles = try preferenceFileNames(in: homePreferencesURL)
        let newPreferenceFiles = remainingFiles.subtracting(existingFiles).filter {
            $0 == "preferences.plist" || $0.contains(preferences.directoryURL.lastPathComponent)
        }
        XCTAssertTrue(newPreferenceFiles.isEmpty, "Unexpected preferences files: \(newPreferenceFiles.sorted())")
    }

    private func preferenceFileNames(in directory: URL) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }
}
