import Foundation

/// Selects process-local Dock behavior for test hosts and explicitly isolated app launches.
nonisolated enum DockMutationPolicy {
    static let inMemoryStoreArgumentKey = "inMemoryDockStore"

    static var isIsolated: Bool {
        isIsolated(
            environment: ProcessInfo.processInfo.environment,
            arguments: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain),
            hasTestRuntime: NSClassFromString("XCTestCase") != nil
                || Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") })
        )
    }

    static func isIsolated(
        environment: [String: String], arguments: [String: Any], hasTestRuntime: Bool
    ) -> Bool {
        let isTestHost = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil || hasTestRuntime
        let isRequested = (arguments[inMemoryStoreArgumentKey] as? String)
            .map { NSString(string: $0).boolValue } ?? false
        return isTestHost || isRequested
    }
}
