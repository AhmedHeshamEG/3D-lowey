import LoweyCore
import LoweyRender
import SwiftUI

/// Appears only for the selection. A few meaningful controls, then actions.
struct InspectorPanel: View {
    @Bindable var editor: EditorModel
    @State private var name = ""
    @State private var showPrefabSheet = false
    @State private var prefabName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let object = editor.singleSelection {
                    TransformEditor(editor: editor, object: object)
                    if object.kind.hasSurface { surfaceSection(object) }
                    if case let .light(type) = object.kind { LightEditor(editor: editor, object: object, type: type) }
                    RecipeInspector(editor: editor, object: object)
                    if case let .asset(id) = object.kind, let asset = editor.library.manifest.asset(id) { assetInfo(asset) }
                } else {
                    Text("\(editor.selection.count) objects selected")
                        .foregroundStyle(Theme.secondaryText)
                    colorRow
                    arrangeSection
                }
                actions
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .panelStyle()
        .sheet(isPresented: $showPrefabSheet) { prefabSheet }
        .onAppear { name = editor.singleSelection?.name ?? "" }
        .onChange(of: editor.selection) { _, _ in name = editor.singleSelection?.name ?? "" }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            if let object = editor.singleSelection {
                Image(systemName: icon(for: object.kind))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                TextField("Name", text: $name)
                    .font(.system(size: 18, weight: .bold))
                    .onSubmit { editor.rename(object.id, to: name) }
                    .accessibilityIdentifier("inspector-name")
                if case let .asset(id) = object.kind, editor.library.manifest.asset(id)?.rig.isRigged == true {
                    Badge(text: "RIGGED")
                }
                if object.kind.prefabID != nil { Badge(text: "PREFAB") }
            } else {
                Text("Selection").font(.system(size: 18, weight: .bold))
            }
            Spacer()
            Button {
                editor.setSelection([])
            } label: {
                Image(systemName: "xmark").foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Deselect")
        }
    }

    // MARK: Surface

    private func surfaceSection(_ object: SceneObject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Colour")
            colorRow
            if object.color != nil, object.kind.assetID != nil {
                Button("Use the model's own colours") { editor.setColor(nil) }
                    .font(.system(size: 13, weight: .semibold))
            }
            HStack {
                Text("Glow").foregroundStyle(Theme.secondaryText)
                Slider(value: Binding(
                    get: { object.emissiveIntensity },
                    set: { editor.setProperty(.emissiveIntensity, .float($0), coalesce: "glow-\(object.id.raw)") }
                ), in: 0 ... 8, onEditingChanged: { editing in if !editing { editor.endGesture() } })
            }
            Picker("Shading", selection: Binding(
                get: { object.shading },
                set: { editor.setProperty(.shading, $0 == .inherit ? nil : .enumeration($0.rawValue)) }
            )) {
                Text("Project").tag(ShadingMode.inherit)
                Text("Smooth").tag(ShadingMode.smooth)
                Text("Flat").tag(ShadingMode.flat)
            }
            .pickerStyle(.segmented)
        }
    }

    private var colorRow: some View {
        PaletteRow(palette: editor.look.palette, selected: editor.singleSelection?.color?.paletteSlot) { slot in
            editor.setColor(.palette(slot))
        }
    }

    private func assetInfo(_ asset: LibraryAsset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Model")
            if let triangles = asset.triangleCount {
                Text("\(triangles) triangles · \(asset.format.rawValue.uppercased())").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            if asset.rig.isRigged {
                Text("Skeleton: \(asset.rig.rawValue.capitalized)").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            if !asset.clips.isEmpty {
                Text("Clips: \(asset.clips.joined(separator: ", "))")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(3)
            }
        }
    }

    // MARK: Arrange (multi-selection)

    private var arrangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Align")
            HStack {
                ForEach(CoreAxis.allCases, id: \.self) { axis in
                    Menu(axis.rawValue.uppercased()) {
                        Button("Min") { editor.align(axis, .min) }
                        Button("Center") { editor.align(axis, .center) }
                        Button("Max") { editor.align(axis, .max) }
                        Button("Distribute evenly") { editor.distribute(axis) }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Capsule().fill(Theme.raised))
                }
            }
        }
    }

    // MARK: Actions

    /// The three things done most (duplicate, hide, delete) as buttons; everything else in one menu.
    private var actions: some View {
        let object = editor.singleSelection
        return HStack(spacing: 8) {
            ActionIcon(systemName: "plus.square.on.square", label: "Duplicate") { editor.duplicateSelection() }
            if let object {
                ActionIcon(systemName: object.isVisible ? "eye.slash" : "eye", label: object.isVisible ? "Hide" : "Show") {
                    editor.toggleVisible(object.id)
                }
            }
            Menu {
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
                    if editor.selection.count > 1 {
                        Button("Group", systemImage: "square.on.square.dashed") { editor.groupSelection() }
                    }
                    if object?.kind == .group {
                        Button("Ungroup", systemImage: "square.dashed") { editor.ungroupSelection() }
                    }
                    if case .primitive = object?.kind {
                        Button("Swap for a model…", systemImage: "arrow.triangle.swap") { editor.beginSwap() }
                    }
                    Button("Save to library…", systemImage: "tray.and.arrow.down") {
                        prefabName = object?.name ?? ""
                        showPrefabSheet = true
                    }
                    if object?.kind.prefabID != nil {
                        Button("Unpack", systemImage: "shippingbox") { editor.unpackSelection() }
                    }
                    if let object {
                        Button(object.isLocked ? "Unlock" : "Lock", systemImage: object.isLocked ? "lock.open" : "lock") {
                            editor.toggleLock(object.id)
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 40)
                    .background(Capsule().fill(Theme.raised))
            }
            .accessibilityLabel("More actions")
            .accessibilityIdentifier("more-actions")
            Spacer(minLength: 0)
            ActionIcon(systemName: "trash", label: "Delete", destructive: true) { editor.deleteSelection() }
        }
    }

    private var prefabSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Save to your library").font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Build once, reuse forever. Every project can place it; edit it once and every copy updates.")
                .foregroundStyle(Theme.secondaryText)
            TextField("Name", text: $prefabName).textFieldStyle(.roundedBorder).font(.system(size: 18))
            HStack {
                Spacer()
                PillButton(title: "Save a copy") {
                    showPrefabSheet = false
                    editor.saveSelectionAsPrefab(name: prefabName, replaceSelection: false)
                }
                PillButton(title: "Save & link", systemName: "link", prominent: true) {
                    showPrefabSheet = false
                    editor.saveSelectionAsPrefab(name: prefabName, replaceSelection: true)
                }
            }
        }
        .padding(28)
        .presentationDetents([.height(300)])
    }

    private func icon(for kind: ObjectKind) -> String {
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

/// A quiet icon action inside a panel (no glass of its own: the panel is the glass).
struct ActionIcon: View {
    let systemName: String
    let label: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(destructive ? Theme.danger : Theme.text)
                .frame(width: 44, height: 40)
                .background(Capsule().fill(Theme.raised))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(label)
        .hoverEffect(.highlight)
    }
}

