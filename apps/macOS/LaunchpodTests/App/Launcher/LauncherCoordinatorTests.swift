import AppKit
import Testing
@testable import Launchpod

@MainActor
struct LauncherCoordinatorTests {
    @Test(arguments: LauncherMode.allCases, [99, 100])
    func rapidTogglesReuseOneSessionAndOnlyTheLatestRequestCanComplete(mode: LauncherMode, count: Int) throws {
        let coordinator = LauncherCoordinator(mode: mode)
        #expect(coordinator.session == nil)
        var transitions: [LauncherPresentationState.Transition] = []
        transitions.append(try #require(coordinator.toggle()))
        let session = try #require(coordinator.session)
        #expect(session.mode == mode)
        #expect(session.state == .preparing)

        for _ in 1..<count {
            transitions.append(try #require(coordinator.toggle()))
            #expect(coordinator.session === session)
        }
        let opens = count % 2 == 1
        let pendingPhase: LauncherPresentationState.Phase = opens ? .preparing : .dismissing
        #expect(session.state == pendingPhase)
        for stale in transitions.dropLast().reversed() {
            #expect(!coordinator.complete(stale))
            #expect(session.state == pendingPhase)
        }
        let latest = try #require(transitions.last)
        #expect(latest.targetIsVisible == opens)
        #expect(coordinator.complete(latest))
        #expect(session.state == (opens ? .visible : .inactive))
        #expect(!coordinator.complete(latest))
        #expect(coordinator.session === session)
    }

    @Test(arguments: LauncherMode.allCases)
    func togglesDuringModeSwitchPreserveDismissalUntilTheNewSelectionCommits(mode: LauncherMode) throws {
        let coordinator = LauncherCoordinator(mode: mode)
        let opening = try #require(coordinator.toggle())
        let original = try #require(coordinator.session)
        let nextMode: LauncherMode = mode == .classical ? .window : .classical
        let dismissal = try #require(coordinator.selectMode(nextMode))

        for _ in 0..<100 {
            #expect(coordinator.toggle() == nil)
            #expect(coordinator.session === original)
            #expect(original.state == .dismissing)
            #expect(coordinator.mode == mode)
            #expect(coordinator.pendingMode == nextMode)
        }
        #expect(!coordinator.complete(opening))
        #expect(coordinator.complete(dismissal))
        #expect(coordinator.session == nil)
        #expect(coordinator.mode == nextMode)
        let nextOpening = try #require(coordinator.toggle())
        let replacement = try #require(coordinator.session)
        #expect(replacement !== original)
        #expect(replacement.mode == nextMode)
        #expect(replacement.state == .preparing)
        #expect(!coordinator.complete(dismissal))
        #expect(coordinator.complete(nextOpening))
    }

    @Test
    func releasingCoordinatorInvalidatesExternallyRetainedPresentation() throws {
        var coordinator: LauncherCoordinator? = LauncherCoordinator()
        let presentation = try #require(coordinator?.sessionForSelectedMode()?.presentation)
        let opening = presentation.toggle()
        weak let releasedCoordinator = coordinator

        coordinator = nil
        #expect(releasedCoordinator == nil)
        #expect(presentation.phase == .inactive)
        #expect(!presentation.complete(opening))
    }

    @Test(arguments: LauncherMode.allCases)
    func createsOnlyTheSelectedSessionAndReusesIt(mode: LauncherMode) throws {
        let coordinator = LauncherCoordinator(mode: mode)
        #expect(coordinator.session == nil)

        let session = try #require(coordinator.sessionForSelectedMode())
        #expect(session.mode == mode)
        #expect(session.state == .inactive)
        #expect(coordinator.sessionForSelectedMode() === session)
        #expect(coordinator.selectMode(mode) == nil)
        #expect(coordinator.session === session)
    }

    @Test
    func inactiveSwitchReleasesSessionBeforeCommittingNewMode() throws {
        var committedModes: [LauncherMode] = []
        let coordinator = LauncherCoordinator(mode: .classical) { committedModes.append($0) }
        var previous = coordinator.sessionForSelectedMode()
        try #require(previous != nil)
        weak let releasedSession = previous
        previous = nil

        #expect(coordinator.selectMode(.window) == nil)
        #expect(releasedSession == nil)
        #expect(coordinator.session == nil)
        #expect(coordinator.mode == .window)
        #expect(committedModes == [.window])
        #expect(coordinator.sessionForSelectedMode()?.mode == .window)
    }

    @Test
    func sameModeSelectionPreservesAnOpeningSession() throws {
        var committedModes: [LauncherMode] = []
        let coordinator = LauncherCoordinator(mode: .window) { committedModes.append($0) }
        let session = try #require(coordinator.sessionForSelectedMode())
        let opening = session.presentation.toggle()

        #expect(coordinator.selectMode(.window) == nil)
        #expect(coordinator.pendingMode == nil)
        #expect(coordinator.session === session)
        #expect(session.state == .preparing)
        #expect(coordinator.complete(opening))
        #expect(session.state == .visible)
        #expect(committedModes.isEmpty)
    }

    @Test
    func switchingWaitsForDismissalAndRejectsInterruptedOpening() throws {
        var committedModes: [LauncherMode] = []
        let coordinator = LauncherCoordinator(mode: .classical) { committedModes.append($0) }
        let previous = try #require(coordinator.sessionForSelectedMode())
        let opening = previous.presentation.toggle()

        let dismissal = try #require(coordinator.selectMode(.window))
        #expect(previous.state == .dismissing)
        #expect(coordinator.mode == .classical)
        #expect(coordinator.pendingMode == .window)
        #expect(coordinator.session === previous)
        #expect(coordinator.sessionForSelectedMode() == nil)
        #expect(committedModes.isEmpty)
        #expect(!coordinator.complete(opening))
        #expect(coordinator.mode == .classical)

        #expect(coordinator.complete(dismissal))
        #expect(previous.state == .inactive)
        #expect(!previous.presentation.complete(opening))
        #expect(!previous.presentation.complete(dismissal))
        #expect(coordinator.session == nil)
        #expect(coordinator.mode == .window)
        #expect(coordinator.pendingMode == nil)
        #expect(committedModes == [.window])
        #expect(!coordinator.complete(dismissal))
    }

    @Test
    func rapidSelectionsKeepTheLatestModeWithoutRevivingTheDismissedSession() throws {
        var committedModes: [LauncherMode] = []
        let coordinator = LauncherCoordinator(mode: .classical) { committedModes.append($0) }
        let original = try #require(coordinator.sessionForSelectedMode())
        #expect(coordinator.complete(original.presentation.toggle()))
        let dismissal = try #require(coordinator.selectMode(.window))

        #expect(coordinator.selectMode(.window) == nil)
        #expect(coordinator.selectMode(.classical) == nil)
        #expect(coordinator.pendingMode == .classical)
        #expect(coordinator.sessionForSelectedMode() == nil)
        #expect(coordinator.complete(dismissal))
        #expect(original.state == .inactive)
        #expect(coordinator.mode == .classical)
        #expect(committedModes.isEmpty)
        let replacement = try #require(coordinator.sessionForSelectedMode())
        #expect(replacement !== original)
        #expect(replacement.state == .inactive)
        #expect(!replacement.presentation.complete(dismissal))
    }

    @Test
    func selectionDuringExistingDismissalWaitsForItsCompletion() throws {
        let coordinator = LauncherCoordinator(mode: .classical)
        let previous = try #require(coordinator.sessionForSelectedMode())
        #expect(coordinator.complete(previous.presentation.toggle()))
        let dismissal = previous.presentation.toggle()

        #expect(coordinator.selectMode(.window) == nil)
        #expect(coordinator.session === previous)
        #expect(coordinator.mode == .classical)
        #expect(coordinator.pendingMode == .window)
        #expect(coordinator.sessionForSelectedMode() == nil)
        #expect(coordinator.complete(dismissal))
        #expect(coordinator.mode == .window)
        #expect(coordinator.session == nil)
        #expect(previous.state == .inactive)
    }

    @Test
    func oneHundredSwitchesReleaseSessionsAndInvalidateOldCallbacks() throws {
        let coordinator = LauncherCoordinator(mode: .classical)
        for _ in 0..<100 {
            var previous = coordinator.sessionForSelectedMode()
            let presentation = try #require(previous?.presentation)
            weak let releasedSession = previous
            let opening = presentation.toggle()
            #expect(coordinator.complete(opening))
            let nextMode: LauncherMode = coordinator.mode == .classical ? .window : .classical
            let dismissal = try #require(coordinator.selectMode(nextMode))
            previous = nil
            #expect(releasedSession != nil)

            #expect(coordinator.complete(dismissal))
            #expect(releasedSession == nil)
            #expect(presentation.phase == .inactive)
            #expect(!presentation.complete(opening))
            #expect(!presentation.complete(dismissal))
            let replacement = try #require(coordinator.sessionForSelectedMode())
            #expect(replacement.mode == nextMode)
            #expect(replacement.state == .inactive)
            #expect(!coordinator.complete(opening))
            #expect(!coordinator.complete(dismissal))
            #expect(replacement.state == .inactive)
        }
    }

    @Test
    func repeatedStopsReleaseSessionsAndAllowFreshStarts() throws {
        let coordinator = LauncherCoordinator(mode: .window)
        for _ in 0..<3 {
            var previous = coordinator.sessionForSelectedMode()
            let presentation = try #require(previous?.presentation)
            weak let releasedSession = previous
            let opening = presentation.toggle()
            previous = nil

            coordinator.stop()
            coordinator.stop()
            #expect(releasedSession == nil)
            #expect(presentation.phase == .inactive)
            #expect(!presentation.complete(opening))
            #expect(coordinator.session == nil)
            #expect(coordinator.mode == .window)
            #expect(coordinator.pendingMode == nil)
            #expect(!coordinator.complete(opening))
        }
    }

    @Test
    func stoppingAnUnfinishedSwitchPreservesTheCommittedMode() throws {
        var committedModes: [LauncherMode] = []
        let coordinator = LauncherCoordinator(mode: .classical) { committedModes.append($0) }
        let previous = try #require(coordinator.sessionForSelectedMode())
        let opening = previous.presentation.toggle()
        let dismissal = try #require(coordinator.selectMode(.window))

        coordinator.stop()
        #expect(coordinator.mode == .classical)
        #expect(coordinator.pendingMode == nil)
        #expect(coordinator.session == nil)
        #expect(previous.state == .inactive)
        #expect(!coordinator.complete(opening))
        #expect(!coordinator.complete(dismissal))
        #expect(committedModes.isEmpty)
        let replacement = try #require(coordinator.sessionForSelectedMode())
        #expect(replacement.mode == .classical)
        #expect(replacement !== previous)
    }

    @Test
    func launchSuccessRequestsDismissalWithoutCompletingIt() async throws {
        let metadata = try AppMetadata(bundleIdentifier: "com.example.Editor",
                                       bundleURL: URL(filePath: "/Applications/Editor.app"), displayName: "Editor")
        var openedURL: URL?
        let launcher = WorkspaceApplicationLauncher { url, _ in
            openedURL = url
            return .current
        }
        let coordinator = LauncherCoordinator(launcher: launcher)
        let session = try #require(coordinator.sessionForSelectedMode())
        #expect(coordinator.complete(session.presentation.toggle()))

        let result = try await coordinator.launch(metadata)
        #expect(openedURL == metadata.bundleURL)
        #expect(result.application.isEqual(NSRunningApplication.current))
        let dismissal = try #require(result.dismissal)
        #expect(session.state == .dismissing)
        #expect(coordinator.complete(dismissal))
        #expect(session.state == .inactive)
    }

    @Test
    func failedLaunchLeavesTheSessionVisible() async throws {
        let failure = NSError(domain: "Launchpod.CoordinatorTests", code: 1)
        let launcher = WorkspaceApplicationLauncher { _, _ in throw failure }
        let coordinator = LauncherCoordinator(launcher: launcher)
        let session = try #require(coordinator.sessionForSelectedMode())
        #expect(coordinator.complete(session.presentation.toggle()))
        let metadata = try AppMetadata(bundleIdentifier: nil,
                                       bundleURL: URL(filePath: "/Applications/Absent.app"), displayName: "Absent")

        do {
            _ = try await coordinator.launch(metadata)
            Issue.record("A failed launch must throw its error.")
        } catch {
            #expect(error as NSError == failure)
        }
        #expect(coordinator.session === session)
        #expect(session.state == .visible)
    }

    @Test
    func delayedLaunchNeitherRetainsOldSessionNorDismissesItsReplacement() async throws {
        var completion: CheckedContinuation<NSRunningApplication, Never>?
        let launcher = WorkspaceApplicationLauncher { _, _ in
            await withCheckedContinuation { completion = $0 }
        }
        let coordinator = LauncherCoordinator(launcher: launcher)
        var previous = coordinator.sessionForSelectedMode()
        weak let releasedSession = previous
        #expect(coordinator.complete(try #require(previous?.presentation.toggle())))
        let metadata = try AppMetadata(bundleIdentifier: nil,
                                       bundleURL: URL(filePath: "/Applications/Editor.app"), displayName: "Editor")
        let launch = Task { try await coordinator.launch(metadata) }
        defer { completion?.resume(returning: .current) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while completion == nil, ContinuousClock.now < deadline { await Task.yield() }
        _ = try #require(completion)
        let dismissal = try #require(coordinator.selectMode(.window))
        previous = nil
        #expect(coordinator.complete(dismissal))
        #expect(releasedSession == nil)
        let replacement = try #require(coordinator.sessionForSelectedMode())
        #expect(coordinator.complete(replacement.presentation.toggle()))

        completion?.resume(returning: .current)
        completion = nil
        let result = try await launch.value
        #expect(result.dismissal == nil)
        #expect(replacement.state == .visible)
        #expect(coordinator.session === replacement)
    }

    @Test(arguments: [false, true])
    func delayedLaunchDismissesOnlyThePresentationThatRequestedIt(reopened: Bool) async throws {
        var completion: CheckedContinuation<NSRunningApplication, Never>?
        let coordinator = LauncherCoordinator(launcher: WorkspaceApplicationLauncher { _, _ in
            await withCheckedContinuation { completion = $0 }
        })
        let session = try #require(coordinator.sessionForSelectedMode())
        let opening = session.presentation.toggle()
        let metadata = try AppMetadata(bundleIdentifier: nil,
                                       bundleURL: URL(filePath: "/Applications/Editor.app"), displayName: "Editor")
        let launch = Task { try await coordinator.launch(metadata) }
        defer { completion?.resume(returning: .current) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while completion == nil, ContinuousClock.now < deadline { await Task.yield() }
        _ = try #require(completion)
        #expect(coordinator.complete(opening))
        if reopened {
            #expect(coordinator.complete(session.presentation.toggle()))
            #expect(coordinator.complete(session.presentation.toggle()))
        }

        completion?.resume(returning: .current)
        completion = nil
        let result = try await launch.value
        if reopened {
            #expect(result.dismissal == nil)
            #expect(session.state == .visible)
        } else {
            #expect(result.dismissal != nil)
            #expect(session.state == .dismissing)
        }
    }
}
