import AppKit
import QuartzCore

/// What one Classical presentation draws on its screen: the screen's desktop picture, loaded
/// asynchronously, the springboard layers built over it, and the menu bar's coverage, which follows
/// their opacity. The window controller owns visibility requests, focus and the window, and decides
/// when this loads, builds, resizes or is torn down; a load's result is delivered only while the
/// caller's `isCurrent` still holds.
@MainActor
final class ClassicalDesktopStage {
    let menuBarVisibility: ClassicalMenuBarVisibility
    private(set) var layers: ClassicalSpringboardLayers?
    /// The display the presentation is on.
    var screenIdentifier: NSNumber?
    /// Called when the system reports a changed desktop picture.
    var desktopPictureDidChange: (@MainActor () -> Void)?
    private let desktopImage: @MainActor (NSScreen) async throws -> CGImage
    private var imageTask: Task<Void, Never>?
    private var desktopObserver: NSObjectProtocol?

    /// Posted by the system when a desktop picture changes (object "BackgroundChanged").
    static let desktopChangedNotification = Notification.Name("com.apple.desktop")

    init(desktopImage: (@MainActor (NSScreen) async throws -> CGImage)?, menuBarVisibility: ClassicalMenuBarVisibility) {
        if let desktopImage {
            self.desktopImage = desktopImage
        } else {
            let picture = ClassicalDesktopPicture()
            self.desktopImage = { screen in try await picture.image(for: screen) }
        }
        self.menuBarVisibility = menuBarVisibility
        desktopObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.desktopChangedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.desktopPictureDidChange?() }
        }
    }

    isolated deinit {
        if let desktopObserver { DistributedNotificationCenter.default().removeObserver(desktopObserver) }
        imageTask?.cancel()
    }

    /// The presented screen, while it is still connected.
    var screen: NSScreen? { NSScreen.screens.first { $0.displayNumber == screenIdentifier } }

    /// Loads `screen`'s desktop picture, replacing a load in progress. `completion` runs unless the
    /// load was cancelled or `isCurrent` no longer holds.
    func loadImage(for screen: NSScreen, isCurrent: @escaping @MainActor () -> Bool,
                   completion: @escaping @MainActor (Result<CGImage, Error>) -> Void) {
        let provider = desktopImage
        imageTask?.cancel()
        imageTask = Task { [weak self] in
            let result: Result<CGImage, Error>
            do { result = .success(try await provider(screen)) } catch { result = .failure(error) }
            guard !Task.isCancelled, let self, isCurrent() else { return }
            self.imageTask = nil
            completion(result)
        }
    }

    func cancelImageLoad() {
        imageTask?.cancel()
        imageTask = nil
    }

    /// Replaces any earlier layers with new ones laid out for `screen`, and returns them with the
    /// desktop layer showing `image`, ready for `ClassicalSpringboardLayers.show`.
    func build(image: CGImage, screen: NSScreen) -> (layers: ClassicalSpringboardLayers, desktop: CALayer) {
        let bounds = CGRect(origin: .zero, size: screen.frame.size)
        let desktop = CALayer()
        desktop.frame = bounds
        desktop.contents = image
        desktop.contentsScale = screen.backingScaleFactor
        let layers = ClassicalSpringboardLayers()
        self.layers?.destroy()
        self.layers = layers
        layers.layout(rootFrame: bounds, contentFrame: bounds)
        return (layers, desktop)
    }

    func tearDown() {
        layers?.destroy()
        layers = nil
    }

    /// Fades a changed desktop picture in over the shown layers.
    func crossfadeDesktop(on screen: NSScreen, isCurrent: @escaping @MainActor () -> Bool) {
        loadImage(for: screen, isCurrent: isCurrent) { [weak self] result in
            guard case let .success(image) = result else { return }
            _ = self?.layers?.crossfadeDesktop(to: image)
        }
    }

    /// Resizes the shown layers to `screen` at once and replaces the desktop picture once loaded;
    /// `failed` receives a load error.
    func resize(to screen: NSScreen, isCurrent: @escaping @MainActor () -> Bool,
                failed: @escaping @MainActor (Error) -> Void) {
        layers?.resizeDesktop(to: CGRect(origin: .zero, size: screen.frame.size), scale: screen.backingScaleFactor)
        loadImage(for: screen, isCurrent: isCurrent) { [weak self] result in
            switch result {
            case let .success(image): self?.layers?.replaceDesktopImage(image)
            case let .failure(error): failed(error)
            }
        }
    }

    // MARK: Menu bar

    /// The layers' on-screen opacity while they may cover the menu bar; nil otherwise. Between
    /// animations the settled model value is used, so completion lands exactly on 0 or 1.
    private func menuBarCoveringOpacity(in window: NSWindow?) -> Float? {
        guard let window, window.isVisible, window.alphaValue > 0, let layers, layers.layer.superlayer != nil else {
            return nil
        }
        let settled = layers.layer.opacity
        return menuBarVisibility.isFollowing ? layers.layer.presentation()?.opacity ?? settled : settled
    }

    func coverMenuBar(in window: NSWindow?) {
        menuBarVisibility.cover(opacity: menuBarCoveringOpacity(in: window))
    }

    /// Covers the menu bar on every display refresh of `window` until `stopFollowing()`.
    func followMenuBar(in window: NSWindow?) {
        guard let content = window?.contentView else { return }
        menuBarVisibility.follow(in: content) { [weak self, weak window] in self?.menuBarCoveringOpacity(in: window) }
    }
}
