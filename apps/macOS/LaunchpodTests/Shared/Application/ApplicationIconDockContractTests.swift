import Foundation
import Testing
@testable import Launchpod

struct ApplicationIconDockContractTests {
    @Test
    @MainActor
    func producerAndDockTileConsumerShareExplicitPersistenceAndNotificationIdentifiers() {
        #expect(ApplicationIconDockContract.defaultsSuiteName == "app.joyx.launchpod.dock-icon")
        #expect(ApplicationIconDockContract.preferenceKey == "applicationIcon")
        #expect(ApplicationIconPreference.preferenceKey == ApplicationIconDockContract.preferenceKey)
        #expect(ApplicationIconDockContract.changedNotification.rawValue ==
                "app.joyx.launchpod.applicationIconChanged")
    }

    @Test
    func stableIdentifiersMapToTheResourcesConsumedByTheDockTile() {
        let expected: [(ApplicationIcon, String)] = [
            (.colorTiles, "ApplicationIconColorTiles"),
            (.colorGrid, "ApplicationIconColorGrid"),
            (.darkGrid, "ApplicationIconDarkGrid"),
            (.rocket, "ApplicationIconRocket")
        ]

        #expect(ApplicationIcon.allCases == expected.map(\.0))
        #expect(ApplicationIconDockContract.defaultIdentifier == ApplicationIcon.colorTiles.rawValue)
        for (icon, assetName) in expected {
            #expect(ApplicationIconDockContract.assetName(for: icon.rawValue) == assetName)
            #expect(icon.assetName == assetName)
        }
        #expect(ApplicationIconDockContract.assetName(for: "unknown") == nil)
    }
}
