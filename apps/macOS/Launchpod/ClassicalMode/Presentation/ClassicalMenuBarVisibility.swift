import AppKit
import Darwin

/// Owns the menu-bar opacity request and releases it back to system control.
@MainActor
final class ClassicalMenuBarVisibility {
    struct Operations {
        let connectionID: Int32
        let setAlpha: @MainActor (Int32, Double, Double, Float) -> Int32
        let reset: @MainActor (Int32) -> Int32
    }

    /// An outstanding reset obligation, not confirmation of the menu bar's rendered state.
    private(set) var hasPendingReset = false
    private var requestedAlpha: Float?
    private static let minimumStep: Float = 0.01
    private let frames = ClassicalFrameLink()
    private let resolveOperations: @MainActor () -> Operations?
    private lazy var operations = resolveOperations()

    init(resolveOperations: (@MainActor () -> Operations?)? = nil) {
        self.resolveOperations = resolveOperations ?? Self.nativeOperations
    }

    isolated deinit {
        frames.stop()
        restore()
    }

    var isFollowing: Bool { frames.isRunning }

    /// Makes the menu bar the complement of a covering layer's opacity, so the launcher appears to
    /// cover it; nil means nothing currently covers it and leaves the request unchanged.
    func cover(opacity: Float?) {
        guard let opacity else { return }
        setAlpha(1 - opacity)
    }

    /// Re-applies `cover(opacity:)` on every display refresh of `view` until `stopFollowing()`.
    func follow(in view: NSView, opacity: @escaping @MainActor () -> Float?) {
        frames.start(in: view) { [weak self] in self?.cover(opacity: opacity()) }
        cover(opacity: opacity())
    }

    func stopFollowing() {
        frames.stop()
    }

    func hide() {
        setAlpha(0)
    }

    /// Requests an override alpha; intermediate steps below `minimumStep` are coalesced,
    /// while the fully hidden and fully shown endpoints are always delivered.
    func setAlpha(_ alpha: Float) {
        let alpha = min(max(alpha, 0), 1)
        if let requestedAlpha {
            guard requestedAlpha != alpha else { return }
            let isEndpoint = alpha == 0 || alpha == 1
            guard isEndpoint || abs(requestedAlpha - alpha) >= Self.minimumStep else { return }
        }
        guard let operations else { return }
        requestedAlpha = alpha
        hasPendingReset = true
        if operations.setAlpha(operations.connectionID, 0, 1, alpha) != 0 {
            restore()
        }
    }

    /// Failed reset sends remain pending so the next cleanup can retry them.
    func restore() {
        requestedAlpha = nil
        guard hasPendingReset, let operations else { return }
        if operations.reset(operations.connectionID) == 0 {
            hasPendingReset = false
        }
    }

    private static func nativeOperations() -> Operations? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] == nil,
              environment["XCTestBundlePath"] == nil,
              NSClassFromString("XCTestCase") == nil,
              !Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") }),
              let functions = NativeFunctions() else { return nil }
        let connectionID = functions.mainConnectionID()
        guard connectionID != 0 else { return nil }
        return Operations(connectionID: connectionID, setAlpha: { connection, inset, factor, alpha in
            functions.setAlpha(connection, inset, factor, alpha)
        }, reset: { connection in
            functions.reset(connection)
        })
    }

    @MainActor
    private final class NativeFunctions {
        typealias MainConnectionID = @convention(c) () -> Int32
        typealias SetAlpha = @convention(c) (Int32, Double, Double, Float) -> Int32
        typealias Reset = @convention(c) (Int32) -> Int32

        private let handle: UnsafeMutableRawPointer
        let mainConnectionID: MainConnectionID
        let setAlpha: SetAlpha
        let reset: Reset

        init?() {
            guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                                      RTLD_LAZY | RTLD_LOCAL) else { return nil }
            guard let connection = dlsym(handle, "CGSMainConnectionID"),
                  let setter = dlsym(handle, "SLSSetMenuBarInsetAndAlpha"),
                  let reset = dlsym(handle, "SLSResetMenuBarSystemOverrideAlphas") else {
                dlclose(handle)
                return nil
            }
            self.handle = handle
            mainConnectionID = unsafeBitCast(connection, to: MainConnectionID.self)
            setAlpha = unsafeBitCast(setter, to: SetAlpha.self)
            self.reset = unsafeBitCast(reset, to: Reset.self)
        }

        isolated deinit {
            dlclose(handle)
        }
    }
}
