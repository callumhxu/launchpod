import XCTest
@testable import Launchpod

final class ClassicalFolderGlassPreferenceTests: XCTestCase {
    func testGlassIsOnByDefaultAndCanBeExplicitlyDisabled() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }

        XCTAssertTrue(ClassicalFolderGlassPreference.isEnabled(in: defaults))
        XCTAssertNil(defaults.object(forKey: ClassicalFolderGlassPreference.key))

        defaults.set(false, forKey: ClassicalFolderGlassPreference.key)
        XCTAssertFalse(ClassicalFolderGlassPreference.isEnabled(in: defaults))

        defaults.set(true, forKey: ClassicalFolderGlassPreference.key)
        XCTAssertTrue(ClassicalFolderGlassPreference.isEnabled(in: defaults))
    }
}
