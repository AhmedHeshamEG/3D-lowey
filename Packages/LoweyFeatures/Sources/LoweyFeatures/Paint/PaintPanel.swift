import HmmDesign
import LoweyCore
import SwiftUI

/// Paint: on objects and over the ground. The Shadow Brush paints where an object's toon shadow falls; Scatter paints
/// copies of the selection across the ground. Colour painting on models joins them with the brush engine.
struct PaintPanel: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HmmPanel("Paint", width: 360, sizing: HmmPanelSizing(id: "paint"), close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                HStack(spacing: HmmSpacing.xs) {
                    ChoiceChip(title: "Shadow Brush", systemName: "circle.lefthalf.striped.horizontal", isOn: editor.tool == .shadowBrush) {
                        editor.tool = .shadowBrush
                    }
                    .accessibilityIdentifier("tool-shadow-brush")
                    ChoiceChip(title: "Scatter", systemName: "circle.hexagongrid", isOn: editor.tool == .scatter) { editor.tool = .scatter }
                        .accessibilityIdentifier("tool-scatter")
                }
                if editor.tool == .scatter { scatter } else { shadowBrush }
            }
        }
        .onAppear { if !editor.tool.paintsSurfaces { editor.tool = .shadowBrush } }
    }

    @ViewBuilder private var scatter: some View {
        if editor.selection.isEmpty {
            Hint("Select what to scatter first (a tree, a rock…), then drag an area on the ground.")
        } else {
            Hint("Drag on the ground: copies of the selection fill the area. How many, size variety and spacing are below the stage.")
        }
    }

    private var shadowBrush: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HStack(spacing: HmmSpacing.xs) {
                ChoiceChip(title: "Push shadow in", systemName: "circle.lefthalf.filled", isOn: editor.shadowBrush.pushesShadow) {
                    editor.shadowBrush.pushesShadow = true
                }
                ChoiceChip(title: "Pull light out", systemName: "sun.max", isOn: !editor.shadowBrush.pushesShadow) {
                    editor.shadowBrush.pushesShadow = false
                }
            }
            Hint("Paint on an object with the Pencil: its toon shadow follows your strokes (faces get clean, designed shadow shapes). "
                + "Size and strength are the sidebar's sliders. Each stroke is one undo step.")
            PanelSection("Presets") {
                FlowChips(items: ShadowPreset.allCases.map { preset in (preset.rawValue, preset.title) }, isOn: { _ in false }) { key in
                    if let preset = ShadowPreset(rawValue: key) { editor.applyShadowPreset(preset) }
                }
                Hint("On the selection; a character's goes on its head.")
            }
            if editor.selectionHasShadowPaint {
                HmmPillButton("Clear the selection's shadow painting", systemName: "eraser", role: .destructive) { editor.clearShadowPaint() }
            }
        }
    }
}

/// The Shadow Brush's quick options.
struct ShadowBrushOptionsBar: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            ChoiceChip(title: "Shadow in", systemName: "circle.lefthalf.filled", isOn: editor.shadowBrush.pushesShadow) {
                editor.shadowBrush.pushesShadow = true
            }
            ChoiceChip(title: "Light out", systemName: "sun.max", isOn: !editor.shadowBrush.pushesShadow) { editor.shadowBrush.pushesShadow = false }
            HmmButton("xmark", label: "Done painting shadows", size: 36) { editor.tool = .select }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground()
    }
}

/// Scatter options while the Scatter tool is on.
struct ScatterOptionsBar: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.m) {
            LabeledSlider(title: "How many", value: Double(editor.scatter.count), range: 3 ... 150, format: { "\(Int($0))" }) {
                editor.scatter.count = Int($0)
            }
            .frame(width: 180)
            LabeledSlider(title: "Size variety", value: editor.scatter.scaleVariation, range: 0 ... 0.6, format: NumberFormat.percent) {
                editor.scatter.scaleVariation = $0
            }
            .frame(width: 150)
            LabeledSlider(title: "Spacing", value: editor.scatter.spacing, range: 0 ... 2) { editor.scatter.spacing = $0 }
                .frame(width: 150)
            HmmButton("xmark", label: "Done scattering", size: 36) { editor.tool = .select }
        }
        .padding(HmmSpacing.s)
        .hmmPanelBackground()
        .overlay(alignment: .top) {
            Text(editor.selection.isEmpty ? "Select something to scatter" : "Drag on the ground to paint an area")
                .font(.hmm(.caption, weight: .semibold))
                .foregroundStyle(editor.selection.isEmpty ? theme.danger : theme.text2)
                .offset(y: -18)
        }
    }
}
