import Foundation
import Testing
@testable import Launchpod

struct AppMetadataTests {
    @Test(arguments: [
        "/Applications/Example.app",
        "/Applications/Example.app/",
        "/Applications/./Example.app",
        "/Applications/Tools/../Example.app"
    ])
    func lexicalLocationVariantsNormalizeWithoutRequiringAnInstalledApp(path: String) throws {
        let metadata = try AppMetadata(
            bundleIdentifier: "com.example.Example",
            bundleURL: URL(fileURLWithPath: path, isDirectory: true),
            displayName: "Example"
        )

        #expect(metadata.bundleURL.absoluteString == "file:///Applications/Example.app/")
    }

    @Test(arguments: [
        ("file:///Applications/%2E/Example.app", "/Applications/Example.app"),
        ("file:///Applications/Tools/%2E%2E/Example.app", "/Applications/Example.app"),
        ("file:///Applications/Editor%20Pro.app", "/Applications/Editor Pro.app"),
        ("file:///Applications/Progress%25.app", "/Applications/Progress%.app"),
        ("file:///Applications/%E6%96%87%E7%A8%BF.app", "/Applications/\u{6587}\u{7a3f}.app"),
        ("file:///Applications/%F0%9F%9A%80.app", "/Applications/🚀.app"),
        ("file:///Applications/%252E/Example.app", "/Applications/%2E/Example.app"),
        ("file:///Applications/%252E%252E/Example.app", "/Applications/%2E%2E/Example.app"),
        ("file:///Applications/Tools%2FExample.app", "/Applications/Tools%2FExample.app"),
        ("file:///Applications/Tools%252FExample.app", "/Applications/Tools%2FExample.app")
    ])
    func encodedLocationsHaveTheSameCanonicalValueAfterPersistence(location: String, expectedPath: String) throws {
        let metadata = try AppMetadata(
            bundleIdentifier: "com.example.Editor", bundleURL: #require(URL(string: location)), displayName: "Editor"
        )
        let expected = URL(fileURLWithPath: expectedPath, isDirectory: true)
        let restored = try JSONDecoder().decode(AppMetadata.self, from: JSONEncoder().encode(metadata))
        let canonicalMetadata = try AppMetadata(
            bundleIdentifier: "com.example.Editor", bundleURL: expected, displayName: "Editor"
        )
        let source = try AppSource(kind: .system, directoryURL: URL(fileURLWithPath: "/Applications", isDirectory: true))
        let record = AppRecord(metadata: metadata, source: source)

        #expect(metadata.bundleURL == expected)
        #expect(restored == metadata)
        #expect(record.matchesBundleAndLocation(of: canonicalMetadata))
    }

