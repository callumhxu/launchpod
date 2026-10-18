import Foundation
import UniformTypeIdentifiers

/// Builds the first Classical arrangement from applications currently in the catalog.
nonisolated enum ClassicalInitialLayout {
    private struct DirectoryGroup {
        let title: String
        var direct: [AppIdentity] = []
        var deeper: [AppIdentity] = []
    }

    private static let mainPageBundleIDs = [
        "com.apple.Server.v3", "com.apple.AppStore", "com.apple.Safari", "com.apple.mail",
        "com.apple.AddressBook", "com.apple.iCal", "com.apple.reminders", "com.apple.Notes",
        "com.apple.FaceTime", "com.apple.MobileSMS", "com.apple.Maps", "com.apple.findmy",
        "com.apple.PhotoBooth", "com.apple.GenerativePlaygroundApp", "com.apple.Photos",
        "com.apple.Music", "com.apple.podcasts", "com.apple.TV", "com.apple.VoiceMemos",
        "com.apple.garageband10", "com.apple.iMovieApp", "com.apple.iWork.Keynote",
        "com.apple.iWork.Numbers", "com.apple.iWork.Pages", "com.apple.weather",
        "com.apple.news", "com.apple.stocks", "com.apple.iBooksX", "com.apple.clock",
        "com.apple.calculator", "com.apple.freeform", "com.apple.Home",
        "com.apple.siri.launcher", "com.apple.ScreenContinuity", "com.apple.Passwords",
        "com.apple.systempreferences"
    ]

    private static let otherFolderBundleIDs = [
        "com.apple.shortcuts", "com.apple.QuickTimePlayerX", "com.apple.Dictionary",
        "com.apple.TextEdit", "com.apple.FontBook", "com.apple.ScreenSharing",
        "com.apple.exposelauncher", "com.apple.backup.launcher", "com.apple.Preview",
        "com.apple.screenshot.launcher", "com.apple.Image_Capture",
        "com.apple.DigitalColorMeter", "com.apple.ColorSyncUtility", "com.apple.Stickies",
        "com.apple.grapher", "com.apple.VoiceOverUtility", "com.apple.printcenter",
        "com.apple.Automator", "com.apple.ScriptEditor2", "com.apple.audio.AudioMIDISetup",
        "com.apple.BluetoothFileExchange", "com.apple.DiskUtility",
        "com.apple.SystemProfiler", "com.apple.ActivityMonitor", "com.apple.Console",
        "com.apple.Terminal", "com.apple.airport.airportutility",
        "com.apple.MigrateAssistant", "com.apple.helpviewer"
    ]

    private static let includeAsGameBundleIDs: Set<String> = [
        "com.blizzard.diablo3", "com.epicgames.com.chairentertainment.Fortnite",
        "net.battle.app", "net.battle.bootstrapper", "com.roblox.RobloxPlayer",
        "com.epicgames.EpicGamesLauncher", "com.GearboxSoftware.Borderlands3",
        "com.square-enix.finalfantasyxiv", "com.mojang.minecraftlauncher"
    ]

    /// Bundle identifiers supplied by the built-in first-page and Other templates.
    static let templateBundleIDs = Set(mainPageBundleIDs + otherFolderBundleIDs)

    static func make(records: [AppRecord], capacity: Int) -> ClassicalLayout {
        let capacity = max(capacity, 1)
        let sorted = ClassicalLayoutTitleOrder.sorted(records)
        // Multiple installed copies share one template position; their order follows catalog titles.
        var byBundleID: [String: [AppIdentity]] = [:]
        for record in sorted {
            guard let bundleID = record.metadata.knownBundleIdentifier else { continue }
            byBundleID[bundleID, default: []].append(record.id)
        }

        var placed = Set<AppIdentity>()
        func take(_ bundleID: String) -> [AppIdentity] {
            let ids = byBundleID[bundleID]?.filter { !placed.contains($0) } ?? []
            placed.formUnion(ids)
            return ids
        }

        var items = mainPageBundleIDs.flatMap(take).map(ClassicalLayoutItem.app)
        var otherIDs = otherFolderBundleIDs.flatMap(take)
        let betaIDs = sorted.compactMap { record -> AppIdentity? in
            guard record.metadata.isBeta == true, record.isMissing == false,
                  !placed.contains(record.id) else { return nil }
            placed.insert(record.id)
            return record.id
        }
        let gameIDs = sorted.compactMap { record -> AppIdentity? in
            let listed = record.metadata.isStoreApp == false
                && record.metadata.knownBundleIdentifier.map(includeAsGameBundleIDs.contains) == true
            guard record.isMissing == false,
                  isGameCategory(record.metadata.categoryIdentifier) || listed,
                  !placed.contains(record.id) else {
                return nil
            }
            placed.insert(record.id)
            return record.id
        }
        for record in sorted where !placed.contains(record.id) && isUtilitiesApp(record.metadata.bundleURL) {
            otherIDs.append(record.id)
            placed.insert(record.id)
        }
        if !otherIDs.isEmpty {
            let pages = stride(from: 0, to: otherIDs.count, by: capacity).map {
                Array(otherIDs[$0..<min($0 + capacity, otherIDs.count)])
            }
            items.append(.folder(ClassicalLayoutFolder(id: .defaultOther, title: "Other", pages: pages,
                                                       usesDefaultTitle: true)))
        }
        if !betaIDs.isEmpty {
            let pages = stride(from: 0, to: betaIDs.count, by: capacity).map {
                Array(betaIDs[$0..<min($0 + capacity, betaIDs.count)])
            }
            items.append(.folder(ClassicalLayoutFolder(id: .defaultTestFlight, title: "TestFlight", pages: pages,
                                                       usesDefaultTitle: true)))
        }
        if !gameIDs.isEmpty {
            let pages = stride(from: 0, to: gameIDs.count, by: capacity).map {
                Array(gameIDs[$0..<min($0 + capacity, gameIDs.count)])
            }
            items.append(.folder(ClassicalLayoutFolder(id: .defaultGames, title: "Games", pages: pages,
                                                       usesDefaultTitle: true)))
        }
        let (appleItems, appleIDs) = applePathGroups(in: sorted, excluding: placed, capacity: capacity)
        items.append(contentsOf: appleItems)
        placed.formUnion(appleIDs)
        let (directoryItems, directoryIDs) = directoryGroups(in: sorted, excluding: placed,
                                                              capacity: capacity)
        items.append(contentsOf: directoryItems)
        placed.formUnion(directoryIDs)

        let pages = stride(from: 0, to: items.count, by: capacity).map {
            Array(items[$0..<min($0 + capacity, items.count)])
        }
        // A catalog may include third-party apps and more than one copy of a bundle. They follow
        // the known first-page entries and retain the catalog's title order.
        var layout: ClassicalLayout
        do {
            layout = try ClassicalLayout(pages: pages)
        } catch {
            assertionFailure("The fixed initial layout contains duplicate identities")
            layout = ClassicalLayout()
        }
        layout.addToNextAvailableSpace(sorted.map(\.id).filter { !placed.contains($0) }, capacity: capacity)
        layout.markAutomaticTemplate(records: records)
        return layout
    }

    /// Places template applications discovered after the first catalog at their built-in positions.
    /// Only layouts explicitly marked as automatic can be changed this way.
    static func insertingLateTemplateApps(into layout: ClassicalLayout,
                                          records: [AppRecord], capacity: Int) -> ClassicalLayout {
        guard let knownBundleIDs = layout.automaticTemplateBundleIDs else { return layout }
        let capacity = max(capacity, 1)
        let placed = Set(layout.identities)
        let late = ClassicalLayoutTitleOrder.sorted(records).compactMap { record -> (AppIdentity, String)? in
            guard !placed.contains(record.id), !layout.excludedIDs.contains(record.id),
                  let bundleID = record.metadata.knownBundleIdentifier,
                  templateBundleIDs.contains(bundleID) else { return nil }
            return (record.id, bundleID)
        }
        guard !late.isEmpty else { return layout }

        var bundleIDs = knownBundleIDs
        for (id, bundleID) in late { bundleIDs[id] = bundleID }
        var root = layout.pages.flatMap { $0 }
        for (id, bundleID) in late where mainPageBundleIDs.contains(bundleID) {
            let rank = mainPageBundleIDs.firstIndex(of: bundleID)!
            let slot = root.firstIndex { item in
                guard let existing = item.app else { return true }
                guard let existingBundleID = bundleIDs[existing],
                      let existingRank = mainPageBundleIDs.firstIndex(of: existingBundleID) else { return true }
                return existingRank > rank
            } ?? root.count
            root.insert(.app(id), at: slot)
        }

        let lateOther = late.filter { otherFolderBundleIDs.contains($0.1) }
        if !lateOther.isEmpty {
            let folderSlot = root.firstIndex { $0.folder?.id == .defaultOther }
            var folder = folderSlot.flatMap { root[$0].folder }
                ?? ClassicalLayoutFolder(id: .defaultOther, title: "Other", pages: [[]], usesDefaultTitle: true)
            var members = folder.pages.flatMap { $0 }
            for (id, bundleID) in lateOther {
                let rank = otherFolderBundleIDs.firstIndex(of: bundleID)!
                let slot = members.firstIndex { existing in
                    guard let existingBundleID = bundleIDs[existing],
                          let existingRank = otherFolderBundleIDs.firstIndex(of: existingBundleID) else { return true }
                    return existingRank > rank
                } ?? members.count
                members.insert(id, at: slot)
            }
            folder.pages = stride(from: 0, to: members.count, by: capacity).map {
                Array(members[$0..<min($0 + capacity, members.count)])
            }
            if let folderSlot {
                root[folderSlot] = .folder(folder)
            } else {
                let slot = root.firstIndex { item in
                    if item.folder?.id == .defaultTestFlight || item.folder?.id == .defaultGames
                        || item.folder?.id == .defaultServer || item.folder?.id == .defaultAppleInternal {
                        return true
                    }
                    guard let id = item.app, let bundleID = bundleIDs[id] else { return true }
                    return !mainPageBundleIDs.contains(bundleID)
                } ?? root.count
                root.insert(.folder(folder), at: slot)
            }
        }

        let pages = stride(from: 0, to: root.count, by: capacity).map {
            Array(root[$0..<min($0 + capacity, root.count)])
        }
        guard let arrangement = try? ClassicalLayout(pages: pages) else { return layout }
        var updated = layout
        updated.replacePages(from: arrangement)
        updated.rememberTemplate(records: records)
        return updated
    }

    private static func isUtilitiesApp(_ url: URL) -> Bool {
        let path = url.path
        return path.hasPrefix("/Applications/Utilities")
            || path.hasPrefix("/System/Applications/Utilities")
    }

    private static func applePathGroups(in records: [AppRecord], excluding placed: Set<AppIdentity>,
                                        capacity: Int) -> ([ClassicalLayoutItem], Set<AppIdentity>) {
        let paths: [(components: [String], id: ClassicalLayoutFolder.ID, title: String, excludesAppleID: Bool)] = [
            (["/", "Applications", "Server"], .defaultServer, "Server", true),
            (["/", "AppleInternal"], .defaultAppleInternal, "Apple Internal", false)
        ]
        var items: [ClassicalLayoutItem] = []
        var grouped = Set<AppIdentity>()
        for path in paths {
            let members = records.filter { record in
                guard !placed.contains(record.id), !grouped.contains(record.id),
                      record.metadata.bundleURL.standardizedFileURL.pathComponents.starts(with: path.components)
                else { return false }
                if path.excludesAppleID,
                   record.metadata.knownBundleIdentifier?.lowercased().hasPrefix("com.apple.") == true {
                    return false
                }
                return true
            }.map(\.id)
            guard !members.isEmpty else { continue }
            grouped.formUnion(members)
            let pages = stride(from: 0, to: members.count, by: capacity).map {
                Array(members[$0..<min($0 + capacity, members.count)])
            }
            items.append(.folder(ClassicalLayoutFolder(id: path.id, title: path.title,
                                                      pages: pages, usesDefaultTitle: true)))
        }
        return (items, grouped)
    }

    private static func directoryGroups(in records: [AppRecord], excluding placed: Set<AppIdentity>,
                                        capacity: Int) -> ([ClassicalLayoutItem], Set<AppIdentity>) {
        var minimumDepth: [String: Int] = [:]
        for record in records where !isUtilitiesApp(record.metadata.bundleURL) {
            let source = record.source.directoryURL.standardizedFileURL.pathComponents
            let app = record.metadata.bundleURL.standardizedFileURL.pathComponents
            guard app.count > source.count, app.starts(with: source) else { continue }
            let path = record.source.directoryURL.standardizedFileURL.path
            minimumDepth[path] = min(minimumDepth[path] ?? .max, app.count - 1)
        }

        var groups: [String: DirectoryGroup] = [:]
        var grouped = Set<AppIdentity>()
        for record in records where !placed.contains(record.id) {
            let source = record.source.directoryURL.standardizedFileURL.pathComponents
            let app = record.metadata.bundleURL.standardizedFileURL.pathComponents
            guard app.starts(with: source),
                  let baseline = minimumDepth[record.source.directoryURL.standardizedFileURL.path],
                  app.count - 1 > baseline else { continue }
            var directoryURL = record.metadata.bundleURL.deletingLastPathComponent()
            while directoryURL.pathComponents.count > baseline + 1 {
                directoryURL.deleteLastPathComponent()
            }
            let key = directoryURL.path
            if groups[key] == nil {
                groups[key] = DirectoryGroup(title: FileManager.default.displayName(atPath: key))
            }
            if app.count - 1 == baseline + 1 {
                groups[key]?.direct.append(record.id)
            } else {
                groups[key]?.deeper.append(record.id)
            }
            grouped.insert(record.id)
        }

        var items: [ClassicalLayoutItem] = []
        let ordered = groups.sorted { lhs, rhs in
            let result = (lhs.value.title as NSString).compare(rhs.value.title)
            return result == .orderedSame ? lhs.key < rhs.key : result == .orderedAscending
        }
        for (_, group) in ordered {
            for (title, ids, otherBase) in [(group.title, group.direct, nil),
                                            ("\(group.title) (Other)", group.deeper, group.title)]
                where !ids.isEmpty {
                let pages = stride(from: 0, to: ids.count, by: capacity).map {
                    Array(ids[$0..<min($0 + capacity, ids.count)])
                }
                items.append(.folder(ClassicalLayoutFolder(title: title, pages: pages,
                                                          usesDefaultTitle: otherBase != nil,
                                                          directoryOtherBaseTitle: otherBase)))
            }
        }
        return (items, grouped)
    }

    private static func isGameCategory(_ identifier: String?) -> Bool {
        guard let identifier, let category = UTType(identifier),
              let games = UTType("public.app-category.games"),
              let boardGames = UTType("public.app-category.board-games") else { return false }
        return category.conforms(to: games) || category.conforms(to: boardGames)
    }
}
