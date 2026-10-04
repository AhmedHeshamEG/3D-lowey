import HmmDesign
import LoweyCore
import SwiftUI

/// The part of the inspector that depends on what the object is.
struct KindSection: View {
    let editor: EditorModel
    let object: SceneObject

    var body: some View {
        switch object.kind {
        case let .light(type): LightSection(editor: editor, object: object, type: type)
        case .camera: CameraSection(editor: editor, camera: object.id)
        case let .text(recipe): TextSection(editor: editor, object: object, recipe: recipe)
        case let .overlay(recipe): OverlaySection(editor: editor, object: object, recipe: recipe)
        case let .particles(recipe): ParticleSection(editor: editor, object: object, recipe: recipe)
        default: EmptyView()
        }
    }
}

private struct LightSection: View {
    let editor: EditorModel
    let object: SceneObject
    let type: LightType

    var body: some View {
        PanelSection("Light") {
            ColorPicker("Colour", selection: Binding(get: { (object[.lightColor]?.colorValue?.resolved(in: editor.look.palette) ?? .white).color },
                                                     set: { editor.setProperty(.lightColor, .color(.rgba(RGBA($0))), coalesce: "lightcolor") }),
                        supportsOpacity: false)
            slider("Strength", .lightIntensity, 0 ... 6, 1)
            if type != .directional { slider("Reach", .lightRange, 0.5 ... 30, 6) }
            if type == .spot { slider("Cone", .spotAngle, 5 ... 120, 40) }
            if type == .directional {
                Hint("Only the sun casts shadows; lamps and spots light without them.")
            }
        }
        .font(.hmm(.body))
    }

    private func slider(_ title: String, _ key: PropertyKey, _ range: ClosedRange<Double>, _ fallback: Double) -> some View {
        LabeledSlider(title: title, value: object[key]?.floatValue ?? fallback, range: range, set: {
            editor.setProperty(key, .float($0), coalesce: "\(key.rawValue)-\(object.id.raw)")
        }, done: editor.endGesture)
    }
}

private struct TextSection: View {
    let editor: EditorModel
    let object: SceneObject
    let recipe: TextRecipe
    @State private var text = ""

    var body: some View {
        PanelSection("Text") {
            TextField("Words", text: $text, axis: .vertical)
                .font(.hmm(.headline, weight: .semibold))
                .lineLimit(1 ... 4)
                .onSubmit { editor.updateText(object.id) { $0.text = text } }
                .onAppear { text = recipe.text }
                .onChange(of: object.id) { _, _ in text = recipe.text }
                .accessibilityIdentifier("text-content")
            HmmPillButton("Apply", systemName: "checkmark") { editor.updateText(object.id) { $0.text = text } }
            Picker("Style", selection: Binding(get: { recipe.style }, set: { style in editor.updateText(object.id) { $0.style = style } })) {
                ForEach(TextRecipe.Style.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledSlider(title: "Depth", value: recipe.depth, range: 0.02 ... 1) { value in editor.updateText(object.id) { $0.depth = value } }
            Picker("Align", selection: Binding(get: { recipe.alignment }, set: { alignment in editor.updateText(object.id) { $0.alignment = alignment } })) {
                Image(systemName: "text.alignleft").tag(TextRecipe.Alignment.left)
                Image(systemName: "text.aligncenter").tag(TextRecipe.Alignment.center)
                Image(systemName: "text.alignright").tag(TextRecipe.Alignment.right)
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct OverlaySection: View {
    let editor: EditorModel
    let object: SceneObject
    let recipe: OverlayRecipe
    @State private var text = ""

    var body: some View {
        PanelSection(recipe.shape.title) {
            if recipe.shape.hasText {
                TextField("Words", text: $text, axis: .vertical)
                    .font(.hmm(.headline, weight: .semibold))
                    .lineLimit(1 ... 4)
                    .onSubmit { editor.updateOverlay(object.id) { $0.text = text } }
                    .onAppear { text = recipe.text }
                    .onChange(of: object.id) { _, _ in text = recipe.text }
                HmmPillButton("Apply", systemName: "checkmark") { editor.updateOverlay(object.id) { $0.text = text } }
                Picker("Font", selection: Binding(get: { recipe.font }, set: { font in editor.updateOverlay(object.id) { $0.font = font } })) {
                    ForEach(OverlayRecipe.Font.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if recipe.shape == .arrow {
                LabeledSlider(title: "Bend", value: recipe.bend, range: -1 ... 1) { value in editor.updateOverlay(object.id) { $0.bend = value } }
                LabeledSlider(title: "Length", value: recipe.aspect, range: 1 ... 8) { value in editor.updateOverlay(object.id) { $0.aspect = value } }
            }
            if [.highlight, .rectangle].contains(recipe.shape) {
                LabeledSlider(title: "Width", value: recipe.aspect, range: 0.5 ... 6) { value in editor.updateOverlay(object.id) { $0.aspect = value } }
            }
            if [.circle, .rectangle, .triangle, .star, .highlight].contains(recipe.shape) {
                Toggle("Filled", isOn: Binding(get: { recipe.filled }, set: { filled in editor.updateOverlay(object.id) { $0.filled = filled } }))
            }
            followMenu
            Hint("Drag it in the frame, pinch to size it, twist to turn it.")
        }
        .font(.hmm(.body))
    }

    private var followMenu: some View {
        Menu {
            if recipe.anchor != nil { Button("Stop following") { editor.updateOverlay(object.id) { $0.anchor = nil } } }
            ForEach(editor.baseScene.orderedIDs().filter { !(editor.baseScene.objects[$0]?.kind.isOverlay ?? true) }, id: \.self) { id in
                Button(editor.baseScene.objects[id]?.name ?? "?") { editor.updateOverlay(object.id) { $0.anchor = id } }
            }
        } label: {
            Label(recipe.anchor.flatMap { editor.baseScene.objects[$0]?.name }.map { "Follows \($0)" } ?? "Follow an object", systemImage: "link")
                .font(.hmm(.body, weight: .semibold))
        }
    }
}

private struct ParticleSection: View {
    let editor: EditorModel
    let object: SceneObject
    let recipe: ParticleRecipe

    var body: some View {
        PanelSection(recipe.preset.title) {
            LabeledSlider(title: "Amount", value: object.transform.scale.x, range: 0.1 ... 4, set: { value in
                editor.perform(.setProperties([PropertyChange(object: object.id, key: .scale, value: .vec3(Vec3(value, value, value)))]),
                               coalesceKey: "amount-\(object.id.raw)")
            }, done: editor.endGesture)
            LabeledSlider(title: "Size", value: recipe.size, range: 0.01 ... 1.5) { value in editor.updateParticles(object.id) { $0.size = value } }
            LabeledSlider(title: "Speed", value: recipe.speed, range: 0 ... 12) { value in editor.updateParticles(object.id) { $0.speed = value } }
            LabeledSlider(title: "Spread", value: recipe.spread, range: 0 ... 180) { value in editor.updateParticles(object.id) { $0.spread = value } }
            if recipe.burst {
                HStack {
                    Text("Goes off at \(TimeFormat.clock(recipe.burstTime))").font(.hmm(.body, weight: .semibold))
                    Spacer()
                    HmmPillButton("Playhead", systemName: "arrow.down.to.line") { editor.updateParticles(object.id) { $0.burstTime = editor.time } }
                }
            } else {
                Hint("Animate Emission (keys or Perform) to start and stop it.")
            }
            HmmPillButton("New variation", systemName: "dice") { editor.updateParticles(object.id) { $0.seed = UInt64.random(in: 1 ... 999_999) } }
        }
    }
}
