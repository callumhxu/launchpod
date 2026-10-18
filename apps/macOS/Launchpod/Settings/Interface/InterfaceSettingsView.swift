import SwiftUI

struct InterfaceSettingsView: View {
    @Binding var classicalHidesDock: Bool
    @Binding var classicalFolderLiquidGlass: Bool
    @Binding var classicalRows: Int
    @Binding var classicalColumns: Int

    init(
        classicalHidesDock: Binding<Bool>,
        classicalFolderLiquidGlass: Binding<Bool>,
        classicalRows: Binding<Int>,
        classicalColumns: Binding<Int>
    ) {
        _classicalHidesDock = classicalHidesDock
        _classicalFolderLiquidGlass = classicalFolderLiquidGlass
        _classicalRows = classicalRows
        _classicalColumns = classicalColumns
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $classicalHidesDock) {
                    SettingsRowLabel(title: "Hide Dock",
                                     subtitle: "Covers the Dock while Launchpod is shown full screen.",
                                     systemImage: "square.bottomthird.inset.filled")
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("classicalHidesDockToggle")

                Toggle(isOn: $classicalFolderLiquidGlass) {
                    Label("Liquid Glass", systemImage: "square.stack.3d.up")
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("classicalFolderLiquidGlassToggle")

                LabeledContent {
                    dimensionField("Columns", value: $classicalColumns,
                                   identifier: "classicalColumnsStepper")
                    Text(verbatim: "×")
                        .foregroundStyle(.secondary)
                    dimensionField("Rows", value: $classicalRows,
                                   identifier: "classicalRowsStepper")
                } label: {
                    Label("Icon Grid", systemImage: "square.grid.3x3")
                }
            } header: {
                Text("Classical")
            } footer: {
                Text("Applies the next time Launchpod opens.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    /// A number field with an attached stepper; typed values are clamped to the supported grid range.
    private func dimensionField(_ title: LocalizedStringKey, value: Binding<Int>, identifier: String) -> some View {
        let clamped = Binding {
            value.wrappedValue
        } set: {
            value.wrappedValue = ClassicalSpringboardGeometry.clampedDimension($0)
        }
        return HStack(spacing: Metrics.fieldToStepperSpacing) {
            TextField(title, value: clamped, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .focusEffectDisabled()
                .frame(width: Metrics.fieldWidth)
            Stepper(title, value: clamped, in: ClassicalGridPreference.range)
                .accessibilityIdentifier(identifier)
        }
        .labelsHidden()
    }

    private enum Metrics {
        static let fieldWidth: CGFloat = 44
        static let fieldToStepperSpacing: CGFloat = 4
    }
}
