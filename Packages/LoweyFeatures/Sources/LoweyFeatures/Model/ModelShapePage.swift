import HmmDesign
import LoweyCore
import SwiftUI

/// Model ▸ Shape: sketch on any surface, pick faces / edges / corners to push and pull, combine solids. Choosing a
/// sketch shape or a pick mode closes the panel so the stage is free; the bar at the bottom holds the rest.
struct ModelShapePage: View {
    let editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            PanelSection("Sketch") {
                TileGrid {
                    ForEach(SketchKind.allCases) { kind in
                        TileButton(title: kind.title, systemName: kind.systemImage, identifier: "sketch-\(kind.rawValue)") {
                            start(.sketch(kind))
                        }
                    }
                }
                Hint("Tap on a face or the ground. Closed shapes fill; tap one and drag it up into a solid, or into a face to cut.")
            }
            PanelSection("Push & pull") {
                TileGrid {
                    ForEach(MeshSelection.Mode.allCases.reversed(), id: \.self) { mode in
                        TileButton(title: mode.label, systemName: Self.icon(for: mode), identifier: "pick-\(mode.rawValue)") {
                            start(.pick(mode))
                        }
                    }
                }
                Hint("Tap a face and drag it. Tap the number to type an exact size, like 25 or 2*12.")
            }
            PanelSection("Combine") {
                HStack(spacing: HmmSpacing.xs) {
                    ForEach(MeshBoolean.Operation.allCases, id: \.self) { operation in
                        HmmPillButton(operation.label, systemName: Self.icon(for: operation)) { editor.combineSelection(operation) }
                            .accessibilityIdentifier("boolean-\(operation.rawValue)")
                    }
                }
                .disabled(editor.modelableSelection.count < 2)
                Hint("Select two or more shapes (touch and hold adds one). The first one keeps its look and place.")
            }
            if editor.convertibleSelection != nil {
                HmmPillButton("Make editable", systemName: "cube.transparent") { editor.makeSelectionEditable() }
                    .accessibilityIdentifier("make-editable")
            }
        }
    }

    private func start(_ mode: ModelingMode) {
        editor.startModeling(mode)
        editor.openPanel = nil
    }

    static func icon(for mode: MeshSelection.Mode) -> String {
        switch mode {
        case .face: "square.fill"
        case .edge: "line.diagonal"
        case .vertex: "smallcircle.filled.circle"
        }
    }

    static func icon(for operation: MeshBoolean.Operation) -> String {
        switch operation {
        case .union: "square.on.square"
        case .subtract: "square.on.square.dashed"
        case .intersect: "square.on.square.intersection.dashed"
        }
    }
}

/// The Model tool's bar at the bottom of the stage: pick modes, sketch shapes, and what the current pick can do.
struct ModelOptionsBar: View {
    let editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(MeshSelection.Mode.allCases.reversed(), id: \.self) { mode in
                HmmButton(ModelShapePage.icon(for: mode), label: mode.label, isOn: editor.modeling.mode == .pick(mode), size: 36) {
                    editor.startModeling(.pick(mode))
                }
            }
            Divider().frame(height: 24)
            ForEach(SketchKind.allCases) { kind in
                HmmButton(kind.systemImage, label: kind.title, isOn: editor.modeling.mode == .sketch(kind), size: 36) {
                    editor.startModeling(.sketch(kind))
                }
            }
            if editor.modeling.pending != nil {
                HmmButton("checkmark", label: "Done", size: 36) { editor.finishSketchShape() }
            }
            if editor.modeling.elements.map({ !$0.isEmpty }) == true {
                Divider().frame(height: 24)
                HmmButton("plus.magnifyingglass", label: "Grow", size: 36) { editor.growPick() }
                HmmButton("minus.magnifyingglass", label: "Shrink", size: 36) { editor.shrinkPick() }
                HmmButton("square.grid.3x3.square", label: "Select similar", size: 36) { editor.selectSimilar() }
            }
            HmmButton("xmark", label: "Done modelling", size: 36) { editor.stopModeling() }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground()
    }
}
