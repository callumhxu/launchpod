import Foundation
import XCTest
@testable import Launchpod

/// The first Classical arrangement built from the applications in the catalog.
final class ClassicalInitialLayoutTests: XCTestCase {
    private func record(_ bundleID: String?, name: String, category: String? = nil,
                        directoryPath: String = "/Applications", isBeta: Bool? = nil,
                        isMissing: Bool? = nil, isStoreApp: Bool? = nil,
                        sourceDirectoryPath: String? = nil) throws -> AppRecord {
        let directory = URL(filePath: directoryPath, directoryHint: .isDirectory)
        let sourceDirectory = URL(filePath: sourceDirectoryPath ?? directoryPath, directoryHint: .isDirectory)
        return AppRecord(
            id: AppIdentity(),
            metadata: try AppMetadata(bundleIdentifier: bundleID,
                                      bundleURL: directory.appending(path: "\(name).app", directoryHint: .isDirectory),
                                      displayName: name, version: nil, buildVersion: nil,
                                      categoryIdentifier: category,
                                      contentModificationDate: nil, isBeta: isBeta, isStoreApp: isStoreApp),
            source: try AppSource(kind: .custom, directoryURL: sourceDirectory, isOnline: true),
            isMissing: isMissing
        )
    }

    func testMainPageTemplateOrderPrecedesDisplayNameOrder() throws {
        let settings = try record("com.apple.systempreferences", name: "A Settings")
        let notes = try record("com.apple.Notes", name: "B Notes")
        let safari = try record("com.apple.Safari", name: "Y Safari")
        let appStore = try record("com.apple.AppStore", name: "Z Store")

        let layout = ClassicalInitialLayout.make(records: [settings, notes, safari, appStore], capacity: 3)

        XCTAssertEqual(layout.pages.flatMap { $0.compactMap(\.app) },
                       [appStore.id, safari.id, notes.id, settings.id],
                       "The Dock template orders these apps independently of their localized display names")
        XCTAssertEqual(layout.pages.map(\.count), [3, 1])
    }

    func testUntemplatedSystemAppPrecedesAlphabeticallyEarlierUserApp() throws {
        let system = try record("com.example.system", name: "Z System",
                                directoryPath: "/System/Applications")
        let user = try record("com.example.user", name: "A User")

        let layout = ClassicalInitialLayout.make(records: [user, system], capacity: 2)

        XCTAssertEqual(layout.pages, [[.app(system.id), .app(user.id)]],
                       "Automatic root placement applies system priority before title order")
    }

    func testEveryCopyMatchingATemplateBundleIDStaysAtItsTemplatePosition() throws {
        let store = try record("com.apple.AppStore", name: "Store")
        let safariOne = try record("com.apple.Safari", name: "Safari Primary")
        let safariTwo = try record("com.apple.Safari", name: "Safari External",
                                   directoryPath: "/Volumes/External/Applications")
        let notes = try record("com.apple.Notes", name: "Notes")

        let layout = ClassicalInitialLayout.make(records: [notes, safariTwo, store, safariOne], capacity: 4)
        let root = layout.pages.flatMap { $0.compactMap(\.app) }

        XCTAssertEqual(root.count, 4)
        XCTAssertEqual(root.first, store.id)
        XCTAssertEqual(Set(root[1...2]), Set([safariOne.id, safariTwo.id]),
                       "Both Safari copies occupy adjacent slots at Safari's template position")
        XCTAssertEqual(root.last, notes.id)
    }

    func testUtilitiesMembersFormOneFolderInTemplateOrder() throws {
        let terminal = try record("com.apple.Terminal", name: "A Terminal")
        let diskUtility = try record("com.apple.DiskUtility", name: "B Disk Utility")
        let dictionary = try record("com.apple.Dictionary", name: "Y Dictionary")
        let shortcuts = try record("com.apple.shortcuts", name: "Z Shortcuts")
        let safari = try record("com.apple.Safari", name: "Safari")

        let layout = ClassicalInitialLayout.make(
            records: [terminal, diskUtility, dictionary, shortcuts, safari], capacity: 2)

        XCTAssertEqual(layout.pages.first?.first?.app, safari.id)
        let folder = try XCTUnwrap(layout.pages.first?.last?.folder)
        XCTAssertEqual(folder.id, .defaultOther)
        XCTAssertEqual(folder.title, "Other", "The saved title does not depend on the chosen app language")
        XCTAssertTrue(folder.usesDefaultTitle)
        XCTAssertEqual(folder.pages, [[shortcuts.id, dictionary.id], [diskUtility.id, terminal.id]],
                       "The folder's members retain the Dock template order across pages")
        XCTAssertEqual(layout.identities.count, 5)
    }

    /// The default Utilities folder keeps every application in catalog order when it needs a
    /// second page. A five-row, seven-column page holds 35 icons.
    func testInitialUtilitiesFolderPaginatesAtThirtyFiveItems() throws {
        let utilities = try (0..<36).map { index in
            try record("com.example.utility\(index)", name: String(format: "Utility %02d", index),
                       directoryPath: "/Applications/Utilities")
        }

        let full = ClassicalInitialLayout.make(records: Array(utilities.prefix(35).reversed()), capacity: 35)
        XCTAssertEqual(full.folders.first?.pages, [utilities.prefix(35).map(\.id)])

        let overflow = ClassicalInitialLayout.make(records: Array(utilities.reversed()), capacity: 35)
        let folder = try XCTUnwrap(overflow.folders.first)
        XCTAssertEqual(folder.pages.map(\.count), [35, 1])
        XCTAssertEqual(folder.identities, utilities.map(\.id), "Overflow keeps the folder's title order")
        XCTAssertEqual(folder.pages[1], [utilities[35].id], "Item 36 starts the next folder page")
    }

