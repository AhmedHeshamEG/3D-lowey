import HmmDesign
import LoweyCore
import SwiftUI
import UIKit

/// Search first, browse second: your models, builds, worlds and scripts. Tap to place, drag onto the stage, touch and
/// hold for options.
struct LibraryPanel: View {
    @Bindable var editor: EditorModel
    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @State private var importing = false
    @State private var editingItem: LibraryItem?
    @State private var editName = ""
    @State private var editTags = ""
    @Environment(\.hmmTheme) private var theme

    private var library: LibraryModel { editor.library }

    var body: some View {
        HmmPanel(isSwapping ? "Swap for…" : "Library", width: 400, close: close) {
            VStack(alignment: .leading, spacing: HmmSpacing.s) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.text2)
                    TextField("Search: tree, desk, robot…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("library-search")
                    HmmButton("square.and.arrow.down", label: "Import models", size: 36) { importing = true }
                }
                .padding(.horizontal, HmmSpacing.s)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: HmmRadius.control, style: .continuous).fill(theme.surface2))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HmmSpacing.xs) {
                        ForEach(isSwapping ? [.models, .favorites, .recent] : LibraryFilter.allCases, id: \.self) { item in
                            ChoiceChip(title: item.displayName, isOn: filter == item) { filter = item }
                        }
                    }
                }
                if library.importing > 0 {
                    Label("Importing \(library.importing)…", systemImage: "arrow.down.circle").font(.hmm(.footnote)).foregroundStyle(theme.text2)
                }
                if results.isEmpty {
                    HmmEmptyState(query.isEmpty ? "shippingbox" : "questionmark.folder",
                                  title: query.isEmpty ? "Your library is empty" : "Nothing called “\(query)” yet",
                                  message: "Import USDZ, glTF, GLB or OBJ models (a whole folder works), or build something and Save to library.",
                                  actionTitle: "Import models") { importing = true }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: HmmSpacing.s)], spacing: HmmSpacing.s) {
                        ForEach(results) { item in
                            LibraryTile(item: item, thumbnail: library.thumbnail(for: item))
                                .onTapGesture {
                                    HmmHaptics.play(.commit)
                                    editor.place(item)
                                }
                                .draggable(item.id)
                                .contextMenu { menu(for: item) }
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: LibraryModel.importTypes, allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            Task {
                let count = await library.importFiles(urls)
                editor.app.show(count == 0 ? "No models there (USDZ, glTF, GLB, OBJ)" : "Imported \(count) model\(count == 1 ? "" : "s")")
                if count > 0 { filter = .models }
            }
        }
        .alert("Edit", isPresented: Binding(get: { editingItem != nil }, set: { if !$0 { editingItem = nil } })) {
            TextField("Name", text: $editName)
            TextField("Tags, comma separated", text: $editTags)
            Button("Save") {
                if let item = editingItem {
                    library.rename(item, to: editName)
                    library.setTags(item, editTags.split(separator: ",").map(String.init))
                }
                editingItem = nil
            }
            Button("Cancel", role: .cancel) { editingItem = nil }
        }
        .onAppear { if isSwapping { filter = .models } }
    }

    private var isSwapping: Bool {
        if case .swap = editor.libraryPurpose { return true }
        return false
    }

    private var results: [LibraryItem] {
        let items = LibrarySearch.search(query, in: library.manifest, filter: filter)
        guard isSwapping else { return items }
        return items.filter {
            if case .asset = $0 {
                true
            } else {
                false
            }
        }
    }

    private func close() {
        editor.openPanel = nil
        editor.libraryPurpose = .place
    }

    @ViewBuilder
    private func menu(for item: LibraryItem) -> some View {
        Button(item.favorite ? "Unfavourite" : "Favourite", systemImage: item.favorite ? "star.slash" : "star") { library.toggleFavorite(item) }
        Button("Rename & tags", systemImage: "tag") {
            editName = item.name
            editTags = item.tags.joined(separator: ", ")
            editingItem = item
        }
        if case let .prefab(prefab) = item, !editor.selection.isEmpty, editor.singleSelection?.kind.prefabID != prefab.id {
            Button("Replace with the selection", systemImage: "arrow.triangle.2.circlepath") { editor.updatePrefab(prefab.id) }
        }
        Button("Remove from library", systemImage: "trash", role: .destructive) { library.remove(item) }
    }
}

private struct LibraryTile: View {
    let item: LibraryItem
    let thumbnail: UIImage?
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else {
                        ZStack {
                            theme.surface2
                            Image(systemName: placeholder).font(.system(size: 28)).foregroundStyle(theme.text3)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
                HStack(spacing: 4) {
                    if case let .asset(asset) = item, asset.rig.isRigged { Badge(text: "RIGGED") }
                    if item.favorite { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(theme.accent) }
                }
                .padding(6)
            }
            Text(item.name).font(.hmm(.footnote, weight: .semibold)).lineLimit(1).foregroundStyle(theme.text)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library-item-\(item.name)")
        .hoverEffect(.lift)
    }

    private var placeholder: String {
        switch item {
        case .asset: "shippingbox"
        case .prefab: "hammer"
        case .look: "paintpalette"
        case .script: "curlybraces"
        }
    }
}
