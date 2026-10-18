import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct LayoutBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct AdvancedSettingsView: View {
    let layout: ClassicalLayoutModel?
    let onLayoutChanged: @MainActor @Sendable () -> Void
    let launchAtLogin: LaunchAtLoginModel
    @State private var backup: LayoutBackupDocument?
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var showResetConfirmation = false
    @State private var showImportConfirmation = false
    @State private var pendingImport: Data?

    init(
        layout: ClassicalLayoutModel?,
        onLayoutChanged: @escaping @MainActor @Sendable () -> Void,
        launchAtLogin: LaunchAtLoginModel
    ) {
        self.layout = layout
        self.onLayoutChanged = onLayoutChanged
        self.launchAtLogin = launchAtLogin
    }

    var body: some View {
        Form {
            Section("Startup") {
                LabeledContent {
                    Toggle("Launch at Login", isOn: launchAtLoginBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("Launch at Login")
                        .accessibilityIdentifier("launchAtLoginToggle")
                        .settingsRowCentered()
                } label: {
                    SettingsRowLabel(
                        title: LocalizedStringResource("Launch at Login"),
                        subtitle: LocalizedStringResource("Open Launchpod automatically when you log in."),
                        systemImage: "power"
                    )
                }
            }

            Section("Layout") {
                LabeledContent {
                    Button("Restore…") { showResetConfirmation = true }
                        .disabled(layout?.layout == nil)
                        .settingsRowCentered()
                } label: {
                    SettingsRowLabel(
                        title: "Default Classical Layout",
                        subtitle: "Restore Launchpod's initial arrangement using the apps currently installed.",
                        systemImage: "square.grid.3x3"
                    )
                }

                LabeledContent {
                    Button("Import…") { isImporting = true }
                        .disabled(layout == nil)
                        .settingsRowCentered()
                    Button("Export…") { exportLayout() }
                        .disabled(layout?.layout == nil)
                        .settingsRowCentered()
                } label: {
                    SettingsRowLabel(
                        title: "Layout Backup",
                        subtitle: "Save or restore your Classical pages, folders, names, and icon positions.",
                        systemImage: "arrow.up.arrow.down.square"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else {
                if case let .failure(error) = result { NSApplication.shared.presentError(error) }
                return
            }
            Task { @MainActor in
                do {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    _ = try JSONDecoder().decode(ClassicalLayout.self, from: data)
                    pendingImport = data
                    showImportConfirmation = true
                } catch { NSApplication.shared.presentError(error) }
            }
        }
        .fileExporter(isPresented: $isExporting, document: backup,
                      contentType: .json, defaultFilename: "Launchpod Layout") { result in
            if case let .failure(error) = result { NSApplication.shared.presentError(error) }
            backup = nil
        }
        .alert("Replace Layout?", isPresented: $showImportConfirmation) {
            Button("Replace Layout", role: .destructive) { importLayout() }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Your current Classical layout will be replaced. Export a backup first if you want to keep it.")
        }
        .alert("Restore Default Layout?", isPresented: $showResetConfirmation) {
            Button("Restore Layout", role: .destructive) { resetLayout() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your saved Classical icon positions and folders will be removed. App sources and other settings stay as they are.")
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchAtLogin.isEnabled
        } set: { isEnabled in
            do {
                try launchAtLogin.setEnabled(isEnabled)
            } catch {
                NSApplication.shared.presentError(error)
            }
        }
    }

    private func exportLayout() {
        guard let layout else { return }
        Task { @MainActor in
            do {
                backup = LayoutBackupDocument(data: try await layout.exportData())
                isExporting = true
            } catch { NSApplication.shared.presentError(error) }
        }
    }

    private func importLayout() {
        guard let layout, let data = pendingImport else { return }
        pendingImport = nil
        Task { @MainActor in
            do {
                try await layout.importData(data)
                onLayoutChanged()
            } catch { NSApplication.shared.presentError(error) }
        }
    }

    private func resetLayout() {
        guard let layout else { return }
        Task { @MainActor in
            do {
                try await layout.resetToSystemLayout()
                onLayoutChanged()
            } catch { NSApplication.shared.presentError(error) }
        }
    }
}
