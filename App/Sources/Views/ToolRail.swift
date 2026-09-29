import LoweyCore
import LoweyRender
import SwiftUI

/// Feather-style floating rail: tools, add, library, colour, gizmo mode, undo/redo.
struct ToolRail: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(spacing: 10) {
            IconButton(systemName: "plus", label: "Add", isOn: editor.railPanel == .add) {
                editor.railPanel = editor.railPanel == .add ? nil : .add
            }
            IconButton(systemName: "books.vertical.fill", label: "Library", isOn: editor.showLibrary) {
                editor.libraryPurpose = .place
                editor.showLibrary.toggle()
            }
            Divider().frame(width: 28).overlay(Theme.panelStroke)
            ForEach(Tool.allCases) { tool in
                IconButton(systemName: tool.systemImage, label: tool.title, isOn: editor.tool == tool) {
                    editor.tool = tool
                }
            }
            // Move / turn / size only matter with something selected.
            if editor.tool == .select, !editor.selection.isEmpty {
                Divider().frame(width: 28).overlay(Theme.panelStroke)
                ForEach(GizmoMode.allCases, id: \.self) { mode in
                    IconButton(systemName: icon(for: mode), label: "Gizmo \(mode.rawValue)", isOn: editor.gizmoMode == mode, size: 40) {
                        editor.gizmoMode = mode
                    }
                }
            }
            Divider().frame(width: 28).overlay(Theme.panelStroke)
            Button {
                editor.railPanel = editor.railPanel == .color ? nil : .color
            } label: {
                Circle()
                    .fill(editor.currentColor.resolved(in: editor.look.palette).color)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                    .frame(width: Theme.touch, height: Theme.touch)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Colour")
            IconButton(systemName: "list.bullet.indent", label: "Outliner", isOn: editor.showOutliner) {
                editor.showOutliner.toggle()
            }
        }
        .padding(6)
        .panelStyle(cornerRadius: 30)
        .animation(.snappy(duration: 0.25), value: editor.selection.isEmpty)
    }

    private func icon(for mode: GizmoMode) -> String {
        switch mode {
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .rotate: "arrow.triangle.2.circlepath"
        case .scale: "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// Blockout shapes, lights, camera. One tap each.
struct AddMenu: View {
    let editor: EditorModel
    let dismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 10)]

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: 340)
        .frame(maxHeight: 640)
        .fixedSize(horizontal: false, vertical: true)
        .panelStyle()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Blockout")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(PrimitiveShape.allCases, id: \.self) { shape in
                    tile(shape.displayName, icon: icon(for: shape)) { editor.addPrimitive(shape) }
                        .accessibilityIdentifier("add-\(shape.rawValue)")
                }
            }
            SectionHeader(title: "Light & camera")
            LazyVGrid(columns: columns, spacing: 10) {
                tile("Lamp", icon: "lightbulb.fill") { editor.addLight(.point) }
                tile("Spot", icon: "light.overhead.right.fill") { editor.addLight(.spot) }
                tile("Sun", icon: "sun.max.fill") { editor.addLight(.directional) }
                tile("Camera", icon: "video.fill") { editor.addCamera() }
            }
            AddStorySection(editor: editor) { title, icon, action in AnyView(tile(title, icon: icon, action: action)) }
        }
        .padding(18)
    }

    private func tile(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
            dismiss()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 24))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(Theme.text)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
        }
        .buttonStyle(.plain)
    }

    private func icon(for shape: PrimitiveShape) -> String {
        switch shape {
        case .cube: "cube.fill"
        case .sphere: "circle.fill"
        case .cylinder: "cylinder.fill"
        case .cone: "cone.fill"
        case .plane: "square.fill"
        case .torus: "circle.circle"
        case .ramp: "triangle.fill"
        }
    }
}

/// Palette slots first (few decisions), custom colour second.
struct ColorPickerPanel: View {
    @Bindable var editor: EditorModel
    @State private var custom = Color.white

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Project palette")
            PaletteRow(palette: editor.look.palette, selected: editor.currentColor.paletteSlot,
                       remove: { editor.removePaletteSwatch($0) }) { slot in
                editor.setColor(.palette(slot))
            }
            Text("Palette colours stay linked: change the palette in Look and everything updates. Long-press a colour to remove it.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            SectionHeader(title: "Custom")
            ColorPicker("Pick any colour", selection: $custom, supportsOpacity: false)
                .onChange(of: custom) { _, value in
                    editor.setColor(.rgba(RGBA(value)))
                }
        }
        .padding(18)
        .frame(width: 320)
        .panelStyle()
    }
}

struct PaletteRow: View {
    let palette: Palette
    let selected: Int?
    /// Offers "Remove from palette" on a long press when set.
    var remove: ((Int) -> Void)?
    let pick: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 8)], spacing: 8) {
            ForEach(palette.visibleSlots, id: \.self) { index in
                let swatch = palette.swatches[index]
                Button {
                    Haptics.select()
                    pick(index)
                } label: {
                    Circle()
                        .fill(swatch.color.color)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(selected == index ? Theme.accent : .white.opacity(0.2), lineWidth: selected == index ? 3 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
                .contextMenu {
                    if let remove {
                        Button("Remove from palette", systemImage: "trash", role: .destructive) { remove(index) }
                    }
                }
            }
        }
    }
}