    func testUntemplatedUtilitiesAppsJoinOtherAfterItsTemplateMembers() throws {
        let terminal = try record("com.apple.Terminal", name: "Terminal")
        let systemUtility = try record("com.example.systemutility", name: "A System Utility",
                                       directoryPath: "/System/Applications/Utilities")
        let userUtility = try record("com.example.userutility", name: "Z User Utility",
                                     directoryPath: "/Applications/Utilities")
        let sameNameOutside = try record("com.example.outside", name: "A System Utility",
                                         directoryPath: "/Applications")

        let layout = ClassicalInitialLayout.make(
            records: [sameNameOutside, userUtility, terminal, systemUtility], capacity: 2)
        let folder = try XCTUnwrap(layout.folders.first)

        XCTAssertEqual(folder.id, .defaultOther)
        XCTAssertEqual(folder.pages, [[terminal.id, systemUtility.id], [userUtility.id]],
                       "Template members lead; remaining Utilities entries follow in title order")
        XCTAssertTrue(layout.pages.joined().contains(.app(sameNameOutside.id)))
        XCTAssertNotNil(layout.position(of: sameNameOutside.id))
    }

    func testUtilitiesPathPrefixAlsoIncludesSimilarlyNamedDirectory() throws {
        let utility = try record("com.example.utility", name: "Utility",
                                 directoryPath: "/Applications/Utilities")
        let sibling = try record("com.example.sibling", name: "Sibling",
                                 directoryPath: "/Applications/UtilitiesLike")

        let layout = ClassicalInitialLayout.make(records: [sibling, utility], capacity: 3)

        XCTAssertEqual(layout.folders.first?.id, .defaultOther)
        XCTAssertEqual(layout.folders.first?.pages, [[sibling.id, utility.id]],
                       "Dock checks the Utilities path as a string prefix, without a trailing separator")
    }

    func testNestedApplicationDirectoriesFormNamedAndOtherFolders() throws {
        let direct = try record("com.example.direct", name: "Direct", sourceDirectoryPath: "/Applications")
        let one = try record("com.example.one", name: "One", directoryPath: "/Applications/Foo",
                             sourceDirectoryPath: "/Applications")
        let two = try record("com.example.two", name: "Two", directoryPath: "/Applications/Foo",
                             sourceDirectoryPath: "/Applications")
        let deep = try record("com.example.deep", name: "Deep", directoryPath: "/Applications/Foo/Sub",
                              sourceDirectoryPath: "/Applications")

        let layout = ClassicalInitialLayout.make(records: [deep, two, direct, one], capacity: 5)
        let named = try XCTUnwrap(layout.folders.first { $0.title == "Foo" })
        let deeper = try XCTUnwrap(layout.folders.first { $0.title == "Foo (Other)" })

        XCTAssertEqual(named.pages, [[one.id, two.id]], "The immediate directory's apps sort by title")
        XCTAssertEqual(deeper.pages, [[deep.id]], "Deeper descendants remain distinct from direct children")
        XCTAssertTrue(deeper.usesDefaultTitle)
        XCTAssertEqual(deeper.directoryOtherBaseTitle, "Foo")
        XCTAssertTrue(layout.pages.joined().contains(.app(direct.id)))
        XCTAssertEqual(layout.folders.map(\.title), ["Foo", "Foo (Other)"],
                       "Directory folders follow Dock's string-key order")
    }

    func testShallowestObservedNestedTierRemainsRootWithoutDirectSourceApps() throws {
        let one = try record("com.example.one", name: "One", directoryPath: "/Applications/Foo",
                             sourceDirectoryPath: "/Applications")

        let layout = ClassicalInitialLayout.make(records: [one], capacity: 5)

        XCTAssertEqual(layout.pages, [[.app(one.id)]],
                       "The source's minimum observed app depth is the root tier for this first layout")
        XCTAssertTrue(layout.folders.isEmpty)
    }

    func testDeeperDirectoryUsesAncestorRelativeToObservedRootDepth() throws {
        let shallowest = try record("com.example.one", name: "One", directoryPath: "/Applications/Foo/Sub",
                                    sourceDirectoryPath: "/Applications")
        let deeper = try record("com.example.two", name: "Two", directoryPath: "/Applications/Foo/Sub/Deep",
                                sourceDirectoryPath: "/Applications")

        let layout = ClassicalInitialLayout.make(records: [deeper, shallowest], capacity: 5)

        XCTAssertTrue(layout.pages.joined().contains(.app(shallowest.id)))
        XCTAssertEqual(layout.folders.map(\.title), ["Deep"])
        XCTAssertEqual(layout.folders.first?.pages, [[deeper.id]],
                       "The grouping ancestor follows the source's shallowest observed app depth")
    }

