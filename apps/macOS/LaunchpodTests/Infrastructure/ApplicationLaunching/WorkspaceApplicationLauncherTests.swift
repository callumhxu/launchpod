import AppKit
import XCTest
@testable import Launchpod

// XCTest runs this host-mutating suite before the Swift Testing suites.
// Run the test target with parallel testing disabled to preserve that boundary.
@MainActor
final class WorkspaceApplicationLauncherTests: XCTestCase {
    func testSelectedCopiesAndLiteralFileNamesReachTheWorkspaceWithoutIdentifierLookup() async throws {
        let boundary = ControlledApplicationOpen()
        defer { boundary.cancelPending() }
        let launcher = WorkspaceApplicationLauncher(openApplication: boundary.open)
        let copies = try [
            metadata(path: "/Applications/\u{5de5}\u{5177}%2F Editor.app", identifier: "com.example.Editor"),
            metadata(path: "/Volumes/Other/Editor.app", identifier: "com.example.Editor")
        ]

        for (index, copy) in copies.enumerated() {
            let task = Task { try await launcher.launch(copy) }
            try await waitForRequests(index + 1, from: boundary)
            XCTAssertEqual(boundary.requests[index].url, copy.bundleURL)
            boundary.complete(index, with: .success(.current))
            _ = try await task.value
        }

        XCTAssertEqual(boundary.requests[0].url.path, "/Applications/\u{5de5}\u{5177}%2F Editor.app")
        XCTAssertNotEqual(boundary.requests[0].url, boundary.requests[1].url)
    }

    func testEveryRequestActivatesTheSelectedInstallationWithoutForcingANewInstanceOrPrompting() async throws {
        let boundary = ControlledApplicationOpen()
        defer { boundary.cancelPending() }
        let launcher = WorkspaceApplicationLauncher(openApplication: boundary.open)
        let app = try metadata()

        for index in 0..<2 {
            let task = Task { try await launcher.launch(app) }
            try await waitForRequests(index + 1, from: boundary)
            let configuration = boundary.requests[index].configuration
            XCTAssertTrue(configuration.activates)
            XCTAssertFalse(configuration.createsNewApplicationInstance)
            XCTAssertFalse(configuration.allowsRunningApplicationSubstitution)
            XCTAssertFalse(configuration.promptsUserIfNeeded)
            XCTAssertFalse(configuration.hides)
            XCTAssertFalse(configuration.hidesOthers)
            boundary.complete(index, with: .success(.current))
            _ = try await task.value
        }
    }

    func testRepeatedRequestsReturnTheirSystemResultsWithoutCachingALaunchSuccess() async throws {
        let boundary = ControlledApplicationOpen()
        defer { boundary.cancelPending() }
        let launcher = WorkspaceApplicationLauncher(openApplication: boundary.open)
        let app = try metadata()
        let expected = NSRunningApplication.current

        for index in 0..<3 {
            let task = Task { try await launcher.launch(app) }
            try await waitForRequests(index + 1, from: boundary)
            boundary.complete(index, with: .success(expected))
            let result = try await task.value
            XCTAssertTrue(result.isEqual(expected))
        }

        XCTAssertEqual(boundary.requests.count, 3)
    }

    func testOriginalSystemErrorIsPropagatedAndAFailedLaunchCanBeRetried() async throws {
        let boundary = ControlledApplicationOpen()
        defer { boundary.cancelPending() }
        let launcher = WorkspaceApplicationLauncher(openApplication: boundary.open)
        let app = try metadata()
        let failure = NSError(domain: "Launchpod.Test.Launch", code: 17, userInfo: ["detail": "selected copy unavailable"])
        let first = Task { try await launcher.launch(app) }
        try await waitForRequests(1, from: boundary)
        boundary.complete(0, with: .failure(failure))

        do {
            _ = try await first.value
            XCTFail("A system launch failure must not report success.")
        } catch {
            XCTAssertEqual(error as NSError, failure)
        }

        let retry = Task { try await launcher.launch(app) }
        try await waitForRequests(2, from: boundary)
        boundary.complete(1, with: .success(.current))
        let result = try await retry.value
        XCTAssertTrue(result.isEqual(NSRunningApplication.current))
        XCTAssertEqual(boundary.requests.map(\.url), [app.bundleURL, app.bundleURL])
    }

    func testConcurrentRequestsHaveIndependentOutcomesEvenWhenTheyCompleteOutOfOrder() async throws {
        let boundary = ControlledApplicationOpen()
        defer { boundary.cancelPending() }
        let launcher = WorkspaceApplicationLauncher(openApplication: boundary.open)
        let app = try metadata()
        let first = Task { try await launcher.launch(app) }
        try await waitForRequests(1, from: boundary)
        let second = Task { try await launcher.launch(app) }
        try await waitForRequests(2, from: boundary)
        let failure = NSError(domain: "Launchpod.Test.Launch", code: 29)
        boundary.complete(1, with: .failure(failure))
        boundary.complete(0, with: .success(.current))

        let result = try await first.value
        XCTAssertTrue(result.isEqual(NSRunningApplication.current))
        do {
            _ = try await second.value
            XCTFail("The second request must preserve its own failure.")
        } catch {
            XCTAssertEqual(error as NSError, failure)
        }
        XCTAssertEqual(boundary.requests.count, 2)
    }

