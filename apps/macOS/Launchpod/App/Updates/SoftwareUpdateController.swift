import Combine
import Foundation
import Sparkle

@MainActor
protocol SoftwareUpdateDriving: AnyObject {
    var canCheckForUpdates: Bool { get }
    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> { get }
    var hasAvailableUpdate: Bool { get }
    var hasAvailableUpdatePublisher: AnyPublisher<Bool, Never> { get }
    func checkForUpdates()
}

/// Owns the updater for the application lifetime and leaves unconfigured builds inert.
@MainActor
final class SoftwareUpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates: Bool
    @Published private(set) var hasAvailableUpdate = false
    let configuration: SoftwareUpdateConfiguration?

    private let driver: (any SoftwareUpdateDriving)?
    private var canCheckForUpdatesObservation: AnyCancellable?
    private var availableUpdateObservation: AnyCancellable?

    convenience init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        self.init(configuration: SoftwareUpdateConfiguration(infoDictionary: infoDictionary)) {
            SparkleUpdateDriver()
        }
    }

    init(
        configuration: SoftwareUpdateConfiguration?,
        makeDriver: @MainActor () -> any SoftwareUpdateDriving
    ) {
        self.configuration = configuration
        guard configuration != nil else {
            driver = nil
            canCheckForUpdates = false
            return
        }

        let driver = makeDriver()
        self.driver = driver
        canCheckForUpdates = driver.canCheckForUpdates
        canCheckForUpdatesObservation = driver.canCheckForUpdatesPublisher
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
        hasAvailableUpdate = driver.hasAvailableUpdate
        availableUpdateObservation = driver.hasAvailableUpdatePublisher
            .sink { [weak self] hasAvailableUpdate in
                self?.hasAvailableUpdate = hasAvailableUpdate
            }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        driver?.checkForUpdates()
    }
}

@MainActor
private final class SparkleUpdateDriver: NSObject, SoftwareUpdateDriving, SPUUpdaterDelegate {
    @Published private(set) var hasAvailableUpdate = false
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        super.init()
        _ = updaterController
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .eraseToAnyPublisher()
    }

    var hasAvailableUpdatePublisher: AnyPublisher<Bool, Never> {
        $hasAvailableUpdate.eraseToAnyPublisher()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        hasAvailableUpdate = true
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        hasAvailableUpdate = false
    }
}
