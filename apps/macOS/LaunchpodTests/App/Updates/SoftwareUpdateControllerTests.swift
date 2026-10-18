import Combine
import Foundation
import Testing
@testable import Launchpod

@MainActor
struct SoftwareUpdateControllerTests {
    @Test func missingConfigurationLeavesUpdatesUnavailableWithoutCreatingADriver() {
        var madeDriver = false

        let controller = SoftwareUpdateController(configuration: nil) {
            madeDriver = true
            return UpdateDriverSpy(canCheckForUpdates: true)
        }

        #expect(!madeDriver)
        #expect(controller.configuration == nil)
        #expect(!controller.canCheckForUpdates)
        #expect(!controller.hasAvailableUpdate)
        controller.checkForUpdates()
    }

    @Test func configuredControllerDelegatesChecksWithoutUsingTheNetwork() throws {
        let configuration = try configuration()
        let driver = UpdateDriverSpy(canCheckForUpdates: true)
        let controller = SoftwareUpdateController(configuration: configuration) { driver }

        #expect(controller.configuration == configuration)
        #expect(controller.canCheckForUpdates)

        controller.checkForUpdates()

        #expect(driver.checkCount == 1)
    }

    @Test func controllerTracksDriverAvailabilityAndRejectsUnavailableChecks() throws {
        let driver = UpdateDriverSpy(canCheckForUpdates: false)
        let controller = SoftwareUpdateController(configuration: try configuration()) { driver }
        #expect(!controller.canCheckForUpdates)

        controller.checkForUpdates()
        #expect(driver.checkCount == 0)

        driver.setCanCheckForUpdates(true)
        #expect(controller.canCheckForUpdates)
        controller.checkForUpdates()
        #expect(driver.checkCount == 1)

        driver.setCanCheckForUpdates(false)
        #expect(!controller.canCheckForUpdates)
        controller.checkForUpdates()
        #expect(driver.checkCount == 1)
    }

    @Test func updateNotificationTracksDiscoveryIndependentlyOfCheckAvailability() throws {
        let driver = UpdateDriverSpy(canCheckForUpdates: true)
        let controller = SoftwareUpdateController(configuration: try configuration()) { driver }
        #expect(!controller.hasAvailableUpdate)
        driver.updates.send(true)
        #expect(controller.hasAvailableUpdate)
        driver.setCanCheckForUpdates(false)
        #expect(controller.hasAvailableUpdate)
        driver.updates.send(false)
        #expect(!controller.hasAvailableUpdate)
    }

    private func configuration() throws -> SoftwareUpdateConfiguration {
        try #require(SoftwareUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://updates.example.test/launchpod/appcast.xml",
            "SUPublicEDKey": "configured-signing-key"
        ]))
    }
}

@MainActor
private final class UpdateDriverSpy: SoftwareUpdateDriving {
    private let availability: CurrentValueSubject<Bool, Never>
    let updates = CurrentValueSubject<Bool, Never>(false)
    var hasAvailableUpdate: Bool { updates.value }
    var hasAvailableUpdatePublisher: AnyPublisher<Bool, Never> { updates.eraseToAnyPublisher() }
    private(set) var checkCount = 0

    init(canCheckForUpdates: Bool) {
        availability = CurrentValueSubject(canCheckForUpdates)
    }

    var canCheckForUpdates: Bool { availability.value }

    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
        availability.eraseToAnyPublisher()
    }

    func setCanCheckForUpdates(_ value: Bool) {
        availability.send(value)
    }

    func checkForUpdates() {
        checkCount += 1
    }
}
