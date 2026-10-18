import Foundation
import Testing
@testable import Launchpod

struct AppSourceTests {
    @Test(arguments: [
        (AppSource.Kind.system, "system", "file:///Applications/"),
        (.user, "user", "file:///Users/example/Applications/"),
        (.custom, "custom", "file:///Volumes/External/Apps/")
    ])
    func sourceSchemaPreservesItsKindAndActualDirectory(
        kind: AppSource.Kind, identifier: String, directory: String
    ) throws {
        let fixture = Data("{\"kind\":\"\(identifier)\",\"directoryURL\":\"\(directory)\",\"isOnline\":true,\"volumeUUIDString\":\"d80d927e-0000-4444-aaaa-0123456789ab\"}".utf8)
        let source = try JSONDecoder().decode(AppSource.self, from: fixture)

        #expect(source.kind == kind)
        #expect(source.directoryURL.absoluteString == directory)
        #expect(source.isOnline == true)
        #expect(source.volumeUUIDString == "d80d927e-0000-4444-aaaa-0123456789ab")
        #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? NSDictionary
            == JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
    }

    @Test
    func customDirectoriesRemainDistinctAfterLexicalNormalization() throws {
        let first = try AppSource(
            kind: .custom, directoryURL: URL(fileURLWithPath: "/Volumes/External/Tools/../Apps", isDirectory: true)
        )
        let second = try AppSource(
            kind: .custom, directoryURL: URL(fileURLWithPath: "/Volumes/External/apps", isDirectory: true)
        )

        #expect(first.directoryURL.absoluteString == "file:///Volumes/External/Apps/")
        #expect(first != second)
    }

    @Test
    func unknownAdditionalSourceFieldsDoNotBreakExistingData() throws {
        let fixture = Data(#"{"kind":"custom","directoryURL":"file:///Volumes/External/Apps/","isOnline":null,"volumeUUIDString":null,"futureField":true}"#.utf8)
        let source = try JSONDecoder().decode(AppSource.self, from: fixture)

        #expect(source.kind == .custom)
        #expect(source.directoryURL.absoluteString == "file:///Volumes/External/Apps/")
        #expect(source.isOnline == nil)
        #expect(source.volumeUUIDString == nil)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        #expect(Set(encoded.keys) == ["kind", "directoryURL"])
    }

    @Test(arguments: [nil, false, true] as [Bool?])
    func onlineStateAndRawVolumeIdentifierSurvivePersistence(isOnline: Bool?) throws {
        let source = try AppSource(
            kind: .custom, directoryURL: URL(fileURLWithPath: "/Volumes/External/Apps", isDirectory: true),
            isOnline: isOnline, volumeUUIDString: "d80d927e-0000-4444-aaaa-0123456789ab"
        )
        let data = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(AppSource.self, from: data)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(restored.isOnline == isOnline)
        #expect(restored.volumeUUIDString == "d80d927e-0000-4444-aaaa-0123456789ab")
        #expect(object["isOnline"] as? Bool == isOnline)
        #expect(object["volumeUUIDString"] as? String == "d80d927e-0000-4444-aaaa-0123456789ab")
        if isOnline == nil {
            #expect(object["isOnline"] == nil)
        }
    }

    @Test(arguments: [
        #"{"kind":"custom","directoryURL":"file:///Volumes/External/Apps/","isOnline":"false"}"#,
        #"{"kind":"custom","directoryURL":"file:///Volumes/External/Apps/","isOnline":0}"#,
        #"{"kind":"custom","directoryURL":"file:///Volumes/External/Apps/","volumeUUIDString":7}"#
    ])
    func malformedSourceObservationsAreNotSilentlyDiscarded(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppSource.self, from: Data(json.utf8))
        }
    }

    @Test(arguments: [
        #"{}"#,
        #"{"kind":"custom"}"#,
        #"{"kind":"network","directoryURL":"file:///Applications/"}"#,
        #"{"kind":4,"directoryURL":"file:///Applications/"}"#,
        #"{"kind":"system","directoryURL":null}"#
    ])
    func malformedSourceCannotBeMisclassifiedAsADefaultSource(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppSource.self, from: Data(json.utf8))
        }
    }

    @Test(arguments: ["https://example.com/Apps/", "file:Apps"])
    func sourceConstructionAndDecodingRejectInvalidDirectories(location: String) throws {
        let url = try #require(URL(string: location))
        #expect(throws: AppSource.ValidationError.self) {
            try AppSource(kind: .custom, directoryURL: url)
        }
        let fixture = try JSONSerialization.data(withJSONObject: ["kind": "custom", "directoryURL": location])
        #expect(throws: AppSource.ValidationError.self) {
            try JSONDecoder().decode(AppSource.self, from: fixture)
        }
    }
}
