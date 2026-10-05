import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// Move, turn or size with the gizmo (the joystick follows the same choice).
struct GizmoModeRow: View {
    let editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(GizmoMode.allCases, id: \.self) { mode in
                ChoiceChip(title: mode.title, systemName: mode.systemImage, isOn: editor.gizmoMode == mode) {
                    editor.tool = .select
                    editor.gizmoMode = mode
                }
                .accessibilityIdentifier("gizmo-\(mode.rawValue)")
            }
        }
    }
}

/// Align and distribute several things.
struct ArrangeSection: View {
    let editor: EditorModel

    var body: some View {
        PanelSection("Align") {
            HStack(spacing: HmmSpacing.xs) {
                ForEach(CoreAxis.allCases, id: \.self) { axis in
                    Menu {
                        Button("Min") { editor.align(axis, .min) }
                        Button("Centre") { editor.align(axis, .center) }
                        Button("Max") { editor.align(axis, .max) }
                        Button("Distribute evenly") { editor.distribute(axis) }
                    } label: {
                        Text(axis.rawValue.uppercased())
                            .font(.hmm(.body, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .accessibilityLabel("Align along \(axis.rawValue)")
                }
            }
        }
    }
}
