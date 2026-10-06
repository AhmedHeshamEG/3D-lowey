import HmmDesign
import LoweyCore
import SwiftUI

/// Paint ▸ Colour's quick options under the stage: what the Pencil does, the layer it paints on, and the picture being
/// placed (project it or put it away).
struct PaintOptionsBar: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            if editor.colourPaint.picture != nil {
                HmmPillButton("Project", systemName: "light.beacon.max") { editor.projectPicture() }
                    .disabled(editor.paintTarget?.paint == nil)
                    .accessibilityIdentifier("paint-project")
                HmmButton("xmark", label: "Put the picture away", size: 36) { editor.colourPaint.picture = nil }
            } else {
                ForEach(ColourPaintSettings.Mode.allCases) { mode in
                    ChoiceChip(title: mode.title, systemName: mode.systemImage, isOn: editor.colourPaint.mode == mode) {
                        editor.colourPaint.mode = mode
                    }
                }
                if let object = editor.paintTarget, let layer = editor.paintLayer(of: object) {
                    Text(layer.name).font(.hmm(.footnote, weight: .semibold)).foregroundStyle(theme.text2).lineLimit(1)
                        .padding(.horizontal, HmmSpacing.xs)
                }
                HmmButton("xmark", label: "Done painting", size: 36) { editor.tool = .select }
            }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground()
    }
}

/// The picture being placed over the stage: drag to move, pinch to size; see-through so the model shows under it.
struct PaintPictureOverlay: View {
    @Bindable var editor: EditorModel
    @State private var start: CGRect?

    var body: some View {
        if let picture = editor.colourPaint.picture {
            Image(decorative: picture.image, scale: 1)
                .resizable()
                .opacity(0.55)
                .frame(width: picture.rect.width, height: picture.rect.height)
                .position(x: picture.rect.midX, y: picture.rect.midY)
                .gesture(move.simultaneously(with: size))
                .accessibilityLabel("Picture to project")
                .accessibilityIdentifier("paint-picture")
        }
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let from = start ?? editor.colourPaint.picture?.rect ?? .zero
                start = from
                editor.colourPaint.picture?.rect.origin = CGPoint(x: from.minX + value.translation.width, y: from.minY + value.translation.height)
            }
            .onEnded { _ in start = nil }
    }

    private var size: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let from = start ?? editor.colourPaint.picture?.rect ?? .zero
                start = from
                let width = max(from.width * value.magnification, 40), height = max(from.height * value.magnification, 40)
                editor.colourPaint.picture?.rect = CGRect(x: from.midX - width / 2, y: from.midY - height / 2, width: width, height: height)
            }
            .onEnded { _ in start = nil }
    }
}
