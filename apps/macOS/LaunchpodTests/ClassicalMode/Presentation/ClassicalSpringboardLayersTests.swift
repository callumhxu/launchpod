import QuartzCore
import Testing
@testable import Launchpod

@MainActor
@Suite(.serialized)
struct ClassicalSpringboardLayersTests {
    @Test
    func preparesDesktopBelowContentAndScalesOnlyContent() throws {
        let layers = ClassicalSpringboardLayers()
        defer { layers.destroy() }
        let host = CALayer()
        let desktop = CALayer()
        desktop.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        let observer = TransactionObserver()
        observer.content = layers.contentLayer
        layers.layer.delegate = observer

        #expect(layers.show(in: host, desktopLayer: desktop, reduceMotion: false))

        #expect(layers.layer.superlayer === host)
        #expect(layers.layer.sublayers?.first === layers.desktopContainerLayer)
        #expect(layers.layer.sublayers?.last === layers.contentLayer)
        #expect(desktop.superlayer === layers.desktopContainerLayer)
        #expect(layers.desktopContainerLayer.frame == desktop.frame)
        let entering = try #require(observer.opacityChanges.first)
        #expect(entering.previousOpacity == 0)
        #expect(CATransform3DEqualToTransform(entering.contentTransform,
                                            CATransform3DMakeScale(1.05, 1.05, 1)))
        #expect(layers.layer.opacity == 1)
        #expect(CATransform3DIsIdentity(layers.contentLayer.transform))
        #expect(CATransform3DIsIdentity(layers.layer.transform))
        #expect(CATransform3DIsIdentity(layers.desktopContainerLayer.transform))
        #expect(CATransform3DIsIdentity(desktop.transform))
        #expect(desktop.filters == nil, "The wallpaper layer itself stays unfiltered")
        #expect(layers.isVisible)
    }

    /// The wallpaper is blurred (radius 30, hard edges), saturated 1.8, then each channel scaled by
    /// 0.55 plus 0.05292, and kept as a raster at the screen's scale.
    @Test
    func desktopContainerBlursSaturatesAndDimsTheWallpaper() throws {
        let layers = ClassicalSpringboardLayers()
        defer { layers.destroy() }
        let container = layers.desktopContainerLayer
        let filters = container.filters
        #expect(CoreAnimationFilterReading.types(filters) == ["gaussianBlur", "colorSaturate", "colorMatrix"])
        let blur = CoreAnimationFilterReading.first("gaussianBlur", in: filters)
        #expect(CoreAnimationFilterReading.number("inputRadius", of: blur) == 30)
        #expect(blur?.value(forKey: "inputHardEdges") as? Bool == true)
        let saturate = CoreAnimationFilterReading.first("colorSaturate", in: filters)
        #expect(abs(try #require(CoreAnimationFilterReading.number("inputAmount", of: saturate)) - 1.8) < 1e-6)
        let matrix = try #require(CoreAnimationFilterReading.colorMatrix(of: CoreAnimationFilterReading.first("colorMatrix", in: filters)))
        let scale: Float = 0.55, bias: Float = 0.05292
        #expect(matrix == [scale, 0, 0, 0, bias,
                           0, scale, 0, 0, bias,
                           0, 0, scale, 0, bias,
                           0, 0, 0, 1, 0])
        #expect(container.shouldRasterize)

        let desktop = CALayer()
        desktop.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        #expect(layers.show(in: CALayer(), desktopLayer: desktop, reduceMotion: true))
        layers.resizeDesktop(to: CGRect(x: 0, y: 0, width: 1470, height: 956), scale: 2)
        #expect(container.rasterizationScale == 2)
        #expect(desktop.contentsScale == 2)
    }

    @Test(arguments: [false, true])
    func preparationAndLayoutPreserveCallerActionState(disabled: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(disabled)
        defer { CATransaction.commit() }
        let layers = ClassicalSpringboardLayers()
        defer { layers.destroy() }
        let host = CALayer()
        let observer = TransactionObserver()
        layers.desktopContainerLayer.delegate = observer
        #expect(layers.show(in: host, desktopLayer: CALayer(), reduceMotion: false))
        #expect(CATransaction.disableActions() == disabled)
        #expect(observer.keys.isEmpty)

        let scale = CATransform3DMakeScale(1.05, 1.05, 1)
        CATransaction.setDisableActions(true)
        layers.contentLayer.transform = scale
        CATransaction.setDisableActions(disabled)
        layers.contentLayer.delegate = observer
        let frame = CGRect(x: 0, y: 30, width: 800, height: 570)
        layers.layout(rootFrame: CGRect(x: 20, y: 40, width: 800, height: 600),
                      contentFrame: frame)

        #expect(CATransaction.disableActions() == disabled)
        #expect(observer.keys.isEmpty)
        #expect(layers.layer.frame == CGRect(x: 20, y: 40, width: 800, height: 600))
        #expect(layers.contentLayer.bounds.size == frame.size)
        #expect(layers.contentLayer.position == CGPoint(x: frame.midX, y: frame.midY))
        #expect(CATransform3DEqualToTransform(layers.contentLayer.transform, scale))
    }

    @Test
    func enterAndExitInheritDurationWithFloatPrecisionAndSystemCurves() throws {
        let layers = ClassicalSpringboardLayers()
        defer { layers.destroy() }
        let observer = TransactionObserver()
        observer.content = layers.contentLayer
        layers.layer.delegate = observer
        let host = CALayer()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.73123456789)
        defer { CATransaction.commit() }
        #expect(layers.show(in: host, desktopLayer: CALayer(), reduceMotion: false))
        let entering = try #require(observer.opacityChanges.last)
        #expect(entering.duration == Double(Float(0.73123456789)))
        expectTiming(entering.timing, name: .easeIn)

        CATransaction.setAnimationDuration(0.41987654321)
        #expect(layers.hide(reduceMotion: false))
        let exiting = try #require(observer.opacityChanges.last)
        #expect(exiting.duration == Double(Float(0.41987654321)))
        expectTiming(exiting.timing, name: .easeOut)
        #expect(layers.layer.opacity == 0)
        #expect(CATransform3DEqualToTransform(exiting.contentTransform,
                                            CATransform3DMakeScale(1.05, 1.05, 1)))
        #expect(CATransform3DIsIdentity(layers.desktopContainerLayer.transform))
        #expect(!layers.isVisible)
        #expect(layers.desktopLayer == nil)
    }

    /// 5 s is selected only for allowed Shift in both paths.
    @Test
    func allowedShiftSlowsBothFadesEvenWhenReduceMotionSkipsScaling() throws {
        let inheritedEnter = Double(Float(0.73123456789))
        let inheritedExit = Double(Float(0.41987654321))
        let cases: [(allowed: Bool, shifted: Bool, reduceMotion: Bool, enter: Double, exit: Double)] = [
            (false, false, false, inheritedEnter, inheritedExit),
            (false, true, false, inheritedEnter, inheritedExit),
            (true, false, false, inheritedEnter, inheritedExit),
            (true, true, false, 5, 5),
            (false, true, true, inheritedEnter, inheritedExit),
            (true, true, true, 5, 5),
        ]
        for entry in cases {
            let layers = ClassicalSpringboardLayers()
            defer { layers.destroy() }
            let observer = TransactionObserver()
            observer.content = layers.contentLayer
            layers.layer.delegate = observer
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.73123456789)
            defer { CATransaction.commit() }

            #expect(layers.show(in: CALayer(), desktopLayer: CALayer(), reduceMotion: entry.reduceMotion,
                                slowMotionAllowed: entry.allowed, shiftKeyDown: entry.shifted))
            let entering = try #require(observer.opacityChanges.last)
            #expect(entering.duration == entry.enter)
            #expect(entering.previousOpacity == 0)
            #expect(layers.layer.opacity == 1)
            #expect(CATransform3DEqualToTransform(entering.contentTransform,
                                                 entry.reduceMotion ? CATransform3DIdentity
                                                     : CATransform3DMakeScale(1.05, 1.05, 1)))

            CATransaction.setAnimationDuration(0.41987654321)
            #expect(layers.hide(reduceMotion: entry.reduceMotion,
                                slowMotionAllowed: entry.allowed, shiftKeyDown: entry.shifted))
            let exiting = try #require(observer.opacityChanges.last)
            #expect(exiting.duration == entry.exit)
            #expect(layers.layer.opacity == 0)
            #expect(CATransform3DEqualToTransform(exiting.contentTransform,
                                                 entry.reduceMotion ? CATransform3DIdentity
                                                     : CATransform3DMakeScale(1.05, 1.05, 1)))
        }
    }

    @Test
    func reduceMotionKeepsFadeAndDoesNotScheduleContentTransform() throws {
        let layers = ClassicalSpringboardLayers()
        defer { layers.destroy() }
        let existingTransform = CATransform3DMakeScale(1.2, 1.3, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layers.contentLayer.transform = existingTransform
        CATransaction.commit()
        let contentObserver = TransactionObserver()
        layers.contentLayer.delegate = contentObserver
        let rootObserver = TransactionObserver()
        rootObserver.content = layers.contentLayer
        layers.layer.delegate = rootObserver
        let host = CALayer()
        #expect(layers.show(in: host, desktopLayer: CALayer(), reduceMotion: true))
        #expect(layers.layer.opacity == 1)
        #expect(CATransform3DEqualToTransform(layers.contentLayer.transform, existingTransform))
        #expect(layers.hide(reduceMotion: true))
        #expect(layers.layer.opacity == 0)
        let exiting = try #require(rootObserver.opacityChanges.last)
        #expect(CATransform3DEqualToTransform(exiting.contentTransform, existingTransform))
        #expect(!contentObserver.keys.contains("transform"))
    }

    @Test
    func repeatedTargetsDoNotReplaceDesktopOrRestartAnimation() {
        let layers = ClassicalSpringboardLayers()
        defer { layers.destroy() }
        let host = CALayer()
        let original = CALayer()
        let unused = CALayer()
        let observer = TransactionObserver()
        layers.layer.delegate = observer
        #expect(!layers.hide(reduceMotion: false))
        #expect(layers.show(in: host, desktopLayer: original, reduceMotion: false))
        let showCount = observer.opacityChanges.count
        #expect(!layers.show(in: host, desktopLayer: unused, reduceMotion: false))
        #expect(observer.opacityChanges.count == showCount)
        #expect(layers.desktopLayer === original)
        #expect(unused.superlayer == nil)
        #expect(layers.hide(reduceMotion: false))
        let hideCount = observer.opacityChanges.count
        #expect(!layers.hide(reduceMotion: false))
        #expect(observer.opacityChanges.count == hideCount)
    }

    @Test
    func realTransactionCompletionRemovesHiddenRootAndDesktop() async throws {
        let layers = ClassicalSpringboardLayers()
        defer { layers.destroy() }
        let host = CALayer()
        let desktop = CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        #expect(layers.show(in: host, desktopLayer: desktop, reduceMotion: false))
        #expect(layers.hide(reduceMotion: false))
        CATransaction.commit()
        CATransaction.flush()
        for _ in 0..<100 where layers.layer.superlayer != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(layers.layer.superlayer == nil)
        #expect(desktop.superlayer == nil)
        #expect(CATransform3DIsIdentity(layers.contentLayer.transform))
    }

    @Test
    func releasingOwnerDetachesHostRetainedLayers() {
        let host = CALayer()
        let desktop = CALayer()
        var owner: ClassicalSpringboardLayers? = ClassicalSpringboardLayers()
        weak let releasedOwner = owner
        let root = owner!.layer
        #expect(owner!.show(in: host, desktopLayer: desktop, reduceMotion: false))
        owner = nil
        #expect(releasedOwner == nil)
        #expect(root.superlayer == nil)
        #expect(desktop.superlayer == nil)
    }

    @Test
    func exitCompletionObservesCleanupAndCanReenterWithoutLosingNewDesktop() async throws {
        let layers = ClassicalSpringboardLayers()
        defer { layers.destroy() }
        let host = CALayer()
        let oldDesktop = CALayer()
        let replacement = CALayer()
        var completed = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        #expect(layers.show(in: host, desktopLayer: oldDesktop, reduceMotion: false))
        let hidden = layers.hide(reduceMotion: false) {
            #expect(layers.desktopLayer == nil)
            #expect(oldDesktop.superlayer == nil)
            #expect(layers.layer.superlayer == nil)
            #expect(layers.show(in: host, desktopLayer: replacement, reduceMotion: false))
            completed = true
        }
        #expect(hidden)
        CATransaction.commit()
        CATransaction.flush()
        for _ in 0..<100 where !completed {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(completed)
        #expect(layers.desktopLayer === replacement)
        #expect(replacement.superlayer === layers.desktopContainerLayer)
        #expect(layers.layer.superlayer === host)
    }

    @Test(arguments: [false, true])
    func capturedExitCleanupUsesCurrentVisibilityAndOnlyItsOldDesktop(hideAgain: Bool) throws {
        let layers = ClassicalSpringboardLayers()
        defer { layers.destroy() }
        let host = CALayer()
        let oldDesktop = CALayer()
        let newDesktop = CALayer()
        let observer = TransactionObserver()
        layers.layer.delegate = observer
        #expect(layers.show(in: host, desktopLayer: oldDesktop, reduceMotion: false))
        #expect(layers.hide(reduceMotion: false))
        let oldCompletion = try #require(observer.opacityChanges.last?.completion)
        #expect(layers.show(in: host, desktopLayer: newDesktop, reduceMotion: false))
        if hideAgain { #expect(layers.hide(reduceMotion: false)) }
        // Invoke the registered CA block to control ordering, not a replacement cleanup implementation.
        oldCompletion()
        #expect(oldDesktop.superlayer == nil)
        #expect(layers.isVisible == !hideAgain)
        if hideAgain {
            #expect(layers.layer.superlayer == nil)
        } else {
            #expect(layers.layer.superlayer === host)
            #expect(layers.desktopLayer === newDesktop)
            #expect(newDesktop.superlayer === layers.desktopContainerLayer)
        }
    }

    @Test
    func destroyDetachesAllDesktopsAndLateCompletionCannotAffectAnotherInstance() throws {
        let layers = ClassicalSpringboardLayers()
        let host = CALayer()
        let oldDesktop = CALayer()
        let currentDesktop = CALayer()
        let observer = TransactionObserver()
        layers.layer.delegate = observer
        #expect(layers.show(in: host, desktopLayer: oldDesktop, reduceMotion: false))
        #expect(layers.hide(reduceMotion: false))
        let lateCompletion = try #require(observer.opacityChanges.last?.completion)
        #expect(layers.show(in: host, desktopLayer: currentDesktop, reduceMotion: false))
        layers.destroy()
        #expect(layers.layer.superlayer == nil)
        #expect(oldDesktop.superlayer == nil)
        #expect(currentDesktop.superlayer == nil)
        #expect(layers.layer.animationKeys()?.isEmpty != false)
        #expect(layers.contentLayer.animationKeys()?.isEmpty != false)
        #expect(!layers.show(in: host, desktopLayer: CALayer(), reduceMotion: false))
        #expect(!layers.hide(reduceMotion: false))

        let replacement = ClassicalSpringboardLayers()
        defer { replacement.destroy() }
        let replacementDesktop = CALayer()
        #expect(replacement.show(in: host, desktopLayer: replacementDesktop, reduceMotion: false))
        lateCompletion()
        #expect(replacement.isVisible)
        #expect(replacement.layer.superlayer === host)
        #expect(replacement.desktopLayer === replacementDesktop)
    }

    private func expectTiming(_ timing: CAMediaTimingFunction?, name: CAMediaTimingFunctionName) {
        let expected = CAMediaTimingFunction(name: name)
        for index in 0...3 {
            var actualPoint: [Float] = [0, 0]
            var expectedPoint: [Float] = [0, 0]
            timing?.getControlPoint(at: index, values: &actualPoint)
            expected.getControlPoint(at: index, values: &expectedPoint)
            #expect(timing != nil)
            #expect(actualPoint == expectedPoint)
        }
    }
}

@MainActor
private final class TransactionObserver: NSObject, CALayerDelegate {
    struct Change {
        let previousOpacity: Float
        let contentTransform: CATransform3D
        let duration: CFTimeInterval
        let timing: CAMediaTimingFunction?
        let completion: (() -> Void)?
    }

    weak var content: CALayer?
    var keys: [String] = []
    var opacityChanges: [Change] = []

    nonisolated func action(for layer: CALayer, forKey event: String) -> (any CAAction)? {
        MainActor.assumeIsolated {
            keys.append(event)
            if event == "opacity" {
                opacityChanges.append(Change(
                    previousOpacity: layer.opacity,
                    contentTransform: content?.transform ?? CATransform3DIdentity,
                    duration: CATransaction.animationDuration(),
                    timing: CATransaction.animationTimingFunction(),
                    completion: CATransaction.completionBlock()
                ))
            }
            return nil
        }
    }
}
