import SwiftUI

/// Folder creation and opening with disposable sample apps.
struct OnboardingFolderDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var illustration
    @State private var sample = OnboardingDemoState()
    @State private var replay = 0
    @State private var isPlaying = true

    var body: some View {
        VStack(spacing: OnboardingParameters.sectionSpacing) {
            ZStack {
                if sample.isFolderOpen {
                    expandedFolder
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                } else {
                    HStack(spacing: OnboardingParameters.itemSpacing) {
                        if !sample.folderApps.isEmpty { collapsedFolder }
                        ForEach(sample.apps) { app in
                            OnboardingSampleTile(app: app)
                                .matchedGeometryEffect(id: app, in: illustration)
                                .onDrag {
                                    isPlaying = false
                                    return NSItemProvider(object: app.rawValue as NSString)
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let raw = items.first,
                                          let source = OnboardingDemoState.App(rawValue: raw),
                                          Set([source, app]) == Set([.notes, .music]) else { return false }
                                    perform { sample.createFolder() }
                                    return true
                                }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: OnboardingParameters.folderStageHeight)
            .padding(OnboardingParameters.sectionSpacing)
            .background(.quinary, in: .rect(cornerRadius: OnboardingParameters.panelCornerRadius))

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboardingFolderDescription")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: OnboardingParameters.itemSpacing) { controls }
                VStack(spacing: OnboardingParameters.itemSpacing) { controls }
            }
        }
        .accessibilityIdentifier("onboardingFolderDemo")
        .task(id: replay) { await play() }
    }

    @ViewBuilder private var controls: some View {
        Button("Create Folder") { perform { sample.createFolder() } }
            .disabled(!sample.folderApps.isEmpty)
            .accessibilityIdentifier("onboardingTryFolders")
        if sample.isFolderOpen {
            Button("Close Folder") { perform { sample.closeFolder() } }
                .accessibilityIdentifier("onboardingCloseFolder")
        } else {
            Button("Open Folder") { perform { sample.openFolder() } }
                .disabled(sample.folderApps.isEmpty)
                .accessibilityIdentifier("onboardingOpenFolder")
        }
        Button("Reset Demo") { perform { sample.reset() } }
            .accessibilityIdentifier("onboardingResetFolderDemo")
        Button("Replay") {
            perform { sample.reset() }
            isPlaying = true
            replay += 1
        }
        .accessibilityIdentifier("onboardingReplayFolder")
    }

    private var collapsedFolder: some View {
        Button {
            perform { sample.openFolder() }
        } label: {
            VStack(spacing: OnboardingParameters.compactSpacing) {
                HStack(spacing: 0) {
                    ForEach(sample.folderApps) { app in
                        OnboardingSampleTile(app: app)
                            .scaleEffect(OnboardingParameters.folderPreviewScale)
                            .frame(width: OnboardingParameters.folderPreviewWidth)
                            .matchedGeometryEffect(id: app, in: illustration)
                    }
                }
                .frame(height: OnboardingParameters.tileSize)
                .background(.regularMaterial, in: .rect(cornerRadius: OnboardingParameters.tileCornerRadius))
                Text("Sample Folder").font(.caption)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Folder")
        .accessibilityIdentifier("onboardingSampleFolder")
    }

    private var expandedFolder: some View {
        VStack(spacing: OnboardingParameters.sectionSpacing) {
            Text("Sample Folder").font(.headline)
            HStack(spacing: OnboardingParameters.sectionSpacing) {
                ForEach(sample.folderApps) { app in
                    OnboardingSampleTile(app: app)
                        .matchedGeometryEffect(id: app, in: illustration)
                }
            }
        }
        .padding(OnboardingParameters.pagePadding)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: OnboardingParameters.panelCornerRadius))
        .accessibilityIdentifier("onboardingExpandedFolder")
    }

    private var description: LocalizedStringKey {
        if sample.isFolderOpen {
            "Open a folder to see the apps inside. Close it to return to your grid."
        } else if sample.folderApps.isEmpty {
            "Drag Notes onto Music to create a sample folder, or choose Create Folder."
        } else {
            "Two apps, one folder. Click the sample folder to open it."
        }
    }

    private func perform(_ action: () -> Void) {
        isPlaying = false
        withAnimation(reduceMotion ? nil : OnboardingParameters.demonstration, action)
    }

    private func play() async {
        guard !reduceMotion else { return }
        do {
            try await Task.sleep(for: OnboardingParameters.demoPause)
            guard !Task.isCancelled, isPlaying, !reduceMotion else { return }
            withAnimation(OnboardingParameters.demonstration) { sample.createFolder() }
            try await Task.sleep(for: OnboardingParameters.demoPause)
            guard !Task.isCancelled, isPlaying, !reduceMotion else { return }
            withAnimation(OnboardingParameters.demonstration) { sample.openFolder() }
            isPlaying = false
        } catch { }
    }
}
