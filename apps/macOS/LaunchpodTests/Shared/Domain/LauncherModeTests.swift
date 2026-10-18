import Foundation
import Testing
@testable import Launchpod

struct LauncherModeTests {
    @Test(arguments: [
        (LauncherMode.classical, "classical"),
        (LauncherMode.window, "window")
    ])
    func stableIdentifiersMatchPersistedValues(mode: LauncherMode, identifier: String) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let persistedValue = Data("\"\(identifier)\"".utf8)

        #expect(mode.rawValue == identifier)
        #expect(try encoder.encode(mode) == persistedValue)
        #expect(try decoder.decode(LauncherMode.self, from: persistedValue) == mode)
    }
}
