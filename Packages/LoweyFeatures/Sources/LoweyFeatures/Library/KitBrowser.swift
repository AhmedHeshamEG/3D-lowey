import HmmDesign
import LoweyCore
import SwiftUI

/// The Kit by Set: pick a Set (Room & Desk, City Street…), then its categories, 16 tiles each until you ask for the
/// rest. Tap to place, drag onto the stage.
struct KitBrowser: View {
    @Bindable var editor: EditorModel
    @Binding var selectedSet: String?
    @Binding var expanded: Set<String>
    @Environment(\.hmmTheme) private var theme

    private var library: LibraryModel { editor.library }

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            FlowChips(items: library.kitSets.map { kitSet in (kitSet.name, kitSet.name) }, isOn: { $0 == currentSet }) { name in
                selectedSet = name
            }
            .accessibilityIdentifier("kit-sets")
            ForEach(library.browse(currentSet ?? ""), id: \.category) { group in
                section(group.category, assets: group.assets)
            }
            Hint("The Kit: CC0 models by Kenney and Quaternius, real-world size, ready for every Look. Search finds them too.")
        }
    }

    private var currentSet: String? { selectedSet ?? library.kitSets.first?.name }

    private func section(_ category: String, assets: [LibraryAsset]) -> some View {
        let key = "\(currentSet ?? "")/\(category)"
        let shown = expanded.contains(key) ? assets : Array(assets.prefix(16))
        return PanelSection(category) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: HmmSpacing.s)], spacing: HmmSpacing.s) {
                ForEach(shown) { asset in
                    let item = LibraryItem.asset(asset)
                    LibraryTile(item: item, thumbnail: library.thumbnail(for: item))
                        .onAppear { library.requestThumbnail(for: item) }
                        .onTapGesture {
                            HmmHaptics.play(.commit)
                            editor.place(item)
                        }
                        .draggable(item.id)
                }
            }
            if assets.count > 16, !expanded.contains(key) {
                HmmPillButton("Show all \(assets.count)", systemName: "chevron.down") { expanded.insert(key) }
            }
        }
    }
}
