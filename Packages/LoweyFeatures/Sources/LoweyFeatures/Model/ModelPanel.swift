import HmmDesign
import LoweyCore
import SwiftUI

/// Model: everything that goes into the world (shapes, lights, cameras, words, effects, buildings), shaping it
/// (sketches, push/pull, booleans, bevels, shells, symmetry, printing), the library of models, and precision (snapping,
/// units, measuring, the section view).
struct ModelPanel: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HmmPanel(isSwapping ? "Swap for…" : "Model", width: 380, sizing: HmmPanelSizing(id: "model"), close: close) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                if !isSwapping { pages }
                switch isSwapping ? ModelPage.library : editor.modelPage {
                case .add: ModelAddPage(editor: editor)
                case .shape: ModelShapePage(editor: editor)
                case .library: LibraryBrowser(editor: editor)
                case .precision: PrecisionPage(editor: editor)
                }
            }
        }
    }

    private var pages: some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(ModelPage.allCases) { page in
                ChoiceChip(title: page.title, systemName: page.systemImage, isOn: editor.modelPage == page) {
                    withHmmAnimation(.snappy) { editor.modelPage = page }
                }
                .accessibilityIdentifier("model-\(page.rawValue)")
            }
        }
    }

    private var isSwapping: Bool {
        if case .swap = editor.libraryPurpose { return true }
        return false
    }

    private func close() {
        editor.openPanel = nil
        editor.libraryPurpose = .place
    }
}
