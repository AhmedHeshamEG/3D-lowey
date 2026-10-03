import HmmDesign
import LoweyCore
import SwiftUI

/// Draw ▸ Ink: Pencil strokes in 3D that always face the camera. Draw, erase, or pick strokes to move, smooth,
/// thicken or delete them; a drawing can write itself on.
struct InkSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HStack(spacing: HmmSpacing.xs) {
                ForEach(InkMode.allCases) { mode in
                    ChoiceChip(title: mode.title, systemName: mode.systemImage, isOn: editor.ink.mode == mode) { editor.ink.mode = mode }
                        .accessibilityIdentifier("ink-\(mode.rawValue)")
                }
            }
            switch editor.ink.mode {
            case .draw:
                GuideSection(editor: editor)
                LabeledSlider(title: "Smoothing", value: editor.ink.smoothing, range: 0 ... 1) { editor.ink.smoothing = $0 }
                Hint(drawHint)
            case .erase:
                LabeledSlider(title: "Eraser size", value: editor.ink.eraserRadius, range: 4 ... 60,
                              format: { "\(Int($0.rounded())) pt" }) { editor.ink.eraserRadius = $0 }
                Hint(editor.activeInk.map { "Erases “\($0.name)” only." } ?? "Rub out ink with the Pencil.")
            case .select:
                picked
            }
            if editor.activeInk != nil {
                HmmPillButton("Write it on from the playhead", systemName: "signature") { editor.writeOnInk() }
            }
            Hint("Width and opacity are the sidebar's sliders.")
        }
        .font(.hmm(.body))
    }

    private var drawHint: String {
        if let active = editor.activeInk {
            return "Strokes join “\(active.name)”. Tap empty space to start a new drawing."
        }
        return "Your first stroke starts a new ink drawing; the next ones join it. Tap empty space to start another."
    }

    @ViewBuilder private var picked: some View {
        if editor.inkStrokes.isEmpty {
            Hint("Tap a stroke or draw a loop around strokes with the Pencil. Then drag them, or change them here.")
        } else {
            Text(editor.inkStrokes.count == 1 ? "1 stroke" : "\(editor.inkStrokes.count) strokes")
                .font(.hmm(.body, weight: .semibold))
            HStack(spacing: HmmSpacing.xs) {
                HmmButton("wand.and.rays", label: "Smooth", size: 40) { editor.smoothInkStrokes() }
                HmmButton("minus.circle", label: "Thinner", size: 40) { editor.scaleInkStrokes(by: 0.75) }
                HmmButton("plus.circle", label: "Thicker", size: 40) { editor.scaleInkStrokes(by: 1.33) }
                HmmButton("trash", label: "Delete strokes", size: 40, role: .destructive) { editor.deleteInkStrokes() }
                HmmButton("xmark", label: "Done", size: 40) { editor.inkStrokes = [] }
            }
        }
    }
}

/// What strokes are drawn on: a plane (facing me, ground, front, side), a box, cylinder or sphere, or an object.
struct GuideSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        PanelSection("Draws on") {
            FlowChips(items: GuideKind.allCases.map { ($0.rawValue, $0.title) }, isOn: { $0 == editor.draw.guide.rawValue }) { key in
                if let kind = GuideKind(rawValue: key) { editor.draw.guide = kind }
            }
            if editor.draw.guide == .plane {
                FlowChips(items: PlaneLock.allCases.map { ($0.rawValue, $0.title) }, isOn: { $0 == editor.draw.planeLock.rawValue }) { key in
                    if let lock = PlaneLock(rawValue: key) { editor.draw.planeLock = lock }
                }
                LabeledSlider(title: "Plane offset", value: editor.draw.planeOffset, range: -3 ... 3) { editor.draw.planeOffset = $0 }
            } else if editor.draw.guide != .object {
                LabeledSlider(title: "Guide size", value: editor.draw.guideSize, range: 0.3 ... 6) { editor.draw.guideSize = $0 }
            }
        }
    }
}

/// The ink tool's quick options at the bottom of the stage.
struct InkOptionsBar: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(InkMode.allCases) { mode in
                ChoiceChip(title: mode.title, systemName: mode.systemImage, isOn: editor.ink.mode == mode) { editor.ink.mode = mode }
            }
            HmmButton("xmark", label: "Done drawing", size: 36) { editor.tool = .select }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground()
    }
}
