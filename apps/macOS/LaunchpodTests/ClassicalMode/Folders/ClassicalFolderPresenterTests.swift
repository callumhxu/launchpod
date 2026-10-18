import AppKit
import QuartzCore
import XCTest
@testable import Launchpod

/// Opening and closing a folder over the root pages: while it is open the root pages scale to 0.95
/// and fade out entirely, their page dots hide and the closed cell is replaced by the panel; closing
/// restores all of it and, 0.25 s later, asks for the root pages to be laid out again.
@MainActor
final class ClassicalFolderPresenterTests: XCTestCase {
    private func isScale(_ transform: CATransform3D, _ scale: CGFloat) -> Bool {
        CATransform3DEqualToTransform(transform, CATransform3DMakeScale(scale, scale, 1))
    }

    func testSlowMotionPreferenceDefaultsOffAndRequiresExplicitEnablement() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }

        XCTAssertFalse(ClassicalFolderPresenter.slowMotionAllowed(in: defaults))
        defaults.set(true, forKey: "slow-motion-allowed")
        XCTAssertTrue(ClassicalFolderPresenter.slowMotionAllowed(in: defaults))
        defaults.set(false, forKey: "slow-motion-allowed")
        XCTAssertFalse(ClassicalFolderPresenter.slowMotionAllowed(in: defaults))
    }

    func testOpeningHidesTheRootPagesAndClosingRestoresThem() throws {
        let fixture = try ClassicalFolderTestBoard([["A", .folder("Work", [["B", "C"]]), "D"], ["E"]])
        let presenter = fixture.board.folders
        var visibility: [Bool] = []
        presenter.visibilityChanged = { visibility.append($0) }
        var delays: [TimeInterval] = []
        presenter.sleep = { delays.append($0) }
        var settled = 0
        let didClose = presenter.didClose
        presenter.didClose = { settled += 1; didClose?() }
        let cell = try fixture.folderCell("Work")
        let dotsWereHidden = fixture.board.pager.dotsLayer.isHidden

        let folder = try fixture.open("Work")
        XCTAssertTrue(isScale(fixture.background.transform, 0.95), "The root pages scale to 0.95")
        XCTAssertEqual(fixture.background.opacity, 0, "and fade out entirely")
        XCTAssertTrue(fixture.board.pager.dotsLayer.isHidden, "The root page dots hide")
        XCTAssertEqual(cell.opacity, 0, "The panel replaces the closed cell")
        XCTAssertTrue(folder.layer.superlayer === fixture.host, "The panel is above the root pages, not inside them")
        XCTAssertEqual(folder.layer.titleLayer.string as? String, "Work")
        XCTAssertEqual(visibility, [true])

        presenter.close()
        fixture.waitUntilClosed()
        XCTAssertTrue(CATransform3DIsIdentity(fixture.background.transform))
        XCTAssertEqual(fixture.background.opacity, 1)
        XCTAssertEqual(fixture.board.pager.dotsLayer.isHidden, dotsWereHidden)
        XCTAssertEqual(cell.opacity, 1)
        XCTAssertFalse(cell.titleLayer.isHidden)
        XCTAssertNil(folder.layer.superlayer)
        XCTAssertEqual(visibility, [true, false])
        ClassicalFolderTestBoard.waitUntil { settled == 1 }
        XCTAssertEqual(delays, [0.25], "The root pages are laid out again 0.25 s after the folder closed")
    }

    func testReduceMotionFadesTheRootPagesWithoutScaling() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        fixture.board.folders.reduceMotion = { true }
        try fixture.open("Work")
        XCTAssertTrue(CATransform3DIsIdentity(fixture.background.transform))
        XCTAssertEqual(fixture.background.opacity, 0)
    }

    /// The panel grows while the root grid fades and recedes, then both reverse together on close.
    /// These primary motions run together; the folder page dots fade in after opening completes.
    func testPanelAndRootPagesAnimateTogetherInBothDirections() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                      contentView: fixture.content)
        defer { panel.close() }

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        let openingPanel = try XCTUnwrap(folder.layer.backdropLayer.animation(forKey: "bounds"),
                                         "The folder backdrop grows from its closed cell")
        let openingFade = try XCTUnwrap(fixture.background.animation(forKey: "opacity"),
                                        "The root pages fade while the panel grows")
        XCTAssertNotNil(fixture.background.animation(forKey: "transform"), "The root pages recede")
        XCTAssertNotNil(folder.layer.titleLayer.animation(forKey: "opacity"), "The folder title appears")
        XCTAssertEqual(openingPanel.duration, openingFade.duration, accuracy: 0.05)
        XCTAssertGreaterThan(openingPanel.duration, 0.15)
        XCTAssertLessThan(openingPanel.duration, 0.5)
        fixture.waitUntilOpened()

        fixture.board.folders.close()
        let closingPanel = try XCTUnwrap(folder.layer.backdropLayer.animation(forKey: "bounds"),
                                         "The backdrop shrinks into its closed cell")
        let closingFade = try XCTUnwrap(fixture.background.animation(forKey: "opacity"),
                                        "The root pages return while the panel shrinks")
        XCTAssertNotNil(fixture.background.animation(forKey: "transform"), "The root pages grow back")
        XCTAssertNotNil(folder.layer.titleLayer.animation(forKey: "opacity"), "The folder title disappears")
        XCTAssertEqual(closingPanel.duration, closingFade.duration, accuracy: 0.05)
        XCTAssertEqual(closingPanel.duration, openingPanel.duration, accuracy: 0.05)
        fixture.waitUntilClosed()
    }

    /// The clipping mask must follow the backdrop throughout the transition, while the first
    /// page's icon moves between its closed thumbnail and its open slot.
    func testMaskAndFirstPageIconAnimateWithTheBackdropInBothDirections() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                      contentView: fixture.content)
        defer { panel.close() }

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        let first = try XCTUnwrap(folder.cell(for: try fixture.record("A").id))
        let backdropOpen = try XCTUnwrap(folder.layer.backdropLayer.animation(forKey: "bounds"))
        let maskOpen = try XCTUnwrap(folder.layer.maskLayer.animation(forKey: "bounds"))
        let iconOpen = try XCTUnwrap(first.iconLayer.animation(forKey: "bounds"))
        XCTAssertEqual(maskOpen.duration, backdropOpen.duration, accuracy: 0.05)
        XCTAssertEqual(iconOpen.duration, backdropOpen.duration, accuracy: 0.05)
        XCTAssertEqual(folder.layer.maskLayer.frame, folder.layer.backdropLayer.frame)
        XCTAssertEqual(first.iconLayer.frame, first.layout.iconFrame)
        fixture.waitUntilOpened()

        fixture.board.folders.close()
        let backdropClose = try XCTUnwrap(folder.layer.backdropLayer.animation(forKey: "bounds"))
        let maskClose = try XCTUnwrap(folder.layer.maskLayer.animation(forKey: "bounds"))
        let iconClose = try XCTUnwrap(first.iconLayer.animation(forKey: "bounds"))
        XCTAssertEqual(maskClose.duration, backdropClose.duration, accuracy: 0.05)
        XCTAssertEqual(iconClose.duration, backdropClose.duration, accuracy: 0.05)
        XCTAssertEqual(folder.layer.maskLayer.frame, folder.layer.backdropLayer.frame)
        let thumbnail = try fixture.folderCell("Work").thumbnailFrame(at: 0, in: folder.layer)
        let closedIcon = folder.layer.convert(first.iconLayer.frame, from: first.jitterLayer)
        XCTAssertEqual(closedIcon.midX, thumbnail.midX, accuracy: 0.5)
        XCTAssertEqual(closedIcon.midY, thumbnail.midY, accuracy: 0.5)
        fixture.waitUntilClosed()
    }

    /// Holding Shift slows opening to five seconds when slow motion is allowed.
    func testShiftSlowsOpeningToFiveSecondsWhenAllowed() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                      contentView: fixture.content)
        defer { panel.close() }
        fixture.board.folders.reduceMotion = { false }
        fixture.board.folders.slowMotionAllowed = { true }
        fixture.board.folders.shiftKeyDown = { true }

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        let opening = try XCTUnwrap(folder.layer.backdropLayer.animation(forKey: "bounds"))
        XCTAssertEqual(opening.duration, 5, accuracy: 0.01)
        fixture.board.folders.close(animated: false)
    }

    func testShiftSlowsClosingToFiveSecondsWhenAllowed() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                      contentView: fixture.content)
        defer { panel.close() }
        fixture.board.folders.reduceMotion = { false }
        fixture.board.folders.shiftKeyDown = { false }

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        fixture.waitUntilOpened()
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        fixture.board.folders.slowMotionAllowed = { true }
        fixture.board.folders.shiftKeyDown = { true }

        fixture.board.folders.close()
        let closing = try XCTUnwrap(folder.layer.backdropLayer.animation(forKey: "bounds"))
        XCTAssertEqual(closing.duration, 5, accuracy: 0.01)
        fixture.board.folders.close(animated: false)
    }

    func testShiftDoesNotSlowOpeningWhenSlowMotionIsDisallowed() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                      contentView: fixture.content)
        defer { panel.close() }
        fixture.board.folders.reduceMotion = { false }
        fixture.board.folders.slowMotionAllowed = { false }
        fixture.board.folders.shiftKeyDown = { true }

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        let opening = try XCTUnwrap(folder.layer.backdropLayer.animation(forKey: "bounds"))
        XCTAssertLessThan(opening.duration, 0.5)
        fixture.waitUntilOpened()
        fixture.board.folders.close(animated: false)
    }

    func testShiftDoesNotSlowClosingWhenSlowMotionIsDisallowed() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                      contentView: fixture.content)
        defer { panel.close() }
        fixture.board.folders.reduceMotion = { false }
        fixture.board.folders.shiftKeyDown = { false }

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        fixture.waitUntilOpened()
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        fixture.board.folders.slowMotionAllowed = { false }
        fixture.board.folders.shiftKeyDown = { true }

        fixture.board.folders.close()
        let closing = try XCTUnwrap(folder.layer.backdropLayer.animation(forKey: "bounds"))
        XCTAssertLessThan(closing.duration, 0.5)
        fixture.board.folders.close(animated: false)
    }

    /// The folder page indicator appears after the backdrop finishes expanding, in its own brief
    /// fade. It must not be visible inside the tiny closed-cell geometry during the first phase.
    func testFolderPageDotsFadeInAfterThePanelOpens() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"], ["C"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                      contentView: fixture.content)
        defer { panel.close() }

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        XCTAssertEqual(folder.pager.dotsLayer.opacity, 0, "The indicator stays hidden as the backdrop grows")

        fixture.waitUntilOpened()
        XCTAssertEqual(folder.pager.dotsLayer.opacity, 1)
        let fade = try XCTUnwrap(folder.pager.dotsLayer.animation(forKey: "opacity"),
                                 "The indicator appears in a second motion phase")
        XCTAssertEqual(fade.duration, 0.1, accuracy: 0.01)
        fixture.board.folders.close()
        fixture.waitUntilClosed()
    }

    func testShiftSlowsThePageDotFadeWhenSlowMotionIsAllowed() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"], ["C"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                      contentView: fixture.content)
        defer { panel.close() }
        fixture.board.folders.reduceMotion = { false }
        fixture.board.folders.slowMotionAllowed = { true }
        fixture.board.folders.shiftKeyDown = { true }

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        let deadline = Date().addingTimeInterval(6)
        while fixture.board.folders.isOpening && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(fixture.board.folders.isOpening)
        let fade = try XCTUnwrap(folder.pager.dotsLayer.animation(forKey: "opacity"))
        XCTAssertEqual(fade.duration, 0.5, accuracy: 0.01)
        fixture.board.folders.close(animated: false)
    }

    func testShiftSlowsPageDotFadeEvenWhenSlowMotionIsDisallowed() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"], ["C"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                      contentView: fixture.content)
        defer { panel.close() }
        fixture.board.folders.reduceMotion = { false }
        fixture.board.folders.slowMotionAllowed = { false }
        fixture.board.folders.shiftKeyDown = { true }

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        let opening = try XCTUnwrap(folder.layer.backdropLayer.animation(forKey: "bounds"))
        XCTAssertLessThan(opening.duration, 0.5, "The main folder motion is not in slow mode")
        fixture.waitUntilOpened()
        let dots = try XCTUnwrap(folder.pager.dotsLayer.animation(forKey: "opacity"))
        XCTAssertEqual(dots.duration, 0.5, accuracy: 0.01)
        fixture.board.folders.close(animated: false)
    }

    func testReduceMotionSkipsShiftedPageDotAnimation() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"], ["C"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                      contentView: fixture.content)
        defer { panel.close() }
        fixture.board.folders.reduceMotion = { true }
        fixture.board.folders.slowMotionAllowed = { true }
        fixture.board.folders.shiftKeyDown = { true }

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        fixture.waitUntilOpened()
        XCTAssertEqual(folder.pager.dotsLayer.opacity, 1)
        XCTAssertNil(folder.pager.dotsLayer.animation(forKey: "opacity"))
        fixture.board.folders.close(animated: false)
    }

    /// Reduce Motion drops only the 0.95 scale of the root pages; their fade in and out still
    /// animates with the transition, in a window where Core Animation adds implicit animations.
    func testReduceMotionStillCrossFadesTheRootPages() throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let panel = NativeAppTestSupport.makeKeyPanel(size: ClassicalFolderTestBoard.geometry.screenSize,
                                                      contentView: fixture.content)
        defer { panel.close() }
        fixture.board.folders.reduceMotion = { true }

        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        XCTAssertEqual(fixture.background.opacity, 0)
        XCTAssertNotNil(fixture.background.animation(forKey: "opacity"), "The root pages fade out")
        XCTAssertTrue(CATransform3DIsIdentity(fixture.background.transform))
        XCTAssertNil(fixture.background.animation(forKey: "transform"), "The root pages do not scale")
        fixture.waitUntilOpened()

        fixture.board.folders.close()
        XCTAssertEqual(fixture.background.opacity, 1)
        XCTAssertNotNil(fixture.background.animation(forKey: "opacity"), "The root pages fade back in")
        XCTAssertNil(fixture.background.animation(forKey: "transform"))
        fixture.waitUntilClosed()
    }

    /// Closing from a later folder page shrinks the first page's icons into the closed cell's
    /// thumbnails, which show that first page; each title travels with its icon, centred under the
    /// thumbnail, and fades out.
    func testClosingFromALaterPageShrinksTheFirstPageIntoTheThumbnails() throws {
        let first = ["A", "B", "C", "D", "E", "F"]
        let fixture = try ClassicalFolderTestBoard([[.folder("Many", [first, ["G"]]), "H"]])
        let cell = try fixture.folderCell("Many")
        let thumbnails = first.indices.map { cell.thumbnailFrame(at: $0, in: fixture.host) }
        let folder = try fixture.open("Many")
        folder.pager.settle(on: 1)
        XCTAssertEqual(folder.pager.currentPage, 1)

        fixture.board.folders.close()

        for (index, name) in first.enumerated() {
            let item = try XCTUnwrap(folder.cell(for: try fixture.record(name).id))
            let icon = fixture.host.convert(item.iconLayer.frame, from: item.jitterLayer)
            XCTAssertEqual(icon.midX, thumbnails[index].midX, accuracy: 0.5, name)
            XCTAssertEqual(icon.midY, thumbnails[index].midY, accuracy: 0.5, name)
            XCTAssertEqual(icon.width, thumbnails[index].width, accuracy: 0.5, name)
            let title = fixture.host.convert(item.titleLayer.frame, from: item.jitterLayer)
            XCTAssertEqual(title.midX, thumbnails[index].midX, accuracy: 0.5, "\(name)'s title stays centred on its icon")
            XCTAssertEqual(item.titleLayer.opacity, 0, name)
        }
        let later = try XCTUnwrap(folder.cell(for: try fixture.record("G").id))
        let laterIcon = fixture.host.convert(later.iconLayer.frame, from: later.jitterLayer)
        XCTAssertFalse(thumbnails.contains { abs($0.midX - laterIcon.midX) < 0.5 && abs($0.midY - laterIcon.midY) < 0.5 },
                       "The later page's icons do not collapse into the first page's thumbnails")
        fixture.waitUntilClosed()
    }

    /// Icons growing out of, or shrinking into, the thumbnails are resampled with Lanczos while they
    /// move; once opening completes they return to linear filtering. Only the panel is scaled with
    /// the root pages on exit.
    func testTransitioningIconsUseLanczosAndOpenIconsLinear() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), "C"]])
        let lanczos = CALayerContentsFilter(rawValue: "lanczos")
        XCTAssertTrue(fixture.board.openFolder(try fixture.folderID("Work")))
        let folder = try XCTUnwrap(fixture.board.folders.openFolder)
        let items = try ["A", "B"].map { try XCTUnwrap(folder.cell(for: try fixture.record($0).id)) }
        XCTAssertEqual(items.map(\.iconLayer.minificationFilter), [lanczos, lanczos], "While growing")
        fixture.waitUntilOpened()
        XCTAssertEqual(items.map(\.iconLayer.minificationFilter), [.linear, .linear], "Once open")
        XCTAssertEqual(fixture.board.folders.panelLayers.count, 1)
        XCTAssertTrue(fixture.board.folders.panelLayers.first === folder.layer)

        fixture.board.folders.close()
        XCTAssertEqual(items.map(\.iconLayer.minificationFilter), [lanczos, lanczos], "While shrinking")
        fixture.waitUntilClosed()
    }

    /// The folder's title and page dots grow out of, and collapse back to, the whole closed cell:
    /// the title's bottom at the cell's top and the dots at the cell's bottom, both centred on it.
    func testTitleAndDotsCollapseToTheClosedCell() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Many", [["A", "B", "C", "D", "E", "F"], ["G"]]), "H"]])
        let cell = try fixture.folderCell("Many")
        let cellFrame = fixture.host.convert(cell.bounds, from: cell)
        let folder = try fixture.open("Many")

        fixture.board.folders.close()

        let title = fixture.host.convert(folder.layer.titleLayer.frame, from: folder.layer)
        XCTAssertEqual(title.minY, cellFrame.maxY, accuracy: 0.5)
        XCTAssertEqual(title.midX, cellFrame.midX, accuracy: 0.5)
        XCTAssertEqual(folder.layer.titleLayer.opacity, 0)
        let dots = folder.pager.dotsLayer
        let dotsFrame = fixture.host.convert(dots.frame, from: try XCTUnwrap(dots.superlayer))
        XCTAssertEqual(dotsFrame.minY, cellFrame.minY, accuracy: 0.5)
        XCTAssertEqual(dotsFrame.midX, cellFrame.midX, accuracy: 0.5)
        XCTAssertEqual(dots.opacity, 0)
        fixture.waitUntilClosed()
    }

    func testOpeningWithTheKeyboardSelectsTheFirstApplication() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"], ["C"]])]])
        let folder = try fixture.open("Work", selectingFirstItem: true)
        ClassicalFolderTestBoard.waitUntil { folder.selectedRecord != nil }
        XCTAssertEqual(folder.selectedRecord?.metadata.displayName, "A")

        fixture.board.folders.close()
        fixture.waitUntilClosed()
        let unselected = try fixture.open("Work")
        XCTAssertNil(unselected.selectedRecord, "A click opens the folder without a selection")
    }

    func testOnlyOneFolderIsShownAtATime() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]]), .folder("Games", [["C", "D"]])]])
        let work = try fixture.open("Work")
        XCTAssertFalse(fixture.board.openFolder(try fixture.folderID("Games")))
        XCTAssertTrue(fixture.board.folders.openFolder === work)
    }

    func testClosingEndsDeletingModeInsideTheFolder() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let folder = try fixture.open("Work")
        folder.setDeleting(true)
        fixture.board.folders.close()
        XCTAssertFalse(folder.isDeleting)
    }

    /// The open folder is announced to accessibility as a folder, in the app's language.
    func testOpenFolderIsAnAccessibilityElementWithALocalizedRole() throws {
        let fixture = try ClassicalFolderTestBoard([[.folder("Work", [["A", "B"]])]])
        let presenter = fixture.board.folders
        presenter.accessibilityParent = fixture.content
        let expected = [
            "en": "folder", "zh-Hans": CatalogTestSupport.text("folder", locale: "zh-Hans"), "zh-Hant": CatalogTestSupport.text("folder", locale: "zh-Hant"), "fr": CatalogTestSupport.text("folder", locale: "fr"),
            "de": CatalogTestSupport.text("folder", locale: "de"), "ja": CatalogTestSupport.text("folder", locale: "ja"), "ko": CatalogTestSupport.text("folder", locale: "ko"), "es": CatalogTestSupport.text("folder", locale: "es"),
        ]
        for (language, role) in expected.sorted(by: { $0.key < $1.key }) {
            presenter.locale = { Locale(identifier: language) }
            try fixture.open("Work")
            let element = try XCTUnwrap(presenter.accessibilityElement)
            XCTAssertEqual(element.accessibilityRoleDescription(), role, language)
            XCTAssertEqual(element.accessibilityLabel(), "Work")
            XCTAssertTrue(fixture.content.accessibilityChildren()?.contains { ($0 as AnyObject) === element } == true)
            presenter.close()
            fixture.waitUntilClosed()
            XCTAssertNil(presenter.accessibilityElement, "The element is destroyed on close")
        }
    }
}
