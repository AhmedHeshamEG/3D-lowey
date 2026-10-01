import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// Transform: move, turn or size with the gizmo; snapping; the grid; arranging several things; the joystick.
struct TransformPanel: View {
    @Bindable var editor: EditorModel
    @AppStorage(AppSettings.showsJoystick) private var showsJoystick = false
    @AppStorage(AppSettings.joystickSpeed) private var joystickSpeed = 1.0

    var body: some View {
        HmmPanel("Transform", width: 340, close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                HStack(spacing: HmmSpacing.xs) {
                    ForEach(GizmoMode.allCases, id: \.self) { mode in
                        ChoiceChip(title: Self.title(mode), systemName: Self.icon(mode), isOn: editor.gizmoMode == mode) {
                            editor.tool = .select
                            editor.gizmoMode = mode
                        }
                        .accessibilityIdentifier("gizmo-\(mode.rawValue)")
                    }
                }
                Hint("Drag a handle, or drag the object itself across the ground. Two fingers on it: twist turns, pinch sizes.")
                PanelSection("Snapping") {
                    Toggle("Snap to grid", isOn: $editor.snap.grid)
                    if editor.snap.grid {
                        Picker("Grid size", selection: $editor.snap.gridSize) {
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
                }
                if editor.selection.count > 1 { ArrangeSection(editor: editor) }
                if !editor.selection.isEmpty {
                    HmmPillButton("Drop to the ground", systemName: "arrow.down.to.line") { editor.dropSelectionToGround() }
                }
                PanelSection("Joystick") {
                    Toggle("Show the joystick under a selection", isOn: $showsJoystick)
                    if showsJoystick {
                        LabeledSlider(title: "Joystick speed", value: joystickSpeed, range: AppSettings.joystickSpeedRange,
                                      format: { String(format: "%.2g×", $0) }) { joystickSpeed = $0 }
                    }
                }
            }
            .font(.hmm(.body))
        }
    }

    static func title(_ mode: GizmoMode) -> String {
        switch mode {
        case .move: "Move"
        case .rotate: "Turn"
        case .scale: "Size"
        }
    }

    static func icon(_ mode: GizmoMode) -> String {
        switch mode {
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .rotate: "arrow.triangle.2.circlepath"
        case .scale: "arrow.up.left.and.arrow.down.right"
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
