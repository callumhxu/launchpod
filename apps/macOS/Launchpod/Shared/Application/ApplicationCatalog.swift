import Foundation

/// Reconciles directory observations without owning user names, visibility, or layout.
actor ApplicationCatalog {
    struct Update: Sendable {
        let inserted: [AppRecord]
        let updated: [AppRecord]
        /// Changed records and apps in rescanned directories, even when metadata is unchanged.
        let affectedAppIDs: Set<AppIdentity>
        let records: [AppRecord]
        /// Records with a current successful application observation, not a launch guarantee.
        let availableRecords: [AppRecord]
        let unresolvedApplications: [ApplicationScan.Observation]
        let scans: [ApplicationScan]
    }

    private struct Entry {
        var record: AppRecord
        let fileIdentity: ApplicationScan.FileIdentity?
        var directoryIDs: Set<UUID>
    }

    private struct Candidate {
        let observation: ApplicationScan.Observation
        let source: AppSource
        let scanGeneration: Int
        var directoryIDs: Set<UUID>
    }

    private let directories: [ApplicationScan.Directory]
    private let scanner: any ApplicationScanning
    private var scans: [UUID: ApplicationScan] = [:]
    private var entries: [AppIdentity: Entry] = [:]
    private var generation = 0
    private var availableIDs = Set<AppIdentity>()
    private var unresolved: [ApplicationScan.Observation] = []
    private var scanGenerations: [UUID: Int] = [:]

    init(
        directories: [ApplicationScan.Directory],
        scanner: any ApplicationScanning,
        restoredData: AppData? = nil
    ) {
        self.directories = directories
        self.scanner = scanner
        for var record in restoredData?.records ?? [] {
            record.isMissing = nil
            let directoryIDs = Set(directories.filter {
                $0.source.kind == record.source.kind
                    && $0.source.directoryURL == record.source.directoryURL
            }.map(\.id))
            entries[record.id] = Entry(record: record, fileIdentity: nil, directoryIDs: directoryIDs)
        }
    }

    func refresh(directoryIDs: Set<UUID>? = nil) async -> Update {
        generation += 1
        let request = generation
        guard let (refreshed, freshness, listingsAreCurrent) = await scanDirectories(directoryIDs, request: request)
        else { return currentUpdate() }
        let candidates = candidates(from: refreshed, freshness: freshness)
        let resolution = resolve(candidates)
        var next = entries
        var observed = Set<AppIdentity>()
        var deleted = Set<AppIdentity>()
        var uncertain: [ApplicationScan.Observation] = []
        for (index, candidate) in candidates.enumerated() {
            if resolution.unresolved.contains(index) {
                uncertain.append(candidate.observation)
                continue
            }
            let record: AppRecord
            if let id = resolution.matches[index], let entry = entries[id],
               var replacement = try? entry.record.replacingMetadata(
                    with: candidate.observation.metadata, source: candidate.source) {
                replacement.isMissing = false
                record = replacement
            } else {
                record = AppRecord(metadata: candidate.observation.metadata, source: candidate.source,
                                   isMissing: false)
            }
            observed.insert(record.id)
            next[record.id] = Entry(record: record, fileIdentity: candidate.observation.fileIdentity,
                                    directoryIDs: candidate.directoryIDs)
        }
        for (id, entry) in entries where !observed.contains(id) {
            let relevant = entry.directoryIDs.compactMap { refreshed[$0] }
            let complete = listingsAreCurrent && !entry.directoryIDs.isEmpty
                && relevant.count == entry.directoryIDs.count
                && entry.directoryIDs.allSatisfy { freshness[$0] == request }
                && relevant.allSatisfy { $0.isComplete && $0.source.isOnline == true }
            let missing = complete ? await scanner.isMissing(at: entry.record.metadata.bundleURL) : nil
            guard request == generation, !Task.isCancelled else { return currentUpdate() }
            if missing == true {
                // The containing sources were scanned completely and are online. This is a
                // deleted application, not an unavailable volume or an incomplete scan.
                next.removeValue(forKey: id)
                deleted.insert(id)
                continue
            }
            var record = entry.record
            if let source = relevant.first?.source,
               let replacement = try? record.replacingMetadata(with: record.metadata, source: source) {
                record = replacement
            }
            record.isMissing = nil
            next[id] = Entry(record: record, fileIdentity: entry.fileIdentity,
                             directoryIDs: entry.directoryIDs)
        }
        let previous = entries
        entries = next
        scans = refreshed
        scanGenerations = freshness
        availableIDs = observed
        unresolved = uncertain
        let records = sortedRecords()
        let updated = records.filter { previous[$0.id] != nil && previous[$0.id]?.record != $0 }
        let rescannedDirectoryIDs = Set(freshness.filter { $0.value == request }.keys)
        var affectedAppIDs = Set(updated.map(\.id)).union(deleted)
        for (id, entry) in next {
            let directoryIDs = entry.directoryIDs.union(previous[id]?.directoryIDs ?? [])
            if !directoryIDs.isDisjoint(with: rescannedDirectoryIDs) {
                affectedAppIDs.insert(id)
            }
        }
        return Update(inserted: records.filter { previous[$0.id] == nil },
                      updated: updated, affectedAppIDs: affectedAppIDs,
                      records: records, availableRecords: records.filter { observed.contains($0.id) },
                      unresolvedApplications: uncertain, scans: orderedScans())
    }

    private func scanDirectories(
        _ requested: Set<UUID>?, request: Int
    ) async -> ([UUID: ApplicationScan], [UUID: Int], Bool)? {
        var ids = requested ?? Set(directories.map(\.id))
        var previousCount: Int
        repeat {
            previousCount = ids.count
            for entry in entries.values where !entry.directoryIDs.isDisjoint(with: ids) {
                ids.formUnion(entry.directoryIDs)
            }
        } while previousCount != ids.count
        var refreshed = scans
        var freshness = scanGenerations
        for directory in directories where ids.contains(directory.id) {
            let scan = await scanner.scan(directory)
            guard request == generation, !Task.isCancelled else { return nil }
            refreshed[directory.id] = scan
            freshness[directory.id] = request
        }
        let replacement = ids.contains { id in
            refreshed[id]?.applications.contains { app in
                entries.values.contains { entry in
                    entry.record.matchesBundleAndLocation(of: app.metadata)
                        && entry.fileIdentity != nil && app.fileIdentity != nil
                        && entry.fileIdentity != app.fileIdentity
                }
            } ?? false
        }
        var missingApp = false
        if !replacement && ids.count < directories.count {
            for entry in entries.values where !entry.directoryIDs.isDisjoint(with: ids) {
                let observed = ids.contains { id in
                    refreshed[id]?.applications.contains { app in
                        (entry.fileIdentity != nil && entry.fileIdentity == app.fileIdentity
                            && compatible(entry.record.metadata, app.metadata))
                            || entry.record.matchesBundleAndLocation(of: app.metadata)
                    } ?? false
                }
                guard !observed,
                      entry.directoryIDs.allSatisfy({ id in
                          freshness[id] == request && refreshed[id]?.isComplete == true
                              && refreshed[id]?.source.isOnline == true
                      }) else { continue }
                if await scanner.isMissing(at: entry.record.metadata.bundleURL) == true {
                    guard request == generation, !Task.isCancelled else { return nil }
                    missingApp = true
                    break
                }
                guard request == generation, !Task.isCancelled else { return nil }
            }
        }
        if replacement || missingApp {
            // A moved copy must be found before its former path is replaced or discarded.
            for directory in directories where !ids.contains(directory.id) {
                let scan = await scanner.scan(directory)
                guard request == generation, !Task.isCancelled else { return nil }
                refreshed[directory.id] = scan
                freshness[directory.id] = request
            }
        }
        // A move into an already scanned app directory can be absent from both complete scans.
        // Confirm the whole refresh's listings before treating an old path's absence as deletion.
        var listingsAreCurrent = true
        for directory in directories where freshness[directory.id] == request {
            guard let scan = refreshed[directory.id] else { continue }
            if !(await scanner.isCurrent(scan)) { listingsAreCurrent = false }
            guard request == generation, !Task.isCancelled else { return nil }
        }
        return (refreshed, freshness, listingsAreCurrent)
    }

    private func candidates(from scans: [UUID: ApplicationScan], freshness: [UUID: Int]) -> [Candidate] {
        var result: [Candidate] = []
        let ordered = directories.enumerated().sorted {
            let left = freshness[$0.element.id] ?? 0
            let right = freshness[$1.element.id] ?? 0
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
        for directory in ordered {
            guard let scan = scans[directory.id] else { continue }
            let scanGeneration = freshness[directory.id] ?? 0
            for observation in scan.applications {
                if let index = result.firstIndex(where: {
                    let sameFile = observation.fileIdentity != nil
                        && observation.fileIdentity == $0.observation.fileIdentity
                    let sameLocation = observation.metadata.bundleURL == $0.observation.metadata.bundleURL
                    let compatibleMetadata = compatible(observation.metadata, $0.observation.metadata)
                    let existingIsNewer = $0.scanGeneration > scanGeneration
                    return (sameFile || sameLocation) && (compatibleMetadata || existingIsNewer)
                }) {
                    result[index].directoryIDs.insert(directory.id)
                } else {
                    result.append(Candidate(observation: observation, source: scan.source,
                                             scanGeneration: scanGeneration,
                                             directoryIDs: [directory.id]))
                }
            }
        }
        return result
    }

    private func resolve(_ candidates: [Candidate]) -> (matches: [Int: AppIdentity], unresolved: Set<Int>) {
        var matches: [Int: AppIdentity] = [:]
        var uncertain = Set<Int>()
        let physical = candidates.map { candidate in
            entries.compactMap { id, entry -> AppIdentity? in
                guard let identity = candidate.observation.fileIdentity,
                      identity == entry.fileIdentity,
                      compatible(entry.record.metadata, candidate.observation.metadata) else { return nil }
                return id
            }
        }
        let claims = Dictionary(physical.flatMap { $0 }.map { ($0, 1) }, uniquingKeysWith: +)
        for (index, ids) in physical.enumerated() {
            if ids.count == 1, let id = ids.first, claims[id] == 1 {
                matches[index] = id
            } else if !ids.isEmpty {
                uncertain.insert(index)
            }
        }
        var assigned = Set(matches.values)
        for (index, candidate) in candidates.enumerated() where matches[index] == nil && !uncertain.contains(index) {
            let sameLocation = entries.filter { id, entry in
                !assigned.contains(id) && entry.record.matchesBundleAndLocation(of: candidate.observation.metadata)
            }
            if sameLocation.count == 1, let id = sameLocation.first?.key {
                matches[index] = id
                assigned.insert(id)
            } else if sameLocation.count > 1 {
                uncertain.insert(index)
            } else if candidate.observation.fileIdentity == nil,
                      candidate.observation.metadata.knownBundleIdentifier == nil,
                      entries.values.contains(where: {
                          $0.record.metadata.bundleURL == candidate.observation.metadata.bundleURL
                      }) {
                uncertain.insert(index)
            }
        }
        return (matches, uncertain)
    }

    private func compatible(_ lhs: AppMetadata, _ rhs: AppMetadata) -> Bool {
        guard let lhs = lhs.knownBundleIdentifier, let rhs = rhs.knownBundleIdentifier else { return true }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private func currentUpdate() -> Update {
        let records = sortedRecords()
        return Update(inserted: [], updated: [], affectedAppIDs: [], records: records,
                      availableRecords: records.filter { availableIDs.contains($0.id) },
                      unresolvedApplications: unresolved, scans: orderedScans())
    }

    private func sortedRecords() -> [AppRecord] {
        entries.values.map(\.record).sorted {
            if $0.metadata.bundleURL.path != $1.metadata.bundleURL.path {
                return $0.metadata.bundleURL.path < $1.metadata.bundleURL.path
            }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }

    private func orderedScans() -> [ApplicationScan] {
        directories.compactMap { scans[$0.id] }
    }
}
