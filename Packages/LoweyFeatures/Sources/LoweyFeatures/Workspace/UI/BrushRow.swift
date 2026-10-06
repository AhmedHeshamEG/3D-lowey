import HmmDesign
import LoweyCore
import SwiftUI

/// The brush a drawing or painting tool holds, drawing its sample stroke; tap for the brush library.
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

/// A brush drawing its sample stroke (drawn by the brush engine, cached by the brush model).
struct BrushPreviewImage: View {
    let brushes: BrushModel
    let brush: Brush
    let width: Double
    let height: Double
    let color: RGBA
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // Reading the revision redraws the picture when a brush changes.
        let revision = brushes.revision
        Group {
            if revision >= 0, let image = brushes.preview(brush, width: width, height: height, color: color, scale: displayScale) {
                Image(decorative: image, scale: displayScale)
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}
