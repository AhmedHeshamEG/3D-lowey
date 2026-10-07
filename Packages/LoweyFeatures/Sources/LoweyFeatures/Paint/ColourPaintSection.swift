import HmmDesign
import LoweyCore
import PhotosUI
import SwiftUI

/// Paint ▸ Colour: the brush and colour, the object being painted (made ready on first use), its layers, and a picture
/// to project from the camera.
struct ColourPaintSection: View {
    @Bindable var editor: EditorModel
    @State private var photo: PhotosPickerItem?
    @State private var choosingFile = false
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            HStack(spacing: HmmSpacing.xs) {
                ForEach(ColourPaintSettings.Mode.allCases) { mode in
                    ChoiceChip(title: mode.title, systemName: mode.systemImage, isOn: editor.colourPaint.mode == mode) {
                        editor.colourPaint.mode = mode
                    }
                    .accessibilityIdentifier("paint-\(mode.rawValue)")
                }
            }
            BrushRow(editor: editor, tool: .paint)
            PanelSection("Colour") {
                ColourChooser(editor: editor)
            }
            target
            Hint("Size and opacity are the sidebar's sliders. Fingers move around; the Pencil paints.")
        }
        .onChange(of: photo) { _, item in load(item) }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let image = UIImage(contentsOfFile: url.path)?.cgImage { place(image) }
        }
    }

    @ViewBuilder private var target: some View {
        if let object = editor.paintTarget {
            if object.paint != nil {
                PaintLayersSection(editor: editor, object: object)
                picture
            } else if editor.colourPaint.preparing.contains(object.id) {
                HStack(spacing: HmmSpacing.s) {
                    ProgressView()
                    Text("Getting \(object.name) ready to paint").font(.hmm(.footnote)).foregroundStyle(theme.text2)
                }
            } else {
                HmmPillButton("Paint \(object.name)", systemName: "paintbrush.pointed") { editor.preparePaint(object.id) }
                    .accessibilityIdentifier("paint-start")
                Hint("Or start a stroke on it with the Pencil.")
            }
        } else {
            Hint("Tap a shape, a modelled part or a placed model to paint it.")
        }
    }

    private var picture: some View {
        PanelSection("Project a picture") {
            HStack(spacing: HmmSpacing.xs) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Photos", systemImage: "photo")
                }
                .buttonStyle(.bordered)
                Button("Files", systemImage: "folder") { choosingFile = true }
                    .buttonStyle(.bordered)
            }
            Hint("Place it over the model with your fingers, then Project: it lands on what the camera sees.")
        }
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data)?.cgImage { place(image) }
            photo = nil
        }
    }

    /// The picture over the middle of the stage, 60 % of its width.
    private func place(_ image: CGImage) {
        let stage = editor.stage?.bounds.size ?? CGSize(width: 1024, height: 768)
        let width = stage.width * 0.6
        let height = width * CGFloat(image.height) / CGFloat(max(image.width, 1))
        editor.colourPaint.picture = PaintPicture(image: image, rect: CGRect(x: (stage.width - width) / 2, y: (stage.height - height) / 2,
                                                                             width: width, height: height))
        editor.openPanel = nil
    }
}

/// An object's paint layers, top first: show/hide, choose the one the Pencil paints on, its opacity and blend, and
/// the layer actions.
struct PaintLayersSection: View {
    @Bindable var editor: EditorModel
    let object: SceneObject
    @State private var renaming: (id: String, name: String)?
    @State private var gesture = UUID().uuidString
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let paint = object.paint
        let current = editor.paintLayer(of: object)
        PanelSection("Layers") {
            VStack(spacing: HmmSpacing.xxs) {
                ForEach((paint?.layers ?? []).reversed()) { layer in
                    row(layer, isCurrent: layer.id == current?.id)
                }
            }
            if let current {
                LabeledSlider(title: "Layer opacity", value: current.opacity, range: 0 ... 1, format: NumberFormat.percent) { value in
                    editor.updatePaintLayer(current.id, of: object.id, gesture: gesture) { $0.opacity = value }
                }
                FlowChips(items: PaintBlend.allCases.map { ($0.rawValue, $0.title) }, isOn: { $0 == current.blend.rawValue }) { key in
                    guard let blend = PaintBlend(rawValue: key) else { return }
                    editor.updatePaintLayer(current.id, of: object.id) { $0.blend = blend }
                }
                actions(current, paint: paint)
            }
        }
        .alert("Rename layer", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: Binding(get: { renaming?.name ?? "" }, set: { renaming?.name = $0 }))
            Button("Rename") {
                if let renaming { editor.updatePaintLayer(renaming.id, of: object.id) { $0.name = renaming.name } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func row(_ layer: PaintLayer, isCurrent: Bool) -> some View {
        HStack(spacing: HmmSpacing.s) {
            Button {
                editor.updatePaintLayer(layer.id, of: object.id) { $0.visible.toggle() }
            } label: {
                Image(systemName: layer.visible ? "eye" : "eye.slash").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.visible ? "Hide \(layer.name)" : "Show \(layer.name)")
            Text(layer.name).font(.hmm(.body, weight: isCurrent ? .semibold : .regular)).lineLimit(1)
            Spacer(minLength: 0)
            if layer.blend != .normal { Text(LocalizedStringKey(layer.blend.title)).font(.hmm(.caption)).foregroundStyle(theme.text2) }
            Text("\(Int((layer.opacity * 100).rounded())) %").font(.hmm(.caption).monospacedDigit()).foregroundStyle(theme.text2)
        }
        .padding(.horizontal, HmmSpacing.xs)
        .background(isCurrent ? theme.accent.opacity(0.18) : theme.surface2, in: RoundedRectangle(cornerRadius: HmmRadius.control, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            editor.choosePaintLayer(layer.id, on: object.id)
            gesture = UUID().uuidString
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { renaming = (layer.id, layer.name) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("paint-layer-\(layer.id)")
    }

    private func actions(_ layer: PaintLayer, paint: ObjectPaint?) -> some View {
        let index = paint?.layerIndex(layer.id) ?? 0
        let count = paint?.layers.count ?? 0
        return HStack(spacing: HmmSpacing.xs) {
            HmmButton("plus", label: "Add a layer", size: 40) { editor.addPaintLayer(to: object.id) }
                .accessibilityIdentifier("paint-layer-add")
            Menu {
                Button("Duplicate", systemImage: "plus.square.on.square") { editor.duplicatePaintLayer(layer.id, of: object.id) }
                Button("Merge down", systemImage: "square.3.layers.3d.down.right") { editor.mergePaintLayerDown(layer.id, of: object.id) }
                    .disabled(index == 0)
                Button("Move up", systemImage: "arrow.up") { editor.movePaintLayer(layer.id, of: object.id, by: 1) }
                    .disabled(index >= count - 1)
                Button("Move down", systemImage: "arrow.down") { editor.movePaintLayer(layer.id, of: object.id, by: -1) }
                    .disabled(index == 0)
                Button("Clear", systemImage: "eraser") { editor.clearPaintLayer(layer.id, of: object.id) }
                Button("Rename", systemImage: "pencil") { renaming = (layer.id, layer.name) }
                Divider()
                Button("Delete layer", systemImage: "trash", role: .destructive) { editor.deletePaintLayer(layer.id, of: object.id) }
                Button("Remove all paint", systemImage: "paintbrush.pointed", role: .destructive) { editor.removePaint(from: object.id) }
            } label: {
                Label("Layer", systemImage: "ellipsis.circle").font(.hmm(.body))
            }
            .accessibilityIdentifier("paint-layer-menu")
        }
    }
}
