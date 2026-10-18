import XCTest
@testable import Launchpod

@MainActor
final class ClassicalMenuBarVisibilityTests: XCTestCase {
    func testResolutionIsLazyAndUnavailableOperationsNeverCreateCleanupWork() {
        var resolutions = 0
        let visibility = ClassicalMenuBarVisibility(resolveOperations: {
            resolutions += 1
            return nil
        })
        visibility.restore()
        XCTAssertEqual(resolutions, 0)
        visibility.hide()
        visibility.hide()
        visibility.restore()
        XCTAssertEqual(resolutions, 1)
        XCTAssertFalse(visibility.hasPendingReset)
    }

    func testHideRequestsOnlyAlphaZeroAndResetUsesTheSameResolvedConnection() {
        var resolutions = 0
        var alphas: [Float] = []
        var resetConnections: [Int32] = []
        weak var activeVisibility: ClassicalMenuBarVisibility?
        let visibility = ClassicalMenuBarVisibility(resolveOperations: {
            resolutions += 1
            return .init(connectionID: 73, setAlpha: { connection, inset, scale, alpha in
                XCTAssertEqual(connection, 73)
                XCTAssertEqual(inset, 0)
                XCTAssertEqual(scale, 1)
                XCTAssertTrue(activeVisibility?.hasPendingReset == true)
                alphas.append(alpha)
                return 0
            }, reset: { connection in
                resetConnections.append(connection)
                return 0
            })
        })
        activeVisibility = visibility
        visibility.hide()
        visibility.hide()
        XCTAssertEqual(alphas, [0])
        XCTAssertTrue(visibility.hasPendingReset)
        visibility.restore()
        visibility.restore()
        XCTAssertFalse(visibility.hasPendingReset)
        XCTAssertEqual(resetConnections, [73])
        visibility.hide()
        visibility.restore()
        XCTAssertEqual(resolutions, 1)
        XCTAssertEqual(alphas, [0, 0])
        XCTAssertEqual(resetConnections, [73, 73])
    }

    func testFailedHideSendImmediatelyResetsWithoutLeavingAnActiveRequest() {
        var events: [String] = []
        let visibility = ClassicalMenuBarVisibility(resolveOperations: {
            .init(connectionID: 19, setAlpha: { _, _, _, alpha in
                XCTAssertEqual(alpha, 0)
                events.append("hide")
                return 1
            }, reset: { connection in
                XCTAssertEqual(connection, 19)
                events.append("reset")
                return 0
            })
        })
        visibility.hide()
        XCTAssertEqual(events, ["hide", "reset"])
        XCTAssertFalse(visibility.hasPendingReset)
        visibility.restore()
        XCTAssertEqual(events, ["hide", "reset"])
        visibility.hide()
        XCTAssertEqual(events, ["hide", "reset", "hide", "reset"])
        XCTAssertFalse(visibility.hasPendingReset)
    }

    func testFailedHideAndImmediateResetRetainCleanupForAnExplicitRetry() {
        var resets = 0
        let visibility = ClassicalMenuBarVisibility(resolveOperations: {
            .init(connectionID: 31, setAlpha: { connection, _, _, alpha in
                XCTAssertEqual(connection, 31)
                XCTAssertEqual(alpha, 0)
                return 1
            }, reset: { connection in
                XCTAssertEqual(connection, 31)
                resets += 1
                return resets == 1 ? 1 : 0
            })
        })
        visibility.hide()
        XCTAssertEqual(resets, 1)
        XCTAssertTrue(visibility.hasPendingReset)
        visibility.restore()
        XCTAssertEqual(resets, 2)
        XCTAssertFalse(visibility.hasPendingReset)
    }

    func testFailedResetKeepsCleanupPendingAndReentryReassertsAlphaZero() {
        var resets = 0
        var hideRequests = 0
        let visibility = ClassicalMenuBarVisibility(resolveOperations: {
            .init(connectionID: 29, setAlpha: { _, _, _, _ in
                hideRequests += 1
                return 0
            }, reset: { connection in
                XCTAssertEqual(connection, 29)
                resets += 1
                return resets == 1 ? 1 : 0
            })
        })
        visibility.hide()
        visibility.restore()
        XCTAssertTrue(visibility.hasPendingReset)
        visibility.hide()
        XCTAssertEqual(hideRequests, 2)
        visibility.restore()
        XCTAssertEqual(resets, 2)
        XCTAssertFalse(visibility.hasPendingReset)
    }

    func testDeinitializationRetriesPendingResetButDoesNotResetAnIdleOwner() {
        for requestedHide in [false, true] {
            var resets = 0
            var visibility: ClassicalMenuBarVisibility? = ClassicalMenuBarVisibility(resolveOperations: {
                .init(connectionID: 43, setAlpha: { _, _, _, _ in 0 }, reset: { connection in
                    XCTAssertEqual(connection, 43)
                    resets += 1
                    return resets == 1 ? 1 : 0
                })
            })
            if requestedHide {
                visibility?.hide()
                visibility?.restore()
                XCTAssertTrue(visibility?.hasPendingReset == true)
            }
            visibility = nil
            XCTAssertEqual(resets, requestedHide ? 2 : 0)
        }
    }

    func testIntermediateAlphasCoalesceSmallStepsButAlwaysDeliverEndpoints() {
        var alphas: [Float] = []
        let visibility = ClassicalMenuBarVisibility(resolveOperations: {
            .init(connectionID: 5, setAlpha: { _, _, _, alpha in
                alphas.append(alpha)
                return 0
            }, reset: { _ in 0 })
        })
        visibility.setAlpha(1)
        visibility.setAlpha(0.995)
        visibility.setAlpha(0.5)
        visibility.setAlpha(0.495)
        visibility.setAlpha(0.005)
        visibility.setAlpha(-1)
        visibility.hide()
        XCTAssertEqual(alphas, [1, 0.5, 0.005, 0])
        XCTAssertTrue(visibility.hasPendingReset)
        visibility.restore()
        XCTAssertFalse(visibility.hasPendingReset)
        visibility.setAlpha(0.995)
        XCTAssertEqual(alphas, [1, 0.5, 0.005, 0, 0.995])
    }
}
