import AppKit

enum ApplicationIconApplyError: Error, Equatable {
    case assetUnavailable(name: String)
}

protocol ApplicationIconApplying {
    @MainActor
    func apply(_ icon: ApplicationIcon) throws

    @MainActor
    func notifyDockTile()
}

extension ApplicationIconApplying {
    @MainActor
    func notifyDockTile() {}
}

nonisolated enum ApplicationIconApplierFactory {
    static func make(
        isIsolated: Bool,
        system: @autoclosure () -> any ApplicationIconApplying
    ) -> any ApplicationIconApplying {
        isIsolated ? IsolatedApplicationIconApplier() : system()
    }
}

private struct IsolatedApplicationIconApplier: ApplicationIconApplying {
    nonisolated init() {}

    @MainActor
    func apply(_ icon: ApplicationIcon) throws {}
}

struct SystemApplicationIconApplier: ApplicationIconApplying {
    private let loadImage: @MainActor (String) -> NSImage?
    private let setRunningIcon: @MainActor (NSImage?) -> Void
    private let postDockTileChange: @MainActor () -> Void

    nonisolated init(
        loadImage: @escaping @MainActor (String) -> NSImage? = { NSImage(named: $0) },
        setRunningIcon: @escaping @MainActor (NSImage?) -> Void = {
            NSApplication.shared.applicationIconImage = $0
        },
        postDockTileChange: @escaping @MainActor () -> Void = {
            DistributedNotificationCenter.default().postNotificationName(
                ApplicationIconDockContract.changedNotification,
                object: nil
            )
        }
    ) {
        self.loadImage = loadImage
        self.setRunningIcon = setRunningIcon
        self.postDockTileChange = postDockTileChange
    }

    @MainActor
    func apply(_ icon: ApplicationIcon) throws {
        guard icon.rawValue != ApplicationIconDockContract.defaultIdentifier else {
            setRunningIcon(nil)
            return
        }
        guard let image = loadImage(icon.assetName) else {
            throw ApplicationIconApplyError.assetUnavailable(name: icon.assetName)
        }
        setRunningIcon(image)
    }

    @MainActor
    func notifyDockTile() {
        postDockTileChange()
    }
}
