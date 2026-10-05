import HmmDesign
import LoweyCore
import SwiftUI

/// Model ▸ Snapping: the grid, faces snapping flush to other objects and the ground, turning in steps. Precision for
/// modelling lives here, with the units sizes are shown and typed in.
struct SnappingPage: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Toggle("Snap to grid", isOn: $editor.snap.grid)
                .accessibilityIdentifier("snap-grid")
            if editor.snap.grid {
                Picker("Grid size", selection: $editor.snap.gridSize) {
                    Text("1 cm").tag(0.01)
                    Text("10 cm").tag(0.1)
                    Text("25 cm").tag(0.25)
                    Text("50 cm").tag(0.5)
                    Text("1 m").tag(1.0)
                }
                .pickerStyle(.segmented)
            }
            Toggle("Snap to objects", isOn: $editor.snap.objects)
            Toggle("Snap to the ground", isOn: $editor.snap.ground)
            Toggle("Turn in steps", isOn: $editor.snap.rotation)
            if editor.snap.rotation {
                Picker("Step", selection: $editor.snap.rotationStep) {
                    Text("15°").tag(15.0)
                    Text("45°").tag(45.0)
                    Text("90°").tag(90.0)
                }
                .pickerStyle(.segmented)
            }
            Toggle("Grid on the ground", isOn: $editor.showsGrid)
                .accessibilityIdentifier("show-grid")
            Picker("Units", selection: $editor.units) {
                ForEach(LengthUnit.allCases, id: \.self) { unit in
                    Text(unit.symbol).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("units")
            Hint("This project remembers these. How close a face must be to snap is the sidebar's top slider.")
        }
        .font(.hmm(.body))
    }
}
