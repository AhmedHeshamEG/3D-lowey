import HmmDesign
import LoweyCore
import SwiftUI

/// The selection's size in the project's units (width × height × depth of its bounds), and what the Model tool has
/// picked on it ("Face · 800 mm²").
struct SizeSection: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        if let size = editor.selectionSizeText {
            VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                HStack {
                    Text("Size").foregroundStyle(theme.text2)
                    Spacer()
                    Text(size).monospacedDigit()
                        .accessibilityIdentifier("selection-size")
                }
                if let pick = editor.pickSummary {
                    HStack {
                        Text("Picked").foregroundStyle(theme.text2)
                        Spacer()
                        Text(pick).monospacedDigit()
                            .accessibilityIdentifier("pick-summary")
                    }
                }
            }
            .font(.hmm(.body))
        }
    }
}
