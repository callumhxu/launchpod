import AppKit
import CoreServices

/// Opens an application on a global queue: `LSOpenFromURLSpec` with the
/// bundle as the only item URL, launch flags `0x45` — which include `kLSLaunchAndDisplayErrors`, so
/// LaunchServices itself shows first-launch confirmations and failures — and the display to open
/// on passed as the `'disp'` parameter. Nothing waits for the application to finish launching.
nonisolated enum ClassicalApplicationOpener {
    static let launchFlags: LSLaunchFlags = LSLaunchFlags(rawValue: 0x45)
    /// `'disp'` (`0x64697370`).
    static let displayKeyword: AEKeyword = 0x6469_7370

    /// Missing bundles are not opened.
    static func canOpen(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func open(_ url: URL, display: CGDirectDisplayID?) {
        DispatchQueue.global().async {
            _ = openNow(url, display: display)
        }
    }

    @discardableResult
    static func openNow(_ url: URL, display: CGDirectDisplayID?) -> OSStatus {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        let parameters = display.map { display -> NSAppleEventDescriptor in
            let record = NSAppleEventDescriptor.record()
            record.setDescriptor(NSAppleEventDescriptor(int32: Int32(bitPattern: display)), forKeyword: displayKeyword)
            return record
        }
        let items = [url] as CFArray
        return withUnsafePointer(to: parameters?.aeDesc?.pointee ?? AEDesc()) { descriptor in
            var spec = LSLaunchURLSpec(appURL: nil, itemURLs: Unmanaged.passUnretained(items),
                                       passThruParams: parameters == nil ? nil : descriptor,
                                       launchFlags: launchFlags, asyncRefCon: nil)
            return LSOpenFromURLSpec(&spec, nil)
        }
    }
}
