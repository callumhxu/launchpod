import AppKit
import Testing
@testable import Launchpod

@MainActor
struct LaunchpodDockTileTests {
    private final class DetachedDockTile: NSDockTile {
        private(set) var displays = 0
        private var storedContentView: NSView?
        override var size: NSSize { NSSize(width: 64, height: 64) }
        override var contentView: NSView? {
            get { storedContentView }
            set { storedContentView = newValue }
        }
        override func display() { displays += 1 }
    }

    private final class RecordingNotificationCenter: NotificationCenter, @unchecked Sendable {
        private(set) var names: [Notification.Name?] = []
        private(set) var queues: [OperationQueue?] = []
        private(set) var registrations: [ObjectIdentifier] = []
        private(set) var removals: [ObjectIdentifier] = []

        override func addObserver(forName name: Notification.Name?, object obj: Any?,
                                  queue: OperationQueue?, using block: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
            let token = super.addObserver(forName: name, object: obj, queue: queue, using: block)
            names.append(name)
            queues.append(queue)
            registrations.append(ObjectIdentifier(token))
            return token
        }

        override func removeObserver(_ observer: Any) {
            removals.append(ObjectIdentifier(observer as AnyObject))
            super.removeObserver(observer)
        }
    }

    @Test(arguments: [ApplicationIcon.colorGrid, .darkGrid, .rocket])
    func attachesTheActualPluginResourceWithoutChangingItsImage(icon: ApplicationIcon) throws {
        try withDefaults { defaults in
            defaults.set(icon.rawValue, forKey: ApplicationIconDockContract.preferenceKey)
            let image = try pluginImage(named: icon.assetName)
            let originalPixels = image.tiffRepresentation
            var loadedNames: [String] = []
            let plugin = LaunchpodDockTile(defaults: defaults, notificationCenter: NotificationCenter()) { name in
                loadedNames.append(name)
                return image
            }
            let tile = DetachedDockTile()

            (plugin as NSDockTilePlugIn).setDockTile(tile)

            let view = try #require(tile.contentView as? NSImageView)
            #expect(loadedNames == [icon.assetName])
            #expect(view.image === image)
            #expect(view.image?.tiffRepresentation == originalPixels)
            #expect(view.frame == NSRect(origin: .zero, size: tile.size))
            #expect(view.imageScaling == .scaleProportionallyUpOrDown)
            #expect(view.autoresizingMask == [.width, .height])
            #expect(tile.displays == 1)
        }
    }

    @Test(arguments: [Optional<String>.none, "colorTiles", "unsupported"])
    func missingDefaultOrUnknownIdentifierClearsTheOverride(identifier: String?) throws {
        try withDefaults { defaults in
            if let identifier { defaults.set(identifier, forKey: ApplicationIconDockContract.preferenceKey) }
            let tile = DetachedDockTile()
            tile.contentView = NSView()
            let plugin = LaunchpodDockTile(defaults: defaults, notificationCenter: NotificationCenter()) { _ in
                Issue.record("The bundled-default path must not load an alternate resource")
                return nil
            }

            plugin.setDockTile(tile)

            #expect(tile.contentView == nil)
            #expect(tile.displays == 1)
        }
    }

    @Test
    func notificationUpdatesTheAttachedTileAndDefaultSelectionClearsItsPreviousImage() throws {
        try withDefaults { defaults in
            let center = NotificationCenter()
            let image = try pluginImage(named: ApplicationIcon.rocket.assetName)
            let plugin = LaunchpodDockTile(defaults: defaults, notificationCenter: center) { _ in image }
            let tile = DetachedDockTile()
            plugin.setDockTile(tile)
            defaults.set(ApplicationIcon.rocket.rawValue, forKey: ApplicationIconDockContract.preferenceKey)

            center.post(name: ApplicationIconDockContract.changedNotification, object: nil)

            #expect((tile.contentView as? NSImageView)?.image === image)
            #expect(tile.displays == 2)
            defaults.set(ApplicationIcon.colorTiles.rawValue, forKey: ApplicationIconDockContract.preferenceKey)
            center.post(name: ApplicationIconDockContract.changedNotification, object: nil)
            #expect(tile.contentView == nil)
            #expect(tile.displays == 3)
        }
    }

    @Test
    func repeatedAttachmentRegistersOnceAndDetachRemovesTheObserverBeforeReattachment() throws {
        try withDefaults { defaults in
            let center = RecordingNotificationCenter()
            let plugin = LaunchpodDockTile(defaults: defaults, notificationCenter: center) { _ in nil }
            let first = DetachedDockTile()
            let second = DetachedDockTile()
            plugin.setDockTile(first)
            plugin.setDockTile(second)
            #expect(center.names == [ApplicationIconDockContract.changedNotification])
            #expect(center.queues.count == 1)
            let queue = try #require(center.queues.first)
            #expect(queue === OperationQueue.main)

            center.post(name: ApplicationIconDockContract.changedNotification, object: nil)

            #expect(first.displays == 1)
            #expect(second.displays == 2)
            plugin.setDockTile(nil)
            plugin.setDockTile(nil)
            #expect(center.removals == center.registrations)
            center.post(name: ApplicationIconDockContract.changedNotification, object: nil)
            #expect(second.displays == 2)
            plugin.setDockTile(first)
            #expect(center.registrations.count == 2)
            center.post(name: ApplicationIconDockContract.changedNotification, object: nil)
            #expect(first.displays == 3)
        }
    }

    @Test
    func pluginDeinitializationRemovesItsObserverWithoutARequiredDetachCall() throws {
        try withDefaults { defaults in
            let center = RecordingNotificationCenter()
            let tile = DetachedDockTile()
            var plugin: LaunchpodDockTile? = LaunchpodDockTile(defaults: defaults, notificationCenter: center) { _ in nil }
            weak let observed = plugin
            plugin?.setDockTile(tile)

            plugin = nil

            #expect(observed == nil, "Notification registration must not retain the plugin")
            #expect(center.registrations.count == 1)
            #expect(center.removals == center.registrations)
            center.post(name: ApplicationIconDockContract.changedNotification, object: nil)
            #expect(tile.displays == 1)
        }
    }

    @Test
    func unavailableImagePreservesExistingContentWithoutRedrawing() throws {
        try withDefaults { defaults in
            defaults.set(ApplicationIcon.darkGrid.rawValue, forKey: ApplicationIconDockContract.preferenceKey)
            let plugin = LaunchpodDockTile(defaults: defaults, notificationCenter: NotificationCenter()) { _ in nil }
            let tile = DetachedDockTile()
            let existingContent = NSView()
            tile.contentView = existingContent

            plugin.setDockTile(tile)

            #expect(tile.contentView === existingContent)
            #expect(tile.displays == 0)
        }
    }

    private func pluginImage(named name: String) throws -> NSImage {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let bundle = try #require(Bundle(url: plugins.appendingPathComponent("LaunchpodDockTile.docktileplugin")))
        let resource = try #require(bundle.url(forResource: name, withExtension: "png"))
        return try #require(NSImage(contentsOf: resource))
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        try body(defaults)
    }
}
