import AppKit
import Testing
@testable import Launchpod

@MainActor
struct ApplicationIconApplierTests {
    private final class RecordingApplier: ApplicationIconApplying {
        var applied: [ApplicationIcon] = []
        var notificationCount = 0

        func apply(_ icon: ApplicationIcon) throws {
            applied.append(icon)
        }

        func notifyDockTile() {
            notificationCount += 1
        }
    }

    @Test
    func isolatedFactoryDoesNotConstructOrCallTheSystemApplier() throws {
        var constructedSystemApplier = false
        func makeSystemApplier() -> any ApplicationIconApplying {
            constructedSystemApplier = true
            return RecordingApplier()
        }

        let applier = ApplicationIconApplierFactory.make(
            isIsolated: true,
            system: makeSystemApplier()
        )
        try applier.apply(.colorTiles)
        applier.notifyDockTile()

        #expect(!constructedSystemApplier)
    }

    @Test
    func nonisolatedFactoryReturnsTheProvidedSystemApplier() throws {
        let systemApplier = RecordingApplier()
        let applier = ApplicationIconApplierFactory.make(isIsolated: false, system: systemApplier)

        try applier.apply(.rocket)
        applier.notifyDockTile()

        #expect(systemApplier.applied == [.rocket])
        #expect(systemApplier.notificationCount == 1)
    }

    @Test
    func currentUnitTestProcessUsesTheIsolatedApplicationIconPolicy() {
        #expect(DockMutationPolicy.isIsolated)
    }

    @Test
    func defaultIconClearsTheRunningOverrideWithoutLoadingAnAsset() throws {
        var loadedNames: [String] = []
        var runningIcons: [NSImage?] = []
        let applier = SystemApplicationIconApplier(
            loadImage: { name in
                loadedNames.append(name)
                return NSImage(size: NSSize(width: 16, height: 16))
            },
            setRunningIcon: { runningIcons.append($0) },
            postDockTileChange: { Issue.record("Applying an icon must not notify before persistence") }
        )

        try applier.apply(.colorTiles)

        #expect(loadedNames.isEmpty)
        #expect(runningIcons.count == 1)
        #expect(runningIcons[0] == nil)
    }

    @Test(arguments: [ApplicationIcon.colorGrid, .darkGrid, .rocket])
    func customIconPassesItsFinishedAssetUnchangedToTheRunningOverride(icon: ApplicationIcon) throws {
        let image = try #require(NSImage(named: icon.assetName))
        let originalPixels = image.tiffRepresentation
        var loadedNames: [String] = []
        var runningIcons: [NSImage?] = []
        let applier = SystemApplicationIconApplier(
            loadImage: { name in
                loadedNames.append(name)
                return image
            },
            setRunningIcon: { runningIcons.append($0) },
            postDockTileChange: { Issue.record("Applying an icon must not notify before persistence") }
        )

        try applier.apply(icon)

        #expect(loadedNames == [icon.assetName])
        #expect(runningIcons.count == 1)
        #expect(runningIcons[0] != nil)
        #expect(runningIcons[0] === image)
        #expect(runningIcons[0]?.tiffRepresentation == originalPixels)
    }

    @Test
    func unavailableCustomAssetDoesNotChangeTheRunningOverride() {
        var runningUpdateCount = 0
        var notificationCount = 0
        let applier = SystemApplicationIconApplier(
            loadImage: { _ in nil },
            setRunningIcon: { _ in runningUpdateCount += 1 },
            postDockTileChange: { notificationCount += 1 }
        )

        #expect(throws: ApplicationIconApplyError.assetUnavailable(name: ApplicationIcon.darkGrid.assetName)) {
            try applier.apply(.darkGrid)
        }
        #expect(runningUpdateCount == 0)
        #expect(notificationCount == 0)
    }

    @Test
    func dockTileNotificationUsesTheInjectedPublisher() {
        var notificationCount = 0
        let applier = SystemApplicationIconApplier(
            loadImage: { _ in nil },
            setRunningIcon: { _ in },
            postDockTileChange: { notificationCount += 1 }
        )

        applier.notifyDockTile()

        #expect(notificationCount == 1)
    }
}
