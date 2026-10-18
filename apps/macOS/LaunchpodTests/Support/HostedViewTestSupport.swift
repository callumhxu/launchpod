import AppKit
import SwiftUI
import XCTest

@MainActor
final class HostedViewTestSupport {
    let host: NSView
    let window: NSWindow
    private let restoreHost: @MainActor () -> Void

    init(view: some View, size: CGSize) throws {
        try NativeAppTestSupport.requireNativeWindowTests()
        restoreHost = try NativeAppTestSupport.isolateHostWindows()
        let hosting = NSHostingView(rootView: view
            .environment(\.locale, Locale(identifier: "en"))
            .transaction { $0.disablesAnimations = true })
        host = hosting
        window = NativeAppTestSupport.makeKeyPanel(size: size, contentView: hosting)
        hosting.layoutSubtreeIfNeeded()
    }

    func close() {
        window.close()
        restoreHost()
    }

}
