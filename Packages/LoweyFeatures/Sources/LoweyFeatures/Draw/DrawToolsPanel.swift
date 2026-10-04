import HmmDesign
import LoweyCore
import SwiftUI

/// Draw: ink strokes and solid shapes in 3D on a guide, and the Shadow Brush. The Pencil draws, fingers keep moving
/// the view.
struct DrawToolsPanel: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HmmPanel("Draw", width: 360, close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                HStack(spacing: HmmSpacing.xs) {
                    ChoiceChip(title: "Ink", systemName: "pencil.tip", isOn: editor.tool == .ink) { editor.tool = .ink }
                        .accessibilityIdentifier("tool-ink")
                    ChoiceChip(title: "Solid shape", systemName: "scribble.variable", isOn: editor.tool == .draw) { editor.tool = .draw }
                        .accessibilityIdentifier("tool-draw")
                    ChoiceChip(title: "Flipbook", systemName: "book.pages", isOn: editor.tool == .flipbook) { editor.tool = .flipbook }
                        .accessibilityIdentifier("tool-flipbook")
                    ChoiceChip(title: "Shadow Brush", systemName: "circle.lefthalf.striped.horizontal", isOn: editor.tool == .shadowBrush) {
                        editor.tool = .shadowBrush
                    }
                    .accessibilityIdentifier("tool-shadow-brush")
                }
                switch editor.tool {
                case .shadowBrush: shadowBrush
                case .draw: solidShape
                case .flipbook: FlipbookSection(editor: editor)
                default: InkSection(editor: editor)
                }
            }
        }
        .onAppear { if !editor.tool.paints { editor.tool = .ink } }
    }

    private var solidShape: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            PanelSection("Becomes") {
                TileGrid(minimum: 74) {
                    ForEach(DrawingRecipe.Style.solid, id: \.self) { style in
                        TileButton(title: style.title, systemName: style.systemImage) { editor.draw.style = style }
                            .overlay(RoundedRectangle(cornerRadius: HmmRadius.card).stroke(Color.accentColor, lineWidth: editor.draw.style == style ? 2 : 0))
                    }
                }
                Hint(editor.draw.style.hint)
            }
            GuideSection(editor: editor)
            if editor.draw.style == .extrude {
                LabeledSlider(title: "Depth", value: editor.draw.extrudeDepth, range: 0.02 ... 3) { editor.draw.extrudeDepth = $0 }
            }
            Toggle("Mirror", isOn: $editor.draw.mirror)
            Toggle("Draw with a finger too", isOn: Binding(get: { !editor.draw.pencilOnly }, set: { editor.draw.pencilOnly = !$0 }))
            Hint("Width and smoothing are the sidebar's sliders. Draw, then hold: the stroke snaps to a clean line, circle or rectangle.")
        }
        .font(.hmm(.body))
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

/// The solid-shape tool's quick options at the bottom of the stage.
struct DrawOptionsBar: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(DrawingRecipe.Style.solid, id: \.self) { style in
                ChoiceChip(title: style.title, systemName: style.systemImage, isOn: editor.draw.style == style) { editor.draw.style = style }
            }
            HmmButton("arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Mirror", isOn: editor.draw.mirror, size: 36) {
                editor.draw.mirror.toggle()
            }
            HmmButton("xmark", label: "Done drawing", size: 36) { editor.tool = .select }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground()
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

extension DrawingRecipe.Style {
    /// The solid-shape styles (ink has its own tool).
    static let solid: [DrawingRecipe.Style] = [.tube, .ribbon, .extrude, .lathe]

    var title: String {
        switch self {
        case .tube: "Tube"
        case .ribbon: "Ribbon"
        case .extrude: "Extrude"
        case .lathe: "Lathe"
        case .ink: "Ink"
        }
    }

    var systemImage: String {
        switch self {
        case .tube: "scribble.variable"
        case .ribbon: "wave.3.right"
        case .extrude: "square.stack.3d.up"
        case .lathe: "rotate.3d"
        case .ink: "pencil.tip"
        }
    }

    var hint: String {
        switch self {
        case .tube: "Lines become round tubes."
        case .ribbon: "Flat strips on the surface."
        case .extrude: "Draw a closed outline: it becomes a solid."
        case .lathe: "Draw half a profile: it spins into a vase, a trunk or a tower."
        case .ink: "Pencil lines in 3D that always face the camera."
        }
    }
}
