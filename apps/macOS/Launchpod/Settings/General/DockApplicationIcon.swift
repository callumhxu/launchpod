import AppKit
import SwiftUI

struct DockApplicationIcon: NSViewRepresentable {
    let applicationIcon: ApplicationIcon?

    init(applicationIcon: ApplicationIcon? = nil) {
        self.applicationIcon = applicationIcon
    }

    func makeNSView(context: Context) -> DockApplicationIconView {
        DockApplicationIconView(applicationURL: Bundle.main.bundleURL, image: resolvedImage)
    }

    func updateNSView(_ nsView: DockApplicationIconView, context: Context) {
        nsView.image = resolvedImage
    }

    private var resolvedImage: NSImage {
        ApplicationIconPreviewImage.resolve(applicationIcon)
    }
}

enum ApplicationIconPreviewImage {
    static func resolve(_ icon: ApplicationIcon?) -> NSImage {
        resolve(icon, bundledDefault: bundledDefault, loadAsset: { NSImage(named: $0) })
    }

    static func resolve(
        _ icon: ApplicationIcon?,
        bundledDefault: NSImage,
        loadAsset: (String) -> NSImage?
    ) -> NSImage {
        guard let icon, icon != .colorTiles,
              let source = loadAsset(icon.assetName)
        else { return bundledDefault }
        return source
    }

    private static let bundledDefault = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
}

final class DockApplicationIconView: NSImageView, NSDraggingSource {
    let applicationURL: URL
    private var mouseDownEvent: NSEvent?

    override var intrinsicContentSize: NSSize { .zero }

    init(applicationURL: URL, image: NSImage = ApplicationIconPreviewImage.resolve(nil)) {
        self.applicationURL = applicationURL
        super.init(frame: .zero)
        self.image = image
        imageScaling = .scaleProportionallyUpOrDown
        setAccessibilityIdentifier("dockApplicationIcon")
        setAccessibilityLabel("Launchpod")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent, let item = makeDraggingItem() else { return }
        self.mouseDownEvent = nil
        beginDraggingSession(with: [item], event: mouseDownEvent, source: self)
    }

    func makeDraggingItem() -> NSDraggingItem? {
        guard applicationURL.isFileURL,
              applicationURL.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: applicationURL.path),
              let image else { return nil }
        let item = NSDraggingItem(pasteboardWriter: applicationURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        return item
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.copy, .link]
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
