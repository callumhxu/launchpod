import Foundation
import Testing
@testable import Launchpod

@MainActor
struct AppServicesTests {
    @Test
    func restoresUserDataBeforeDiscoveryAndFlushesUpdatesWhenStopped() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        _ = try fixture.application("Editor.app", in: apps)
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let initial = await ApplicationCatalog(directories: [directory], scanner: ApplicationScanner()).refresh()
        let saved = try #require(initial.records.first)
        let customization = AppCustomization(appID: saved.id, isHidden: true, customName: "My Editor")
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        try await store.save(AppData(records: [saved], customizations: [customization]))
        var errors: [any Error] = []
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { errors.append($0) })
        try await services.start()
        try await services.start()
        #expect(services.data?.customizations == [customization])
        try await wait { services.availableRecords.map(\.id) == [saved.id] }
        _ = try fixture.application("Installed.app", in: apps, identifier: "com.example.Installed")
        try await wait { services.availableRecords.count == 2 }

        try await services.stop()
        #expect(!services.isRunning)
        #expect(services.availableRecords.isEmpty)
        let persisted = try #require(try await store.load())
        #expect(persisted.records.count == 2)
        #expect(persisted.records.contains { $0.id == saved.id })
        #expect(persisted.customizations == [customization])
        #expect(errors.isEmpty)
    }

    @Test
    func storeInstallationAfterFirstScanIsMarkedButExistingAndOrdinaryAppsAreNot() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let staging = try fixture.directory("Staging")
        let initialURL = try fixture.application("Initial.app", in: apps, identifier: "com.example.Initial")
        try addReceipt(to: initialURL)
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { Issue.record($0) })
        defer { Task { try? await services.stop() } }

        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 1 }
        #expect(services.availableRecords.first?.isRecentlyAdded == nil,
                "The first catalog observation does not represent a new installation.")

        let stagedURL = try fixture.application("Installed.app", in: staging,
                                                identifier: "com.example.Installed")
        try addReceipt(to: stagedURL)
        let installedURL = apps.appendingPathComponent("Installed.app", isDirectory: true)
        try FileManager.default.moveItem(at: stagedURL, to: installedURL)
        let ordinaryURL = try fixture.application("Ordinary.app", in: apps, identifier: "com.example.Ordinary")
        try await wait { services.availableRecords.count == 3 }
        let installed = try #require(services.availableRecords.first { $0.metadata.bundleURL == installedURL })
        let ordinary = try #require(services.availableRecords.first { $0.metadata.bundleURL == ordinaryURL })
        try await wait {
            services.availableRecords.first { $0.metadata.bundleURL == installedURL }?.isRecentlyAdded == true
        }
        #expect(services.availableRecords.first { $0.id == installed.id }?.isRecentlyAdded == true)
        #expect(ordinary.isRecentlyAdded == nil)
        #expect(services.availableRecords.first { $0.metadata.bundleURL == initialURL }?.isRecentlyAdded == nil,
                "An unrelated directory rescan must not mark the existing Store app.")

        try await services.stop()
        let persisted = try #require(try await store.load()?.records.first { $0.id == installed.id })
        #expect(persisted.isRecentlyAdded == true)
        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 3 }
        let rescanned = try #require(services.availableRecords.first { $0.id == installed.id })
        #expect(rescanned.isRecentlyAdded == true)

        try await services.stop()
    }

    @Test
    func storeVersionUpdateMarksAnEstablishedAppWithoutChangingItsIdentity() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let appURL = try fixture.application("Editor.app", in: apps, identifier: "com.example.Editor",
                                             values: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"])
        try addReceipt(to: appURL)
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { Issue.record($0) })
        defer { Task { try? await services.stop() } }

        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 1 }
        let original = try #require(services.availableRecords.first)
        #expect(original.isRecentlyAdded == nil)

        try fixture.writeInfo([
            "CFBundlePackageType": "APPL", "CFBundleExecutable": "Fixture",
            "CFBundleIdentifier": "com.example.Editor", "CFBundleName": "Fixture Name",
            "CFBundleDisplayName": "Fixture Display Name",
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "2"
        ], at: appURL)
        try await wait {
            services.availableRecords.first?.metadata.buildVersion == "2"
                && services.availableRecords.first?.isRecentlyAdded == true
        }
        #expect(services.availableRecords.first?.id == original.id)

        services.markOpened(original.id)
        try await wait { services.availableRecords.first?.isRecentlyAdded == false }
        try fixture.writeInfo([
            "CFBundlePackageType": "APPL", "CFBundleExecutable": "Fixture",
            "CFBundleIdentifier": "com.example.Editor", "CFBundleName": "Fixture Name",
            "CFBundleDisplayName": "Fixture Display Name",
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "3"
        ], at: appURL)
        try await wait {
            services.availableRecords.first?.metadata.buildVersion == "3"
                && services.availableRecords.first?.isRecentlyAdded == true
        }
        try await services.stop()
        #expect(try await store.load()?.records.first?.isRecentlyAdded == true)
    }

    @Test
    func storeInstallationWhileStoppedIsMarkedFromSavedDirectoryBaseline() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let existingURL = try fixture.application("Existing.app", in: apps,
                                                   identifier: "com.example.Existing")
        try addReceipt(to: existingURL)
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { Issue.record($0) })
        defer { Task { try? await services.stop() } }

        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 1 }
        #expect(services.availableRecords.first?.isRecentlyAdded == nil)
        try await services.stop()

        let installedURL = try fixture.application("Installed.app", in: apps,
                                                    identifier: "com.example.Installed")
        try addReceipt(to: installedURL)
        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 2 }
        #expect(services.availableRecords.first { $0.metadata.bundleURL == installedURL }?.isRecentlyAdded == true)
        #expect(services.availableRecords.first { $0.metadata.bundleURL == existingURL }?.isRecentlyAdded == nil)
        try await services.stop()
        #expect(try await store.load()?.records.first {
            $0.metadata.bundleURL == installedURL
        }?.isRecentlyAdded == true)
    }

    @Test
    func unknownStoreOriginInSavedRecordDoesNotBecomeANewInstallation() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let appURL = try fixture.application("Existing.app", in: apps,
                                             identifier: "com.example.Existing")
        try addReceipt(to: appURL)
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let scanned = await ApplicationCatalog(directories: [directory], scanner: ApplicationScanner()).refresh()
        let observed = try #require(scanned.records.first)
        let metadata = observed.metadata
        let unknownOrigin = try AppMetadata(
            bundleIdentifier: metadata.bundleIdentifier, bundleURL: metadata.bundleURL,
            displayName: metadata.displayName, version: metadata.version,
            buildVersion: metadata.buildVersion, categoryIdentifier: metadata.categoryIdentifier,
            contentModificationDate: metadata.contentModificationDate, isApplication: metadata.isApplication,
            isUIElement: metadata.isUIElement, isBackgroundOnly: metadata.isBackgroundOnly,
            isBeta: metadata.isBeta, isStoreApp: nil
        )
        let saved = AppRecord(id: observed.id, metadata: unknownOrigin, source: observed.source)
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        try await store.save(AppData(records: [saved]))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { Issue.record($0) })
        defer { Task { try? await services.stop() } }

        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 1 }
        #expect(services.availableRecords.first?.id == saved.id)
        #expect(services.availableRecords.first?.metadata.isStoreApp == true)
        #expect(services.availableRecords.first?.isRecentlyAdded == nil)
        try await services.stop()
    }

    @Test
    func knownAppGainingStoreReceiptIsMarkedAfterBaseline() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let appURL = try fixture.application("Installed.app", in: apps,
                                             identifier: "com.example.Installed")
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { Issue.record($0) })
        defer { Task { try? await services.stop() } }

        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 1 }
        let original = try #require(services.availableRecords.first)
        #expect(original.metadata.isStoreApp == false)
        #expect(original.isRecentlyAdded == nil)
        try await services.stop()

        try addReceipt(to: appURL)
        try await services.start()
        try await wait {
            services.hasCurrentScan && services.availableRecords.first?.metadata.isStoreApp == true
        }
        #expect(services.availableRecords.first?.id == original.id)
        #expect(services.availableRecords.first?.isRecentlyAdded == true)
        try await services.stop()
        #expect(try await store.load()?.records.first?.isRecentlyAdded == true)
    }

    @Test
    func emptyScannedDirectoryRemainsABaselineAfterRestart() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { Issue.record($0) })
        defer { Task { try? await services.stop() } }

        try await services.start()
        try await wait { services.hasCurrentScan }
        #expect(services.availableRecords.isEmpty)
        try await services.stop()

        let installedURL = try fixture.application("Installed.app", in: apps,
                                                    identifier: "com.example.Installed")
        try addReceipt(to: installedURL)
        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 1 }
        #expect(services.availableRecords.first?.isRecentlyAdded == true)
        try await services.stop()
        #expect(try await store.load()?.records.first?.isRecentlyAdded == true)
    }

    @Test
    func addingAnAlreadyPopulatedDirectoryDoesNotMarkItsStoreApps() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let originalFolder = try fixture.directory("Original")
        let addedFolder = try fixture.directory("Added")
        _ = try fixture.application("Original.app", in: originalFolder, identifier: "com.example.Original")
        let addedURL = try fixture.application("Existing.app", in: addedFolder,
                                               identifier: "com.example.Existing")
        try addReceipt(to: addedURL)
        let originalDirectory = ApplicationScan.Directory(
            source: try AppSource(kind: .custom, directoryURL: originalFolder)
        )
        let addedDirectory = ApplicationScan.Directory(
            source: try AppSource(kind: .custom, directoryURL: addedFolder)
        )
        let services = AppServices(
            store: try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage")),
            icons: AppIconRepository(cacheCostLimit: 0), directories: [originalDirectory],
            onError: { Issue.record($0) }
        )
        defer { Task { try? await services.stop() } }

        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 1 }
        try await services.updateDirectories([originalDirectory, addedDirectory])
        try await wait { services.hasCurrentScan && services.availableRecords.count == 2 }
        #expect(services.availableRecords.first { $0.metadata.bundleURL == addedURL }?.isRecentlyAdded == nil)
        try await services.stop()
    }

    @Test
    func copyingAnAlreadyKnownStoreAppDoesNotMarkTheCopyAsNewInstallation() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let originalURL = try fixture.application("Original.app", in: apps, identifier: "com.example.Shared")
        try addReceipt(to: originalURL)
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let services = AppServices(
            store: try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage")),
            icons: AppIconRepository(cacheCostLimit: 0), directories: [directory],
            onError: { Issue.record($0) }
        )
        defer { Task { try? await services.stop() } }

        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 1 }
        let copyURL = apps.appendingPathComponent("Copy.app", isDirectory: true)
        try FileManager.default.copyItem(at: originalURL, to: copyURL)
        try await wait { services.availableRecords.count == 2 }
        #expect(services.availableRecords.first { $0.metadata.bundleURL == copyURL }?.isRecentlyAdded == nil)
        try await services.stop()
    }

    @Test
    func persistedRecentlyAddedFlagSurvivesDiscoveryAndClearsAfterAcceptedOpen() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let appURL = try fixture.application("Installed.app", in: apps, identifier: "com.example.Installed")
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let initial = await ApplicationCatalog(directories: [directory], scanner: ApplicationScanner()).refresh()
        var saved = try #require(initial.records.first)
        saved.isRecentlyAdded = true
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        try await store.save(AppData(records: [saved]))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { Issue.record($0) })
        defer { Task { try? await services.stop() } }

        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 1 }
        #expect(services.availableRecords.first?.metadata.bundleURL == appURL)
        #expect(services.availableRecords.first?.id == saved.id)
        #expect(services.availableRecords.first?.isRecentlyAdded == true)

        try await services.stop()
        #expect(try await store.load()?.records.first?.isRecentlyAdded == true)
        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 1 }
        #expect(services.availableRecords.first?.isRecentlyAdded == true)

        services.markOpened(saved.id)
        try await wait { services.availableRecords.first { $0.id == saved.id }?.isRecentlyAdded == false }
        try await services.stop()
        #expect(try await store.load()?.records.first { $0.id == saved.id }?.isRecentlyAdded == false)
    }

    @Test
    func acceptedOpenClearsAllCopiesWithMatchingBundleIdentifier() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let firstURL = try fixture.application("First.app", in: apps, identifier: "com.example.Shared")
        let secondURL = try fixture.application("Second.app", in: apps, identifier: "com.example.Shared")
        let unrelatedURL = try fixture.application("Other.app", in: apps, identifier: "com.example.Other")
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let initial = await ApplicationCatalog(directories: [directory], scanner: ApplicationScanner()).refresh()
        #expect(initial.records.count == 3)
        let savedRecords = initial.records.map { record -> AppRecord in
            var record = record
            record.isRecentlyAdded = true
            return record
        }
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        try await store.save(AppData(records: savedRecords))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { Issue.record($0) })
        defer { Task { try? await services.stop() } }

        try await services.start()
        try await wait { services.hasCurrentScan && services.availableRecords.count == 3 }
        let first = try #require(services.availableRecords.first { $0.metadata.bundleURL == firstURL })
        let second = try #require(services.availableRecords.first { $0.metadata.bundleURL == secondURL })
        let unrelated = try #require(services.availableRecords.first { $0.metadata.bundleURL == unrelatedURL })
        #expect(first.id != second.id)
        #expect(services.availableRecords.allSatisfy { $0.isRecentlyAdded == true })

        services.markOpened(first.id)
        try await wait {
            services.availableRecords.first { $0.id == first.id }?.isRecentlyAdded == false &&
            services.availableRecords.first { $0.id == second.id }?.isRecentlyAdded == false
        }
        #expect(services.availableRecords.first { $0.id == unrelated.id }?.isRecentlyAdded == true)
        try await services.stop()
        let persisted = try #require(try await store.load())
        #expect(persisted.records.first { $0.id == first.id }?.isRecentlyAdded == false)
        #expect(persisted.records.first { $0.id == second.id }?.isRecentlyAdded == false)
        #expect(persisted.records.first { $0.id == unrelated.id }?.isRecentlyAdded == true)
    }

    private func addReceipt(to application: URL) throws {
        let receipt = try #require(Bundle(url: application)?.appStoreReceiptURL)
        try FileManager.default.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x31]).write(to: receipt)
    }

    @Test
    func directoryUpdatePreservesOtherAppsCachedIconsAndPendingLoads() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let affectedDirectory = try fixture.directory("Affected")
        let otherDirectory = try fixture.directory("Other")
        let affectedURL = try fixture.application("Editor.app", in: affectedDirectory)
        let otherURL = try fixture.application("Reader.app", in: otherDirectory)
        let directories = try [affectedDirectory, otherDirectory].map {
            ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: $0))
        }
        let loader = ControlledAppIconLoader()
        defer { Task { await loader.finish() } }
        let icons = AppIconRepository(loader: loader, cacheCostLimit: 1024 * 1024)
        let services = AppServices(
            store: try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage")),
            icons: icons, directories: directories, onError: { Issue.record($0) }
        )
        defer { Task { try? await services.stop() } }
        var startupUpdates = 0
        services.onApplicationsChanged = { _ in startupUpdates += 1 }
        try await services.start()
        try await wait { services.availableRecords.count == 2 }
        // The file monitor may still rescan a directory for events from creating the fixture, or after
        // replacing its stream once the first scan reports bundle paths. Such a rescan rightly cancels
        // that directory's pending icon loads, so the loads below start only once discovery is quiet.
        try await waitForQuiet { startupUpdates }
        let affected = try #require(services.availableRecords.first { $0.metadata.bundleURL == affectedURL })
        let other = try #require(services.availableRecords.first { $0.metadata.bundleURL == otherURL })
        let size = try AppIconSize(pointSize: CGSize(width: 32, height: 32), backingScale: 1)
        let original = try AppIconTestSupport.icon(size: size)
        for (index, record) in [affected, other].enumerated() {
            let load = Task { try await icons.icon(for: record, size: size) }
            defer { load.cancel() }
            try await AppIconTestSupport.wait { await loader.requests.count == index + 1 }
            await loader.succeed(index, with: original)
            _ = try await load.value
        }
        let largerSize = try AppIconSize(pointSize: CGSize(width: 64, height: 64), backingScale: 1)
        let largerIcon = try AppIconTestSupport.icon(size: largerSize)
        let pending = Task { try await icons.icon(for: other, size: largerSize) }
        defer { pending.cancel() }
        try await AppIconTestSupport.wait { await loader.requests.count == 3 }
        var published: [(records: [AppRecord], affected: Set<AppIdentity>)] = []
        services.onApplicationsChanged = { [weak services] ids in
            MainActor.preconditionIsolated()
            published.append((services?.availableRecords ?? [], ids))
        }

        _ = try fixture.application("Installed.app", in: affectedDirectory, identifier: "com.example.Installed")
        try await wait { published.contains { $0.records.count == 3 } }
        let notification = try #require(published.first { $0.records.count == 3 })
        #expect(notification.records == services.availableRecords)
        #expect(notification.affected.contains(affected.id), "Unchanged metadata still requires an icon refresh.")
        #expect(!notification.affected.contains(other.id))
        #expect(services.availableRecords.first { $0.id == affected.id } == affected)
        await loader.succeed(2, with: largerIcon)
        #expect(try await pending.value.cgImage === largerIcon.cgImage)
        await loader.allowCompletedRenditionReloads()
        #expect(try await icons.icon(for: other, size: size).cgImage === original.cgImage)
        #expect(await loader.requests.dropFirst(3).allSatisfy {
            $0.metadata == other.metadata && $0.size == size
        })

        await loader.requireExplicitCompletions()
        let reloadIndex = await loader.requests.count
        let reload = Task { try await icons.icon(for: affected, size: size) }
        defer { reload.cancel() }
        try await AppIconTestSupport.wait { await loader.requests.count == reloadIndex + 1 }
        #expect(await loader.requests[reloadIndex].metadata == affected.metadata)
        #expect(await loader.requests[reloadIndex].size == size)
        let replacement = try AppIconTestSupport.icon(size: size, red: 0)
        await loader.succeed(reloadIndex, with: replacement)
        #expect(try await reload.value.cgImage === replacement.cgImage)
        try await services.stop()
    }

    @Test(arguments: [false, true])
    func delayedInitialScanPublishesInstalledRecordsUnlessServicesStopped(stopBeforeScanCompletes: Bool) async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let appURL = try fixture.application("Editor.app", in: apps)
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let scanner = PausingFirstScanScanner()
        defer { Task { await scanner.resume() } }
        let services = AppServices(
            store: try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage")),
            icons: AppIconRepository(cacheCostLimit: 0), directories: [directory], scanner: scanner,
            onError: { Issue.record($0) }
        )
        defer { Task { try? await services.stop() } }
        var published: [[AppRecord]] = []
        services.onApplicationsChanged = { [weak services] ids in
            MainActor.preconditionIsolated()
            let records = services?.availableRecords ?? []
            #expect(Set(records.map(\.id)).isSubset(of: ids))
            #expect(services?.data?.records == records)
            published.append(records)
        }

        try await services.start()
        try await AppIconTestSupport.wait { await scanner.isPaused }
        #expect(services.isRunning)
        #expect(services.availableRecords.isEmpty)
        #expect(!services.hasCurrentScan)
        #expect(published.isEmpty)
        if stopBeforeScanCompletes {
            try await services.stop()
            #expect(!services.hasCurrentScan)
        }
        await scanner.resume()
        try await AppIconTestSupport.wait { await scanner.didReturn }

        if stopBeforeScanCompletes {
            for _ in 0..<10 { await Task.yield() }
            #expect(published.isEmpty)
            #expect(services.availableRecords.isEmpty)
        } else {
            try await wait { !published.isEmpty }
            #expect(services.hasCurrentScan)
            #expect(published.last?.map(\.metadata.bundleURL) == [appURL])
            let publicationCount = published.count
            try await services.stop()
            #expect(!services.hasCurrentScan)
            #expect(published.count == publicationCount, "Stopping is not a new catalog observation.")
        }
    }

    @Test
    func repeatedStartStopCyclesDiscoverNewFilesWithoutLosingExistingIdentities() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { Issue.record($0) })
        var priorIDs = Set<AppIdentity>()

        for index in 0..<3 {
            _ = try fixture.application("Editor\(index).app", in: apps,
                                        identifier: "com.example.Editor\(index)")
            try await services.start()
            try await services.start()
            #expect(services.isRunning)
            try await wait { services.availableRecords.count == index + 1 }
            let currentIDs = Set(services.availableRecords.map(\.id))
            #expect(priorIDs.isSubset(of: currentIDs))
            priorIDs = currentIDs

            try await services.stop()
            try await services.stop()
            #expect(!services.isRunning)
            #expect(services.availableRecords.isEmpty)
            #expect(Set(try await store.load()?.records.map(\.id) ?? []) == priorIDs)
        }
    }

    @Test
    func updatingToAnAddedDirectoryDiscoversItsAppsAndPreservesTheExistingCatalog() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let originalFolder = try fixture.directory("Original")
        let addedFolder = try fixture.directory("Added")
        let originalApp = try fixture.application("Original.app", in: originalFolder,
                                                  identifier: "com.example.Original")
        let addedApp = try fixture.application("Added.app", in: addedFolder,
                                               identifier: "com.example.Added")
        let originalDirectory = ApplicationScan.Directory(
            source: try AppSource(kind: .custom, directoryURL: originalFolder)
        )
        let addedDirectory = ApplicationScan.Directory(
            source: try AppSource(kind: .custom, directoryURL: addedFolder)
        )
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [originalDirectory], onError: { Issue.record($0) })
        defer { Task { try? await services.stop() } }

        try await services.start()
        try await wait { services.availableRecords.map(\.metadata.bundleURL) == [originalApp] }
        let originalIdentity = try #require(services.availableRecords.first?.id)

        try await services.updateDirectories([originalDirectory, addedDirectory])
        try await wait { Set(services.availableRecords.map(\.metadata.bundleURL)) == [originalApp, addedApp] }
        #expect(services.isRunning)
        #expect(services.availableRecords.first { $0.metadata.bundleURL == originalApp }?.id == originalIdentity)
        #expect(services.availableRecords.contains { $0.metadata.bundleURL == addedApp })
        try await services.stop()
        #expect(Set(try await store.load()?.records.map(\.metadata.bundleURL) ?? []) == [originalApp, addedApp])
    }

    @Test
    func unreadableStoredDataBlocksDiscoveryAndPreservesTheFile() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let store = try AppDataStore(directoryURL: fixture.root)
        let invalid = Data("not a valid app data document".utf8)
        try invalid.write(to: store.fileURL, options: .atomic)
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [], onError: { Issue.record($0) })

        do {
            try await services.start()
            Issue.record("Invalid persisted data must prevent startup.")
        } catch {}
        #expect(!services.isRunning)
        #expect(services.data == nil)
        #expect(services.availableRecords.isEmpty)
        try await services.stop()
        #expect(try Data(contentsOf: store.fileURL) == invalid)
    }

    /// Returns once `count` has stayed unchanged for `quiet`, failing after `timeout`.
    private func waitForQuiet(_ count: @MainActor () -> Int, quiet: Duration = .milliseconds(750),
                              timeout: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var last = count()
        var quietSince = ContinuousClock.now
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            let current = count()
            if current != last {
                last = current
                quietSince = ContinuousClock.now
            } else if ContinuousClock.now - quietSince >= quiet {
                return
            }
        }
        Issue.record("Discovery kept publishing updates.")
    }

    private func wait(until condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Timed out waiting for the production discovery update.")
    }

    @Test
    func failedUpdateSaveReportsErrorWithoutDiscardingUserData() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let storage = fixture.root.appendingPathComponent("Storage")
        let originalStore = try AppDataStore(directoryURL: storage)
        let customization = AppCustomization(appID: AppIdentity(), isHidden: true, customName: "Saved")
        let original = try AppData(customizations: [customization])
        try await originalStore.save(original)
        let failure = CocoaError(.fileWriteOutOfSpace)
        let failingStore = try AppDataStore(directoryURL: storage, write: { _, _ in throw failure })
        _ = try fixture.application("Editor.app", in: apps)
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        var errors: [any Error] = []
        let services = AppServices(store: failingStore, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { errors.append($0) })

        try await services.start()
        try await wait { !errors.isEmpty }
        #expect(services.data?.customizations == [customization])
        #expect(services.availableRecords.count == 1)
        do {
            try await services.stop()
            Issue.record("Shutdown must report an update that could not be saved.")
        } catch {
            #expect(error as NSError == failure as NSError)
        }
        #expect(services.availableRecords.count == 1)
        #expect(services.data?.customizations == [customization])
        #expect(try await originalStore.load() == original)
    }

    @Test
    func returningToSavedSnapshotClearsAnEarlierSaveFailure() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        let app = try fixture.application("Editor.app", in: apps)
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let initial = await ApplicationCatalog(directories: [directory], scanner: ApplicationScanner()).refresh()
        let original = try AppData(records: initial.records, scannedDirectoryURLs: [apps.standardized])
        let storage = fixture.root.appendingPathComponent("Storage")
        let originalStore = try AppDataStore(directoryURL: storage)
        try await originalStore.save(original)
        let store = try AppDataStore(directoryURL: storage, write: { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })
        var errors: [any Error] = []
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { errors.append($0) })
        try await services.start()
        try await wait { services.availableRecords.count == 1 }
        let moved = apps.appendingPathComponent("Renamed.app", isDirectory: true)
        try FileManager.default.moveItem(at: app, to: moved)
        try await wait { !errors.isEmpty }
        #expect(services.data != original)

        try FileManager.default.moveItem(at: moved, to: app)
        try await wait { services.data == original }
        try await services.stop()
        #expect(try await originalStore.load() == original)
    }

    /// A mode layout saved while handling a published change refers to the change's identities, so
    /// the app data holding them is already on disk when the change is published.
    @Test
    func publishedCatalogChangeIsAlreadySaved() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        _ = try fixture.application("Editor.app", in: apps)
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"))
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { Issue.record($0) })
        var published: [(saved: AppData?, current: AppData?, hasCurrentScan: Bool)] = []
        services.onApplicationsChanged = { [weak services] _ in
            let saved = (try? Data(contentsOf: store.fileURL)).flatMap { try? JSONDecoder().decode(AppData.self, from: $0) }
            published.append((saved, services?.data, services?.hasCurrentScan == true))
        }

        try await services.start()
        try await wait { !published.isEmpty }
        _ = try fixture.application("Viewer.app", in: apps, identifier: "com.example.Viewer")
        try await wait { published.contains { $0.current?.records.count == 2 } }
        try await services.stop()

        for change in published {
            #expect(change.hasCurrentScan)
            #expect(change.saved != nil)
            #expect(change.saved == change.current, "The published records are already saved")
        }
    }

    /// A failed save is reported, and the launcher still receives the change.
    @Test
    func failedSaveStillPublishesTheChange() async throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("Apps")
        _ = try fixture.application("Editor.app", in: apps)
        let directory = ApplicationScan.Directory(source: try AppSource(kind: .custom, directoryURL: apps))
        let failure = CocoaError(.fileWriteOutOfSpace)
        let store = try AppDataStore(directoryURL: fixture.root.appendingPathComponent("Storage"),
                                     write: { _, _ in throw failure })
        var errors: [any Error] = []
        var published: [Set<AppIdentity>] = []
        let services = AppServices(store: store, icons: AppIconRepository(cacheCostLimit: 0),
                                   directories: [directory], onError: { errors.append($0) })
        services.onApplicationsChanged = { published.append($0) }

        try await services.start()
        try await wait { !published.isEmpty && !errors.isEmpty }
        let editor = try #require(services.data?.records.first)
        #expect(services.hasCurrentScan)
        #expect(services.availableRecords.map(\.id) == [editor.id])
        #expect(published.first?.contains(editor.id) == true)
        #expect(errors.first as? NSError == failure as NSError)
        await #expect(throws: CocoaError.self) { try await services.stop() }
    }
}
