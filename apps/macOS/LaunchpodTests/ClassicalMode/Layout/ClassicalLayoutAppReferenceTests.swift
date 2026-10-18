import Foundation
import XCTest
@testable import Launchpod

/// The bundle and location a layout keeps for each application identity, and the catalog identity
/// that takes over a slot when the shared app data replaced that identity.
final class ClassicalLayoutAppReferenceTests: XCTestCase {
    private func record(_ bundleID: String?, path: String, id: AppIdentity = AppIdentity()) throws -> AppRecord {
        let bundleURL = URL(filePath: path, directoryHint: .isDirectory)
        return AppRecord(
            id: id,
            metadata: try AppMetadata(bundleIdentifier: bundleID, bundleURL: bundleURL,
                                      displayName: bundleURL.deletingPathExtension().lastPathComponent),
            source: try AppSource(kind: .custom, directoryURL: bundleURL.deletingLastPathComponent(), isOnline: true)
        )
    }

    private func reference(_ record: AppRecord) throws -> ClassicalLayoutAppReference {
        try XCTUnwrap(ClassicalLayoutAppReference(record: record))
    }

    func testReferenceRequiresABundleIdentifierAndALocalFileLocation() throws {
        let location = URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory)
        XCTAssertThrowsError(try ClassicalLayoutAppReference(id: AppIdentity(), bundleIdentifier: "", bundleURL: location))
        XCTAssertThrowsError(try ClassicalLayoutAppReference(
            id: AppIdentity(), bundleIdentifier: "com.example.Editor",
            bundleURL: try XCTUnwrap(URL(string: "https://example.com/Editor.app"))
        ))
        let valid = try ClassicalLayoutAppReference(id: AppIdentity(), bundleIdentifier: "com.example.Editor",
                                                    bundleURL: location)
        XCTAssertEqual(valid.bundleURL, AppFileURL.normalized(location))
    }

    func testRecordWithoutABundleIdentifierHasNoReference() throws {
        XCTAssertNil(ClassicalLayoutAppReference(record: try record(nil, path: "/Applications/Tool.app")))
        let editor = try record("com.example.Editor", path: "/Applications/Editor.app")
        let saved = try reference(editor)
        XCTAssertEqual(saved.id, editor.id)
        XCTAssertEqual(saved.bundleIdentifier, "com.example.Editor")
        XCTAssertEqual(saved.bundleURL, editor.metadata.bundleURL)
    }

    func testReplacedIdentityIsTakenOverByTheRecordWithTheSameBundleAndLocation() throws {
        let old = try record("com.example.Editor", path: "/Applications/Editor.app")
        let new = try record("COM.EXAMPLE.editor", path: "/Applications/Editor.app")
        let elsewhere = try record("com.example.Editor", path: "/Applications/Old/Editor.app")
        let replacements = ClassicalLayoutAppReference.replacements(for: [try reference(old)],
                                                                    in: [elsewhere, new], excluding: [old.id])
        XCTAssertEqual(replacements, [old.id: new.id], "The bundle identifier matches without regard to case")
    }

    func testIdentityTheCatalogStillHoldsIsNotReplaced() throws {
        let kept = try record("com.example.Editor", path: "/Applications/Editor.app")
        let copy = try record("com.example.Editor", path: "/Applications/Editor.app")
        XCTAssertEqual(ClassicalLayoutAppReference.replacements(for: [try reference(kept)], in: [kept, copy],
                                                                excluding: [kept.id]), [:])
    }

    func testDifferentLocationOrBundleIdentifierIsNotAReplacement() throws {
        let old = try record("com.example.Editor", path: "/Applications/Editor.app")
        let moved = try record("com.example.Editor", path: "/Applications/Tools/Editor.app")
        let other = try record("com.example.Viewer", path: "/Applications/Editor.app")
        XCTAssertEqual(ClassicalLayoutAppReference.replacements(for: [try reference(old)], in: [moved, other],
                                                                excluding: [old.id]), [:])
    }

    func testRecordTheLayoutAlreadyHoldsIsNotClaimed() throws {
        let old = try record("com.example.Editor", path: "/Applications/Editor.app")
        let held = try record("com.example.Editor", path: "/Applications/Editor.app")
        XCTAssertEqual(ClassicalLayoutAppReference.replacements(for: [try reference(old)], in: [held],
                                                                excluding: [old.id, held.id]), [:],
                       "An application already in the layout never gains a second slot")
    }

    func testAmbiguousMatchesAreNotReplaced() throws {
        let old = try record("com.example.Editor", path: "/Applications/Editor.app")
        let first = try record("com.example.Editor", path: "/Applications/Editor.app")
        let second = try record("com.example.Editor", path: "/Applications/Editor.app")
        XCTAssertEqual(ClassicalLayoutAppReference.replacements(for: [try reference(old)], in: [first, second],
                                                                excluding: [old.id]), [:],
                       "Two qualifying records leave the reference unmatched")

        let otherOld = try record("com.example.Editor", path: "/Applications/Editor.app")
        XCTAssertEqual(ClassicalLayoutAppReference.replacements(for: [try reference(old), try reference(otherOld)],
                                                                in: [first], excluding: [old.id, otherOld.id]), [:],
                       "A record claimed by two references replaces neither")
    }

    func testCodingRoundTripsAndRejectsInvalidValues() throws {
        let saved = try reference(try record("com.example.Editor", path: "/Applications/Editor.app"))
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(ClassicalLayoutAppReference.self, from: data), saved)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["id", "bundleIdentifier", "bundleURL"])

        for (key, value) in [("bundleIdentifier", ""), ("bundleURL", "https://example.com/Editor.app")] {
            var edited = json
            edited[key] = value
            XCTAssertThrowsError(try JSONDecoder().decode(ClassicalLayoutAppReference.self,
                                                          from: JSONSerialization.data(withJSONObject: edited)),
                                 "An invalid \(key) is rejected")
        }
    }
}