    func testNestedUtilitiesAppJoinsBuiltInOtherFolder() throws {
        let utility = try record("com.example.tool", name: "Tool", directoryPath: "/Applications/Utilities/Sub",
                                 sourceDirectoryPath: "/Applications")

        let layout = ClassicalInitialLayout.make(records: [utility], capacity: 5)

        XCTAssertEqual(layout.folders.map(\.id), [.defaultOther])
        XCTAssertEqual(layout.folders.first?.pages, [[utility.id]])
    }

    @MainActor
    func testSavedNestedApplicationsKeepUserPlacement() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let one = try record("com.example.one", name: "One", directoryPath: "/Applications/Foo",
                             sourceDirectoryPath: "/Applications")
        let deep = try record("com.example.deep", name: "Deep", directoryPath: "/Applications/Foo/Sub",
                              sourceDirectoryPath: "/Applications")
        let saved = try ClassicalLayout(pages: [[.app(deep.id), .app(one.id)]])
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(saved)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        // The first presentation records where each held application is; the arrangement is unchanged.
        var expected = saved
        expected.rememberApplications([one, deep])

        _ = model.pages(for: [one, deep], capacity: 5)
        await model.flush()

        XCTAssertEqual(model.layout, expected)
        let persisted = try await store.load()
        XCTAssertEqual(persisted, expected)
    }

    @MainActor
    func testSavedRootPlacementOfAUtilitiesAppIsNotAutoGrouped() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let utility = try record("com.example.utility", name: "Utility",
                                 directoryPath: "/Applications/Utilities")
        let safari = try record("com.apple.Safari", name: "Safari")
        let saved = try ClassicalLayout(pages: [[utility.id, safari.id]])
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(saved)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        // The first presentation records where each held application is; the arrangement is unchanged.
        var expected = saved
        expected.rememberApplications([safari, utility])

        _ = model.pages(for: [safari, utility], capacity: 3)
        await model.flush()

        XCTAssertEqual(model.layout, expected)
        XCTAssertTrue(model.layout?.pages.joined().contains(.app(utility.id)) == true)
        let persisted = try await store.load()
        XCTAssertEqual(persisted, expected)
    }

    func testApplePathGroupsUseTheirSubtreesAndServerExcludesAppleBundleIDs() throws {
        let serverZulu = try record("com.example.zulu", name: "Zulu Server",
                                    directoryPath: "/Applications/Server", sourceDirectoryPath: "/Applications")
        let serverAlpha = try record(nil, name: "Alpha Server",
                                     directoryPath: "/Applications/Server/Tools", sourceDirectoryPath: "/Applications")
        let serverApple = try record("COM.APPLE.ServerTool", name: "Apple Server",
                                     directoryPath: "/Applications/Server", sourceDirectoryPath: "/Applications")
        let internalZulu = try record("com.example.internal", name: "Zulu Internal",
                                      directoryPath: "/AppleInternal", sourceDirectoryPath: "/")
        let internalAlpha = try record("com.apple.internalTool", name: "Alpha Internal",
                                       directoryPath: "/AppleInternal/Tools", sourceDirectoryPath: "/")
        let nearby = try record("com.example.nearby", name: "Nearby",
                                directoryPath: "/Applications/ServerLike", sourceDirectoryPath: "/Applications")

        let layout = ClassicalInitialLayout.make(records: [nearby, internalZulu, serverZulu,
                                                           serverApple, internalAlpha, serverAlpha], capacity: 6)
        XCTAssertEqual(layout.pages.flatMap { $0.compactMap(\.folder?.id) }.prefix(2),
                       [.defaultServer, .defaultAppleInternal])
        XCTAssertEqual(layout.folder(.defaultServer)?.pages, [[serverAlpha.id, serverZulu.id]])
        XCTAssertEqual(layout.folder(.defaultAppleInternal)?.pages, [[internalAlpha.id, internalZulu.id]])
        XCTAssertFalse(layout.folder(.defaultServer)?.identities.contains(serverApple.id) == true)
        XCTAssertFalse(layout.folder(.defaultServer)?.identities.contains(nearby.id) == true)
        XCTAssertEqual(Set(layout.identities), Set([serverZulu.id, serverAlpha.id, serverApple.id,
                                                    internalZulu.id, internalAlpha.id, nearby.id]))
    }

    func testLateOtherTemplateFolderStaysBeforeApplePathGroups() throws {
        let server = try record("com.example.server", name: "Server Tool",
                                directoryPath: "/Applications/Server", sourceDirectoryPath: "/Applications")
        let internalApp = try record("com.example.internal", name: "Internal Tool",
                                     directoryPath: "/AppleInternal", sourceDirectoryPath: "/")
        let textEdit = try record("com.apple.TextEdit", name: "TextEdit")
        let initial = ClassicalInitialLayout.make(records: [internalApp, server], capacity: 4)

        let refreshed = ClassicalInitialLayout.insertingLateTemplateApps(
            into: initial, records: [textEdit, internalApp, server], capacity: 4
        )

        XCTAssertEqual(refreshed.pages.flatMap { $0.compactMap(\.folder?.id) },
                       [.defaultOther, .defaultServer, .defaultAppleInternal])
        XCTAssertEqual(refreshed.folder(.defaultOther)?.pages, [[textEdit.id]])
        XCTAssertEqual(refreshed.folder(.defaultServer)?.pages, [[server.id]])
        XCTAssertEqual(refreshed.folder(.defaultAppleInternal)?.pages, [[internalApp.id]])
    }

    @MainActor
    func testApplePathObservationDoesNotRegroupSavedRootApp() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let server = try record("com.example.server", name: "Server Tool",
                                directoryPath: "/Applications/Server", sourceDirectoryPath: "/Applications")
        let ordinary = try record("com.example.ordinary", name: "Ordinary")
        let saved = try ClassicalLayout(pages: [[.app(server.id), .app(ordinary.id)]])
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(saved)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        // The first presentation records where each held application is; the arrangement is unchanged.
        var expected = saved
        expected.rememberApplications([ordinary, server])

        _ = model.pages(for: [ordinary, server], capacity: 4)
        await model.flush()

        XCTAssertEqual(model.layout, expected)
        let persisted = try await store.load()
        XCTAssertEqual(persisted, expected)
    }

    func testListOnlyGameCandidatesStayRootWhenEligibilityIsUnknown() throws {
        let appStore = try record("com.apple.AppStore", name: "Store")
        let shortcuts = try record("com.apple.shortcuts", name: "Shortcuts")
        let diablo = try record("com.blizzard.diablo3", name: "Z Diablo", isMissing: false)
        let epic = try record("com.epicgames.EpicGamesLauncher", name: "A Epic Games", isMissing: false)
        let office = try record("com.example.office", name: "B Office")

        let layout = ClassicalInitialLayout.make(records: [diablo, office, shortcuts, epic, appStore], capacity: 2)
        let slots = layout.pages.flatMap { $0 }

        XCTAssertEqual(slots.count, 5)
        XCTAssertEqual(slots[0].app, appStore.id)
        XCTAssertEqual(slots[1].folder?.id, .defaultOther)
        XCTAssertNil(layout.folder(.defaultGames))
        XCTAssertEqual(slots.dropFirst(2).compactMap(\.app), [epic.id, office.id, diablo.id])
    }

    func testListedGameRequiresObservedNonStoreStatusOnFreshLayout() throws {
        let included = try record("com.blizzard.diablo3", name: "Diablo", isMissing: false,
                                  isStoreApp: false)
        let storeCopy = try record("com.epicgames.EpicGamesLauncher", name: "Epic Store",
                                   isMissing: false, isStoreApp: true)
        let categoryGame = try record("com.example.board", name: "Board Game",
                                      category: "public.app-category.board-games", isMissing: false,
                                      isStoreApp: true)
        let unknown = try record("com.mojang.minecraftlauncher", name: "Minecraft",
                                  isMissing: false)
        let caseVariant = try record("COM.BLIZZARD.DIABLO3", name: "Diablo Copy",
                                     isMissing: false, isStoreApp: false)
        let unlisted = try record("com.example.office", name: "Office", isMissing: false,
                                  isStoreApp: false)

        let layout = ClassicalInitialLayout.make(records: [unknown, unlisted, storeCopy, included,
                                                           categoryGame, caseVariant], capacity: 6)

        XCTAssertEqual(layout.folder(.defaultGames)?.pages, [[categoryGame.id, included.id]])
        let rootApps = layout.pages.flatMap { $0 }.compactMap(\.app)
        XCTAssertEqual(Set(rootApps), Set([storeCopy.id, unknown.id, caseVariant.id, unlisted.id]))
    }

    func testObservedGameCategoryGroupsWithoutInferringListOnlyEligibility() throws {
        let minecraft = try record("com.mojang.minecraftlauncher", name: "Minecraft", isMissing: false)
        let unlisted = try record("com.example.newgame", name: "A New Game",
                                  category: "public.app-category.games", isMissing: false)

        let layout = ClassicalInitialLayout.make(records: [unlisted, minecraft], capacity: 3)

        XCTAssertEqual(layout.pages.first?.first?.folder?.id, .defaultGames)
        XCTAssertEqual(layout.pages.first?.first?.folder?.pages, [[unlisted.id]])
        XCTAssertTrue(layout.pages.joined().contains(.app(minecraft.id)))
    }

    func testBoardGameCategoryFormsAnInitialGamesFolder() throws {
        let boardGame = try record("com.example.boardgame", name: "Board Game",
                                   category: "public.app-category.board-games", isMissing: false)
        let office = try record("com.example.office", name: "Office",
                                category: "public.app-category.productivity")

        let layout = ClassicalInitialLayout.make(records: [office, boardGame], capacity: 3)

        XCTAssertEqual(layout.folders.first?.id, .defaultGames)
        XCTAssertEqual(layout.folders.first?.pages, [[boardGame.id]])
        XCTAssertTrue(layout.pages.joined().contains(.app(office.id)),
                      "An unrelated public app category remains on the root page")
    }

    func testBetaApplicationsEnterTestFlightBeforeGamesAndKeepTitleOrder() throws {
        let betaZulu = try record("com.example.betaZulu", name: "Zulu Beta", isBeta: true, isMissing: false)
        let betaAlpha = try record("com.example.betaAlpha", name: "Alpha Beta", isBeta: true, isMissing: false)
        let betaGame = try record("com.example.betaGame", name: "Beta Game",
                                  category: "public.app-category.games", isBeta: true, isMissing: false)
        let game = try record("com.example.game", name: "Game", category: "public.app-category.games",
                              isMissing: false)

        let layout = ClassicalInitialLayout.make(records: [game, betaZulu, betaGame, betaAlpha], capacity: 5)
        let root = try XCTUnwrap(layout.pages.first)
        let testFlight = try XCTUnwrap(root.first?.folder)
        let games = try XCTUnwrap(root.dropFirst().first?.folder)

        XCTAssertEqual(testFlight.id, .defaultTestFlight)
        XCTAssertEqual(testFlight.title, "TestFlight")
        XCTAssertEqual(testFlight.pages, [[betaAlpha.id, betaGame.id, betaZulu.id]],
                       "A Beta game belongs to TestFlight because that pass precedes Games")
        XCTAssertEqual(games.id, .defaultGames)
        XCTAssertEqual(games.pages, [[game.id]])
    }

    func testBetaFlagOnlyGroupsObservedAvailableAppsAfterFirstPageTemplate() throws {
        let safari = try record("com.apple.Safari", name: "Safari", isBeta: true, isMissing: false)
        let beta = try record("com.example.beta", name: "Beta", isBeta: true, isMissing: false)
        let missingBeta = try record("com.example.missing", name: "Missing Beta", isBeta: true,
                                     isMissing: true)
        let unknownAvailability = try record("com.example.unconfirmed", name: "Unconfirmed Beta", isBeta: true)
        let ordinary = try record("com.example.ordinary", name: "Ordinary", isBeta: false)
        let unknown = try record("com.example.unknown", name: "Unknown")

        let layout = ClassicalInitialLayout.make(records: [unknown, beta, ordinary, safari, missingBeta,
                                                          unknownAvailability], capacity: 7)
        let root = try XCTUnwrap(layout.pages.first)

        XCTAssertEqual(root.first?.app, safari.id, "The first-page template claims Safari before the Beta pass")
        XCTAssertEqual(root.dropFirst().first?.folder?.pages, [[beta.id]])
        XCTAssertTrue(root.contains(.app(missingBeta.id)), "Dock excludes not-found runnables from TestFlight")
        XCTAssertTrue(root.contains(.app(unknownAvailability.id)),
                      "Without an observed available state, a Beta flag alone cannot enter TestFlight")
        XCTAssertTrue(root.contains(.app(ordinary.id)))
        XCTAssertTrue(root.contains(.app(unknown.id)), "An unobserved Beta value is not treated as true")
    }

    func testBuiltInOtherTemplateClaimsAvailableBetaAppBeforeTestFlight() throws {
        let betaTerminal = try record("com.apple.Terminal", name: "Terminal", isBeta: true,
                                      isMissing: false)
        let textEdit = try record("com.apple.TextEdit", name: "TextEdit", isMissing: false)

        let layout = ClassicalInitialLayout.make(records: [textEdit, betaTerminal], capacity: 4)

        XCTAssertNil(layout.folder(.defaultTestFlight))
        XCTAssertEqual(layout.folder(.defaultOther)?.pages, [[textEdit.id, betaTerminal.id]])
    }

    @MainActor
    func testBetaObservationDoesNotRegroupSavedRootApp() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let beta = try record("com.example.beta", name: "Beta", isBeta: true)
        let ordinary = try record("com.example.ordinary", name: "Ordinary")
        let saved = try ClassicalLayout(pages: [[.app(beta.id), .app(ordinary.id)]])
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(saved)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        // The first presentation records where each held application is; the arrangement is unchanged.
        var expected = saved
        expected.rememberApplications([ordinary, beta])

        _ = model.pages(for: [ordinary, beta], capacity: 3)
        await model.flush()

        XCTAssertEqual(model.layout, expected, "A new Beta observation must preserve an existing arrangement")
        let persisted = try await store.load()
        XCTAssertEqual(persisted, expected)
    }

    @MainActor
    func testNewGameCategoryDoesNotRegroupASavedRootApp() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let game = try record("com.example.game", name: "Game", category: "public.app-category.games")
        let office = try record("com.example.office", name: "Office")
        let saved = try ClassicalLayout(pages: [[.app(game.id), .app(office.id)]])
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(saved)
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        // The first presentation records where each held application is; the arrangement is unchanged.
        var expected = saved
        expected.rememberApplications([office, game])

        _ = model.pages(for: [office, game], capacity: 3)
        await model.flush()

        XCTAssertEqual(model.layout, expected, "A category discovery must not rebuild an existing user arrangement")
        let persisted = try await store.load()
        XCTAssertEqual(persisted, expected)
    }

    func testListOnlyGameOverrideRemainsUnclaimedWithUnknownEligibility() throws {
        let listed = try record("com.blizzard.diablo3", name: "Listed Diablo", isMissing: false)
        let differentlyCased = try record("COM.BLIZZARD.DIABLO3", name: "Other Diablo", isMissing: false)

        let layout = ClassicalInitialLayout.make(records: [listed, differentlyCased], capacity: 3)

        XCTAssertTrue(layout.folders.isEmpty,
                      "The inclusion list requires store and user-added observations that this catalog does not have")
        XCTAssertEqual(layout.pages, [[.app(listed.id), .app(differentlyCased.id)]])
    }

    func testGamesRequireAnObservedAvailableApplication() throws {
        let available = try record("com.example.available", name: "Available Game",
                                   category: "public.app-category.games", isMissing: false)
        let missingListed = try record("com.blizzard.diablo3", name: "Missing Listed Game", isMissing: true)
        let unknownListed = try record("com.mojang.minecraftlauncher", name: "Unknown Listed Game")
        let unknownCategory = try record("com.example.unknown", name: "Unknown Category Game",
                                         category: "public.app-category.board-games")

        let layout = ClassicalInitialLayout.make(records: [unknownCategory, missingListed, available, unknownListed],
                                                 capacity: 5)

        XCTAssertEqual(layout.folder(.defaultGames)?.pages, [[available.id]])
        XCTAssertTrue(layout.pages.joined().contains(.app(missingListed.id)))
        XCTAssertTrue(layout.pages.joined().contains(.app(unknownListed.id)))
        XCTAssertTrue(layout.pages.joined().contains(.app(unknownCategory.id)))
    }

    @MainActor
    func testLaterListOnlyGameCandidateDoesNotRegroupAnEstablishedLayout() throws {
        let diablo = try record("com.blizzard.diablo3", name: "Diablo",
                                category: "public.app-category.games", isMissing: false)
        let epic = try record("com.epicgames.EpicGamesLauncher", name: "Epic Games",
                              isMissing: false, isStoreApp: false)
        let model = ClassicalLayoutModel(store: nil)

        _ = model.pages(for: [diablo], capacity: 3)
        let first = try XCTUnwrap(model.layout)
        let games = try XCTUnwrap(first.folders.first)
        XCTAssertEqual(games.pages, [[diablo.id]])

        _ = model.pages(for: [epic, diablo], capacity: 3)
        let refreshed = try XCTUnwrap(model.layout)
        XCTAssertEqual(refreshed.folders.first, games)
        XCTAssertEqual(refreshed.pages.first?.last?.app, epic.id,
                       "A new installation uses a free root slot without rebuilding the saved folder")
    }

    func testDefaultFolderDisplayTitleUsesTheSelectedLanguageUntilRenamed() {
        let id = ClassicalLayoutFolder.ID.defaultOther
        let english = ClassicalLayoutFolder.displayTitle(for: id, title: "Other", usesDefaultTitle: true,
                                                         locale: Locale(identifier: "en"))
        let french = ClassicalLayoutFolder.displayTitle(for: id, title: "Other", usesDefaultTitle: true,
                                                        locale: Locale(identifier: "fr"))
        let chinese = ClassicalLayoutFolder.displayTitle(for: id, title: "Other", usesDefaultTitle: true,
                                                         locale: Locale(identifier: "zh-Hans"))

        XCTAssertEqual(english, "Other")
        XCTAssertEqual(french, CatalogTestSupport.text("Other", locale: "fr"))
        XCTAssertEqual(chinese, CatalogTestSupport.text("Other", locale: "zh-Hans"))
        XCTAssertEqual(ClassicalLayoutFolder.displayTitle(for: id, title: "My Apps", usesDefaultTitle: false,
                                                         locale: Locale(identifier: "fr")),
                       "My Apps", "A user rename is kept in every language")
        XCTAssertEqual(ClassicalLayoutFolder.displayTitle(for: id, title: "Other", usesDefaultTitle: false,
                                                         locale: Locale(identifier: "fr")),
                       "Other", "An explicit rename to Other is not translated")
        XCTAssertEqual(ClassicalLayoutFolder.displayTitle(for: .init(), title: "Other", usesDefaultTitle: false,
                                                         locale: Locale(identifier: "fr")),
                       "Other", "An unrelated user folder named Other is not treated as the default folder")
    }

    func testGamesFolderDisplayTitleUsesTheSelectedLanguageUntilRenamed() {
        let id = ClassicalLayoutFolder.ID.defaultGames
        XCTAssertEqual(ClassicalLayoutFolder.displayTitle(for: id, title: "Games", usesDefaultTitle: true,
                                                         locale: Locale(identifier: "fr")), CatalogTestSupport.text("Games", locale: "fr"))
        XCTAssertEqual(ClassicalLayoutFolder.displayTitle(for: id, title: "Games", usesDefaultTitle: true,
                                                         locale: Locale(identifier: "zh-Hans")), CatalogTestSupport.text("Games", locale: "zh-Hans"))
        XCTAssertEqual(ClassicalLayoutFolder.displayTitle(for: id, title: "Games", usesDefaultTitle: false,
                                                         locale: Locale(identifier: "fr")), "Games",
                       "A user rename to the same text no longer follows the app language")
    }

    func testExplicitRenameToOtherStopsAutomaticTranslationAfterSave() throws {
        let terminal = try record("com.apple.Terminal", name: "Terminal")
        var layout = ClassicalInitialLayout.make(records: [terminal], capacity: 2)
        let original = try XCTUnwrap(layout.folders.first)
        XCTAssertTrue(original.usesDefaultTitle)

        XCTAssertTrue(layout.renameFolder(original.id, to: "Other"))
        let decoded = try JSONDecoder().decode(ClassicalLayout.self, from: JSONEncoder().encode(layout))
        let renamed = try XCTUnwrap(decoded.folders.first)
        XCTAssertEqual(renamed.id, original.id)
        XCTAssertEqual(renamed.title, "Other")
        XCTAssertFalse(renamed.usesDefaultTitle)
        XCTAssertEqual(ClassicalLayoutFolder.displayTitle(for: renamed.id, title: renamed.title,
                                                         usesDefaultTitle: renamed.usesDefaultTitle,
                                                         locale: Locale(identifier: "fr")), "Other")
    }

    @MainActor
    func testCatalogRefreshInsertsLateTemplateAppBeforeTheDefaultFolder() throws {
        let safari = try record("com.apple.Safari", name: "Z Safari")
        let appStore = try record("com.apple.AppStore", name: "Y Store")
        let terminal = try record("com.apple.Terminal", name: "A Terminal")
        let shortcuts = try record("com.apple.shortcuts", name: "B Shortcuts")
        let model = ClassicalLayoutModel(store: nil)

        _ = model.pages(for: [terminal, shortcuts, safari, appStore], capacity: 3)
        let original = try XCTUnwrap(model.layout)
        XCTAssertEqual(original.pages.first?.first?.app, appStore.id)
        XCTAssertEqual(original.pages.first?.dropFirst().first?.app, safari.id)
        XCTAssertEqual(original.pages.first?.last?.folder?.pages, [[shortcuts.id, terminal.id]])

        let notes = try record("com.apple.Notes", name: "A Notes")
        _ = model.pages(for: [notes, safari, terminal, appStore, shortcuts], capacity: 3)
        let refreshed = try XCTUnwrap(model.layout)
        XCTAssertEqual(refreshed.pages.first, [.app(appStore.id), .app(safari.id), .app(notes.id)],
                       "A later scan restores a template app to its original position")
        XCTAssertEqual(refreshed.pages.dropFirst().first?.first?.folder?.pages,
                       [[shortcuts.id, terminal.id]], "The default folder moves as one root item")
    }

    @MainActor
    func testLateSafariReturnsToSecondTemplateSlotAfterAutomaticLayoutReload() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let appStore = try record("com.apple.AppStore", name: "Store")
        let safari = try record("com.apple.Safari", name: "Safari")
        let mail = try record("com.apple.mail", name: "Mail")
        let initial = ClassicalLayoutModel(store: store)
        await initial.load()
        _ = initial.pages(for: [mail, appStore], capacity: 3)
        await initial.flush()

        let restored = ClassicalLayoutModel(store: store)
        await restored.load()
        _ = restored.pages(for: [mail, safari, appStore], capacity: 3)
        await restored.flush()

        XCTAssertEqual(restored.layout?.pages, [[.app(appStore.id), .app(safari.id), .app(mail.id)]])
        XCTAssertNotNil(restored.layout?.automaticTemplateBundleIDs)
        let persisted = try await store.load()
        XCTAssertEqual(persisted?.pages, restored.layout?.pages)
    }

    func testLateOtherMemberTakesItsTemplateSlotAndStartsAnotherFolderPage() throws {
        let shortcuts = try record("com.apple.shortcuts", name: "Shortcuts")
        let quickTime = try record("com.apple.QuickTimePlayerX", name: "QuickTime Player")
        let dictionary = try record("com.apple.Dictionary", name: "Dictionary")
        let original = ClassicalInitialLayout.make(records: [dictionary, shortcuts], capacity: 2)

        let updated = ClassicalInitialLayout.insertingLateTemplateApps(
            into: original, records: [dictionary, quickTime, shortcuts], capacity: 2)

        XCTAssertEqual(updated.folders.first?.pages, [[shortcuts.id, quickTime.id], [dictionary.id]])
        XCTAssertNotNil(updated.automaticTemplateBundleIDs)
    }

    @MainActor
    func testNoOpCommitKeepsAutomaticLayoutEligibleForLateSafari() throws {
        let appStore = try record("com.apple.AppStore", name: "Store")
        let safari = try record("com.apple.Safari", name: "Safari")
        let mail = try record("com.apple.mail", name: "Mail")
        let model = ClassicalLayoutModel(store: nil)
        _ = model.pages(for: [mail, appStore], capacity: 3)
        model.commit(try XCTUnwrap(model.layout))

        _ = model.pages(for: [mail, safari, appStore], capacity: 3)

        XCTAssertEqual(model.layout?.pages, [[.app(appStore.id), .app(safari.id), .app(mail.id)]])
    }

    @MainActor
    func testUserReorderPreventsLateTemplateAppFromMovingSavedSlots() throws {
        let appStore = try record("com.apple.AppStore", name: "Store")
        let safari = try record("com.apple.Safari", name: "Safari")
        let mail = try record("com.apple.mail", name: "Mail")
        let model = ClassicalLayoutModel(store: nil)
        _ = model.pages(for: [mail, appStore], capacity: 3)
        model.commit(try ClassicalLayout(pages: [[mail.id, appStore.id]]))
        XCTAssertNil(model.layout?.automaticTemplateBundleIDs)

        _ = model.pages(for: [mail, safari, appStore], capacity: 3)

        XCTAssertEqual(model.layout?.pages, [[.app(mail.id), .app(appStore.id), .app(safari.id)]])
    }

    @MainActor
    func testSavedUserArrangementIsNotReplacedByTheInitialTemplate() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let appStore = try record("com.apple.AppStore", name: "Store")
        let safari = try record("com.apple.Safari", name: "Safari")
        let terminal = try record("com.apple.Terminal", name: "Terminal")
        let saved = try ClassicalLayout(pages: [[safari.id, terminal.id, appStore.id]])
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(saved)

        let model = ClassicalLayoutModel(store: store)
        await model.load()
        // The first presentation records where each held application is; the arrangement is unchanged.
        var expected = saved
        expected.rememberApplications([appStore, terminal, safari])
        _ = model.pages(for: [appStore, terminal, safari], capacity: 3)
        await model.flush()

        XCTAssertEqual(model.layout, expected, "A saved user order takes precedence over the first-launch template")
        let persisted = try await store.load()
        XCTAssertEqual(persisted, expected)
    }

    @MainActor
    func testNewAppsUsePriorityWithoutMovingSavedUserSlots() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let user = try record("com.example.existing", name: "Z Existing")
        let safari = try record("com.apple.Safari", name: "A Safari")
        let newSystem = try record("com.example.newSystem", name: "Z New System",
                                   directoryPath: "/System/Applications")
        let newUser = try record("com.example.newUser", name: "A New User")
        let saved = try ClassicalLayout(pages: [[.app(user.id), .app(safari.id)]])
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(saved)
        let model = ClassicalLayoutModel(store: store)
        await model.load()

        _ = model.pages(for: [newUser, safari, newSystem, user], capacity: 4)
        await model.flush()

        let expected: [[ClassicalLayoutItem]] = [[.app(user.id), .app(safari.id), .app(newSystem.id), .app(newUser.id)]]
        XCTAssertEqual(model.layout?.pages, expected,
                       "New apps append in priority order while the user's saved positions stay intact")
        let persisted = try await store.load()
        XCTAssertEqual(persisted?.pages, expected)
    }

    @MainActor
    func testEmptyStartupCatalogDoesNotSaveBeforeTheFirstPopulatedScan() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let model = ClassicalLayoutModel(store: store)
        await model.load()

        XCTAssertTrue(model.pages(for: [], capacity: 3).isEmpty)
        await model.flush()
        XCTAssertNil(model.layout, "An empty startup snapshot must not establish a flat layout")
        let initiallySaved = try await store.load()
        XCTAssertNil(initiallySaved)

        let safari = try record("com.apple.Safari", name: "Z Safari")
        let shortcuts = try record("com.apple.shortcuts", name: "Y Shortcuts")
        let terminal = try record("com.apple.Terminal", name: "A Terminal")
        _ = model.pages(for: [terminal, shortcuts, safari], capacity: 3)
        await model.flush()

        let seeded = try XCTUnwrap(model.layout)
        XCTAssertEqual(seeded.pages.first?.first?.app, safari.id)
        let folder = try XCTUnwrap(seeded.pages.first?.last?.folder)
        XCTAssertEqual(folder.id, .defaultOther)
        XCTAssertEqual(folder.pages, [[shortcuts.id, terminal.id]])
        let persisted = try await store.load()
        XCTAssertEqual(persisted, seeded)
    }

    @MainActor
    func testTransientEmptyCatalogPreservesLoadedArrangementUntilAppsReturn() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let appStore = try record("com.apple.AppStore", name: "Store")
        let safari = try record("com.apple.Safari", name: "Safari")
        let terminal = try record("com.apple.Terminal", name: "Terminal")
        let saved = try ClassicalLayout(pages: [[safari.id, terminal.id, appStore.id]])
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        try await store.save(saved)
        let model = ClassicalLayoutModel(store: store)
        await model.load()

        XCTAssertTrue(model.pages(for: [], capacity: 3).isEmpty)
        await model.flush()
        XCTAssertEqual(model.layout, saved, "A transient empty catalog must not erase loaded user positions")
        let duringEmptyScan = try await store.load()
        XCTAssertEqual(duringEmptyScan, saved, "The empty snapshot must not overwrite the saved layout")

        let visible = model.pages(for: [appStore, safari, terminal], capacity: 3)
        XCTAssertEqual(visible.first?.compactMap(\.record?.id), [safari.id, terminal.id, appStore.id])
        var expected = saved
        expected.rememberApplications([appStore, safari, terminal])
        XCTAssertEqual(model.layout, expected, "Returning apps keep their loaded positions")
    }

    @MainActor
    func testFolderDragDoesNotPersistItsTranslatedDisplayTitle() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let safari = try record("com.apple.Safari", name: "Safari")
        let shortcuts = try record("com.apple.shortcuts", name: "Shortcuts")
        let terminal = try record("com.apple.Terminal", name: "Terminal")
        let store = ClassicalLayoutStore(directoryURL: fixture.root.appending(path: "Layout", directoryHint: .isDirectory))
        let model = ClassicalLayoutModel(store: store)
        await model.load()
        _ = model.pages(for: [terminal, safari, shortcuts], capacity: 3)
        let initialFolder = try XCTUnwrap(model.layout?.folders.first)
        XCTAssertEqual(initialFolder.id, .defaultOther)

        let shownFolder = ClassicalLayoutFolder(id: initialFolder.id, title: CatalogTestSupport.text("Other", locale: "fr"), pages: initialFolder.pages,
                                                usesDefaultTitle: true)
        let arranged = try ClassicalLayout(pages: [[.folder(shownFolder), .app(safari.id)]])
        model.commitFolderDrag(arranged)
        await model.flush()

        let saved = try await store.load()
        let persisted = try XCTUnwrap(saved?.folders.first)
        XCTAssertEqual(persisted.id, .defaultOther)
        XCTAssertEqual(persisted.title, "Other", "Moving the folder does not turn display translation into user data")
        XCTAssertTrue(persisted.usesDefaultTitle)
        XCTAssertEqual(model.layout?.pages.first?.first?.folder?.id, .defaultOther,
                       "The reordered folder keeps its identity")
    }
}
