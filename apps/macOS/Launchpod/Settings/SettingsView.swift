import SwiftUI

struct SettingsView: View {
    enum Page: String, CaseIterable {
        case general, interface, apps, shortcuts, advanced, about

        func title(locale: Locale) -> String {
            switch self {
            case .general: String(localized: LocalizedStringResource("General", locale: locale))
            case .interface: String(localized: LocalizedStringResource("Interface", locale: locale))
            case .apps: String(localized: LocalizedStringResource("Apps", locale: locale))
            case .shortcuts: String(localized: LocalizedStringResource("Shortcuts", locale: locale))
            case .advanced: String(localized: LocalizedStringResource("Advanced", locale: locale))
            case .about: String(localized: LocalizedStringResource("About", locale: locale))
            }
        }

        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .interface: "macwindow"
            case .apps: "square.grid.2x2"
            case .shortcuts: "keyboard"
            case .advanced: "slider.horizontal.3"
            case .about: "info.circle"
            }
        }
    }

    let page: Page
    let languagePreference: AppLanguagePreference
    let directoryPreference: AppDirectoryPreference
    @Binding var appearance: AppAppearance
    @Binding var showInMenuBar: Bool
    @Binding var classicalHidesDock: Bool
    @Binding var classicalFolderLiquidGlass: Bool
    @Binding var classicalRows: Int
    @Binding var classicalColumns: Int
    let shortcutPreference: ShortcutPreference
    let globalShortcut: GlobalShortcut
    let applicationIconPreference: ApplicationIconPreference
    let launchAtLogin: LaunchAtLoginModel
    let classicalLayout: ClassicalLayoutModel?
    let onLayoutChanged: @MainActor @Sendable () -> Void
    let onDirectoriesChanged: @MainActor @Sendable ([ApplicationScan.Directory]) -> Void
    let keepInDock: KeepInDockModel
    let softwareUpdates: SoftwareUpdateController
    var showIntroduction: @MainActor () -> Void = {}

    var body: some View {
        Group {
            switch page {
            case .general:
                GeneralSettingsView(languagePreference: languagePreference, appearance: $appearance,
                                    showInMenuBar: $showInMenuBar, keepInDock: keepInDock,
                                    applicationIconPreference: applicationIconPreference)
            case .interface:
                InterfaceSettingsView(classicalHidesDock: $classicalHidesDock,
                                      classicalFolderLiquidGlass: $classicalFolderLiquidGlass,
                                      classicalRows: $classicalRows,
                                      classicalColumns: $classicalColumns)
            case .shortcuts:
                ShortcutSettingsView(preference: shortcutPreference, shortcut: globalShortcut)
            case .apps:
                AppsSettingsView(directoryPreference: directoryPreference,
                                 onDirectoriesChanged: { onDirectoriesChanged($0) })
            case .advanced:
                AdvancedSettingsView(layout: classicalLayout, onLayoutChanged: { onLayoutChanged() },
                                     launchAtLogin: launchAtLogin)
            case .about:
                AboutSettingsView(
                    softwareUpdates: softwareUpdates,
                    showIntroduction: showIntroduction
                )
            }
        }
        .buttonStyle(.glass)
        .frame(
            minWidth: 360, maxWidth: 520,
            minHeight: 420, maxHeight: 760
        )
    }
}
