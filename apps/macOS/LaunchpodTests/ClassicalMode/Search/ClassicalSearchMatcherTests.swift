import XCTest
@testable import Launchpod

/// Classical search matching rules.
final class ClassicalSearchMatcherTests: XCTestCase {
    private func match(_ title: String, _ term: String, fileName: String? = nil) -> Bool {
        ClassicalSearchMatcher.matches(title: title, fileName: fileName, term: term)
    }

    /// Applications that cannot be resolved are skipped before matching: a missing application or
    /// one on an offline volume never matches, while unknown availability still does.
    func testMissingAndOfflineApplicationsNeverMatch() throws {
        let url = URL(filePath: "/Applications/Studio.app", directoryHint: .isDirectory)
        let metadata = try AppMetadata(bundleIdentifier: "com.example.studio", bundleURL: url, displayName: "Studio",
                                       version: nil, buildVersion: nil, contentModificationDate: nil)
        func record(isMissing: Bool?, isOnline: Bool?) throws -> AppRecord {
            AppRecord(metadata: metadata,
                      source: try AppSource(kind: .custom, directoryURL: url.deletingLastPathComponent(), isOnline: isOnline),
                      isMissing: isMissing)
        }

        XCTAssertTrue(ClassicalSearchMatcher.matches(try record(isMissing: nil, isOnline: nil), term: "stu"))
        XCTAssertTrue(ClassicalSearchMatcher.matches(try record(isMissing: false, isOnline: true), term: "stu"))
        XCTAssertFalse(ClassicalSearchMatcher.matches(try record(isMissing: true, isOnline: true), term: "stu"))
        XCTAssertFalse(ClassicalSearchMatcher.matches(try record(isMissing: false, isOnline: false), term: "stu"))
        XCTAssertFalse(ClassicalSearchMatcher.matches(try record(isMissing: nil, isOnline: false), term: "Studio"))
    }

    func testTermsPrefixTheTitleOrAnyWordIgnoringCase() {
        XCTAssertTrue(match("Safari", "saf"))
        XCTAssertTrue(match("App Store", "STO"))
        XCTAssertFalse(match("App Store", "tore"), "Only prefixes match, not substrings")
        XCTAssertFalse(match("Safari", ""))
    }

    func testCamelCaseSplitsWords() {
        XCTAssertTrue(match("FaceTime", "time"))
        XCTAssertTrue(match("iMovie", "mov"))
        XCTAssertEqual(ClassicalSearchMatcher.words(in: "FaceTime Pro"), ["Face", "Time", "Pro"])
    }

    func testSingleCapitalsJoinIntoOneWord() {
        XCTAssertEqual(ClassicalSearchMatcher.words(in: "A B C Tool"), ["ABC", "Tool"])
    }

    func testInitialsOfLeadingWordsMatch() {
        XCTAssertTrue(match("System Settings", "ss"))
        XCTAssertTrue(match("Visual Studio Code", "v sc"), "Spaces in the term are ignored for initials")
        XCTAssertFalse(match("Visual Studio Code", "vsca"), "More initials than words never match")
        XCTAssertFalse(match("Visual Studio Code", "sc"), "Initials start at the first word")
    }

    func testSpacesAreIgnoredAgainstTheWholeTitle() {
        XCTAssertTrue(match("System Settings", "systemse"))
        XCTAssertTrue(match("System Settings", "system se"))
        XCTAssertFalse(match("System Settings", "settingssy"))
    }

    func testTheBundleFileNameMatchesWhenItDiffersFromTheTitle() {
        XCTAssertTrue(match("Code", "vis", fileName: "Visual Studio Code"))
        XCTAssertFalse(match("Code", "vis", fileName: "Code"))
    }
}
