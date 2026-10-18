import XCTest
@testable import Launchpod

/// Page slots as shown: an application or a folder of catalog applications, their identities,
/// the layout slots they stand for, removals, and folder renames.
@MainActor
final class ClassicalPageItemTests: XCTestCase {
    private func record(_ name: String) throws -> AppRecord {
        try ClassicalDragTestBoard.record(name)
    }

    func testAnApplicationSlotExposesItsRecordAndNoFolder() throws {
        let a = try record("A")
        let item = ClassicalPageItem.app(a)
        XCTAssertEqual(item.id, .app(a.id))
        XCTAssertEqual(item.record, a)
        XCTAssertNil(item.folder)
        XCTAssertEqual(item.title, "A")
        XCTAssertEqual(item.records, [a])
        XCTAssertEqual(item.layoutItem, .app(a.id))
    }

    func testAFolderSlotListsItsApplicationsInPageOrderAndKeepsItsTitleState() throws {
        let a = try record("A"), b = try record("B"), c = try record("C")
        let id = ClassicalLayoutFolder.ID()
        let item = ClassicalPageItem.folder(ClassicalPageFolder(id: id, title: "Work", pages: [[b, a], [c]],
                                                                usesDefaultTitle: true))
        XCTAssertEqual(item.id, .folder(id))
        XCTAssertNil(item.record)
        XCTAssertEqual(item.title, "Work")
        XCTAssertEqual(item.records, [b, a, c])
        XCTAssertEqual(item.layoutItem, .folder(ClassicalLayoutFolder(id: id, title: "Work", pages: [[b.id, a.id], [c.id]],
                                                                      usesDefaultTitle: true)))
        XCTAssertEqual(ClassicalPageItem.ID(item.layoutItem), item.id, "A layout slot names the same item")
    }

    func testRemovingDropsApplicationsEmptiedFolderPagesAndEmptiedFolders() throws {
        let a = try record("A"), b = try record("B"), c = try record("C")
        let id = ClassicalLayoutFolder.ID()
        let folder = ClassicalPageItem.folder(ClassicalPageFolder(id: id, title: "Work", pages: [[a, b], [c]]))

        XCTAssertNil(ClassicalPageItem.app(a).removing([a.id]))
        XCTAssertEqual(ClassicalPageItem.app(a).removing([b.id]), .app(a))
        XCTAssertEqual(folder.removing([b.id])?.folder?.pages, [[a], [c]])
        XCTAssertEqual(folder.removing([c.id])?.folder?.pages, [[a, b]], "An emptied folder page goes")
        XCTAssertEqual(folder.removing([c.id])?.folder?.title, "Work")
        XCTAssertNil(folder.removing([a.id, b.id, c.id]), "A folder left empty goes")
        XCTAssertEqual(folder.removing([]), folder)
    }

    func testRenameTakesTheSavedTitleStateAndOnlyChangesThatFolder() throws {
        let a = try record("A"), b = try record("B"), c = try record("C")
        let other = ClassicalPageFolder(id: .defaultOther, title: "Other", pages: [[a]], usesDefaultTitle: true)
        let games = ClassicalPageFolder(id: .defaultGames, title: "Games", pages: [[b]], usesDefaultTitle: true)
        var pages: [[ClassicalPageItem]] = [[.app(c)], [.folder(games), .folder(other)]]
        let saved = ClassicalLayoutFolder(id: .defaultOther, title: "Tools", pages: [[a.id]])

        ClassicalPageFolder.rename(.defaultOther, to: "Typed", saved: saved, locale: Locale(identifier: "en"), in: &pages)

        XCTAssertEqual(pages[1][1].folder?.title, "Tools", "The saved title wins over the typed one")
        XCTAssertEqual(pages[1][1].folder?.usesDefaultTitle, false)
        XCTAssertEqual(pages[1][1].folder?.pages, [[a]])
        XCTAssertEqual(pages[1][0], .folder(games))
        XCTAssertEqual(pages[0], [.app(c)])
    }

    func testRenameShowsASavedDefaultTitleInTheLocale() throws {
        let a = try record("A")
        var pages: [[ClassicalPageItem]] = [[.folder(ClassicalPageFolder(id: .defaultOther, title: "Old", pages: [[a]]))]]
        let saved = ClassicalLayoutFolder(id: .defaultOther, title: "Other", pages: [[a.id]], usesDefaultTitle: true)
        let locale = Locale(identifier: "en")

        ClassicalPageFolder.rename(.defaultOther, to: "Typed", saved: saved, locale: locale, in: &pages)

        XCTAssertEqual(pages[0][0].folder?.usesDefaultTitle, true)
        XCTAssertEqual(pages[0][0].folder?.title,
                       ClassicalLayoutFolder.displayTitle(for: .defaultOther, title: "Other", usesDefaultTitle: true,
                                                          locale: locale))
    }

    func testDirectoryOtherTitleStateSurvivesPageProjectionAndRefresh() throws {
        let app = try record("A")
        let id = ClassicalLayoutFolder.ID()
        let saved = ClassicalLayoutFolder(id: id, title: "Foo (Other)", pages: [[app.id]],
                                          usesDefaultTitle: true, directoryOtherBaseTitle: "Foo")
        var pages: [[ClassicalPageItem]] = [[.folder(ClassicalPageFolder(id: id, title: "Old", pages: [[app]]))]]

        ClassicalPageFolder.rename(id, to: "Ignored", saved: saved, locale: Locale(identifier: "en"), in: &pages)

        let shown = try XCTUnwrap(pages[0][0].folder)
        XCTAssertEqual(shown.title, "Foo (Other)")
        XCTAssertTrue(shown.usesDefaultTitle)
        XCTAssertEqual(shown.directoryOtherBaseTitle, "Foo")
        XCTAssertEqual(pages[0][0].layoutItem.folder, saved,
                       "Recreating a layout slot keeps the suffix's source directory name")
    }

    func testRenameWithoutASavedFolderShowsTheTypedTitle() throws {
        let a = try record("A")
        let id = ClassicalLayoutFolder.ID()
        var pages: [[ClassicalPageItem]] = [[.folder(ClassicalPageFolder(id: id, title: "Work", pages: [[a]],
                                                                         usesDefaultTitle: true))]]

        ClassicalPageFolder.rename(id, to: "Typed", saved: nil, locale: Locale(identifier: "en"), in: &pages)

        XCTAssertEqual(pages[0][0].folder?.title, "Typed")
        XCTAssertEqual(pages[0][0].folder?.usesDefaultTitle, true, "Nothing saved leaves the title state as it was")

        let unchanged = pages
        ClassicalPageFolder.rename(ClassicalLayoutFolder.ID(), to: "Else", saved: nil, locale: Locale(identifier: "en"),
                                   in: &pages)
        XCTAssertEqual(pages, unchanged, "An unknown folder changes nothing")
    }
}
