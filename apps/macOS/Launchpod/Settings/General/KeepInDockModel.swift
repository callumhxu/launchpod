import Foundation
import Observation

/// Whether this app is kept in the Dock, and the action that adds it.
///
/// Membership is read from the Dock's persistent apps when observation starts and again whenever the
/// Dock's stored list changes while observation is active.
@Observable
final class KeepInDockModel {
    enum Membership: Equatable {
        /// The Dock's list could not be read.
        case unknown
        case notInDock
        case inDock
    }

    private(set) var membership: Membership = .unknown
    /// An add has written the tile and is waiting for the running Dock to quit.
    private(set) var isAdding = false
    /// The last add attempt could not write the tile, could not quit the Dock, or the tile was gone
    /// once the Dock had quit.
    private(set) var addFailed = false

    let bundleURL: URL
    let bundleIdentifier: String?

    @ObservationIgnored private let store: any DockPersistentAppsStore
    @ObservationIgnored private var changeObservation: AnyObject?
    @ObservationIgnored private var dockQuitObservation: (any Sendable & AnyObject)?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var needsRefresh = false

    init(bundle: Bundle = .main, store: any DockPersistentAppsStore) {
        bundleURL = bundle.bundleURL
        bundleIdentifier = bundle.bundleIdentifier
        self.store = store
    }

    var canAdd: Bool { membership == .notInDock && !isAdding }

    func startObserving() {
        addFailed = false
        refresh()
        changeObservation = store.observeChanges { [weak self] in self?.refresh() }
    }

    func stopObserving() {
        changeObservation = nil
    }

    /// Reads the Dock's list off the main actor. Change notifications that arrive while a read is in
    /// flight are coalesced into one more read.
    func refresh() {
        guard !isRefreshing else {
            needsRefresh = true
            return
        }
        isRefreshing = true
        let store = store
        Task {
            let apps = await Task.detached { store.load() }.value
            isRefreshing = false
            apply(apps)
            if needsRefresh {
                needsRefresh = false
                refresh()
            }
        }
    }

    /// Appends this app's tile to the Dock's persistent apps and asks the Dock to quit; the system
    /// relaunches it with the saved list. Once the Dock has quit, the list is read again: a Dock that
    /// saves its own list while quitting can drop the new tile, which is reported as a failure.
    func addToDock() {
        guard !isAdding else { return }
        isAdding = true
        addFailed = false
        let store = store
        let bundleIdentifier = bundleIdentifier
        let bundleURL = bundleURL
        let dockDidQuit: @MainActor @Sendable () -> Void = { [weak self] in self?.dockDidQuitAfterAdd() }
        Task {
            let outcome = await Task.detached { () -> AddOutcome in
                guard let current = store.load() else { return .failed }
                guard !current.contains(bundleIdentifier: bundleIdentifier, bundleURL: bundleURL) else {
                    return .alreadyInDock
                }
                return store.save(current.appendingTile(for: bundleURL)) ? .saved : .failed
            }.value
            switch outcome {
            case .alreadyInDock:
                isAdding = false
                membership = .inDock
            case .failed:
                finishAdd(failed: true)
            case .saved:
                // Without a restart the tile stays in the saved list and appears the next time the Dock starts.
                let observation = await Task.detached {
                    store.restartDock(whenQuit: dockDidQuit)
                }.value
                guard let observation else {
                    finishAdd(failed: true)
                    return
                }
                if isAdding { dockQuitObservation = observation }
            }
        }
    }

    private enum AddOutcome: Sendable {
        case alreadyInDock, saved, failed
    }

    private func dockDidQuitAfterAdd() {
        guard isAdding else { return }
        dockQuitObservation = nil
        let store = store
        Task {
            let apps = await Task.detached { store.load() }.value
            apply(apps)
            finishAdd(failed: membership != .inDock)
        }
    }

    private func finishAdd(failed: Bool) {
        isAdding = false
        addFailed = failed
        if failed { refresh() }
    }

    private func apply(_ apps: DockPersistentApps?) {
        let current: Membership
        if let apps {
            current = apps.contains(bundleIdentifier: bundleIdentifier, bundleURL: bundleURL) ? .inDock : .notInDock
        } else {
            current = .unknown
        }
        if membership != current { membership = current }
    }
}
