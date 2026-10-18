import SwiftUI

struct ShortcutSettingsView: View {
    let preference: ShortcutPreference
    let shortcut: GlobalShortcut

    var body: some View {
        Form {
            Section("Keyboard Shortcut") {
                LabeledContent {
                    ShortcutRecorder(
                        selection: preference.selection,
                        onRecord: { preference.selection = $0 },
                        onRecordingChanged: { isRecording in
                            if isRecording {
                                shortcut.stop()
                            } else {
                                shortcut.update(binding: preference.selection)
                            }
                        },
                        onClear: {
                            preference.selection = nil
                            shortcut.stop()
                        }
                    )
                    .fixedSize()
                    .help("Use Command, Control, or Option with a letter, number, or symbol. Press Escape to cancel.")
                    .accessibilityIdentifier("launcherShortcutRecorder")
                } label: {
                    Label("Show or Hide Launchpod", systemImage: "keyboard")
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .contain)

                if shortcut.registrationError != nil {
                    Text("This shortcut could not be registered. Choose another combination.")
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("launcherShortcutError")
                }
            }
        }
        .formStyle(.grouped)
    }
}
