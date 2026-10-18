import AppKit
import QuartzCore
import XCTest
@testable import Launchpod

/// The material layers under the Liquid Glass: the open folder's background, at the complement of
/// the root pages' opacity, and a drop glow for each guide, with the guide's fade and grow.
@MainActor
final class ClassicalFolderMaterialsTests: XCTestCase {
    private func withoutActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    private func materialHost() -> NSView {
        let host = NSView(frame: CGRect(origin: .zero, size: ClassicalFolderTestBoard.geometry.screenSize))
        host.wantsLayer = true
        return host
    }

    private func materials(in host: NSView) -> [CALayer] {
        (host.layer?.sublayers ?? []).filter { NSStringFromClass(type(of: $0)) == "MTMaterialLayer" }
    }

    private func requireMaterialLayers() throws {
        guard NSClassFromString("MTMaterialLayer") != nil else { throw XCTSkip("No material layer on this system") }
    }

    func testFolderBackgroundFollowsTheRootPagesOpacityOnlyForAGlassFolder() throws {
        try requireMaterialLayers()
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]], folderGlass: true)
        let window = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: fixture.content)
        defer { window.close() }
        let host = materialHost()
        let subject = ClassicalFolderMaterials(host: host)
        subject.synchronize(folders: fixture.board.folders, dropGlowGuides: [], in: fixture.host)
        XCTAssertTrue(materials(in: host).allSatisfy(\.isHidden), "No material while every folder is closed")

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        fixture.waitUntilOpened()
        let pages = try XCTUnwrap(fixture.board.folders.backgroundLayer)
        XCTAssertTrue(pages === fixture.background, "The root pages fade out behind the open folder")
        withoutActions { pages.opacity = 0.25 }
        subject.synchronize(folders: fixture.board.folders, dropGlowGuides: [], in: fixture.host)
        let background = try XCTUnwrap(materials(in: host).first)
        XCTAssertFalse(background.isHidden)
        XCTAssertEqual(background.opacity, 0.75, accuracy: 0.001)
        XCTAssertEqual(background.frame, host.bounds, "The material covers the whole stage")

        withoutActions { pages.opacity = 1 }
        subject.synchronize(folders: fixture.board.folders, dropGlowGuides: [], in: fixture.host)
        XCTAssertTrue(background.isHidden, "The material is gone once the pages are fully back")
        fixture.board.folders.close(animated: false)
    }

    func testClassicFolderHasNoBackgroundMaterial() throws {
        let restoreHost = try NativeAppTestSupport.isolateHostWindows()
        defer { restoreHost() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let window = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                       contentView: fixture.content)
        defer { window.close() }
        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        fixture.waitUntilOpened()
        let host = materialHost()
        ClassicalFolderMaterials(host: host).synchronize(folders: fixture.board.folders, dropGlowGuides: [],
                                                          in: fixture.host)
        XCTAssertTrue(materials(in: host).isEmpty)
        fixture.board.folders.close(animated: false)
    }

    /// A drop glow covers its guide's frame with the guide's own opacity, scale and animations, and
    /// leaves when its guide is no longer published.
    func testDropGlowCopiesItsGuideAndLeavesWithIt() throws {
        try requireMaterialLayers()
        let host = materialHost()
        let root = CALayer()
        let parent = CALayer()
        let guide = CALayer()
        withoutActions {
            root.frame = host.bounds
            parent.frame = CGRect(x: 100, y: 100, width: 200, height: 200)
            guide.frame = CGRect(x: 20, y: 30, width: 80, height: 80)
            guide.cornerRadius = 18
            guide.opacity = 0
            root.addSublayer(parent)
            parent.addSublayer(guide)
        }
        let grow = CABasicAnimation(keyPath: "transform")
        grow.fromValue = CATransform3DIdentity
        grow.duration = ClassicalDragParameters.dropGlowDuration
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.duration = ClassicalDragParameters.dropGlowDuration
        withoutActions {
            guide.opacity = 1
            guide.transform = CATransform3DMakeScale(1.2, 1.2, 1)
            guide.add(grow, forKey: "transform")
            guide.add(fade, forKey: "opacity")
        }
        let folders = ClassicalFolderPresenter()
        let subject = ClassicalFolderMaterials(host: host)

        subject.synchronize(folders: folders, dropGlowGuides: [guide], in: root)

        let glow = try XCTUnwrap(materials(in: host).first)
        XCTAssertFalse(glow.isHidden)
        XCTAssertEqual(glow.bounds.size, CGSize(width: 80, height: 80))
        XCTAssertEqual(glow.position, CGPoint(x: 160, y: 170))
        XCTAssertEqual(glow.cornerRadius, 18)
        XCTAssertEqual(glow.opacity, 1)
        XCTAssertTrue(CATransform3DEqualToTransform(glow.transform, CATransform3DMakeScale(1.2, 1.2, 1)))
        for key in ["opacity", "transform"] {
            let copied = try XCTUnwrap(glow.animation(forKey: key) as? CABasicAnimation, key)
            XCTAssertEqual(copied.duration, ClassicalDragParameters.dropGlowDuration, key)
        }

        subject.synchronize(folders: folders, dropGlowGuides: [], in: root)
        XCTAssertTrue(materials(in: host).isEmpty, "The glow leaves with its guide")
    }
}
