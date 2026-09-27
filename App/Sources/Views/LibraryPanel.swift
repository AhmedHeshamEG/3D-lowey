import LoweyCore
import LoweyRender
import SwiftUI
import UniformTypeIdentifiers

/// Search first, browse second. Big thumbnails, tags, favorites, recents. Never a template wall.
struct LibraryPanel: View {
    @Bindable var editor: EditorModel
    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @State private var importing = false
    @State private var editingItem: LibraryItem?
    @State private var editName = ""
    @State private var editTags = ""
    @FocusState private var searchFocused: Bool

    private var library: LibraryModel { editor.library }
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isSwapping ? "Swap for…" : "Library")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                if library.importing > 0 {
                    ProgressView().controlSize(.small)
                    Text("Importing \(library.importing)…").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                IconButton(systemName: "square.and.arrow.down", label: "Import models", size: 40) { importing = true }
                IconButton(systemName: "xmark", label: "Close library", size: 40) {
                    editor.showLibrary = false
                    editor.libraryPurpose = .place
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
                TextField("Search: tree, desk, robot…", text: $query)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("library-search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondaryText) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableFilters, id: \.self) { item in
                        Button {
                            Haptics.select()
                            filter = item
                        } label: {
                            Text(item.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .foregroundStyle(filter == item ? Color.black : Theme.text)
                                .background(Capsule().fill(filter == item ? Theme.accent : Theme.raised))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(results) { item in
                            LibraryTile(item: item, thumbnail: library.thumbnail(for: item))
                                .onTapGesture {
                                    Haptics.tap()
                                    editor.place(item)
                                }
                                .draggable(item.id)
                                .contextMenu { menu(for: item) }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(18)
        .panelStyle()
        .fileImporter(isPresented: $importing, allowedContentTypes: LibraryModel.importTypes, allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            Task {
                let count = await library.importFiles(urls)
                editor.app.show(count == 0 ? "No models found there (USDZ, glTF, GLB, OBJ)" : "Imported \(count) model\(count == 1 ? "" : "s")")
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
        .onAppear {
            if isSwapping { filter = .models }
        }
    }

    private var isSwapping: Bool {
        if case .swap = editor.libraryPurpose { return true }
        return false
    }

    private var availableFilters: [LibraryFilter] {
        isSwapping ? [.models, .favorites, .recent] : LibraryFilter.allCases
    }

    private var results: [LibraryItem] {
        let items = LibrarySearch.search(query, in: library.manifest, filter: filter)
        if isSwapping { return items.filter {
            if case .asset = $0 {
                true
            } else {
                false
            }
        } }
        return items
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: query.isEmpty ? "shippingbox" : "questionmark.folder")
                .font(.system(size: 44))
                .foregroundStyle(Theme.secondaryText)
            Text(query.isEmpty ? "Your library is empty" : "Nothing called “\(query)” yet")
                .font(.system(size: 17, weight: .semibold))
            Text(query.isEmpty
                ? "Import USDZ, glTF/GLB or OBJ models (a whole folder works too), or build something and tap “Save to library”."
                : "Import it, or block it out with shapes and save it — then it's here forever.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            PillButton(title: "Import models", systemName: "square.and.arrow.down", prominent: true) { importing = true }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func menu(for item: LibraryItem) -> some View {
        Button(item.favorite ? "Unfavorite" : "Favorite", systemImage: item.favorite ? "star.slash" : "star") {
            library.toggleFavorite(item)
        }
        Button("Rename & tags", systemImage: "tag") {
            editName = item.name
            editTags = item.tags.joined(separator: ", ")
            editingItem = item
        }
        if case let .prefab(prefab) = item, !editor.selection.isEmpty, editor.singleSelection?.kind.prefabID != prefab.id {
            // Edit an unpacked copy, then push it back: every instance in every project updates.
            Button("Replace with selection", systemImage: "arrow.triangle.2.circlepath") { editor.updatePrefab(prefab.id) }
        }
        Button("Remove from library", systemImage: "trash", role: .destructive) { library.remove(item) }
    }
}

private struct LibraryTile: View {
    let item: LibraryItem
    let thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Theme.raised
                            Image(systemName: placeholderIcon).font(.system(size: 30)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack(spacing: 4) {
                    if case let .asset(asset) = item, asset.rig.isRigged { Badge(text: "RIGGED") }
                    if item.favorite {
                        Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                }
                .padding(6)
            }
            Text(item.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(Theme.text)
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("library-item-\(item.name)")
        .hoverEffect(.lift)
    }

    private var placeholderIcon: String {
        switch item {
        case .asset: "shippingbox"
        case .prefab: "hammer"
        case .look: "paintpalette"
        }
    }
}