    @Test
    func metadataPreservesScannedSpellingAndOptionalValues() throws {
        let fixture = Data(#"{"bundleIdentifier":"Com.Example.Editor","bundleURL":"file:///Applications/Example.app/","displayName":"\u6587\u7a3f — Editor","version":"2.4","buildVersion":"204","categoryIdentifier":"public.app-category.developer-tools","contentModificationDate":123456.25,"isApplication":true,"isUIElement":false,"isBackgroundOnly":false}"#.utf8)
        let metadata = try JSONDecoder().decode(AppMetadata.self, from: fixture)

        #expect(metadata.bundleIdentifier == "Com.Example.Editor")
        #expect(metadata.displayName == "\u{6587}\u{7a3f} — Editor")
        #expect(metadata.version == "2.4")
        #expect(metadata.buildVersion == "204")
        #expect(metadata.categoryIdentifier == "public.app-category.developer-tools")
        #expect(metadata.contentModificationDate == Date(timeIntervalSinceReferenceDate: 123456.25))
        #expect(metadata.isApplication == true)
        #expect(metadata.isUIElement == false)
        #expect(metadata.isBackgroundOnly == false)
        #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? NSDictionary
            == JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
    }

    @Test(arguments: [nil, false, true] as [Bool?])
    func unknownDiscoveryFlagsStayDistinctFromExplicitFalse(observed: Bool?) throws {
        let metadata = try AppMetadata(
            bundleIdentifier: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app", isDirectory: true),
            displayName: "Editor", isApplication: observed, isUIElement: observed, isBackgroundOnly: observed,
            isBeta: observed, isStoreApp: observed
        )
        let data = try JSONEncoder().encode(metadata)
        let restored = try JSONDecoder().decode(AppMetadata.self, from: data)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(restored.isApplication == observed)
        #expect(restored.isUIElement == observed)
        #expect(restored.isBackgroundOnly == observed)
        #expect(restored.isBeta == observed)
        #expect(restored.isStoreApp == observed)
        for key in ["isApplication", "isUIElement", "isBackgroundOnly", "isBeta", "isStoreApp"] {
            #expect(object[key] as? Bool == observed)
            if observed == nil {
                #expect(object[key] == nil)
            }
        }
    }

    @Test(arguments: [
        #"{"bundleURL":"file:///Applications/Example.app/","displayName":"Example"}"#,
        #"{"bundleIdentifier":null,"bundleURL":"file:///Applications/Example.app/","displayName":"Example","version":null,"buildVersion":null,"categoryIdentifier":null,"contentModificationDate":null,"isApplication":null,"isUIElement":null,"isBackgroundOnly":null,"futureField":"ignored"}"#
    ])
    func absentAndNullOptionalMetadataDecodeWithoutInventingAnIdentity(json: String) throws {
        let metadata = try JSONDecoder().decode(AppMetadata.self, from: Data(json.utf8))

        #expect(metadata.bundleIdentifier == nil)
        #expect(metadata.version == nil)
        #expect(metadata.buildVersion == nil)
        #expect(metadata.categoryIdentifier == nil)
        #expect(metadata.contentModificationDate == nil)
        #expect(metadata.isApplication == nil)
        #expect(metadata.isUIElement == nil)
        #expect(metadata.isBackgroundOnly == nil)
        #expect(metadata.isBeta == nil)
        #expect(metadata.isStoreApp == nil)
        #expect(metadata.displayName == "Example")
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any])
        #expect(Set(encoded.keys) == ["bundleURL", "displayName"])
    }

    @Test(arguments: [
        ("categoryIdentifier", "7"),
        ("contentModificationDate", #""yesterday""#),
        ("isApplication", "1"),
        ("isUIElement", #""false""#),
        ("isBackgroundOnly", "[]"),
        ("isBeta", #""yes""#),
        ("isStoreApp", #""yes""#)
    ])
    func malformedDiscoveryMetadataIsNotTreatedAsUnknown(field: String, jsonValue: String) {
        let fixture = Data("{\"bundleURL\":\"file:///Applications/Example.app/\",\"displayName\":\"Editor\",\"\(field)\":\(jsonValue)}".utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppMetadata.self, from: fixture)
        }
    }

    @Test(arguments: [
        "https://example.com/Example.app",
        "file:Example.app",
        "file://remote.example/Applications/Example.app",
        "file:///Applications/Example.app?variant=1",
        "file:///Applications/Example.app#icon",
        "file://user@localhost/Applications/Example.app",
        "file://localhost:123/Applications/Example.app"
    ])
    func invalidBundleLocationsFailAtConstructionAndDecoding(location: String) throws {
        let url = try #require(URL(string: location))
        #expect(throws: AppMetadata.ValidationError.self) {
            try AppMetadata(bundleIdentifier: "com.example.Example", bundleURL: url, displayName: "Example")
        }
        let fixture = try JSONSerialization.data(withJSONObject: [
            "bundleURL": location, "displayName": "Example"
        ])
        #expect(throws: AppMetadata.ValidationError.self) {
            try JSONDecoder().decode(AppMetadata.self, from: fixture)
        }
    }

    @Test(arguments: [
        #"{}"#,
        #"{"bundleURL":"file:///Applications/Example.app/"}"#,
        #"{"bundleURL":null,"displayName":"Example"}"#,
        #"{"bundleURL":"file:///Applications/Example.app/","displayName":5}"#,
        #"{"bundleURL":"file:///Applications/Example.app/","displayName":"Example","bundleIdentifier":5}"#,
        #"{"bundleURL":"file:///Applications/Example.app/","displayName":"Example","version":5}"#,
        #"{"bundleURL":"file:///Applications/Example.app/","displayName":"Example","buildVersion":5}"#
    ])
    func malformedMetadataDoesNotSilentlyDefaultRequiredFields(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppMetadata.self, from: Data(json.utf8))
        }
    }
}
