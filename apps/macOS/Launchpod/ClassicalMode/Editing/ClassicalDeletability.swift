import Foundation
import ObjectiveC

/// Whether an application can be deleted: the system uninstaller reports the bundle as
/// uninstallable (1), in practice App Store applications.
///
/// The query is `+[UNUninstallRequest uninstallablityOfFileAtURL:]` in `Uninstall.framework`.
/// Missing frameworks report nothing deletable.
nonisolated enum ClassicalDeletability {
    private typealias Query = @convention(c) (AnyClass, Selector, NSURL) -> Int

    private static let query: (AnyClass, Selector, Query)? = {
        _ = dlopen("/System/Library/PrivateFrameworks/Uninstall.framework/Versions/A/Uninstall", RTLD_NOW)
        let selector = NSSelectorFromString("uninstallablityOfFileAtURL:")
        guard let type = NSClassFromString("UNUninstallRequest"),
              let method = class_getClassMethod(type, selector) else { return nil }
        return (type, selector, unsafeBitCast(method_getImplementation(method), to: Query.self))
    }()

    static func isDeletable(_ url: URL) -> Bool {
        guard let (type, selector, call) = query else { return false }
        return call(type, selector, url as NSURL) == 1
    }
}
