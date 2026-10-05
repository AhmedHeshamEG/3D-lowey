import HmmDesign
import LoweyCore
import SwiftUI

/// The brush a drawing tool holds, drawing its sample stroke; tap for the brush library.
struct BrushRow: View {
    @Bindable var editor: EditorModel
    let tool: BrushTool
    @Environment(\.hmmTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let brush = editor.currentBrush(for: tool)
        Button {
            editor.brushTool = tool
            editor.sheet = .brushes
        } label: {
            HStack(spacing: HmmSpacing.s) {
                BrushPreviewImage(brushes: editor.app.brushes, brush: brush, width: 120, height: 36,
                                  color: colorScheme == .dark ? RGBA(0.93, 0.93, 0.94) : RGBA(0.11, 0.11, 0.12))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Brush").font(.hmm(.footnote)).foregroundStyle(theme.text2)
                    Text(brush.name).font(.hmm(.body, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(theme.text3)
            }
            .padding(HmmSpacing.xs)
            .background(theme.surface2, in: RoundedRectangle(cornerRadius: HmmRadius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Brush: \(brush.name)")
        .accessibilityIdentifier("brush-\(tool.rawValue)")
    }
}

/// A drawing guide's controls: which guide, Drawing Assist, and the guide's own settings. Flipbooks get every kind
/// on the frame; ink gets the ones that make sense on a 3D plane (the stage already draws in real perspective).
struct DrawingGuideControls: View {
    let guide: DrawingGuide?
    let kinds: [DrawingGuide.Kind]
    /// Grid sizes the slider offers, in the guide's units.
    let spacing: ClosedRange<Double>
    let formatSpacing: (Double) -> String
    let set: (DrawingGuide?) -> Void

    var body: some View {
        PanelSection("Drawing guide") {
            FlowChips(items: [("off", "Off")] + kinds.map { ($0.rawValue, $0.title) }, isOn: { $0 == (guide?.kind.rawValue ?? "off") }) { key in
                guard let kind = DrawingGuide.Kind(rawValue: key) else { return set(nil) }
                if guide?.kind != kind { set(kind == .perspective ? .perspective(points: 2) : DrawingGuide(kind: kind, spacing: spacing.lowerBound * 5)) }
            }
            .accessibilityIdentifier("drawing-guide")
            if let guide {
                Toggle("Drawing assist", isOn: Binding(get: { guide.assisted }, set: { value in change { $0.assisted = value } }))
                Hint(guide.kind == .symmetry ? "Every stroke is mirrored as you draw." : "Strokes straighten along the guide.")
                options(guide)
            }
        }
    }

    private func change(_ body: (inout DrawingGuide) -> Void) {
        guard var edited = guide else { return }
        body(&edited)
        set(edited)
    }

    @ViewBuilder private func options(_ guide: DrawingGuide) -> some View {
        switch guide.kind {
        case .grid, .isometric:
            LabeledSlider(title: "Grid size", value: guide.spacing, range: spacing, format: formatSpacing) { value in change { $0.spacing = value } }
            LabeledSlider(title: "Angle", value: guide.angle, range: -90 ... 90, format: { "\(Int($0.rounded()))°" }) { value in change { $0.angle = value } }
        case .perspective:
            PerspectiveOptions(guide: guide) { set($0) }
        case .symmetry:
            FlowChips(items: DrawingGuide.Symmetry.allCases.map { ($0.rawValue, $0.title) }, isOn: { $0 == guide.symmetry.rawValue }) { key in
                if let symmetry = DrawingGuide.Symmetry(rawValue: key) { change { $0.symmetry = symmetry } }
            }
            if guide.symmetry == .radial {
                Stepper(value: Binding(get: { guide.segments }, set: { value in change { $0.segments = value } }), in: 2 ... 24) {
                    Text("Segments: \(guide.segments)")
                }
                Toggle("Mirror each segment", isOn: Binding(get: { guide.mirrorRadial }, set: { value in change { $0.mirrorRadial = value } }))
            }
            LabeledSlider(title: "Angle", value: guide.angle, range: -90 ... 90, format: { "\(Int($0.rounded()))°" }) { value in change { $0.angle = value } }
        }
    }
}

/// Perspective: how many vanishing points, where the horizon is, how far apart the points are.
private struct PerspectiveOptions: View {
    let guide: DrawingGuide
    let set: (DrawingGuide) -> Void

    private var horizon: Double { guide.vanishingPoints.first?.y ?? 0.1 }
    private var spread: Double { guide.vanishingPoints.count > 1 ? abs(guide.vanishingPoints[0].x) : 0.9 }
    private var third: Double { guide.vanishingPoints.count > 2 ? guide.vanishingPoints[2].y : -1.6 }

    var body: some View {
        FlowChips(items: [("1", "1-point"), ("2", "2-point"), ("3", "3-point")], isOn: { $0 == String(guide.vanishingPoints.count) }) { key in
            if let count = Int(key) { set(points(count: count, horizon: horizon, spread: spread, third: third)) }
        }
        LabeledSlider(title: "Horizon", value: horizon, range: -0.5 ... 0.5, format: { NumberFormat.short($0) }) { value in
            set(points(count: guide.vanishingPoints.count, horizon: value, spread: spread, third: third))
        }
        if guide.vanishingPoints.count > 1 {
            LabeledSlider(title: "Points apart", value: spread, range: 0.2 ... 3, format: { NumberFormat.short($0) }) { value in
                set(points(count: guide.vanishingPoints.count, horizon: horizon, spread: value, third: third))
            }
        }
        if guide.vanishingPoints.count > 2 {
            LabeledSlider(title: "Third point", value: third, range: -4 ... -0.6, format: { NumberFormat.short($0) }) { value in
                set(points(count: 3, horizon: horizon, spread: spread, third: value))
            }
        }
    }

    private func points(count: Int, horizon: Double, spread: Double, third: Double) -> DrawingGuide {
        var edited = guide
        edited.vanishingPoints = switch count {
        case 1: [Vec2(0, horizon)]
        case 2: [Vec2(-spread, horizon), Vec2(spread, horizon)]
        default: [Vec2(-spread, horizon), Vec2(spread, horizon), Vec2(0, third)]
        }
        return edited
    }
}

extension DrawingGuide.Kind {
    var title: String {
        switch self {
        case .grid: "2D grid"
        case .isometric: "Isometric"
        case .perspective: "Perspective"
        case .symmetry: "Symmetry"
        }
    }
}

extension DrawingGuide.Symmetry {
    var title: String {
        switch self {
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        case .quadrant: "Quadrant"
        case .radial: "Radial"
        }
    }
}
