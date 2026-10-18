import Foundation
import Testing
@testable import Launchpod

@MainActor
struct AppDirectoryPreferenceTests {
    private struct StoredSelection: Codable {
        let url: URL
        let bookmark: Data
    }

    /// `directory` as an open panel hands it over: a security-scoped URL, which the sandboxed app may
    /// start accessing. A plain file URL of the same folder carries no such grant.
    private func userSelected(_ directory: URL) throws -> URL {
        var stale = false
        let bookmark = try directory.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil,
                                                  relativeTo: nil)
        return try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil,
                       bookmarkDataIsStale: &stale)
    }

    @Test
    func selectedFolderSurvivesPreferenceRecreationAndCanBeRemoved() throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("External Apps")
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }

        do {
            let preference = AppDirectoryPreference(defaults: defaults)
            #expect(try preference.add(userSelected(apps)))
            #expect(try !preference.add(userSelected(apps)), "A folder must appear only once.")
            #expect(preference.customDirectoryURLs == [apps.standardized])
            #expect(preference.directories.last?.source.kind == .custom)
            #expect(preference.directories.last?.source.directoryURL == apps.standardized)
            #expect(defaults.data(forKey: AppDirectoryPreference.preferenceKey) != nil)
        }

        let restored = AppDirectoryPreference(defaults: defaults)
        #expect(restored.customDirectoryURLs == [apps.standardized])
        #expect(restored.directories.last?.source.directoryURL == apps.standardized)
        restored.remove(apps.standardized)
        #expect(restored.customDirectoryURLs.isEmpty)
        #expect(!restored.directories.contains { $0.source.directoryURL == apps.standardized })
        #expect(AppDirectoryPreference(defaults: defaults).customDirectoryURLs.isEmpty)
    }

    @Test
    func builtInFoldersRemainVisibleInThePreferenceWithoutASelection() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }

        let preference = AppDirectoryPreference(defaults: defaults)
        #expect(preference.customDirectoryURLs.isEmpty)
        #expect(preference.directories.map(\.source) == ApplicationScanner.defaultDirectories().map(\.source))
    }

    @Test
    func selectingABuiltInFolderDoesNotCreateACustomEntry() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let builtIn = try #require(ApplicationScanner.defaultDirectories().first?.source.directoryURL)
        let preference = AppDirectoryPreference(defaults: defaults)

        #expect(try !preference.add(builtIn))
        #expect(preference.customDirectoryURLs.isEmpty)
        #expect(defaults.data(forKey: AppDirectoryPreference.preferenceKey) == nil)
    }

    @Test
    func reselectingAnUnavailableFolderRestoresAccessWithoutDuplicatingIt() throws {
        let fixture = try ApplicationDiscoveryTestDirectory()
        defer { fixture.remove() }
        let apps = try fixture.directory("External Apps")
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        let stored = try PropertyListEncoder().encode([
            StoredSelection(url: apps, bookmark: Data("invalid bookmark".utf8))
        ])
        defaults.set(stored, forKey: AppDirectoryPreference.preferenceKey)

        let preference = AppDirectoryPreference(defaults: defaults)
        #expect(preference.customDirectoryURLs == [apps.standardized])
        #expect(preference.unavailableDirectoryURLs == [apps.standardized])
        #expect(!preference.directories.contains { $0.source.directoryURL == apps.standardized })

        #expect(try preference.add(userSelected(apps)))
        #expect(preference.customDirectoryURLs == [apps.standardized])
        #expect(preference.unavailableDirectoryURLs.isEmpty)
        #expect(preference.directories.filter { $0.source.directoryURL == apps.standardized }.count == 1)

        let restored = AppDirectoryPreference(defaults: defaults)
        #expect(restored.customDirectoryURLs == [apps.standardized])
        #expect(restored.unavailableDirectoryURLs.isEmpty)
    }
}
