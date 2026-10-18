import CoreImage
import QuartzCore
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalGroupDragVisualsTests: XCTestCase {
    /// Hovering over an application darkens it, hides both titles and un-magnifies the dragged
    /// icon. Behind the target a pale backdrop and a darken-blended tint appear at once at full
    /// opacity, scaled to 1.1, and pulse twice between 1 and 0.4 after 0.65 s; the pulse is their
    /// opacity animation, so no fade-in plays. Ending the hover removes the highlight.
    func testHoverOnApplicationShowsMeasuredPulseAndClearsTheHighlight() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([["A", "B"]])
        let window = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: fixture.content)
        defer { window.close() }
        let cells = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers)
        let dragged = cells[0]
        let target = cells[1]
        let visuals = ClassicalGroupDragVisuals()
        let sublayersBefore = target.jitterLayer.sublayers ?? []
        let before = CACurrentMediaTime()

        visuals.hover(target: target, dragged: dragged, slow: false)

        let after = CACurrentMediaTime()
        XCTAssertTrue(target.isDarkened)
        XCTAssertEqual(target.titleLayer.opacity, 0)
        XCTAssertEqual(dragged.titleLayer.opacity, 0)
        XCTAssertFalse(dragged.isMagnified)
        let highlights = (target.jitterLayer.sublayers ?? []).filter { layer in !sublayersBefore.contains { $0 === layer } }
        XCTAssertEqual(highlights.count, 2, "The target has a backdrop and a tint")
        XCTAssertTrue(visuals.dropGlowGuides.isEmpty, "The classic appearance has no drop glow")
        let iconIndex = try XCTUnwrap(target.jitterLayer.sublayers?.firstIndex { $0 === target.iconLayer })
        for layer in highlights {
            let index = try XCTUnwrap(target.jitterLayer.sublayers?.firstIndex { $0 === layer })
            XCTAssertLessThan(index, iconIndex, "The highlight lies below the icon")
            XCTAssertEqual(layer.opacity, 1)
            XCTAssertTrue(CATransform3DEqualToTransform(layer.transform, CATransform3DMakeScale(1.1, 1.1, 1)))
            let pulse = try XCTUnwrap(layer.animation(forKey: "opacity") as? CABasicAnimation,
                                      "The pulse is the layer's only opacity animation")
            XCTAssertEqual(pulse.keyPath, "opacity")
            XCTAssertEqual(pulse.fromValue as? Float, 1)
            XCTAssertEqual(pulse.toValue as? Float, 0.4)
            XCTAssertEqual(pulse.duration, 0.11, accuracy: 0.001)
            XCTAssertEqual(pulse.repeatCount, 2)
            XCTAssertTrue(pulse.autoreverses)
            XCTAssertGreaterThanOrEqual(pulse.beginTime, before + 0.65)
            XCTAssertLessThanOrEqual(pulse.beginTime, after + 0.65)
        }
        let tints = highlights.filter { $0.compositingFilter as? String == "darkenBlendMode" }
        XCTAssertEqual(tints.count, 1, "The tint darkens what lies beneath it rather than covering it")
        let tint = try XCTUnwrap(tints.first)
        XCTAssertEqual(try XCTUnwrap(tint.backgroundColor?.components?.first), 0.9412, accuracy: 0.0001)
        XCTAssertEqual(tint.backgroundColor?.alpha, 1)
        let backdrop = try XCTUnwrap(highlights.first { $0 !== tint })
        XCTAssertNil(backdrop.compositingFilter)
        XCTAssertEqual(try XCTUnwrap(backdrop.backgroundColor?.components?.first), 0.9686, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(backdrop.backgroundColor?.alpha), 0.5, accuracy: 0.0001)

        visuals.endHover()

        XCTAssertFalse(target.isDarkened)
        XCTAssertEqual(target.titleLayer.opacity, 1)
        XCTAssertEqual(dragged.titleLayer.opacity, 1)
        XCTAssertTrue(dragged.isMagnified)
        XCTAssertTrue(highlights.allSatisfy { $0.superlayer == nil })
    }

    /// Hovering over a folder leaves its backdrop colour and thumbnails as they are, including
    /// thumbnails the folder shows again or receives while it is hovered, and after the hover.
    func testHoverOnFolderLeavesItsThumbnailsUndarkened() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"], ["D"]])]])
        let target = try fixture.folderCell("Work")
        let dragged = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.first)
        let image = try solidImage()
        target.setThumbnail(image, at: 0)
        let backdrop = target.backdropLayer.backgroundColor
        let visuals = ClassicalGroupDragVisuals()

        visuals.hover(target: target, dragged: dragged, slow: false)
        XCTAssertFalse(target.isDarkened, "A folder target shows no pressed look")
        XCTAssertEqual(target.backdropLayer.backgroundColor, backdrop)
        target.setFolder(ClassicalPageFolder(id: target.folder.id, title: "Work",
                                             pages: [try ["B", "C", "D"].map(fixture.record)]))
        target.setThumbnail(image, at: 2)
        assertThumbnails(of: target, at: [0, 2], show: image, "while hovered")
        for layer in target.thumbnailLayers {
            XCTAssertTrue(layer.filters?.isEmpty ?? true)
            XCTAssertNil(layer.compositingFilter)
        }

        visuals.endHover()
        assertThumbnails(of: target, at: [0, 2], show: image, "after the hover")
        XCTAssertEqual(target.backdropLayer.backgroundColor, backdrop)
    }

    private func assertThumbnails(of cell: ClassicalFolderItemLayer, at indices: [Int], show image: CGImage,
                                  _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        for index in indices {
            XCTAssertTrue((cell.thumbnailLayers[index].contents as AnyObject?) === image,
                          "Thumbnail \(index) keeps its image \(context)", file: file, line: line)
        }
    }

    /// In deleting mode, hovering over an icon stops its jiggle and hides the delete badges of the
    /// target and of the dragged icon; moving off it brings both back.
    func testHoverInDeletingModeStopsTheTargetsJiggleAndHidesBadgesUntilItEnds() throws {
        let fixture = try ClassicalFolderTestBoard([["A", "B", "C"]])
        fixture.board.deletability.isDeletable = { _ in true }
        fixture.board.setDeleting(true)
        let page = try XCTUnwrap(fixture.board.pager.pages.first)
        let dragged = page.itemLayers[0]
        let target = page.itemLayers[1]
        XCTAssertTrue(target.isJittering)
        XCTAssertNotNil(target.closeboxLayer)
        let start = fixture.iconCenter(of: dragged)
        let activation = CGPoint(x: start.x + ClassicalDragParameters.activationDistance + 1, y: start.y)
        fixture.content.mouseDown(with: try fixture.mouse(.leftMouseDown, at: start, time: 0))
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: activation, time: 1))
        XCTAssertTrue(fixture.content.drag.isDragging)
        XCTAssertNotNil(dragged.closeboxLayer, "The dragged icon keeps its badge until it hovers")

        let targetIcon = fixture.iconCenter(of: target)
        let hover = CGPoint(x: targetIcon.x - dragged.position.x + activation.x,
                            y: targetIcon.y - dragged.position.y + activation.y)
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: hover, time: 100))
        XCTAssertTrue(target.isDarkened, "The fixture hovers over the target")
        XCTAssertFalse(target.isJittering)
        XCTAssertNil(target.closeboxLayer)
        XCTAssertNil(dragged.closeboxLayer)

        let emptyFrame = ClassicalFolderTestBoard.geometry.grid.cellFrame(at: 4)
        let empty = fixture.host.convert(CGPoint(x: emptyFrame.midX, y: emptyFrame.midY), from: page.layer)
        let away = CGPoint(x: empty.x - dragged.position.x + hover.x, y: empty.y - dragged.position.y + hover.y)
        fixture.content.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: away, time: 200))
        XCTAssertFalse(target.isDarkened)
        XCTAssertTrue(target.isJittering)
        XCTAssertNotNil(target.closeboxLayer)
        XCTAssertNotNil(dragged.closeboxLayer)
        fixture.content.drag.cancel(animated: false)
    }

    func testMinimizingIntoFolderHidesThumbnailUntilCleared() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        let folder = try fixture.folderCell("Work")
        let cell = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.last)
        let visuals = ClassicalGroupDragVisuals()
        XCTAssertEqual(folder.thumbnailLayers[0].opacity, 1)

        visuals.minimizeTarget(visuals.image(of: cell, in: fixture.host), into: folder, host: fixture.host)

        XCTAssertEqual(folder.thumbnailLayers[0].opacity, 0,
                       "The destination stays hidden while the icon flies into its thumbnail slot")
        visuals.clear()
        XCTAssertEqual(folder.thumbnailLayers[0].opacity, 1)
    }

    func testHoverShrinkUsesFiveSecondsOnlyWithAllowedShiftAndOtherwiseInheritsDuration() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        let window = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: fixture.content)
        defer { window.close() }
        let folder = try fixture.folderCell("Work")
        let cell = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.last)
        let image = try solidImage()
        let source = ClassicalGroupDragVisuals.IconImage(contents: image,
                                                         frame: cell.iconLayer.convert(cell.iconLayer.bounds, to: fixture.host))
        let visuals = ClassicalGroupDragVisuals()

        for (allowed, shifted, expectedDuration) in [(false, true, 0.73), (true, false, 0.73),
                                                       (true, true, 5.0)] {
            visuals.slowMotionAllowed = { allowed }
            visuals.shiftKeyDown = { shifted }
            CATransaction.begin()
            CATransaction.setDisableActions(false)
            CATransaction.setAnimationDuration(0.73)
            visuals.minimizeTarget(source, into: folder, host: fixture.host)
            CATransaction.commit()
            CATransaction.flush()
            let proxy = try XCTUnwrap(folder.sublayers?.first { ($0.contents as AnyObject?) === image })
            let shrink = try XCTUnwrap(proxy.animation(forKey: "transform"))
            XCTAssertEqual(shrink.duration, expectedDuration, accuracy: 0.01)
            visuals.clear()
        }
    }

    func testDropSecondIconRereadsShiftAfterItsStagger() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        let window = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: fixture.content)
        defer { window.close() }
        let folder = try fixture.folderCell("Work")
        let cell = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.last)
        let frame = cell.iconLayer.convert(cell.iconLayer.bounds, to: fixture.host)
        let targetImage = try solidImage()
        let draggedImage = try solidImage()
        let target = ClassicalGroupDragVisuals.IconImage(contents: targetImage, frame: frame)
        let dragged = ClassicalGroupDragVisuals.IconImage(contents: draggedImage,
                                                          frame: frame.offsetBy(dx: 120, dy: 0))
        let visuals = ClassicalGroupDragVisuals()
        visuals.slowMotionAllowed = { true }
        let shift = ShiftInput()
        visuals.shiftKeyDown = { shift.isDown }

        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setAnimationDuration(0.73)
        let started = CACurrentMediaTime()
        visuals.minimize(target: target, dragged: dragged, into: folder, host: fixture.host, draggedIndex: 1)
        CATransaction.commit()
        CATransaction.flush()
        let targetProxy = try XCTUnwrap(folder.sublayers?.first { ($0.contents as AnyObject?) === targetImage })
        XCTAssertEqual(try XCTUnwrap(targetProxy.animation(forKey: "transform")).duration, 0.73, accuracy: 0.01)
        XCTAssertNil(folder.sublayers?.first { ($0.contents as AnyObject?) === draggedImage }?.animation(forKey: "transform"))

        shift.isDown = true
        ClassicalFolderTestBoard.waitUntil {
            CATransaction.flush()
            return folder.sublayers?.first { ($0.contents as AnyObject?) === draggedImage }?
                .animation(forKey: "transform") != nil
        }
        let draggedProxy = try XCTUnwrap(folder.sublayers?.first { ($0.contents as AnyObject?) === draggedImage })
        XCTAssertGreaterThanOrEqual(CACurrentMediaTime() - started, 0.08)
        XCTAssertEqual(try XCTUnwrap(draggedProxy.animation(forKey: "transform")).duration, 5, accuracy: 0.01)
        visuals.clear()
    }

    /// The new folder can open after the dragged icon has shrunk into its thumbnail. The target
    /// icon starts first, so completing its shrink alone must not advance that opening.
    func testNewFolderOpenWaitsForDraggedIconShrink() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        let window = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: fixture.content)
        defer { window.close() }
        let folder = try fixture.folderCell("Work")
        let target = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.last)
        let targetImage = ClassicalGroupDragVisuals.IconImage(contents: try solidImage(),
                                                              frame: target.iconLayer.convert(target.iconLayer.bounds,
                                                                                              to: fixture.host))
        let draggedImage = ClassicalGroupDragVisuals.IconImage(contents: try solidImage(),
                                                               frame: targetImage.frame.offsetBy(dx: 120, dy: 0))
        let visuals = ClassicalGroupDragVisuals()
        var completions = 0
        var draggedThumbnailWasHiddenAtCompletion = false

        visuals.minimize(target: targetImage, dragged: draggedImage, into: folder, host: fixture.host,
                         draggedIndex: 1) {
            completions += 1
            draggedThumbnailWasHiddenAtCompletion = folder.thumbnailLayers[1].opacity == 0
        }

        XCTAssertEqual(completions, 0, "The folder cannot open at the start of the minimize")
        ClassicalFolderTestBoard.waitUntil { completions == 1 }
        XCTAssertTrue(draggedThumbnailWasHiddenAtCompletion,
                      "The callback follows the dragged shrink and precedes its thumbnail reveal")
        XCTAssertEqual(completions, 1)
    }

    func testSlowHoverOnFolderPulsesItsBackdropAndRestoresIt() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]])]])
        let dragged = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.first)
        let target = try fixture.folderCell("Work")
        let visuals = ClassicalGroupDragVisuals()

        visuals.hover(target: target, dragged: dragged, slow: true)

        XCTAssertFalse(target.isDarkened, "A folder target shows no pressed look")
        XCTAssertTrue(CATransform3DEqualToTransform(target.backdropLayer.transform,
                                                    CATransform3DMakeScale(1.1, 1.1, 1)))
        let pulse = try XCTUnwrap(target.backdropLayer.animation(forKey: "opacity") as? CABasicAnimation)
        XCTAssertEqual(pulse.duration, 0.55, accuracy: 0.001)
        XCTAssertEqual(pulse.repeatCount, 2)
        visuals.endHover()
        XCTAssertFalse(target.isDarkened)
        XCTAssertNil(target.backdropLayer.animation(forKey: "opacity"))
        XCTAssertTrue(CATransform3DIsIdentity(target.backdropLayer.transform))
    }

    func testClearingAnInterruptedMinimizeRestoresPreviewScrollAndThumbnails() throws {
        let names = ["B", "C", "D", "E", "F", "G", "H", "I", "J", "K"]
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Many", [names])]])
        let folder = try fixture.folderCell("Many")
        let dragged = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers.first)
        let visuals = ClassicalGroupDragVisuals()
        XCTAssertEqual(folder.thumbnailLayers.count, 10)
        XCTAssertTrue(folder.thumbnailLayers.allSatisfy { $0.opacity == 1 })

        visuals.minimize(target: nil, dragged: visuals.image(of: dragged, in: fixture.host),
                         into: folder, host: fixture.host, draggedIndex: 9)

        XCTAssertEqual(folder.miniGridLayer.bounds.origin.y, 0,
                       "The destination is chosen while the closed preview is at its top")
        XCTAssertEqual(folder.thumbnailLayers[9].opacity, 0)
        visuals.clear()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(folder.miniGridLayer.bounds.origin.y, 0)
        XCTAssertTrue(folder.thumbnailLayers.allSatisfy { $0.opacity == 1 },
                      "Cancellation keeps every thumbnail visible after the pending animation completes")
    }

    /// With Liquid Glass the target neither darkens nor pulses: a guide the shape of a folder cell's
    /// backdrop appears behind its icon, fading in while growing to 1.2 over 0.225 s ease-in-out, and
    /// reverses at the same timing before it leaves when the hover ends.
    func testGlassHoverShowsAGrowingDropGlowBehindTheTargetAndRemovesIt() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([["A", "B"]])
        let window = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: fixture.content)
        defer { window.close() }
        let cells = try XCTUnwrap(fixture.board.pager.pages.first?.itemLayers)
        let dragged = cells[0]
        let target = cells[1]
        let sublayersBefore = target.jitterLayer.sublayers ?? []
        let visuals = ClassicalGroupDragVisuals()
        visuals.showsDropGlow = true

        visuals.hover(target: target, dragged: dragged, slow: false)

        XCTAssertFalse(target.isDarkened)
        XCTAssertEqual(target.titleLayer.opacity, 0)
        let added = (target.jitterLayer.sublayers ?? []).filter { layer in !sublayersBefore.contains { $0 === layer } }
        XCTAssertEqual(added.count, 1, "Only the drop glow guide, no highlight")
        let guide = try XCTUnwrap(visuals.dropGlowGuides.first)
        XCTAssertEqual(visuals.dropGlowGuides.count, 1)
        XCTAssertTrue(added.first === guide)
        let guideIndex = try XCTUnwrap(target.jitterLayer.sublayers?.firstIndex { $0 === guide })
        let iconIndex = try XCTUnwrap(target.jitterLayer.sublayers?.firstIndex { $0 === target.iconLayer })
        XCTAssertLessThan(guideIndex, iconIndex, "The glow lies behind the target")
        let shape = ClassicalFolderGeometry.Cell(iconFrame: target.iconLayer.frame)
        XCTAssertEqual(guide.bounds.size, shape.backdropFrame.size)
        XCTAssertEqual(guide.position, CGPoint(x: shape.backdropFrame.midX, y: shape.backdropFrame.midY))
        XCTAssertEqual(guide.cornerRadius, shape.cornerRadius)
        XCTAssertEqual(guide.opacity, 1)
        XCTAssertTrue(CATransform3DEqualToTransform(guide.transform, CATransform3DMakeScale(1.2, 1.2, 1)))
        try expectGlowTiming(guide)

        visuals.endHover()

        XCTAssertEqual(guide.opacity, 0)
        XCTAssertTrue(CATransform3DIsIdentity(guide.transform))
        try expectGlowTiming(guide)
        ClassicalFolderTestBoard.waitUntil { visuals.dropGlowGuides.isEmpty }
        XCTAssertTrue(visuals.dropGlowGuides.isEmpty)
        XCTAssertNil(guide.superlayer, "The glow leaves the target after fading out")
        XCTAssertEqual(target.titleLayer.opacity, 1)
    }

    private func expectGlowTiming(_ guide: CALayer, file: StaticString = #filePath, line: UInt = #line) throws {
        for key in ["opacity", "transform"] {
            let animation = try XCTUnwrap(guide.animation(forKey: key) as? CABasicAnimation, key, file: file, line: line)
            XCTAssertEqual(animation.duration, 0.225, accuracy: 0.0001, key, file: file, line: line)
            let expected = CAMediaTimingFunction(name: .easeInEaseOut)
            var actualPoint = [Float](repeating: 0, count: 2), expectedPoint = [Float](repeating: 0, count: 2)
            for index in 1...2 {
                animation.timingFunction?.getControlPoint(at: index, values: &actualPoint)
                expected.getControlPoint(at: index, values: &expectedPoint)
                XCTAssertEqual(actualPoint, expectedPoint, key, file: file, line: line)
            }
        }
    }

    private func solidImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                                             bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.5, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try XCTUnwrap(context.makeImage())
    }
}

@MainActor
private final class ShiftInput {
    var isDown = false
}
