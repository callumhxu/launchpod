import Foundation
import Testing
@testable import Launchpod

struct ApplicationScannerTests {
    @Test
    func defaultDirectoriesOmitMissingUserApplicationDirectory() {
        let directories = ApplicationScanner.defaultDirectories()
        let manager = FileManager()
        let system = manager.urls(for: .applicationDirectory, in: .systemDomainMask)
            + manager.urls(for: .applicationDirectory, in: .localDomainMask)
        let user = manager.urls(for: .applicationDirectory, in: .userDomainMask)
        let additional = ["/Users/Shared", "/System/Volumes/Preboot/Cryptexes/App/System/Applications"]
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardized }
        let existingUser = user.filter { url in
            var isDirectory: ObjCBool = false
            return manager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }

        #expect(Set(directories.map(\.source.directoryURL)).isSubset(of: Set(system + existingUser + additional)))
        #expect(directories.contains { $0.source.directoryURL == additional[0] })
        #expect(directories.contains { $0.source.directoryURL == additional[1] })
        #expect(Set(directories.map(\.id)).count == directories.count)
        for directory in directories {
            #expect(directory.source.kind == (user.contains(directory.source.directoryURL) ? .user : .system))
        }

        for missing in user where !existingUser.contains(missing) {
            #expect(!directories.contains { $0.source.directoryURL == missing })
        }
    }

    @Test
    func builtInCryptexAliasesKeepThePrebootSourceAndFindSafari() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let applications = try fixture.directory("Actual Applications")
        let safari = try fixture.application("Safari.app", in: applications,
                                             identifier: "com.apple.Safari")
        let systemAlias = try fixture.symbolicLink(to: applications, named: "System Cryptex Applications")
        let prebootAlias = try fixture.symbolicLink(to: applications, named: "Preboot Cryptex Applications")
        let other = try fixture.directory("Other Applications")

        let directories = ApplicationScanner.builtInDirectories(
            standard: [(url: systemAlias, kind: .system), (url: other, kind: .system)],
            additional: [(url: prebootAlias, kind: .system)]
        )

        #expect(directories.count == 2)
        #expect(directories.contains { $0.source.directoryURL.path == prebootAlias.path })
        #expect(!directories.contains { $0.source.directoryURL.path == systemAlias.path })
        #expect(directories.contains { $0.source.directoryURL == other.standardized })

        let preboot = try #require(directories.first { $0.source.directoryURL.path == prebootAlias.path })
        let scan = await ApplicationScanner().scan(preboot)
        #expect(scan.isComplete)
        #expect(scan.applications.map(\.metadata.bundleIdentifier) == ["com.apple.Safari"])
        #expect(scan.applications.map(\.metadata.bundleURL) == [safari.standardized])
    }

    @Test
    func readsActualBundleMetadataAndSourceObservations() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let url = try fixture.application("Editor.app", values: [
            "CFBundleDisplayName": "Actual Editor",
            "CFBundleShortVersionString": "2.4",
            "CFBundleVersion": "2407",
            "LSApplicationCategoryType": "public.app-category.developer-tools",
            "LSUIElement": false,
            "LSBackgroundOnly": false
        ])
        let scan = await ApplicationScanner().scan(try directory(fixture.root))
        let app = try #require(scan.applications.first)
        let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .isApplicationKey, .localizedNameKey])
        let sourceValues = try fixture.root.resourceValues(forKeys: [.volumeUUIDStringKey])

        #expect(scan.isComplete)
        #expect(scan.applications.count == 1)
        #expect(scan.source.kind == .custom)
        #expect(scan.source.isOnline == true)
        #expect(scan.source.volumeUUIDString == sourceValues.volumeUUIDString)
        #expect(app.metadata.bundleIdentifier == "com.example.DiscoveryFixture")
        #expect(app.metadata.bundleURL == url.standardized)
        let localizedName = try #require(resourceValues.localizedName)
        #expect(app.metadata.displayName == (localizedName.hasSuffix(".app") ? String(localizedName.dropLast(4)) : localizedName))
        #expect(app.metadata.version == "2.4")
        #expect(app.metadata.buildVersion == "2407")
        #expect(app.metadata.categoryIdentifier == "public.app-category.developer-tools")
        #expect(app.metadata.contentModificationDate == resourceValues.contentModificationDate)
        #expect(app.metadata.isApplication == resourceValues.isApplication)
        #expect(app.metadata.isUIElement == false)
        #expect(app.metadata.isBackgroundOnly == false)
    }

    @Test
    func unavailableOptionalMetadataRemainsUnknown() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        _ = try fixture.application("NoIdentifier.app", identifier: nil)

        let scan = await ApplicationScanner().scan(try directory(fixture.root))
        let app = try #require(scan.applications.first)

        #expect(app.metadata.bundleIdentifier == nil)
        #expect(app.metadata.version == nil)
        #expect(app.metadata.buildVersion == nil)
        #expect(app.metadata.categoryIdentifier == nil)
        #expect(app.metadata.isUIElement == nil)
        #expect(app.metadata.isBackgroundOnly == nil)
    }

    @Test
    func storeObservationUsesTheExactBundleReceiptPath() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let direct = try fixture.application("Direct.app", in: apps)
        let store = try fixture.application("Store.app", in: apps)
        let nearMiss = try fixture.application("NearMiss.app", in: apps)
        let receipt = store.appending(path: "Contents/_MASReceipt/receipt")
        try FileManager.default.createDirectory(at: receipt.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data([0x31]).write(to: receipt)
        let suffix = nearMiss.appending(path: "Contents/_MASReceipt/receipt.bak")
        try FileManager.default.createDirectory(at: suffix.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data([0x31]).write(to: suffix)

        let scan = await ApplicationScanner().scan(try directory(apps))
        let byURL = Dictionary(uniqueKeysWithValues: scan.applications.map { ($0.metadata.bundleURL, $0.metadata) })

        #expect(scan.isComplete)
        #expect(byURL[direct.standardized]?.isStoreApp == false)
        #expect(byURL[store.standardized]?.isStoreApp == true)
        #expect(byURL[nearMiss.standardized]?.isStoreApp == false)
    }

    @Test
    func ignoresInvalidBundlesAndDoesNotDiscoverNestedHelpers() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let valid = try fixture.application("Valid.app")
        _ = try fixture.application("Helper.app", in: valid.appendingPathComponent("Contents"))
        _ = try fixture.directory("Empty.app")
        let malformed = try fixture.directory("Malformed.app/Contents")
        try Data("not a property list".utf8).write(to: malformed.appendingPathComponent("Info.plist"))
        try Data("ordinary file".utf8).write(to: fixture.root.appendingPathComponent("File.app"))

        let scan = await ApplicationScanner().scan(try directory(fixture.root))

        #expect(scan.applications.map(\.metadata.bundleURL) == [valid.standardized])
    }

    @Test
    func ordinaryNestedDirectoriesAreScannedRecursively() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let nested = try fixture.directory("Utilities/Tools")
        let app = try fixture.application("Editor.app", in: nested)

        let scan = await ApplicationScanner().scan(try directory(fixture.root))

        #expect(scan.isComplete)
        #expect(scan.applications.map(\.metadata.bundleURL) == [app.standardized])
    }

    @Test(arguments: [false, true])
    func aPackageOrItsContentsCannotBeUsedToExposeNestedHelpers(contents: Bool) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let outer = try fixture.application("Outer.app")
        let inner = outer.appendingPathComponent("Contents", isDirectory: true)
        _ = try fixture.application("Helper.app", in: inner)

        let scan = await ApplicationScanner().scan(try directory(contents ? inner : outer))

        #expect(scan.applications.isEmpty)
    }

    @Test
    func aDirectoryInsideAHiddenAncestorDoesNotExposeApplications() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory(".Hidden/Apps")
        _ = try fixture.application("Editor.app", in: apps)

        let scan = await ApplicationScanner().scan(try directory(apps))

        #expect(scan.applications.isEmpty)
    }

    @Test
    func aCustomDirectoryNamedTrashIsNotTheSystemTrashDirectory() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory(".Trash")
        let app = try fixture.application("Editor.app", in: apps)
        var relationship = FileManager.URLRelationship.other
        try FileManager.default.getRelationship(&relationship, of: .trashDirectory, in: [], toItemAt: app)
        #expect(relationship == .other)

        let scan = await ApplicationScanner().scan(try directory(apps))

        #expect(scan.applications.map(\.metadata.bundleURL) == [app.standardized])
    }

    @Test
    func safariOnACryptexIsScannedWhenTrashRelationshipIsUnsupported() async throws {
        let cryptex = URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
                          isDirectory: true)
        let safari = cryptex.appendingPathComponent("Safari.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: safari.path) else { return }
        var relationship = FileManager.URLRelationship.other
        do {
            try FileManager.default.getRelationship(&relationship, of: .trashDirectory,
                                                    in: [], toItemAt: safari)
            return
        } catch let error as CocoaError where error.code == .featureUnsupported {
            let scan = await ApplicationScanner().scan(try directory(cryptex))
            #expect(scan.applications.contains { $0.metadata.bundleURL == safari.standardized })
        }
    }

    @Test(arguments: [false, true])
    func resolvesFinderAliasesAndSymbolicLinksToActualApplications(symbolic: Bool) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Actual")
        let links = try fixture.directory("Links")
        let original = try fixture.application("Editor.app", in: apps)
        let link = try symbolic
            ? fixture.symbolicLink(to: original, named: "Editor Link.app", in: links)
            : fixture.alias(to: original, named: "Editor Alias", in: links)

        let scan = await ApplicationScanner().scan(try directory(links))

        #expect(scan.isComplete)
        #expect(!scan.applications.isEmpty)
        #expect(scan.applications.allSatisfy { $0.metadata.bundleURL == original.standardized })
        #expect(scan.applications.contains { $0.discoveredURL.standardizedFileURL.path == link.standardizedFileURL.path })
        #expect(scan.applications.contains { symbolic ? $0.isSymbolicLink : $0.isAlias })
    }

    @Test(arguments: [false, true])
    func initiallyBrokenSymbolicLinksRetainTheirExternalTargetParents(missingParents: Bool) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        let external = try ApplicationDiscoveryTestDirectory()
        defer {
            fixture.remove()
            external.remove()
        }
        let parent = missingParents
            ? external.root.appendingPathComponent("Absent/Tools%2F\u{5de5}\u{5177}", isDirectory: true)
            : external.root
        let target = parent.appendingPathComponent("Editor.app", isDirectory: true)
        let link = try fixture.symbolicLink(to: target, named: "Editor Link.app")

        let scan = await ApplicationScanner().scan(try directory(fixture.root))

        #expect(scan.applications.isEmpty)
        #expect(!scan.isComplete)
        #expect(scan.issues.contains { $0.url == link })
        #expect(scan.monitoredURLs.contains { $0.path == parent.path })
    }

    @Test
    func brokenRelativeSymbolicLinkChainsRetainEveryKnownExternalParent() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        let external = try ApplicationDiscoveryTestDirectory()
        defer {
            fixture.remove()
            external.remove()
        }
        let intermediate = external.root.appendingPathComponent("Intermediate.app")
        let targetParent = external.root.appendingPathComponent("Absent/Tools%2F\u{5de5}\u{5177}", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: intermediate.path,
            withDestinationPath: "Absent/Tools%2F\u{5de5}\u{5177}/Editor.app")
        _ = try fixture.symbolicLink(to: intermediate, named: "Editor Link.app")

        let scan = await ApplicationScanner().scan(try directory(fixture.root))

        #expect(scan.applications.isEmpty)
        #expect(!scan.isComplete)
        #expect(scan.monitoredURLs.contains { $0.path == external.root.path })
        #expect(scan.monitoredURLs.contains { $0.path == targetParent.path })
    }

    @Test
    func anInitiallyBrokenSourceLinkRetainsItsExternalTargetParent() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        let external = try ApplicationDiscoveryTestDirectory()
        defer {
            fixture.remove()
            external.remove()
        }
        let target = external.root.appendingPathComponent("Absent/Applications", isDirectory: true)
        let link = try fixture.symbolicLink(to: target, named: "Linked Applications")

        let scan = await ApplicationScanner().scan(try directory(link))

        #expect(scan.applications.isEmpty)
        #expect(!scan.isComplete)
        #expect(scan.source.isOnline == false)
        #expect(scan.monitoredURLs.contains { $0.path == target.deletingLastPathComponent().path })
    }

    @Test
    func rereadsMetadataAfterAnInPlaceInfoPlistUpdate() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let url = try fixture.application("Editor.app", values: ["CFBundleShortVersionString": "1.0"])
        let source = try directory(fixture.root)
        let scanner = ApplicationScanner()
        let before = await scanner.scan(source)
        try fixture.writeInfo([
            "CFBundlePackageType": "APPL", "CFBundleExecutable": "Fixture",
            "CFBundleIdentifier": "com.example.DiscoveryFixture",
            "CFBundleDisplayName": "Updated Editor", "CFBundleShortVersionString": "2.0"
        ], at: url)

        let after = await scanner.scan(source)

        #expect(before.applications.first?.metadata.version == "1.0")
        #expect(after.applications.first?.metadata.version == "2.0")
    }

    @Test
    func missingSourceDoesNotReportACompleteEmptyDirectory() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let absent = fixture.root.appendingPathComponent("Unavailable", isDirectory: true)

        let scan = await ApplicationScanner().scan(try directory(absent))

        #expect(!scan.isComplete)
        #expect(scan.applications.isEmpty)
        #expect(!scan.issues.isEmpty)
        #expect(scan.source.isOnline != true)
    }

    @Test
    func permissionFailureLeavesAnIncompleteScan() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        let restricted = try fixture.directory("Restricted")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: restricted.path)
            fixture.remove()
        }
        _ = try fixture.application("Private.app", in: restricted)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: restricted.path)
        #expect(throws: (any Error).self) {
            try FileManager.default.contentsOfDirectory(at: restricted, includingPropertiesForKeys: nil)
        }

        let scan = await ApplicationScanner().scan(try directory(restricted))

        #expect(!scan.isComplete)
        #expect(scan.applications.isEmpty)
        #expect(!scan.issues.isEmpty)
    }

    @Test
    func aPreviouslyOnlineSourceIsRecheckedWhenItsRootDisappears() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let scanner = ApplicationScanner()
        let initialDirectory = try directory(apps)
        let before = await scanner.scan(initialDirectory)
        let knownOnline = ApplicationScan.Directory(id: initialDirectory.id, source: before.source)
        try FileManager.default.removeItem(at: apps)

        let after = await scanner.scan(knownOnline)

        #expect(before.source.isOnline == true)
        #expect(after.source.isOnline == false)
        #expect(!after.isComplete)
    }

    @Test
    func anApplicationMayOmitThePackageTypeKey() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let app = try fixture.application("Editor.app")
        try fixture.writeInfo([
            "CFBundleExecutable": "Fixture", "CFBundleIdentifier": "com.example.Editor"
        ], at: app)
        #expect(try app.resourceValues(forKeys: [.isApplicationKey]).isApplication == true)

        let scan = await ApplicationScanner().scan(try directory(fixture.root))

        #expect(scan.applications.count == 1)
        #expect(scan.applications.first?.metadata.bundleIdentifier == "com.example.Editor")
    }

    @Test
    func literalPercentSeparatorsAndUnicodeSurviveRealScanningAndLinkResolution() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps%2F\u{5de5}\u{5177}/%2E")
        let app = try fixture.application("Tools%2FEditor.app", in: apps)
        let links = try fixture.directory("Links%2E")
        _ = try fixture.alias(to: app, named: "\u{7f16}\u{8f91}\u{5668}%2F\u{522b}\u{540d}", in: links)
        _ = try fixture.symbolicLink(to: app, named: "\u{5de5}\u{5177}%2F\u{94fe}\u{63a5}.app", in: links)
        let encodedRoot = try #require(URL(string: apps.absoluteString.replacingOccurrences(of: "%252F", with: "%2F")))
        let source = try directory(encodedRoot)
        let scanner = ApplicationScanner()

        let scan = await scanner.scan(source)
        let linkScan = await scanner.scan(try directory(links))

        #expect(source.source.directoryURL == apps.standardized)
        #expect(scan.applications.map(\.metadata.bundleURL) == [app.standardized])
        #expect(!linkScan.applications.isEmpty)
        #expect(linkScan.applications.allSatisfy { $0.metadata.bundleURL == app.standardized })
        #expect(await scanner.isMissing(at: app) == false)
        try FileManager.default.removeItem(at: app)
        #expect(await scanner.isMissing(at: app) == true)
    }

    @Test
    func directoryAndSymbolicLinkCyclesDoNotPreventOtherApplicationsFromBeingScanned() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let app = try fixture.application("Editor.app")
        _ = try fixture.symbolicLink(to: fixture.root, named: "Back to Root")
        let selfLink = fixture.root.appendingPathComponent("Self")
        try FileManager.default.createSymbolicLink(at: selfLink, withDestinationURL: selfLink)
        let first = fixture.root.appendingPathComponent("Loop A")
        let second = fixture.root.appendingPathComponent("Loop B")
        try FileManager.default.createSymbolicLink(at: first, withDestinationURL: second)
        try FileManager.default.createSymbolicLink(at: second, withDestinationURL: first)
        let source = try directory(fixture.root)
        let task = Task { await ApplicationScanner().scan(source) }
        let timeout = Task {
            try await Task.sleep(for: .seconds(3))
            task.cancel()
        }
        defer { timeout.cancel() }

        let scan = await task.value

        #expect(!task.isCancelled)
        #expect(Set(scan.applications.map(\.metadata.bundleURL)) == [app.standardized])
        #expect(!scan.isComplete)
        #expect(!scan.issues.isEmpty)
    }

    @Test(arguments: [false, true])
    func linkedFoldersAreOnlyScannedWhenExplicitlyConfiguredAsSources(symbolic: Bool) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let source = try fixture.directory("Source")
        let tools = try fixture.directory("External Tools")
        let app = try fixture.application("Editor.app", in: tools)
        let linkedFolder = try symbolic
            ? fixture.symbolicLink(to: tools, named: "Tools Link", in: source)
            : fixture.alias(to: tools, named: "Tools Alias", in: source)
        let scanner = ApplicationScanner()

        let ordinary = await scanner.scan(try directory(source))
        let explicit = await scanner.scan(try directory(linkedFolder))

        #expect(ordinary.applications.isEmpty)
        #expect(Set(ordinary.monitoredURLs) == [try fixture.canonicalURL(source)])
        #expect(explicit.applications.map(\.metadata.bundleURL) == [app.standardized])
    }

    @Test(arguments: [false, true])
    func explicitLinkedSourceChecksTheRequestedParentBeforeResolvingItsTarget(symbolic: Bool) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let outer = try fixture.application("Outer.app")
        let contents = outer.appendingPathComponent("Contents", isDirectory: true)
        let helper = try fixture.application("Helper.app", in: contents)
        let links = try fixture.directory("Links")
        let source = try symbolic
            ? fixture.symbolicLink(to: contents, named: "Linked Contents", in: links)
            : fixture.alias(to: contents, named: "Aliased Contents", in: links)

        let scan = await ApplicationScanner().scan(try directory(source))

        #expect(scan.applications.map(\.metadata.bundleURL) == [helper.standardized])
    }

    @Test
    func cancellationIsNotACompleteEmptyScan() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        _ = try fixture.application("Editor.app")
        let source = try directory(fixture.root)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await ApplicationScanner().scan(source)
        }

        let scan = await task.value

        #expect(!scan.isComplete)
    }

    @Test
    func renamingAnAppInvalidatesTheCompletedNestedDirectorySnapshot() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let nested = try fixture.directory("Utilities")
        let app = try fixture.application("Editor.app", in: nested)
        let source = try directory(fixture.root)
        let scanner = ApplicationScanner()
        let before = await scanner.scan(source)
        try #require(before.isComplete)
        #expect(await scanner.isCurrent(before))

        let moved = nested.appendingPathComponent("Renamed.app", isDirectory: true)
        try FileManager.default.moveItem(at: app, to: moved)

        #expect(await !scanner.isCurrent(before), "A nested listing changed even though the root did not")
        let after = await scanner.scan(source)
        #expect(after.isComplete)
        #expect(await scanner.isCurrent(after))
        #expect(after.applications.map(\.metadata.bundleURL) == [moved.standardized])
        #expect(after.applications.first?.fileIdentity == before.applications.first?.fileIdentity)
    }

    @Test
    func anUnknownListingDateCannotConfirmThatACompletedSnapshotIsCurrent() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let scanner = ApplicationScanner()
        var snapshot = await scanner.scan(try directory(fixture.root))
        try #require(snapshot.isComplete)
        snapshot.listedDirectoryModificationDates.updateValue(nil, forKey: fixture.root)

        #expect(await !scanner.isCurrent(snapshot))
    }

    @Test
    func removingAListedDirectoryInvalidatesTheCompletedSnapshot() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let nested = try fixture.directory("Utilities")
        let scanner = ApplicationScanner()
        let snapshot = await scanner.scan(try directory(fixture.root))
        try #require(snapshot.isComplete)
        try FileManager.default.removeItem(at: nested)

        #expect(await !scanner.isCurrent(snapshot))
    }

    @Test
    func cancellingSnapshotValidationCannotConfirmAbsence() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let scanner = ApplicationScanner()
        let snapshot = await scanner.scan(try directory(fixture.root))
        try #require(snapshot.isComplete)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await scanner.isCurrent(snapshot)
        }

        #expect(await !task.value)
    }

    private func directory(_ url: URL) throws -> ApplicationScan.Directory {
        ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: url))
    }
}
