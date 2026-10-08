import HmmDesign
import LoweyCore
import SwiftUI

/// The colour in the hand: the Look's palette (a slot follows the palette when it changes) and any colour at all.
/// One chooser for Paint ▸ Colour and the sidebar's colour well, so every tool picks colour the same way.
struct ColourChooser: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.s) {
            PaletteRow(palette: editor.look.palette, selected: editor.currentColor.paletteSlot) { editor.currentColor = .palette($0) }
            ColorPicker("Any colour", selection: anyColour, supportsOpacity: false).labelsHidden()
                .accessibilityIdentifier("any-colour")
        }
    }

    private var anyColour: Binding<Color> {
        Binding(get: { editor.paintColor.color }, set: { value in
            let resolved = UIColor(value).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            editor.currentColor = .rgba(RGBA(Double(red), Double(green), Double(blue)))
        })
    }
}

/// The sidebar's colour well (CONTEXT §4.1): under the two sliders while a tool that puts colour down is in the hand.
struct SidebarColourWell: View {
    @Bindable var editor: EditorModel
    @State private var choosing = false

    var body: some View {
        HmmColourWell(editor.paintColor.color) { choosing = true }
            .popover(isPresented: $choosing) {
                VStack(alignment: .leading, spacing: HmmSpacing.s) {
                    HmmSectionHeader("Colour")
                    ColourChooser(editor: editor)
                }
                .padding(HmmSpacing.m)
                .frame(width: 300)
                .presentationCompactAdaptation(.popover)
                .accessibilityIdentifier("colour-chooser")
            }
    }
}
