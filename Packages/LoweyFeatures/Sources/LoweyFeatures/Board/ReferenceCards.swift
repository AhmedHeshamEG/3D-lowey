import HmmDesign
import LoweyCore
import SwiftUI

/// Pictures pinned from the Schizzo board, floating over the stage beside the model (CONTEXT §10.7). Drag a card to
/// move it, its corner to size it; touch and hold for its menu.
struct ReferenceCards: View {
    @Bindable var editor: EditorModel

    var body: some View {
        GeometryReader { geometry in
            ForEach(editor.references) { card in
                ReferenceCardView(editor: editor, card: card, stage: geometry.size)
            }
        }
    }
}

private struct ReferenceCardView: View {
    let editor: EditorModel
    let card: ReferenceCard
    let stage: CGSize
    @State private var picture: UIImage?
    @State private var moved = CGSize.zero
    @State private var widthWhileSizing: Double?
    @Environment(\.hmmTheme) private var theme

    private var width: Double { widthWhileSizing ?? card.width }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous) }

    var body: some View {
        content
            .frame(width: width, height: width * card.aspect)
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            .overlay(alignment: .bottomTrailing) { grip }
            .contentShape(shape)
            .hmmHoldMenu(menu)
            .gesture(move)
            .position(x: card.x * stage.width + moved.width, y: card.y * stage.height + moved.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.title.isEmpty ? Text("Reference") : Text(verbatim: card.title))
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("reference-card")
            .task(id: card.image) {
                picture = UIImage(contentsOfFile: editor.referenceURL(card).path)
            }
    }

    @ViewBuilder private var content: some View {
        if let picture {
            Image(uiImage: picture)
                .resizable()
                .interpolation(.high)
        } else {
            theme.surface2
        }
    }

    /// The corner that sizes the card.
    private var grip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.text)
            .frame(width: 28, height: 28)
            .background(theme.surface.opacity(0.85), in: Circle())
            .frame(width: HmmTarget.minimum, height: HmmTarget.minimum)
            .contentShape(Rectangle())
            .gesture(size)
            .accessibilityLabel("Resize")
            .accessibilityIdentifier("reference-card-resize")
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                moved = value.translation
            }
            .onEnded { value in
                var next = card
                next.x = card.x + value.translation.width / max(stage.width, 1)
                next.y = card.y + value.translation.height / max(stage.height, 1)
                moved = .zero
                editor.updateReference(next)
            }
    }

    private var size: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                widthWhileSizing = Self.sized(card.width, by: value.translation.width)
            }
            .onEnded { value in
                var next = card
                next.width = Self.sized(card.width, by: value.translation.width)
                widthWhileSizing = nil
                editor.updateReference(next)
            }
    }

    private static func sized(_ width: Double, by drag: Double) -> Double {
        min(max(width + drag, ReferenceCard.widthRange.lowerBound), ReferenceCard.widthRange.upperBound)
    }

    /// The hold menu, in the one grammar: a pinned picture can't be duplicated, renamed, copied or pasted over, so
    /// those rows are dimmed; its own two actions; Delete takes it off the stage.
    private var menu: HmmHoldMenu {
        HmmHoldMenu(extras: [
            HmmHoldMenu.Item("Open the board", id: "reference-open-board", systemName: "scribble.variable") { editor.openBoard() },
            HmmHoldMenu.Item("Stand it in the scene", id: "reference-stand", systemName: "photo.on.rectangle") { editor.standReferenceInScene(card) }
        ], delete: { editor.removeReference(card.id) })
    }
}
