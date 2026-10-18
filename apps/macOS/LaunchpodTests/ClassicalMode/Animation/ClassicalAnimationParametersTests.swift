import QuartzCore
import XCTest
@testable import Launchpod

/// Values checked at the boundary used by Classical presentation.
final class ClassicalAnimationParametersTests: XCTestCase {
    func testEnterExitValuesKeepTheContentScaleAndDesktopCrossfade() {
        XCTAssertEqual(ClassicalAnimationParameters.EnterExit.hiddenOpacity, 0)
        XCTAssertEqual(ClassicalAnimationParameters.EnterExit.visibleOpacity, 1)
        XCTAssertEqual(ClassicalAnimationParameters.EnterExit.contentScale, 1.05)
        XCTAssertEqual(ClassicalAnimationParameters.EnterExit.desktopCrossfadeDuration, 2)
        XCTAssertEqual(ClassicalAnimationParameters.EnterExit.slowDuration, 5)
        // Ordinary enter/exit inherits the enclosing CA transaction duration; see the layer behavior test.
    }

    func testPagingValuesRetainTheDockSettleAndInputRules() {
        let paging = ClassicalAnimationParameters.Paging.self
        XCTAssertEqual(paging.settleDuration, 0.5)
        XCTAssertEqual(paging.slowSettleDuration, 5)
        let expectedPoints: [[Float]] = [[0, 0], [0, 0], [0.35841, 1.0019], [1, 1]]
        for (index, expected) in expectedPoints.enumerated() {
            var actual: [Float] = [0, 0]
            paging.settleTiming.getControlPoint(at: index, values: &actual)
            XCTAssertEqual(actual[0], expected[0], accuracy: 1e-6)
            XCTAssertEqual(actual[1], expected[1], accuracy: 1e-6)
        }
        XCTAssertEqual(paging.dragActivation, 3)
        XCTAssertEqual(paging.flickSpeed, 200, "The tracked input speed is in points per second")
        XCTAssertEqual(paging.overscrollFactor, 0.25)
        XCTAssertEqual(paging.wheelDeltaScale, 2)
        XCTAssertEqual(paging.wheelSettleDelay, 0.075)
        XCTAssertEqual(paging.slowWheelSettleDelay, 0.375)
    }

    func testFolderValuesKeepTheTransitionPhases() {
        let folder = ClassicalAnimationParameters.Folder.self
        XCTAssertEqual(folder.slowMotionDuration, 5)
        XCTAssertEqual(folder.backgroundScale, 0.95)
        XCTAssertEqual(folder.backgroundOpacity, 0)
        XCTAssertEqual(folder.secondPhaseDuration, 0.1)
        XCTAssertEqual(folder.slowSecondPhaseDuration, 0.5)
        XCTAssertEqual(folder.closeSettleDelay, 0.25)
        XCTAssertEqual(folder.newFolderOpenDelay, 0.75)
    }

    func testEditingValuesKeepJitterAndPressTiming() {
        let editing = ClassicalAnimationParameters.Editing.self
        XCTAssertEqual(editing.jitterDuration, 0.25)
        XCTAssertEqual(editing.jitterFrameInterval, 0.05)
        XCTAssertEqual(editing.jitterRotation, 0.03525565085, accuracy: 1e-11)
        XCTAssertEqual(editing.jitterRandomModulus, 1000)
        XCTAssertEqual(editing.jitterPhaseBucketScale.bitPattern, 0x3e4ccccc)
        XCTAssertEqual(editing.jitterPhaseStartIncrement, 1)
        XCTAssertEqual(editing.jitterPositionSpan, 2)
        XCTAssertEqual(editing.jitterPositionAmplitude, 0.25)
        XCTAssertEqual(editing.longPressDelay, 1)
        XCTAssertEqual(editing.slowLongPressDelay, 5)
    }

    func testJitterBeginTimeUsesTheRecoveredPhaseBuckets() {
        XCTAssertEqual(ClassicalJitter.beginTime(random: 4), 0.05)
        XCTAssertEqual(ClassicalJitter.beginTime(random: 9), 0.1)
    }

    func testDragValuesKeepActivationRestPageTurnAndCellMotion() {
        let drag = ClassicalAnimationParameters.Drag.self
        XCTAssertEqual(drag.activationDistance, 3)
        XCTAssertEqual(drag.speedScale, 1e7)
        XCTAssertEqual(drag.restSpeed, 0.75)
        XCTAssertEqual(drag.restDelay, 0.15)
        XCTAssertEqual(drag.slowRestDelay, 0.75)
        XCTAssertEqual(drag.edgeDelay, 0.7)
        XCTAssertEqual(drag.edgeRepeat, 0.75)
        XCTAssertEqual(drag.slowEdgeDelay, 3.5)
        XCTAssertEqual(drag.slowEdgeRepeat, 3.75)
        XCTAssertEqual(drag.moveDuration, 0.4)
        XCTAssertEqual(drag.magnifiedScale, 1.1)
        XCTAssertEqual(drag.magnifiedTitleOpacity, 0.9)
    }

    func testGroupDragValuesKeepHoverPulseAndDropPhases() {
        let drag = ClassicalAnimationParameters.Drag.self
        XCTAssertEqual(drag.groupDelay, 1)
        XCTAssertEqual(drag.slowGroupDelay, 5)
        XCTAssertEqual(drag.groupHighlightScale, 1.1)
        XCTAssertEqual(drag.groupPulseMinimumOpacity, 0.4)
        XCTAssertEqual(drag.groupPulseDuration, 0.11)
        XCTAssertEqual(drag.slowGroupPulseDuration, 0.55)
        XCTAssertEqual(drag.groupPulseStartDelay, 0.65)
        XCTAssertEqual(drag.groupPulseRepeatCount, 2)
        XCTAssertEqual(drag.groupDropStagger, 0.1)
        XCTAssertEqual(drag.groupThumbnailWidthInset, 3)
        XCTAssertEqual(drag.groupThumbnailShadowOffset, CGSize(width: 0, height: -3))
        XCTAssertEqual(drag.groupThumbnailShadowRadius, 3)
        XCTAssertEqual(drag.groupThumbnailShadowOpacity, 1)
        XCTAssertEqual(drag.groupThumbnailPositionOffset, CGPoint(x: -1, y: 1))
        XCTAssertEqual(drag.folderDissolveOffset, CGPoint(x: 1, y: -1))
        XCTAssertEqual(drag.folderDissolveScale, 0.1)
        XCTAssertEqual(drag.folderReturnOpacity, 0.5)
    }

    func testOpenFeedbackAndRemovalKeepTheirIndependentEffects() {
        let open = ClassicalAnimationParameters.OpenFeedback.self
        XCTAssertEqual(open.duration, 0.25)
        XCTAssertEqual(open.slowDuration, 5)
        XCTAssertEqual(open.startOpacity, 0.9)
        XCTAssertEqual(open.endOpacity, 0.1)
        XCTAssertEqual(open.scale, 2)
        let removal = ClassicalAnimationParameters.Removal.self
        XCTAssertEqual(removal.duration, 0.5)
        XCTAssertEqual(removal.slowDuration, 5)
        XCTAssertEqual(removal.scale, 0.1)
    }
}
