import AppKit
import QuartzCore

/// Calls back on every display refresh of a view's screen until stopped.
@MainActor
final class ClassicalFrameLink {
    private var link: CADisplayLink?

    var isRunning: Bool { link != nil }

    isolated deinit {
        stop()
    }

    func start(in view: NSView, onFrame: @escaping @MainActor () -> Void) {
        guard link == nil else { return }
        let link = view.displayLink(target: Target(onFrame: onFrame), selector: #selector(Target.frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// The display link retains its target; the callback must capture its owner weakly.
    private final class Target: NSObject {
        let onFrame: @MainActor () -> Void

        init(onFrame: @escaping @MainActor () -> Void) {
            self.onFrame = onFrame
        }

        @objc func frame(_ link: CADisplayLink) {
            MainActor.assumeIsolated { onFrame() }
        }
    }
}
