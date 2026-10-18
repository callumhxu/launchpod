import Foundation
import Testing
@testable import Launchpod

struct ApplicationIconDefaultsFactoryTests {
    @Test
    func isolatedProcessUsesTheInjectedFallbackDomain() {
        let fallback = UserDefaults.standard

        let defaults = ApplicationIconDefaultsFactory.make(
            isIsolated: true,
            fallback: fallback
        )

        #expect(defaults === fallback)
    }

    @Test
    func productionProcessUsesTheDedicatedDockIconDomain() {
        let fallback = UserDefaults.standard

        let defaults = ApplicationIconDefaultsFactory.make(
            isIsolated: false,
            fallback: fallback
        )

        #expect(ApplicationIconDockContract.defaultsSuiteName == "app.joyx.launchpod.dock-icon")
        #expect(defaults !== fallback)
    }
}
