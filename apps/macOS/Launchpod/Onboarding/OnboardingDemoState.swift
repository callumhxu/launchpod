import Foundation

/// Disposable sample data for the introduction, independent of application discovery and saved layouts.
struct OnboardingDemoState {
    enum App: String, CaseIterable, Identifiable {
        case notes, music, photos, calendar
        var id: Self { self }
    }

    private(set) var apps = App.allCases
    private(set) var folderApps: [App] = []
    private(set) var isFolderOpen = false
    private(set) var query = ""

    var visibleApps: [App] {
        query.isEmpty ? apps : apps.filter { $0 == .notes }
    }

    mutating func searchForNotes() { query = "notes" }

    mutating func move(_ app: App, before destination: App) {
        guard query.isEmpty, app != destination,
              let source = apps.firstIndex(of: app), apps.contains(destination) else { return }
        apps.remove(at: source)
        if let target = apps.firstIndex(of: destination) { apps.insert(app, at: target) }
    }

    mutating func createFolder() {
        guard folderApps.isEmpty, apps.contains(.notes), apps.contains(.music) else { return }
        folderApps = [.notes, .music]
        apps.removeAll { folderApps.contains($0) }
        query = ""
    }

    mutating func openFolder() {
        guard !folderApps.isEmpty else { return }
        isFolderOpen = true
    }

    mutating func closeFolder() { isFolderOpen = false }
    mutating func reset() { self = Self() }
}