    func testCancellationBeforeSubmissionNeverCallsTheWorkspace() async throws {
        let boundary = ControlledApplicationOpen()
        defer { boundary.cancelPending() }
        let launcher = WorkspaceApplicationLauncher(openApplication: boundary.open)
        let app = try metadata()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await launcher.launch(app)
        }

        do {
            _ = try await task.value
            XCTFail("A pre-cancelled launch must fail before submission.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(boundary.requests.isEmpty)
    }

    func testCancellationAfterSubmissionPreservesTheActualSystemSuccessOrFailure() async throws {
        let app = try metadata()
        let failure = NSError(domain: "Launchpod.Test.Launch", code: 31)
        for systemResult in [Result<NSRunningApplication, Error>.success(.current), .failure(failure)] {
            let boundary = ControlledApplicationOpen()
            defer { boundary.cancelPending() }
            let launcher = WorkspaceApplicationLauncher(openApplication: boundary.open)
            let task = Task { try await launcher.launch(app) }
            try await waitForRequests(1, from: boundary)
            task.cancel()
            boundary.complete(0, with: systemResult)

            switch systemResult {
            case .success(let expected):
                let result = try await task.value
                XCTAssertTrue(result.isEqual(expected))
            case .failure:
                do {
                    _ = try await task.value
                    XCTFail("Cancellation cannot replace the submitted request's system failure.")
                } catch {
                    XCTAssertEqual(error as NSError, failure)
                }
            }
            XCTAssertEqual(boundary.requests.count, 1)
        }
    }

    func testAnOutstandingLaunchSuspendsWithoutBlockingTheMainActor() async throws {
        let boundary = ControlledApplicationOpen()
        defer { boundary.cancelPending() }
        let launcher = WorkspaceApplicationLauncher(openApplication: boundary.open)
        let app = try metadata()
        var completed = false
        let task = Task {
            _ = try await launcher.launch(app)
            completed = true
        }
        try await waitForRequests(1, from: boundary)
        await Task.yield()
        XCTAssertFalse(completed)
        XCTAssertEqual(boundary.requests.count, 1)

        boundary.complete(0, with: .success(.current))
        try await task.value
        XCTAssertTrue(completed)
    }

    func testNativeMissingApplicationReturnsAnErrorOnEveryAttempt() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchpodMissing-\(UUID().uuidString).app", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let app = try metadata(path: missing.path)
        let launcher = WorkspaceApplicationLauncher()
        var errors: [NSError] = []

        for _ in 0..<2 {
            do {
                _ = try await launcher.launch(app)
                XCTFail("NSWorkspace must report a missing application as a failure.")
            } catch {
                XCTAssertFalse(error is CancellationError)
                errors.append(error as NSError)
            }
        }

        XCTAssertEqual(errors.count, 2)
        if errors.count == 2 {
            XCTAssertEqual(errors[0].domain, errors[1].domain)
            XCTAssertEqual(errors[0].code, errors[1].code)
        }
    }

    func testNativeRepeatedOpenReusesOnlyTheCurrentTestHost() async throws {
        let application = NSApplication.shared
        let current = NSRunningApplication.current
        let url = try XCTUnwrap(current.bundleURL)
        XCTAssertEqual(url.standardized, Bundle.main.bundleURL.standardized)
        let originalWindows = application.windows
        let originalKeyWindow = application.keyWindow
        defer {
            for window in application.windows where !originalWindows.contains(where: { $0 === window }) {
                window.close()
            }
            if application.isActive, let originalKeyWindow, originalKeyWindow.isVisible {
                originalKeyWindow.makeKeyAndOrderFront(nil)
            }
        }
        let app = try metadata(path: url.path, identifier: current.bundleIdentifier)
        let launcher = WorkspaceApplicationLauncher()

        let first = try await launcher.launch(app)
        let second = try await launcher.launch(app)

        XCTAssertTrue(first.isEqual(current))
        XCTAssertTrue(second.isEqual(current))
        XCTAssertTrue(first.isEqual(second))
        XCTAssertEqual(first.bundleURL?.standardized, url.standardized)
        XCTAssertFalse(first.isTerminated)
    }

    private func metadata(
        path: String = "/Applications/Example.app", identifier: String? = "com.example.App"
    ) throws -> AppMetadata {
        try AppMetadata(bundleIdentifier: identifier, bundleURL: URL(filePath: path), displayName: "Example")
    }

    private func waitForRequests(_ count: Int, from boundary: ControlledApplicationOpen) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while boundary.requests.count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(boundary.requests.count, count)
        guard boundary.requests.count == count else { throw CocoaError(.coderValueNotFound) }
    }
}

@MainActor
private final class ControlledApplicationOpen {
    struct Request {
        let url: URL
        let configuration: NSWorkspace.OpenConfiguration
    }

    private(set) var requests: [Request] = []
    private var pending: [Int: CheckedContinuation<NSRunningApplication, Error>] = [:]

    func open(_ url: URL, configuration: NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication {
        try await withCheckedThrowingContinuation { continuation in
            let index = requests.count
            requests.append(Request(url: url, configuration: configuration))
            pending[index] = continuation
        }
    }

    func complete(_ index: Int, with result: Result<NSRunningApplication, Error>) {
        pending.removeValue(forKey: index)?.resume(with: result)
    }

    func cancelPending() {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }
}
