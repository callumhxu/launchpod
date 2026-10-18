import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var languagePreference: AppLanguagePreference
    @Binding var appearance: AppAppearance
    @Binding var showInMenuBar: Bool
    /// Owned by the settings window, which chooses the Dock store; tests supply a fake store.
    let keepInDock: KeepInDockModel
    let applicationIconPreference: ApplicationIconPreference
    private let dockIconSize: CGFloat = 48

    init(
        languagePreference: AppLanguagePreference,
        appearance: Binding<AppAppearance>,
        showInMenuBar: Binding<Bool>,
        keepInDock: KeepInDockModel,
        applicationIconPreference: ApplicationIconPreference
    ) {
        self.languagePreference = languagePreference
        _appearance = appearance
        _showInMenuBar = showInMenuBar
        self.keepInDock = keepInDock
        self.applicationIconPreference = applicationIconPreference
    }

    var body: some View {
        Form {
            Section("Language & Appearance") {
                Picker(selection: $languagePreference.selection) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(localizedName(language.name, locale: language == .system
                                           ? languagePreference.locale
                                           : Locale(identifier: language.rawValue)))
                            .tag(language)
                    }
                } label: {
                    Label("Language", systemImage: "globe")
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("appLanguagePicker")

                Picker(selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        Text(localizedName(appearance.name, locale: languagePreference.locale))
                            .tag(appearance)
                    }
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("appAppearancePicker")
            }

            Section("Menu Bar & Dock") {
                Toggle(isOn: $showInMenuBar) {
                    Label("Show in Menu Bar", systemImage: "square.topthird.inset.filled")
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("showInMenuBarToggle")

                LabeledContent {
                    HStack {
                        if keepInDock.membership == .notInDock {
                            Button("Add to Dock") { keepInDock.addToDock() }
                                .disabled(!keepInDock.canAdd)
                                .accessibilityIdentifier("addToDockButton")
                        }
                        DockApplicationIcon(applicationIcon: applicationIconPreference.selection)
                            .frame(width: dockIconSize, height: dockIconSize)
                    }
                    .settingsRowCentered()
                } label: {
                    // The form keeps a label shorter than its control at the top; give it the icon's height.
                    SettingsRowLabel(title: "Keep in Dock", subtitle: keepInDockSubtitle,
                                     systemImage: "square.bottomthird.inset.filled")
                        .frame(minHeight: dockIconSize)
                }
                .accessibilityElement(children: .contain)
                .onAppear { keepInDock.startObserving() }
                .onDisappear { keepInDock.stopObserving() }

                LabeledContent {
                    ApplicationIconPicker(preference: applicationIconPreference)
                        .settingsRowCentered()
                } label: {
                    SettingsRowLabel(title: "Application Icon",
                                     subtitle: "Choose the icon shown in the Dock.",
                                     systemImage: "app.dashed")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func localizedName(_ name: LocalizedStringResource, locale: Locale) -> String {
        var name = name
        name.locale = locale
        return String(localized: name)
    }

    private var keepInDockSubtitle: LocalizedStringResource {
        if keepInDock.addFailed {
            return "Couldn’t add this app to the Dock. Drag its icon to the Dock instead."
        }
        switch keepInDock.membership {
        case .inDock:
            return "This app is in the Dock."
        case .notInDock, .unknown:
            return "Drag this app icon to the Dock."
        }
    }
}

private struct ApplicationIconPicker: View {
    let preference: ApplicationIconPreference
    private let iconSize: CGFloat = 34
    private let selectionIndicatorSize: CGFloat = 5

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(ApplicationIcon.allCases, id: \.self) { icon in
                Button {
                    preference.select(icon)
                } label: {
                    VStack(spacing: 4) {
                        Image(nsImage: image(for: icon))
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize, height: iconSize)

                        Circle()
                            .fill(preference.selection == icon ? Color.blue : .clear)
                            .frame(width: selectionIndicatorSize, height: selectionIndicatorSize)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon.name)
                .accessibilityIdentifier("applicationIcon.\(icon.rawValue)")
                .accessibilityAddTraits(preference.selection == icon ? .isSelected : [])
                .help(Text(icon.name))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("applicationIconPicker")
    }

    private func image(for icon: ApplicationIcon) -> NSImage {
        ApplicationIconPreviewImage.resolve(icon)
    }
}
