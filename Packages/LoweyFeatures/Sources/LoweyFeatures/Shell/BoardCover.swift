import HmmBoard
import HmmBoardUI
import HmmDesign
import LoweyCore
import SwiftUI

/// The project's Schizzo board over the stage (hmm-kit's `HmmBoardScreen`), with what Maquette brings to it: the
/// brush in the hand from the brush library, the Look's palette in the colour chooser, and the Pencil settings.
struct BoardCover: View {
    @Bindable var editor: EditorModel
    let board: BoardModel
    @AppStorage(AppSettings.pencilHoverPreview) private var pencilHover = false
    @AppStorage(AppSettings.sidebarOnRight) private var sidebarOnRight = false
    @AppStorage(HmmPencilOrHand.fingersAlwaysMakeKey) private var fingersMake = false

    var body: some View {
        HmmBoardScreen(model: board, showsHover: pencilHover, sidebarOnRight: sidebarOnRight, close: { editor.closeBoard() }) {
            BrushRow(editor: editor, tool: .board)
                .frame(width: 300)
                .padding(HmmSpacing.xxs)
                .hmmPanelBackground(cornerRadius: HmmRadius.card)
        } colours: { colour in
            BoardColours(editor: editor, colour: colour)
        }
        .onChange(of: editor.currentBrush(for: .board), initial: true) { _, brush in
            board.mutate { $0.brush = brush }
        }
        .onChange(of: fingersMake, initial: true) { _, makes in
            board.pencilOrHand.fingersAlwaysMake = makes
        }
    }
}

/// The board's colour chooser: the Look's palette and any colour.
private struct BoardColours: View {
    let editor: EditorModel
    @Binding var colour: Color

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HmmSectionHeader("Colour")
            PaletteRow(palette: editor.look.palette, selected: nil) { index in
                colour = editor.look.palette.swatches[index].color.color
            }
            ColorPicker("Any colour", selection: $colour, supportsOpacity: false)
                .accessibilityIdentifier("board-any-colour")
        }
    }
}
