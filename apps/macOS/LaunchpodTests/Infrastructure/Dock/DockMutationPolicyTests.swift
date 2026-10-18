import Testing
@testable import Launchpod

struct DockMutationPolicyTests {
    @Test(arguments: ["YES", "true", "1"])
    func explicitUITestIsolationDisablesNativeDockMutation(value: String) {
        #expect(DockMutationPolicy.isIsolated(
            environment: [:], arguments: ["inMemoryDockStore": value], hasTestRuntime: false
        ))
    }

    @Test(arguments: ["XCTestConfigurationFilePath", "XCTestBundlePath"])
    func testRunnerEnvironmentDisablesNativeDockMutation(key: String) {
        #expect(DockMutationPolicy.isIsolated(
            environment: [key: "/tmp/LaunchpodTests"], arguments: [:], hasTestRuntime: false
        ))
    }

    @Test
    func loadedTestRuntimeDisablesNativeDockMutationWithoutAnEnvironmentMarker() {
        #expect(DockMutationPolicy.isIsolated(environment: [:], arguments: [:], hasTestRuntime: true))
    }

    @Test
    func ordinaryLaunchRetainsNativeDockIntegration() {
        #expect(!DockMutationPolicy.isIsolated(environment: [:], arguments: [:], hasTestRuntime: false))
        #expect(!DockMutationPolicy.isIsolated(
            environment: [:], arguments: ["inMemoryDockStore": "NO"], hasTestRuntime: false
        ))
    }
}
