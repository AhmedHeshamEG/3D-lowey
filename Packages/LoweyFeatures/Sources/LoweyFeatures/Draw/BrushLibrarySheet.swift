import HmmDesign
import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// The brush library (Procreate's): sets of brushes, each drawing its own sample stroke. Tap a brush to draw with it;
/// touch and hold for Brush Studio, duplicate, reset, rename, move or delete. Sets are made, renamed, shared as a
/// file and deleted here; brush files from Procreate and Photoshop come in through Import.
struct BrushLibrarySheet: View {
    @Bindable var editor: EditorModel
    @State private var editing: String?
    @State private var importing = false
    @State private var sharing: URL?
    @State private var renaming: Renaming?
    @Environment(\.hmmTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var brushes: BrushModel { editor.app.brushes }
    /// Previews draw in the text colour.
    private var ink: RGBA { colorScheme == .dark ? RGBA(0.93, 0.93, 0.94) : RGBA(0.11, 0.11, 0.12) }

    /// A brush or a set being renamed, and the name typed so far.
    struct Renaming: Identifiable {
        enum Target {
            case brush(String), set(String)
        }

        var target: Target
        var name: String
        var id: String {
            switch target {
            case let .brush(id): "brush:" + id
            case let .set(id): "set:" + id
            }
        }
    }

    var body: some View {
        HmmSheet("Brushes", subtitle: subtitle) {
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("Import brushes", systemName: "square.and.arrow.down") { importing = true }
                    .accessibilityIdentifier("import-brushes")
                HmmPillButton("New set", systemName: "folder.badge.plus") {
                    let name = String(localized: "New set")
                    renaming = Renaming(target: .set(brushes.addSet(named: name)), name: name)
                }
                .accessibilityIdentifier("new-brush-set")
            }
            Hint("Procreate .brushset and .brush files and Photoshop .abr brushes come in as a new set. Touch and hold a brush to edit it.")
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                ForEach(brushes.library.sets) { set in
                    setSection(set)
                }
            }
            .navigationDestination(item: $editing) { id in
                BrushStudioView(brushes: brushes, brushID: id, color: editor.currentColor.resolved(in: editor.look.palette))
            }
        }
        .accessibilityIdentifier("brush-library")
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            Task {
                for url in urls {
                    await editor.app.importBrushes(url)
                }
            }
        }
        .sheet(item: Binding(get: { sharing.map(IdentifiedURL.init) }, set: { sharing = $0?.url })) { ShareSheet(items: [$0.url]) }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { _ in
            TextField("Name", text: Binding(get: { renaming?.name ?? "" }, set: { renaming?.name = $0 }))
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    /// Which tool the chosen brush is for.
    private var subtitle: String {
        editor.brushTool == .ink ? "For ink" : "For flipbooks"
    }

    static let importTypes: [UTType] = BrushFileImport.fileExtensions.compactMap { UTType(filenameExtension: $0) }

    private func setSection(_ set: BrushSet) -> some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            HStack {
                Text(set.name).font(.hmm(.headline, weight: .semibold))
                Spacer()
                Menu {
                    Button("Rename", systemImage: "pencil") { renaming = Renaming(target: .set(set.id), name: set.name) }
                        .disabled(set.builtIn)
                    Button("Share", systemImage: "square.and.arrow.up") { sharing = brushes.shareFile(for: set.id) }
                    if !set.builtIn {
                        Button("Delete set", systemImage: "trash", role: .destructive) { brushes.deleteSet(set.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.hmm(.headline)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Set options")
            }
            if set.brushes.isEmpty {
                Hint("Empty. Move a brush here from its menu.")
            }
            ForEach(set.brushes, id: \.self) { id in
                if let brush = brushes.library.brush(id) { brushRow(brush, in: set) }
            }
        }
        .padding(HmmSpacing.s)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
    }

    private func brushRow(_ brush: Brush, in set: BrushSet) -> some View {
        let chosen = brushes.selection[editor.brushTool] == brush.id || (brushes.selection[editor.brushTool] == nil && brush.id == BuiltInBrushes.inkPenID)
        return Button {
            HmmHaptics.play(.selection)
            brushes.select(brush.id, for: editor.brushTool)
        } label: {
            HStack(spacing: HmmSpacing.s) {
                BrushPreviewImage(brushes: brushes, brush: brush, width: 200, height: 44, color: ink)
                Text(brush.name).font(.hmm(.body)).foregroundStyle(theme.text).lineLimit(1)
                Spacer(minLength: 0)
                if chosen { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
            .padding(.vertical, HmmSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("brush-\(brush.id)")
        .contextMenu { brushMenu(brush, in: set) }
    }

    @ViewBuilder private func brushMenu(_ brush: Brush, in set: BrushSet) -> some View {
        Button("Edit in Brush Studio", systemImage: "slider.horizontal.3") { editing = brush.id }
        Button("Duplicate", systemImage: "plus.square.on.square") { brushes.duplicate(brush.id) }
        if brushes.library.resetTarget(brush.id) != nil {
            Button("Reset", systemImage: "arrow.counterclockwise") { brushes.reset(brush.id) }
        }
        Button("Rename", systemImage: "pencil") { renaming = Renaming(target: .brush(brush.id), name: brush.name) }
        Menu("Move to") {
            ForEach(brushes.library.sets.filter { $0.id != set.id }) { other in
                Button(other.name) { brushes.move(brush.id, to: other.id) }
            }
        }
        if !brushes.library.isBuiltIn(brush.id) {
            Button("Delete", systemImage: "trash", role: .destructive) { brushes.delete(brush.id) }
        }
    }

    private func commitRename() {
        guard let renaming else { return }
        switch renaming.target {
        case let .brush(id): brushes.rename(id, to: renaming.name)
        case let .set(id): brushes.renameSet(id, to: renaming.name)
        }
        self.renaming = nil
    }
}

/// A brush drawing its sample stroke (drawn by the brush engine, cached by the brush model).
struct BrushPreviewImage: View {
    let brushes: BrushModel
    let brush: Brush
    let width: Double
    let height: Double
    let color: RGBA
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // Reading the revision redraws the picture when a brush changes.
        let revision = brushes.revision
        Group {
            if revision >= 0, let image = brushes.preview(brush, width: width, height: height, color: color, scale: displayScale) {
                Image(decorative: image, scale: displayScale)
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}
