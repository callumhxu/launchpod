import Testing
@testable import Launchpod

@MainActor
struct LaunchAtLoginModelTests {
    private final class FakeService: LaunchAtLoginServicing {
        var status: LaunchAtLoginStatus
        var statusAfterRegister: LaunchAtLoginStatus = .enabled
        var statusAfterUnregister: LaunchAtLoginStatus = .notRegistered
        var registerError: TestError?
        var unregisterError: TestError?
        private(set) var registerCount = 0
        private(set) var unregisterCount = 0

        init(status: LaunchAtLoginStatus) {
            self.status = status
        }

        func register() throws {
            registerCount += 1
            status = statusAfterRegister
            if let registerError { throw registerError }
        }

        func unregister() throws {
            unregisterCount += 1
            status = statusAfterUnregister
            if let unregisterError { throw unregisterError }
        }
    }

    private enum TestError: Error, Equatable {
        case unavailable
    }

    @Test(arguments: [
        (LaunchAtLoginStatus.notRegistered, false),
        (.enabled, true),
        (.requiresApproval, true),
        (.notFound, false)
    ])
    func initialStateReflectsTheLoginItemRegistrationStatus(status: LaunchAtLoginStatus, enabled: Bool) {
        let model = LaunchAtLoginModel(service: FakeService(status: status))

        #expect(model.status == status)
        #expect(model.isEnabled == enabled)
    }

    @Test
    func refreshReflectsARegistrationChangeMadeOutsideSettings() {
        let service = FakeService(status: .notRegistered)
        let model = LaunchAtLoginModel(service: service)

        service.status = .requiresApproval
        model.refresh()

        #expect(model.status == .requiresApproval)
        #expect(model.isEnabled)
    }

    @Test
    func enablingRegistersTheMainLoginItemAndRefreshesItsState() throws {
        let service = FakeService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let model = LaunchAtLoginModel(service: service)

        try model.setEnabled(true)

        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 0)
        #expect(model.status == .requiresApproval)
        #expect(model.isEnabled)
    }

    @Test
    func disablingUnregistersTheMainLoginItemAndRefreshesItsState() throws {
        let service = FakeService(status: .enabled)
        let model = LaunchAtLoginModel(service: service)

        try model.setEnabled(false)

        #expect(service.registerCount == 0)
        #expect(service.unregisterCount == 1)
        #expect(model.status == .notRegistered)
        #expect(!model.isEnabled)
    }

    @Test
    func failedRegistrationStillReflectsTheServicesLatestState() {
        let service = FakeService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        service.registerError = .unavailable
        let model = LaunchAtLoginModel(service: service)

        #expect(throws: TestError.unavailable) {
            try model.setEnabled(true)
        }
        #expect(service.registerCount == 1)
        #expect(model.status == .requiresApproval)
        #expect(model.isEnabled)
    }

    @Test
    func failedUnregistrationStillReflectsTheServicesLatestState() {
        let service = FakeService(status: .enabled)
        service.statusAfterUnregister = .notRegistered
        service.unregisterError = .unavailable
        let model = LaunchAtLoginModel(service: service)

        #expect(throws: TestError.unavailable) {
            try model.setEnabled(false)
        }
        #expect(service.unregisterCount == 1)
        #expect(model.status == .notRegistered)
        #expect(!model.isEnabled)
    }
}
