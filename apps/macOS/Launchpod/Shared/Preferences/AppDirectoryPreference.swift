import Foundation
import Observation

/// Keeps user selected app directories accessible while application discovery runs.
@MainActor
@Observable
final class AppDirectoryPreference {
    static let preferenceKey = "appDirectories"

    private struct Selection: Codable {
        let url: URL
        let bookmark: Data
    }

    private(set) var customDirectoryURLs: [URL] = []
    private(set) var unavailableDirectoryURLs: Set<URL> = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var selections: [Selection] = []
    @ObservationIgnored private var accessedURLs: [URL] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.preferenceKey)
            .flatMap { try? PropertyListDecoder().decode([Selection].self, from: $0) } ?? []
        var needsSave = false
        for selection in stored {
            guard let storedURL = AppFileURL.normalized(selection.url) else { continue }
            var stale = false
            let resolved = try? URL(resolvingBookmarkData: selection.bookmark,
                                    options: [.withSecurityScope], relativeTo: nil,
                                    bookmarkDataIsStale: &stale)
            let effectiveURL = resolved.flatMap(AppFileURL.normalized) ?? storedURL
            guard !customDirectoryURLs.contains(effectiveURL) else { continue }
            if effectiveURL != storedURL { needsSave = true }
            customDirectoryURLs.append(effectiveURL)
            if let resolved, resolved.startAccessingSecurityScopedResource() {
                let bookmark = stale
                    ? ((try? resolved.bookmarkData(options: [.withSecurityScope],
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil)) ?? selection.bookmark)
                    : selection.bookmark
                if bookmark != selection.bookmark { needsSave = true }
                selections.append(Selection(url: effectiveURL, bookmark: bookmark))
                accessedURLs.append(resolved)
            } else {
                selections.append(Selection(url: effectiveURL, bookmark: selection.bookmark))
                unavailableDirectoryURLs.insert(effectiveURL)
            }
        }
        if needsSave { save() }
    }

    isolated deinit {
        for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
    }

    var directories: [ApplicationScan.Directory] {
        let standard = ApplicationScanner.defaultDirectories()
        let existing = Set(standard.map(\.source.directoryURL))
        return standard + customDirectoryURLs.compactMap { url in
            guard !existing.contains(url), !unavailableDirectoryURLs.contains(url),
                  let source = try? AppSource(kind: .custom, directoryURL: url) else { return nil }
            return ApplicationScan.Directory(source: source)
        }
    }

    @discardableResult
    func add(_ url: URL) throws -> Bool {
        guard let normalized = AppFileURL.normalized(url) else {
            throw AppSource.ValidationError.invalidDirectoryURL
        }
        guard !ApplicationScanner.defaultDirectories().contains(where: {
            $0.source.directoryURL == normalized
        }) else { return false }
        let existingIndex = customDirectoryURLs.firstIndex(of: normalized)
        if existingIndex != nil && !unavailableDirectoryURLs.contains(normalized) { return false }
        let bookmark = try url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
        guard url.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }
        if let existingIndex {
            selections[existingIndex] = Selection(url: normalized, bookmark: bookmark)
            unavailableDirectoryURLs.remove(normalized)
        } else {
            selections.append(Selection(url: normalized, bookmark: bookmark))
            customDirectoryURLs.append(normalized)
        }
        accessedURLs.append(url)
        save()
        return true
    }

    func remove(_ url: URL) {
        guard let index = customDirectoryURLs.firstIndex(of: url) else { return }
        selections.remove(at: index)
        customDirectoryURLs.remove(at: index)
        unavailableDirectoryURLs.remove(url)
        // A scan of the previous directory set may still be running. Keep its grant until exit.
        save()
    }

    private func save() {
        guard let data = try? PropertyListEncoder().encode(selections) else { return }
        defaults.set(data, forKey: Self.preferenceKey)
    }
}
