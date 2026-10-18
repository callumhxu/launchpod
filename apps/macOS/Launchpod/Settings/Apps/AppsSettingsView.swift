import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppsSettingsView: View {
    @Bindable var directoryPreference: AppDirectoryPreference
    let onDirectoriesChanged: @MainActor @Sendable ([ApplicationScan.Directory]) -> Void
    @State private var isChoosingFolder = false
    @State private var selection: URL?

    var body: some View {
        Form {
            Section {
                List(selection: $selection) {
                    ForEach(builtInDirectoryURLs, id: \.self) { url in
                        folderRow(url) { EmptyView() }
                            .tag(url)
                    }
                    ForEach(directoryPreference.customDirectoryURLs, id: \.self) { url in
                        folderRow(url) {
                            if directoryPreference.unavailableDirectoryURLs.contains(url) {
                                Label("Access Needed", systemImage: "exclamationmark.triangle")
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tag(url)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button {
                        isChoosingFolder = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: NSFont.systemFontSize, height: NSFont.systemFontSize)
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Add Folder")
                    // Built-in app directories are fixed; only added folders can be removed.
                    Button {
                        guard let selection else { return }
                        directoryPreference.remove(selection)
                        self.selection = nil
                        onDirectoriesChanged(directoryPreference.directories)
                    } label: {
                        Label("Remove Folder", systemImage: "minus")
                            .frame(width: NSFont.systemFontSize, height: NSFont.systemFontSize)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!directoryPreference.customDirectoryURLs.contains { $0 == selection })
                }
                .fixedSize()
            } header: {
                Text("App Sources")
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                do {
                    if try directoryPreference.add(url) {
                        onDirectoriesChanged(directoryPreference.directories)
                    }
                } catch {
                    NSApplication.shared.presentError(error)
                }
            case .failure(let error):
                NSApplication.shared.presentError(error)
            }
        }
    }

    // Lists /Applications first and the user's Applications folder last for display only;
    // the scanner's directory order is unchanged.
    private var builtInDirectoryURLs: [URL] {
        let local = Set(FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask))
        let user = Set(FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask))
        let urls = ApplicationScanner.defaultDirectories().map(\.source.directoryURL)
        return urls.filter { local.contains($0) }
            + urls.filter { !local.contains($0) && !user.contains($0) }
            + urls.filter { user.contains($0) }
    }

    private func folderRow(_ url: URL, @ViewBuilder accessories: () -> some View) -> some View {
        LabeledContent {
            accessories()
        } label: {
            Label {
                Text(FileManager.default.displayName(atPath: url.path))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(url.path)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(nsImage: folderIcon(url))
            }
        }
        .help(url.path)
    }

    // A missing directory has no file icon of its own; show the generic folder icon
    // instead of the blank-document icon NSWorkspace returns for nonexistent paths.
    private func folderIcon(_ url: URL) -> NSImage {
        FileManager.default.fileExists(atPath: url.path)
            ? NSWorkspace.shared.icon(forFile: url.path)
            : NSWorkspace.shared.icon(for: .folder)
    }
}
