import AppKit

@MainActor
@objc(LaunchpodDockTile)
final class LaunchpodDockTile: NSObject, @MainActor NSDockTilePlugIn {
    private weak var dockTile: NSDockTile?
    private var iconChangeObserver: NSObjectProtocol?
    private let defaults: UserDefaults?
    private let notificationCenter: NotificationCenter
    private let loadImage: (String) -> NSImage?

    override convenience init() {
        self.init(
            defaults: UserDefaults(suiteName: ApplicationIconDockContract.defaultsSuiteName),
            notificationCenter: DistributedNotificationCenter.default(),
            loadImage: { name in
                guard let url = Bundle(for: LaunchpodDockTile.self).url(forResource: name, withExtension: "png")
                else { return nil }
                return NSImage(contentsOf: url)
            }
        )
    }

    init(defaults: UserDefaults?, notificationCenter: NotificationCenter,
         loadImage: @escaping (String) -> NSImage?) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.loadImage = loadImage
        super.init()
    }

    func setDockTile(_ dockTile: NSDockTile?) {
        self.dockTile = dockTile
        if dockTile == nil {
            stopObservingIconChanges()
            return
        }
        startObservingIconChanges()
        updateIcon()
    }

    isolated deinit {
        stopObservingIconChanges()
    }

    private func startObservingIconChanges() {
        guard iconChangeObserver == nil else { return }
        iconChangeObserver = notificationCenter.addObserver(
            forName: ApplicationIconDockContract.changedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The observer queue guarantees main-thread delivery.
            MainActor.assumeIsolated { self?.updateIcon() }
        }
    }

    private func stopObservingIconChanges() {
        guard let iconChangeObserver else { return }
        notificationCenter.removeObserver(iconChangeObserver)
        self.iconChangeObserver = nil
    }

    private func updateIcon() {
        guard let dockTile else { return }
        let identifier = defaults?.string(forKey: ApplicationIconDockContract.preferenceKey)
            ?? ApplicationIconDockContract.defaultIdentifier

        guard identifier != ApplicationIconDockContract.defaultIdentifier,
              let assetName = ApplicationIconDockContract.assetName(for: identifier)
        else {
            dockTile.contentView = nil
            dockTile.display()
            return
        }
        guard let image = loadImage(assetName) else { return }

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: dockTile.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        dockTile.contentView = imageView
        dockTile.display()
    }
}