struct Badge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.accent.opacity(0.2)))
            .foregroundStyle(Theme.accent)
    }
}

extension Label {
    func pillLabel() -> some View {
        font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .foregroundStyle(Theme.text)
            .background(Capsule().fill(Theme.raised))
    }
}

/// Numeric entry for position / rotation / scale.
struct TransformEditor: View {
    let editor: EditorModel
    let object: SceneObject
    @State private var uniformScale = true
    /// Numbers are for fine-tuning; most moves happen on the stage, so they stay folded until asked for.
    @AppStorage("inspector.transformOpen") private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { open.toggle() }
            } label: {
                HStack {
                    SectionHeader(title: "Position, rotation, size")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("transform-toggle")
            if open { fields }
        }
    }

    private var fields: some View {
        let transform = object.transform
        let euler = editor.eulerDegrees(of: object)
        return VStack(alignment: .leading, spacing: 8) {
            VectorRow(label: "Position", value: transform.position, step: 0.1) { value in
                var t = transform
                t.position = value
                editor.setTransform(object.id, t)
            }
            VectorRow(label: "Rotation", value: euler, step: 15) { value in
                editor.setEulerDegrees(value, of: object.id)
            }
            VectorRow(label: "Scale", value: transform.scale, step: 0.1) { value in
                var t = transform
                if uniformScale {
                    // Whichever component changed drives all three.
                    let old = transform.scale
                    let ratio = [value.x / max(old.x, 1e-6), value.y / max(old.y, 1e-6), value.z / max(old.z, 1e-6)]
                        .first { abs($0 - 1) > 1e-9 } ?? 1
                    t.scale = old * ratio
                } else {
                    t.scale = value
                }
                editor.setTransform(object.id, t)
            }
            Toggle("Keep proportions", isOn: $uniformScale)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

struct VectorRow: View {
    let label: String
    let value: Vec3
    let step: Double
    let commit: (Vec3) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 62, alignment: .leading)
            ForEach(CoreAxis.allCases, id: \.self) { axis in
                NumberField(axis: axis, value: value[axis], step: step) { newValue in
                    var copy = value
                    copy[axis] = newValue
                    commit(copy)
                }
            }
        }
    }
}

