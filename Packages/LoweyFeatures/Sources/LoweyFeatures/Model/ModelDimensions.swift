import HmmDesign
import LoweyCore
import SwiftUI

/// The numbers floating beside what the Model tool measures: the push/pull distance, the sides of the rectangle just
/// drawn, a circle's diameter, a line's length. Tap one to type an exact length (`25`, `2*12`, `1.5 cm`).
struct ModelDimensions: View {
    let editor: EditorModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(editor.dimensionLabels) { label in
                DimensionChip(editor: editor, label: label)
                    .position(label.point)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DimensionChip: View {
    let editor: EditorModel
    let label: DimensionLabel
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.hmmTheme) private var theme

    private var editing: Bool { editor.modeling.editing == label.field }

    var body: some View {
        Group {
            if editing {
                // Empty, with the current size as its placeholder: what you type replaces it.
                TextField(label.text, text: $text)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                    .onSubmit { editor.submitDimension(label.field, text: text) }
                    .frame(width: 110)
                    .accessibilityIdentifier("dimension-field")
                    .onAppear {
                        text = ""
                        focused = true
                    }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused, editing { editor.modeling.editing = nil }
                    }
            } else {
                Button {
                    HmmHaptics.play(.selection)
                    if !editor.dimensionTapped(label.field) { editor.modeling.editing = label.field }
                } label: {
                    Text(label.text).monospacedDigit()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dimension-\(Self.identifier(label.field))")
                .accessibilityLabel(Text(label.text))
                .accessibilityHint(Self.hint(label.field))
            }
        }
        .font(.hmm(.footnote, weight: .semibold))
        .padding(.horizontal, HmmSpacing.s)
        .frame(minHeight: 32)
        .background(Capsule().fill(editing ? theme.surface : theme.accent))
        .foregroundStyle(editing ? theme.text : theme.onAccent)
        .contentShape(Capsule())
    }

    static func identifier(_ field: DimensionField) -> String {
        switch field {
        case .pull: "pull"
        case .rectangleSide(true): "width"
        case .rectangleSide(false): "depth"
        case .diameter: "diameter"
        case .lineLength: "length"
        case .offset: "offset"
        case .shapeAmount: "shape-size"
        case .measured: "measured"
        case let .kept(id): "kept-\(id.raw)"
        case .wallHeight: "wall-height"
        case .wallThickness: "wall-thickness"
        }
    }

    static func hint(_ field: DimensionField) -> Text {
        switch field {
        case .measured: Text("Keep this measurement on the stage")
        case .kept: Text("Select this dimension")
        default: Text("Type an exact length")
        }
    }
}
