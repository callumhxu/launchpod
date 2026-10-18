import Foundation
import CoreFoundation

/// Serializes directory scans and bundle reads outside the main actor.
actor ApplicationScanner: ApplicationScanning {
    private struct DirectoryLocation {
        let bookmark: Data
        let identity: ApplicationScan.FileIdentity
    }

    private var locations: [UUID: DirectoryLocation] = [:]
    private let fileManager = FileManager()
    private let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .isApplicationKey, .isAliasFileKey,
        .isSymbolicLinkKey, .fileResourceIdentifierKey, .volumeIdentifierKey,
        .volumeUUIDStringKey, .contentModificationDateKey, .localizedNameKey, .canonicalPathKey
    ]

    nonisolated static func defaultDirectories() -> [ApplicationScan.Directory] {
        let manager = FileManager()
        let domains: [(FileManager.SearchPathDomainMask, AppSource.Kind)] = [
            (.systemDomainMask, .system), (.localDomainMask, .system), (.userDomainMask, .user)
        ]
        let standard: [(url: URL, kind: AppSource.Kind)] = domains.flatMap { domain, kind in
            manager.urls(for: .applicationDirectory, in: domain).compactMap { url in
                if domain == .userDomainMask {
                    var isDirectory: ObjCBool = false
                    guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                          isDirectory.boolValue else { return nil }
                }
                return (url, kind)
            }
        }
        let additional: [(url: URL, kind: AppSource.Kind)] = [
            (URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications"), .system),
            (URL(fileURLWithPath: "/Users/Shared"), .system)
        ]
        return builtInDirectories(standard: standard, additional: additional)
    }

    /// Keeps an explicitly named app directory when a search-path URL reaches the same directory.
    nonisolated static func builtInDirectories(
        standard: [(url: URL, kind: AppSource.Kind)],
        additional: [(url: URL, kind: AppSource.Kind)]
    ) -> [ApplicationScan.Directory] {
        let preferred = additional.compactMap { try? AppSource(kind: $0.kind, directoryURL: $0.url) }
        let preferredLocations = Set(preferred.map { directoryIdentityURL(for: $0.directoryURL) })
        var seen = Set<URL>()
        let standardDirectories = standard.compactMap { candidate -> ApplicationScan.Directory? in
            guard let source = try? AppSource(kind: candidate.kind, directoryURL: candidate.url) else {
                return nil
            }
            let location = directoryIdentityURL(for: source.directoryURL)
            guard !preferredLocations.contains(location), seen.insert(location).inserted else { return nil }
            return ApplicationScan.Directory(source: source)
        }
        let additionalDirectories = preferred.compactMap { source -> ApplicationScan.Directory? in
            guard seen.insert(directoryIdentityURL(for: source.directoryURL)).inserted else { return nil }
            return ApplicationScan.Directory(source: source)
        }
        return standardDirectories + additionalDirectories
    }

    private nonisolated static func directoryIdentityURL(for url: URL) -> URL {
        let resolved = url.resolvingSymlinksInPath()
        let path = (try? resolved.resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath ?? resolved.path
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    func scan(_ directory: ApplicationScan.Directory) async -> ApplicationScan {
        let requestedURL = directory.source.directoryURL
        let hasAccess = requestedURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { requestedURL.stopAccessingSecurityScopedResource() } }
        var source = directory.source
        var applications: [ApplicationScan.Observation] = []
        var issues: [ApplicationScan.Issue] = []
        var monitored = Set([requestedURL])
        var rootLinkTargets = Set<URL>()
        var listingDates: [URL: Date?] = [:]
        var accessedRoot = false
        do {
            monitored = [try Self.canonicalMonitoringURL(for: requestedURL)]
        } catch {
            issues.append(.init(url: requestedURL, error: error))
        }
        do {
            let locatedRoot = try directoryURL(for: directory) { rootLinkTargets.insert($0) }
            let rootValues = try freshValues(at: locatedRoot)
            let root = URL(fileURLWithPath: rootValues.canonicalPath ?? locatedRoot.path)
            guard rootValues.isDirectory == true else {
                throw CocoaError(.fileReadCorruptFile)
            }
            source = try AppSource(kind: source.kind, directoryURL: root, isOnline: true,
                                   volumeUUIDString: rootValues.volumeUUIDString)
            accessedRoot = true
            do {
                monitored.insert(try Self.canonicalMonitoringURL(for: root))
            } catch {
                monitored.insert(root)
                issues.append(.init(url: root, error: error))
            }
            if let identity = ApplicationScan.FileIdentity(resourceValues: rootValues),
               let bookmark = try? root.bookmarkData(options: [], includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
                locations[directory.id] = DirectoryLocation(bookmark: bookmark, identity: identity)
            }
            if rootValues.isPackage != true, hasEligibleParent(of: requestedURL) {
                try collect(at: root, applications: &applications, issues: &issues,
                            monitored: &monitored, listingDates: &listingDates)
            }
        } catch {
            issues.append(.init(url: source.directoryURL, error: error))
            if !accessedRoot {
                source = (try? AppSource(kind: source.kind, directoryURL: source.directoryURL,
                                         isOnline: Self.isAbsent(error) ? false : nil,
                                         volumeUUIDString: source.volumeUUIDString)) ?? source
            }
        }
        monitorLinkTargets(rootLinkTargets, monitored: &monitored, issues: &issues)
        return ApplicationScan(directory: directory, source: source, applications: applications,
                               isComplete: issues.isEmpty && !Task.isCancelled, issues: issues,
                               monitoredURLs: monitored.sorted { $0.path < $1.path },
                               listedDirectoryModificationDates: listingDates)
    }

    func isCurrent(_ scan: ApplicationScan) async -> Bool {
        let requestedURL = scan.directory.source.directoryURL
        let hasAccess = requestedURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { requestedURL.stopAccessingSecurityScopedResource() } }
        return (try? listingIssues(for: scan.listedDirectoryModificationDates).isEmpty) == true
    }

    func isMissing(at url: URL) async -> Bool? {
        do {
            _ = try freshValues(at: url)
            return false
        } catch {
            return Self.isAbsent(error) ? true : nil
        }
    }

    private func directoryURL(
        for directory: ApplicationScan.Directory, onLinkTarget: (URL) -> Void
    ) throws -> URL {
        if let location = locations[directory.id] {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: location.bookmark,
                                      options: [.withoutUI, .withoutMounting], relativeTo: nil,
                                      bookmarkDataIsStale: &stale),
               let values = try? freshValues(at: resolved),
               ApplicationScan.FileIdentity(resourceValues: values) == location.identity {
                return resolved
            }
        }
        return try Self.resolve(directory.source.directoryURL, onLinkTarget: onLinkTarget).url
    }

    private func collect(
        at root: URL,
        applications: inout [ApplicationScan.Observation],
        issues: inout [ApplicationScan.Issue],
        monitored: inout Set<URL>,
        listingDates: inout [URL: Date?]
    ) throws {
        var pending = [root]
        var visited = Set<URL>()
        while let directory = pending.popLast() {
            try Task.checkCancellation()
            guard visited.insert(directory).inserted else { continue }
            let children: [URL]
            do {
                guard try !isInTrash(directory) else { continue }
                // Read before listing: a later change must differ from this value.
                listingDates.updateValue(try modificationDate(of: directory), forKey: directory)
                children = try fileManager.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            } catch {
                issues.append(.init(url: directory, error: error))
                continue
            }
            for child in children.sorted(by: { $0.path < $1.path }) {
                try Task.checkCancellation()
                var linkTargets = Set<URL>()
                var needsTargetMonitoring = true
                defer {
                    if needsTargetMonitoring {
                        monitorLinkTargets(linkTargets, monitored: &monitored, issues: &issues)
                    }
                }
                do {
                    let item = try Self.resolve(child) { linkTargets.insert($0) }
                    let values = try freshValues(at: item.url)
                    needsTargetMonitoring = values.isApplication == true
                    if values.isApplication == true {
                        if let observation = try application(at: item.url, discoveredAt: child,
                                                              values: values, alias: item.isAlias,
                                                              symlink: item.isSymbolicLink) {
                            applications.append(observation)
                        }
                    } else if values.isDirectory == true && values.isPackage != true
                        && !item.isAlias && !item.isSymbolicLink {
                        pending.append(item.url)
                    }
                } catch {
                    issues.append(.init(url: child, error: error))
                }
            }
        }
        issues.append(contentsOf: try listingIssues(for: listingDates))
    }

    // A listing is a snapshot. An entry renamed, moved, or removed while the scan reads it can
    // be missing from every listing, so absence is trusted only when no listed directory changed.
    private func listingIssues(for listingDates: [URL: Date?]) throws -> [ApplicationScan.Issue] {
        var issues: [ApplicationScan.Issue] = []
        for (directory, listed) in listingDates.sorted(by: { $0.key.path < $1.key.path }) {
            try Task.checkCancellation()
            do {
                guard let listed, try modificationDate(of: directory) == listed else {
                    throw POSIXError(.EAGAIN)
                }
            } catch {
                issues.append(.init(url: directory, error: error))
            }
        }
        return issues
    }

    private func modificationDate(of directory: URL) throws -> Date? {
        var fresh = URL(fileURLWithPath: directory.path)
        fresh.removeAllCachedResourceValues()
        return try fresh.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func monitorLinkTargets(
        _ targets: Set<URL>, monitored: inout Set<URL>, issues: inout [ApplicationScan.Issue]
    ) {
        for target in targets {
            let parent = target.deletingLastPathComponent()
            do {
                let canonical = try Self.canonicalMonitoringURL(for: parent) { monitored.insert($0) }
                monitored.insert(canonical)
            } catch {
                monitored.insert(parent)
                issues.append(.init(url: parent, error: error))
            }
        }
    }

    private func application(
        at url: URL, discoveredAt discoveredURL: URL, values: URLResourceValues,
        alias: Bool, symlink: Bool
    ) throws -> ApplicationScan.Observation? {
        guard try !isInTrash(url) else { return nil }
        guard let info = CFBundleCopyInfoDictionaryForURL(url as CFURL) as? [String: Any],
              !info.isEmpty else {
            // A link target outside the listed directories may be mid-removal or mid-install. The
            // link still exists, so it cannot confirm that the application is gone.
            if alias || symlink { throw CocoaError(.fileReadCorruptFile) }
            return nil
        }
        let localizedName = values.localizedName.map {
            ($0 as NSString).pathExtension.caseInsensitiveCompare("app") == .orderedSame
                ? ($0 as NSString).deletingPathExtension : $0
        }
        let name = localizedName ?? (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let metadata = try AppMetadata(
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            bundleURL: URL(fileURLWithPath: values.canonicalPath ?? url.path),
            displayName: name, version: info["CFBundleShortVersionString"] as? String,
            buildVersion: info["CFBundleVersion"] as? String,
            categoryIdentifier: Self.category(of: url, info: info),
            contentModificationDate: values.contentModificationDate, isApplication: values.isApplication,
            isUIElement: Self.boolean(info["LSUIElement"]),
            isBackgroundOnly: Self.boolean(info["LSBackgroundOnly"]),
            isBeta: Self.betaStatus(of: url),
            isStoreApp: fileManager.fileExists(atPath: url.appending(path: "Contents/_MASReceipt/receipt").path)
        )
        return ApplicationScan.Observation(
            metadata: metadata, discoveredURL: discoveredURL,
            fileIdentity: ApplicationScan.FileIdentity(resourceValues: values),
            isAlias: alias, isSymbolicLink: symlink
        )
    }

    private nonisolated static func resolve(
        _ url: URL, onLinkTarget: (URL) -> Void = { _ in }
    ) throws -> (url: URL, isAlias: Bool, isSymbolicLink: Bool) {
        var resolved = URL(fileURLWithPath: url.path)
        var seen = Set<URL>()
        var alias = false
        var symlink = false
        while seen.insert(resolved).inserted {
            try Task.checkCancellation()
            resolved.removeAllCachedResourceValues()
            let values = try resolved.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey])
            alias = alias || values.isAliasFile == true
            symlink = symlink || values.isSymbolicLink == true
            if values.isSymbolicLink == true {
                let destination = try FileManager.default.destinationOfSymbolicLink(atPath: resolved.path)
                let next = URL(filePath: destination, relativeTo: resolved.deletingLastPathComponent()).absoluteURL
                onLinkTarget(next)
                guard next != resolved else { throw CocoaError(.fileReadCorruptFile) }
                resolved = next
            } else if values.isAliasFile == true {
                resolved = try URL(resolvingAliasFileAt: resolved, options: [.withoutUI, .withoutMounting])
                onLinkTarget(resolved)
            } else {
                return (resolved, alias, symlink)
            }
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    /// Retains the file system spelling so later removal events need no filesystem lookup.
    nonisolated static func canonicalMonitoringURL(
        for url: URL, onExistingAncestor: (URL) -> Void = { _ in }
    ) throws -> URL {
        var ancestor = url
        var suffix: [String] = []
        while true {
            try Task.checkCancellation()
            do {
                let resolved = try resolve(ancestor).url
                let values = try resolved.resourceValues(forKeys: [.canonicalPathKey])
                if let path = values.canonicalPath {
                    let existing = URL(fileURLWithPath: path)
                    onExistingAncestor(existing)
                    return suffix.reversed().reduce(existing) { $0.appendingPathComponent($1) }
                }
                throw CocoaError(.fileReadUnknown)
            } catch {
                guard Self.isAbsent(error) else { throw error }
                let parent = ancestor.deletingLastPathComponent()
                guard parent != ancestor else { throw error }
                suffix.append(ancestor.lastPathComponent)
                ancestor = parent
            }
        }
    }

    private func freshValues(at url: URL) throws -> URLResourceValues {
        var fresh = URL(fileURLWithPath: url.path)
        fresh.removeAllCachedResourceValues()
        return try fresh.resourceValues(forKeys: resourceKeys)
    }

    private func hasEligibleParent(of url: URL) -> Bool {
        var parent = url.deletingLastPathComponent()
        while parent.path != "/" {
            if parent.lastPathComponent.hasPrefix(".") { return false }
            let values = try? parent.resourceValues(forKeys: [.isPackageKey])
            if values?.isPackage == true { return false }
            parent.deleteLastPathComponent()
        }
        return true
    }

    private func isInTrash(_ url: URL) throws -> Bool {
        var relationship = FileManager.URLRelationship.other
        do {
            try fileManager.getRelationship(&relationship, of: .trashDirectory, in: [], toItemAt: url)
        } catch let error as CocoaError where error.code == .featureUnsupported {
            // Cryptex volumes have no Trash relationship. Their applications are still scannable.
            return false
        }
        return relationship == .same || relationship == .contains
    }

    /// Core Foundation's private `_kCFURLApplicationCategoriesKey` URL resource key; nil when the
    /// symbol is unavailable.
    private nonisolated static let applicationCategoriesKey: CFString? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_kCFURLApplicationCategoriesKey") else { return nil }
        return symbol.load(as: CFString?.self)
    }()

    private nonisolated static let applicationIsBetaKey: CFString? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_kCFURLApplicationIsBetaKey") else { return nil }
        return symbol.load(as: CFString?.self)
    }()

    /// The first of the application categories Core Foundation reports for the bundle. When it reports
    /// none, or the resource key is unavailable, the non-empty Info.plist `LSApplicationCategoryType`.
    private static func category(of url: URL, info: [String: Any]) -> String? {
        // Launch Services reports no category until it registers a new bundle, so the Info.plist
        // value keeps the category stable across scans of an unchanged bundle.
        let declared = (info["LSApplicationCategoryType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard let key = applicationCategoriesKey else { return declared }
        var value: Unmanaged<CFTypeRef>?
        guard CFURLCopyResourcePropertyForKey(url as CFURL, key, &value, nil),
              let reported = (value?.takeRetainedValue() as? [String])?.first, !reported.isEmpty
        else { return declared }
        return reported
    }

    /// The system's application beta status; false when the resource has no Boolean value, and nil
    /// only when the resource key is unavailable.
    private static func betaStatus(of url: URL) -> Bool? {
        guard let key = applicationIsBetaKey else { return nil }
        // Launch Services has no value until it registers a new bundle. A missing value is not a
        // positive beta observation, so it reads as false rather than changing on a later scan.
        var value: Unmanaged<CFTypeRef>?
        guard CFURLCopyResourcePropertyForKey(url as CFURL, key, &value, nil),
              let number = value?.takeRetainedValue() as? NSNumber else { return false }
        return number.boolValue
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private nonisolated static func isAbsent(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            return error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError
        }
        return error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
    }
}
