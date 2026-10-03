import HmmDesign
import LoweyCore
import SwiftUI

/// The parameters of a My Look: shading, lines, print and finish, animation stepping.
struct MyLookEditor: View {
    let editor: EditorModel
    let preset: LookPreset
    @State private var name = ""

    var body: some View {
        PanelSection("My Look") {
            TextField("Name", text: $name)
                .font(.hmm(.headline, weight: .semibold))
                .onSubmit { editor.renameCustomLook(preset.id, to: name) }
                .onAppear { name = preset.name }
            Picker("Shading", selection: binding(\.shading.model)) {
                Text("Toon").tag(LookModel.toon)
                Text("Clay").tag(LookModel.clay)
            }
            .pickerStyle(.segmented)
            Picker("Bands", selection: binding(\.shading.bands)) {
                Text("2 bands").tag(2)
                Text("3 bands").tag(3)
            }
            .pickerStyle(.segmented)
            slider("Shadow edge", \.shading.edgeSoftness, 0.002 ... 0.08)
            slider("Shadow depth", \.shading.shadowValue, 0 ... 0.7)
            slider("Rim light", \.shading.rim, 0 ... 1)
            slider("Contact shading", \.shading.contactShading, 0 ... 1)
            slider("Shape smoothing", \.shading.smoothing, 0 ... 1)
            Toggle("Lines", isOn: binding(\.lines.enabled))
            if preset.lines.enabled {
                slider("Line width", \.lines.width, 0.5 ... 6)
                slider("Boil", \.lines.boil, 0 ... 1)
                Toggle("Pencil lines", isOn: binding(\.lines.pencil))
                Picker("Line colour", selection: binding(\.lines.colorMode)) {
                    Text("Darkened colour").tag(LineParams.ColorMode.darkened)
                    Text("Ink").tag(LineParams.ColorMode.ink)
                }
                .pickerStyle(.segmented)
            }
            slider("Halftone", \.comic.halftone, 0 ... 1)
            Toggle("Colour misregistration", isOn: binding(\.comic.misregistration))
            slider("Paper grain", \.finish.paperGrain, 0 ... 1)
            slider("Saturation", \.finish.saturation, -1 ... 1)
            Toggle("Accents keep their colour", isOn: binding(\.finish.accentKeepsColor))
            Picker("Animation", selection: binding(\.stepping)) {
                Text("On ones").tag(Stepping.onOnes)
                Text("On twos").tag(Stepping.onTwos)
                Text("On threes").tag(Stepping.onThrees)
                Text("On fours").tag(Stepping.onFours)
            }
            .pickerStyle(.segmented)
        }
    }

    private func binding<Value: Equatable>(_ path: WritableKeyPath<LookPreset, Value>) -> Binding<Value> {
        Binding(get: { preset[keyPath: path] }, set: { value in editor.updateCustomLook(preset.id) { $0[keyPath: path] = value } })
    }

    private func slider(_ title: String, _ path: WritableKeyPath<LookPreset, Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledSlider(title: title, value: preset[keyPath: path], range: range, set: { value in
            editor.updateCustomLook(preset.id, coalesce: "mylook-\(title)") { $0[keyPath: path] = value }
        }, done: editor.endGesture)
    }
}

/// Finish: glow, vignette, grain, grade, outlines over any Look, colour fringe, retro, textures, depth of field.
/// Applied identically on the stage and in exports.
struct FinishSection: View {
    let editor: EditorModel

    private var post: PostSettings { editor.look.post }

    var body: some View {
        PanelSection("Finish") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.xs) {
                    ForEach(PostSettings.Preset.allCases) { preset in
                        ChoiceChip(title: preset.title, isOn: post == preset.settings) {
                            editor.updatePost { settings in
                                let keepDepth = settings.depthOfField
                                settings = preset.settings
                                settings.depthOfField = keepDepth
                            }
                        }
                    }
                }
            }
            row("Glow", \.bloom)
            row("Vignette", \.vignette)
            row("Grain", \.grain)
            row("Exposure", \.exposure, -2 ... 2)
            row("Contrast", \.contrast, -1 ... 1)
            row("Colour", \.saturation, -1 ... 1)
            row("Warmth", \.temperature, -1 ... 1)
            row("Outlines", \.outline)
            row("Colour fringe", \.chromaticAberration)
            row("Retro", \.retro)
            Picker("Texture", selection: Binding(get: { post.texture }, set: { texture in editor.updatePost { $0.texture = texture } })) {
                ForEach(PostSettings.Texture.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if post.texture != .none { row("Texture", \.textureStrength) }
            Toggle("Depth of field from the camera", isOn: Binding(get: { post.depthOfField }, set: { value in editor.updatePost { $0.depthOfField = value } }))
                .font(.hmm(.body))
        }
    }

    private func row(_ title: String, _ path: WritableKeyPath<PostSettings, Double>, _ range: ClosedRange<Double> = 0 ... 1) -> some View {
        LabeledSlider(title: title, value: post[keyPath: path], range: range, set: { value in
            editor.updatePost(coalesce: "post-\(title)") { $0[keyPath: path] = value }
        }, done: editor.endGesture)
    }
}

/// The world: sun, sky, ambient, fog, stars and ground.
struct WorldSection: View {
    let editor: EditorModel

    private var look: Look { editor.look }

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Toggle("Fog", isOn: Binding(get: { look.fog.enabled }, set: { value in editor.updateLook { $0.fog.enabled = value } }))
            if look.fog.enabled { slider("Fog distance", \.fog.distance, 5 ... 200) }
            slider("Stars", \.sky.stars, 0 ... 1)
            Toggle("Ground", isOn: Binding(get: { look.ground.visible }, set: { value in editor.updateLook { $0.ground.visible = value } }))
            slider("Sun height", \.lighting.sunElevation, 2 ... 90)
            slider("Sun direction", \.lighting.sunAzimuth, 0 ... 360)
            slider("Sun strength", \.lighting.sunIntensity, 0 ... 2)
            slider("Ambient", \.lighting.ambientIntensity, 0 ... 2)
            slider("Exposure", \.lighting.exposure, -2 ... 2)
            Toggle("Sun shadows", isOn: Binding(get: { look.lighting.sunShadows }, set: { value in editor.updateLook { $0.lighting.sunShadows = value } }))
            color("Sun colour", \.lighting.sunColor)
            color("Sky top", \.sky.top)
            color("Horizon", \.sky.horizon)
            color("Below", \.sky.bottom)
            color("Fog colour", \.fog.color)
            color("Ground colour", \.ground.color)
            slider("Ground size", \.ground.size, 5 ... 200)
        }
        .font(.hmm(.body))
    }

    private func slider(_ title: String, _ path: WritableKeyPath<Look, Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledSlider(title: title, value: look[keyPath: path], range: range, set: { value in
            editor.updateLook(coalesce: "look-\(title)") { $0[keyPath: path] = value }
        }, done: editor.endGesture)
    }

    private func color(_ title: String, _ path: WritableKeyPath<Look, RGBA>) -> some View {
        ColorPicker(title, selection: Binding(get: { look[keyPath: path].color }, set: { value in
            editor.updateLook(coalesce: "look-\(title)") { $0[keyPath: path] = RGBA(value) }
        }), supportsOpacity: false)
    }
}
