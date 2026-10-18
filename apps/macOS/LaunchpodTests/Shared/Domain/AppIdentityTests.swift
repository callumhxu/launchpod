import Foundation
import Testing
@testable import Launchpod

struct AppIdentityTests {
    @Test
    func persistedIdentityUsesAUUIDStringIndependentOfBundleMetadata() throws {
        let value = UUID(uuidString: "41B4AC56-38CE-4C82-880F-A92032C13A20")!
        let identity = AppIdentity(rawValue: value)
        let fixture = Data(#""41B4AC56-38CE-4C82-880F-A92032C13A20""#.utf8)

        #expect(try JSONEncoder().encode(identity) == fixture)
        let restored = try JSONDecoder().decode(AppIdentity.self, from: fixture)
        #expect(restored.rawValue == value)
        #expect([identity: "saved user data"][restored] == "saved user data")
    }

    @Test(arguments: [#"null"#, #"42"#, #"{}"#, #"[]"#, #""""#, #""com.example.app""#])
    func malformedPersistedIdentityCannotBecomeAValidKey(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppIdentity.self, from: Data(json.utf8))
        }
    }
}