struct NumberField: View {
    let axis: CoreAxis
    let value: Double
    let step: Double
    let commit: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(axis.rawValue.uppercased(), text: $text)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.center)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .frame(minWidth: 56, minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.raised))
            .overlay(alignment: .topLeading) {
                Rectangle().fill(color).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2)).padding(.vertical, 6)
            }
            .focused($focused)
            .onAppear { text = NumberFormat.short(value) }
            .onChange(of: value) { _, newValue in if !focused { text = NumberFormat.short(newValue) } }
            .onSubmit {
                if let number = Double(text.replacingOccurrences(of: ",", with: ".")) { commit(number) }
            }
    }

    private var color: Color {
        switch axis {
        case .x: Color(red: 0.96, green: 0.33, blue: 0.36)
        case .y: Color(red: 0.45, green: 0.86, blue: 0.4)
        case .z: Color(red: 0.35, green: 0.58, blue: 1)
        }
    }
}

/// Light controls: colour, strength, reach, cone, shadows.
struct LightEditor: View {
    let editor: EditorModel
    let object: SceneObject
    let type: LightType
    @State private var color = Color.white

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Light")
            ColorPicker("Colour", selection: $color, supportsOpacity: false)
                .onAppear { color = (object[.lightColor]?.colorValue?.resolved(in: editor.look.palette) ?? .white).color }
                .onChange(of: color) { _, value in editor.setProperty(.lightColor, .color(.rgba(RGBA(value)))) }
            sliderRow("Strength", key: .lightIntensity, range: 0 ... 6, fallback: 1)
            if type != .directional { sliderRow("Reach", key: .lightRange, range: 0.5 ... 30, fallback: 6) }
            if type == .spot { sliderRow("Cone", key: .spotAngle, range: 5 ... 120, fallback: 40) }
            if type != .point {
                Toggle("Shadows", isOn: Binding(
                    get: { object[.lightShadows]?.boolValue ?? true },
                    set: { editor.setProperty(.lightShadows, .bool($0)) }
                ))
            }
        }
    }

    private func sliderRow(_ title: String, key: PropertyKey, range: ClosedRange<Double>, fallback: Double) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.secondaryText).frame(width: 70, alignment: .leading)
            Slider(value: Binding(
                get: { object[key]?.floatValue ?? fallback },
                set: { editor.setProperty(key, .float($0), coalesce: "\(key.rawValue)-\(object.id.raw)") }
            ), in: range, onEditingChanged: { editing in if !editing { editor.endGesture() } })
        }
    }
}
