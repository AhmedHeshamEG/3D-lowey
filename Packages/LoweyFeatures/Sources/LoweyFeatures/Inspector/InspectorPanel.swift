import HmmDesign
import LoweyCore
import SwiftUI

/// Slides in from the right while something is selected: Transform · Look override · Lines · Motion · Metadata, and
/// the actions. The few controls used most come first; the rest sit behind More.
struct InspectorPanel: View {
    @Bindable var editor: EditorModel
    @State private var name = ""
    @State private var showsMore = false
    @State private var savingPrefab = false
    @State private var prefabName = ""
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, HmmSpacing.m)
                .padding(.top, HmmSpacing.s)
            ScrollView {
                VStack(alignment: .leading, spacing: HmmSpacing.m) {
                    if let object = editor.singleSelection {
                        single(object)
                    } else {
                        Text("\(editor.selection.count) objects").font(.hmm(.body)).foregroundStyle(theme.text2)
                        PaletteRow(palette: editor.look.palette, selected: nil) { editor.setColor(.palette($0)) }
                        LookOverrideSection(editor: editor, object: nil)
                        MotionSection(editor: editor)
                    }
                    actions
                }
                .padding(HmmSpacing.m)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 330)
        .frame(maxHeight: .infinity, alignment: .top)
        .hmmPanelBackground()
        .onAppear { name = editor.singleSelection?.name ?? "" }
        .onChange(of: editor.selection) { _, _ in name = editor.singleSelection?.name ?? "" }
        .alert("Save to your library", isPresented: $savingPrefab) {
            TextField("Name", text: $prefabName)
            Button("Save a copy") { editor.saveSelectionAsPrefab(name: prefabName, replaceSelection: false) }
            Button("Save & link") { editor.saveSelectionAsPrefab(name: prefabName, replaceSelection: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Build once, reuse it everywhere. Linked copies update when you edit the original.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector")
    }

    @ViewBuilder
    private func single(_ object: SceneObject) -> some View {
        TransformSection(editor: editor, object: object)
        if object.kind.hasSurface { SurfaceSection(editor: editor, object: object) }
        KindSection(editor: editor, object: object)
        if object.kind.hasSurface || object.kind == .group { LookOverrideSection(editor: editor, object: object) }
        MotionSection(editor: editor)
        if showsMore { MetadataSection(editor: editor, object: object) }
        Button(showsMore ? "Less" : "More") { withHmmAnimation(.standard) { showsMore.toggle() } }
            .font(.hmm(.body, weight: .semibold))
            .accessibilityIdentifier("inspector-more")
    }

    private var header: some View {
        HStack(spacing: HmmSpacing.s) {
            if let object = editor.singleSelection {
                Image(systemName: Self.icon(for: object.kind)).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.accent)
                TextField("Name", text: $name)
                    .font(.hmm(.headline, weight: .semibold))
                    .onSubmit { editor.rename(object.id, to: name) }
                    .accessibilityIdentifier("inspector-name")
                if object.kind.prefabID != nil { Badge(text: "BUILD") }
            } else {
                Text("Selection").font(.hmm(.headline, weight: .semibold))
            }
            Spacer()
            HmmButton("xmark", label: "Deselect", size: 32) { editor.setSelection([]) }
        }
    }

    /// The three things done most as buttons; everything else in one menu.
    private var actions: some View {
        let object = editor.singleSelection
        return HStack(spacing: HmmSpacing.xs) {
            HmmButton("plus.square.on.square", label: "Duplicate", size: 40) { editor.duplicateSelection() }
            if let object {
                HmmButton(object.isVisible ? "eye.slash" : "eye", label: object.isVisible ? "Hide" : "Show", size: 40) { editor.toggleVisible(object.id) }
            }
            Menu {
                moreActions(object)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 40)
            }
            .accessibilityLabel("More actions")
            .accessibilityIdentifier("more-actions")
            Spacer(minLength: 0)
            HmmButton("trash", label: "Delete", size: 40, role: .destructive) { editor.deleteSelection() }
        }
    }

    @ViewBuilder
    private func moreActions(_ object: SceneObject?) -> some View {
        Section {
            Menu("Array", systemImage: "square.grid.3x3") {
                let step = editor.arrayStep
                Button("Row of 5") { editor.array(.line(count: 5, step: Vec3(step, 0, 0))) }
                Button("Row of 10") { editor.array(.line(count: 10, step: Vec3(step, 0, 0))) }
                Button("Grid 3 × 3") { editor.array(.grid(columns: 3, rows: 3, spacingX: step, spacingZ: step)) }
                Button("Grid 5 × 5") { editor.array(.grid(columns: 5, rows: 5, spacingX: step, spacingZ: step)) }
                Button("Circle of 8") { editor.array(.circle(count: 8, radius: max(step * 1.5, 1), faceCenter: true)) }
                Button("Circle of 12") { editor.array(.circle(count: 12, radius: max(step * 2, 1.5), faceCenter: true)) }
            }
            Button("Scatter", systemImage: "circle.hexagongrid") { editor.tool = .scatter }
            Button("To the ground", systemImage: "arrow.down.to.line") { editor.dropSelectionToGround() }
        }
        Section {
            if editor.selection.count > 1 { Button("Group", systemImage: "square.on.square.dashed") { editor.groupSelection() } }
            if object?.kind == .group { Button("Ungroup", systemImage: "square.dashed") { editor.ungroupSelection() } }
            if case .primitive = object?.kind { Button("Swap for a model…", systemImage: "arrow.triangle.swap") { editor.beginSwap() } }
            Button("Save to library…", systemImage: "tray.and.arrow.down") {
                prefabName = object?.name ?? ""
                savingPrefab = true
            }
            if object?.kind.prefabID != nil { Button("Unpack", systemImage: "shippingbox") { editor.unpackSelection() } }
            if let object {
                Button(object.isLocked ? "Unlock" : "Lock", systemImage: object.isLocked ? "lock.open" : "lock") { editor.toggleLock(object.id) }
            }
            Button("Copy", systemImage: "doc.on.doc") { editor.copySelection() }
        }
    }

    static func icon(for kind: ObjectKind) -> String {
        switch kind {
        case .group: "square.on.square.dashed"
        case .primitive: "cube"
        case .asset: "shippingbox"
        case .prefab: "shippingbox.circle"
        case .drawing: "scribble"
        case .light: "lightbulb"
        case .camera: "video"
        case .text: "textformat"
        case .overlay: "square.on.square.intersection.dashed"
        case .particles: "sparkles"
        case .card: "photo.on.rectangle"
        }
    }
}
