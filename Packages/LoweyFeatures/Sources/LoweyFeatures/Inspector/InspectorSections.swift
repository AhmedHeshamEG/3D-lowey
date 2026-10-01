import HmmDesign
import LoweyCore
import SwiftUI

/// Position, rotation and size as numbers (folded: most moves happen on the stage).
struct TransformSection: View {
    let editor: EditorModel
    let object: SceneObject
    @State private var uniformScale = true
    @AppStorage("inspector.transformOpen") private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            Button {
                withAnimation(.hmmSnappy) { open.toggle() }
            } label: {
                HStack {
                    HmmSectionHeader("Transform")
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).rotationEffect(.degrees(open ? 90 : 0))
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
        return VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            VectorRow(label: "Position", value: transform.position) { value in
                var updated = transform
                updated.position = value
                editor.setTransform(object.id, updated)
            }
            VectorRow(label: "Rotation", value: editor.eulerDegrees(of: object)) { editor.setEulerDegrees($0, of: object.id) }
            VectorRow(label: "Size", value: transform.scale) { value in
                var updated = transform
                if uniformScale {
                    // Whichever number changed drives all three.
                    let old = transform.scale
                    let ratio = [value.x / max(old.x, 1e-6), value.y / max(old.y, 1e-6), value.z / max(old.z, 1e-6)].first { abs($0 - 1) > 1e-9 } ?? 1
                    updated.scale = old * ratio
                } else {
                    updated.scale = value
                }
                editor.setTransform(object.id, updated)
            }
            Toggle("Keep proportions", isOn: $uniformScale).font(.hmm(.footnote))
        }
    }
}

struct VectorRow: View {
    let label: String
    let value: Vec3
    let commit: (Vec3) -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.xxs) {
            Text(label).font(.hmm(.footnote, weight: .semibold)).foregroundStyle(theme.text2).frame(width: 60, alignment: .leading)
            ForEach(CoreAxis.allCases, id: \.self) { axis in
                NumberField(axis: axis, value: value[axis]) { newValue in
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
    let commit: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        TextField(axis.rawValue.uppercased(), text: $text)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.center)
            .font(.hmmNumbers(.footnote))
            .frame(minWidth: 54, minHeight: 36)
            .background(RoundedRectangle(cornerRadius: HmmRadius.control).fill(theme.surface2))
            .overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: 3).padding(.vertical, 8)
            }
            .focused($focused)
            .onAppear { text = NumberFormat.short(value) }
            .onChange(of: value) { _, newValue in if !focused { text = NumberFormat.short(newValue) } }
            .onSubmit { if let number = Double(text.replacingOccurrences(of: ",", with: ".")) { commit(number) } }
            .accessibilityLabel(axis.rawValue.uppercased())
    }

    private var color: Color {
        switch axis {
        case .x: Color(red: 0.96, green: 0.33, blue: 0.36)
        case .y: Color(red: 0.45, green: 0.86, blue: 0.4)
        case .z: Color(red: 0.35, green: 0.58, blue: 1)
        }
    }
}

/// Colour, glow, shape smoothing and the bevel.
struct SurfaceSection: View {
    let editor: EditorModel
    let object: SceneObject

    var body: some View {
        PanelSection("Colour") {
            PaletteRow(palette: editor.look.palette, selected: object.color?.paletteSlot) { editor.setColor(.palette($0)) }
            if object.color != nil, object.kind.assetID != nil {
                Button("Use the model's own colours") { editor.setColor(nil) }.font(.hmm(.footnote, weight: .semibold))
            }
            LabeledSlider(title: "Glow", value: object.emissiveIntensity, range: 0 ... 8, set: {
                editor.setProperty(.emissiveIntensity, .float($0), coalesce: "glow-\(object.id.raw)")
            }, done: editor.endGesture)
            LabeledSlider(title: "Shape smoothing", value: object[.smoothing]?.floatValue ?? editor.lookPreset.shading.smoothing, range: 0 ... 1,
                          format: NumberFormat.percent, set: {
                              editor.setProperty(.smoothing, .float($0), coalesce: "smoothing-\(object.id.raw)")
                          }, done: editor.endGesture)
            if case let .primitive(shape) = object.kind, BevelSpec.applies(to: shape) {
                LabeledSlider(title: "Bevel", value: object[.bevel]?.floatValue ?? 0, range: 0 ... 0.2, format: { "\(Int(($0 * 100).rounded())) cm" },
                              set: { editor.setProperty(.bevel, .float($0), coalesce: "bevel-\(object.id.raw)") }, done: editor.endGesture)
            }
        }
    }
}

/// Look override: this object in another Look (one character from another universe), its lines, accent and gloss.
struct LookOverrideSection: View {
    let editor: EditorModel
    let object: SceneObject?

    var body: some View {
        PanelSection("Look") {
            Menu {
                Button("The scene's Look") { editor.setLookOverride(nil) }
                ForEach(editor.allLooks) { preset in
                    Button(preset.name) { editor.setLookOverride(preset.id) }
                }
            } label: {
                Label(currentTitle, systemImage: "paintpalette").font(.hmm(.body, weight: .semibold))
            }
            .accessibilityIdentifier("look-override")
            if let object {
                LabeledSlider(title: "Line weight", value: object.lineWeight, range: 0 ... 3, format: { String(format: "%.2g×", $0) }, set: {
                    editor.setProperty(.lineWeight, .float($0), coalesce: "lineweight-\(object.id.raw)")
                }, done: editor.endGesture)
                LabeledSlider(title: "Rim light", value: object[.rimStrength]?.floatValue ?? editor.lookPreset.shading.rim, range: 0 ... 1,
                              format: NumberFormat.percent, set: {
                                  editor.setProperty(.rimStrength, .float($0), coalesce: "rim-\(object.id.raw)")
                              }, done: editor.endGesture)
                Toggle("Accent (keeps its colour in Sketch)", isOn: Binding(get: { object.isAccent }, set: { editor.setProperty(.accent, .bool($0)) }))
                if accentCount > 1, editor.lookPreset.finish.accentKeepsColor {
                    Hint("\(accentCount) accents in this shot. One accent per shot reads best.")
                }
                Toggle("Glossy highlight", isOn: Binding(get: { object.isGlossy }, set: { editor.setProperty(.glossy, .bool($0)) }))
            }
        }
        .font(.hmm(.body))
    }

    private var currentTitle: String {
        guard let id = object?.lookOverride else { return "The scene's Look (\(editor.lookPreset.name))" }
        return LookLibrary.resolve(id, custom: editor.document.project.customLooks).name
    }

    private var accentCount: Int {
        editor.baseScene.objects.values.filter(\.isAccent).count
    }
}
