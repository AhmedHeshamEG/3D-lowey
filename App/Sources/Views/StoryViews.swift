import LoweyCore
import LoweyRender
import SwiftUI

/// Inspector sections for 3D text, overlays and particle effects.
struct RecipeInspector: View {
    @Bindable var editor: EditorModel
    let object: SceneObject
    @State private var text = ""

    var body: some View {
        switch object.kind {
        case let .text(recipe): textSection(recipe)
        case let .overlay(recipe): overlaySection(recipe)
        case let .particles(recipe): particleSection(recipe)
        default: EmptyView()
        }
    }

    // MARK: 3D text

    private func textSection(_ recipe: TextRecipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Text")
            TextField("Words", text: $text, axis: .vertical)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1 ... 4)
                .onSubmit { editor.updateText(object.id) { $0.text = text } }
                .onAppear { text = recipe.text }
                .onChange(of: object.id) { _, _ in text = recipe.text }
                .accessibilityIdentifier("text-content")
            PillButton(title: "Apply", systemName: "checkmark") { editor.updateText(object.id) { $0.text = text } }
            Picker("Style", selection: Binding(get: { recipe.style }, set: { style in editor.updateText(object.id) { $0.style = style } })) {
                ForEach(TextRecipe.Style.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            slider("Depth", value: recipe.depth, range: 0.02 ... 1) { value in editor.updateText(object.id) { $0.depth = value } }
            Picker("Align", selection: Binding(get: { recipe.alignment }, set: { alignment in editor.updateText(object.id) { $0.alignment = alignment } })) {
                Image(systemName: "text.alignleft").tag(TextRecipe.Alignment.left)
                Image(systemName: "text.aligncenter").tag(TextRecipe.Alignment.center)
                Image(systemName: "text.alignright").tag(TextRecipe.Alignment.right)
            }
            .pickerStyle(.segmented)
            if !recipe.coreMeshable, recipe.style == .blocky {
                Text("Blocky covers A–Z, 0–9 and punctuation; other letters use the Bold font.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: Overlays

    private func overlaySection(_ recipe: OverlayRecipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: recipe.shape.title)
            if recipe.shape.hasText {
                TextField("Words", text: $text, axis: .vertical)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1 ... 4)
                    .onSubmit { editor.updateOverlay(object.id) { $0.text = text } }
                    .onAppear { text = recipe.text }
                    .onChange(of: object.id) { _, _ in text = recipe.text }
                PillButton(title: "Apply", systemName: "checkmark") { editor.updateOverlay(object.id) { $0.text = text } }
                Picker("Font", selection: Binding(get: { recipe.font }, set: { font in editor.updateOverlay(object.id) { $0.font = font } })) {
                    ForEach(OverlayRecipe.Font.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if recipe.shape == .arrow {
                slider("Bend", value: recipe.bend, range: -1 ... 1) { value in editor.updateOverlay(object.id) { $0.bend = value } }
                slider("Length", value: recipe.aspect, range: 1 ... 8) { value in editor.updateOverlay(object.id) { $0.aspect = value } }
            }
            if [.highlight, .rectangle].contains(recipe.shape) {
                slider("Width", value: recipe.aspect, range: 0.5 ... 6) { value in editor.updateOverlay(object.id) { $0.aspect = value } }
            }
            if [.circle, .rectangle, .triangle, .star, .highlight].contains(recipe.shape) {
                Toggle("Filled", isOn: Binding(get: { recipe.filled }, set: { filled in editor.updateOverlay(object.id) { $0.filled = filled } }))
            }
            if ![.title, .label, .image, .question, .exclamation].contains(recipe.shape) {
                slider("Line", value: recipe.stroke, range: 0.03 ... 0.4) { value in editor.updateOverlay(object.id) { $0.stroke = value } }
            }
            HStack {
                if recipe.anchor != nil {
                    PillButton(title: "Stop following", systemName: "link.badge.plus") { editor.updateOverlay(object.id) { $0.anchor = nil } }
                }
                Menu {
                    ForEach(editor.baseScene.orderedIDs().filter { !(editor.baseScene.objects[$0]?.kind.isOverlay ?? true) }, id: \.self) { id in
                        Button(editor.baseScene.objects[id]?.name ?? "?") { editor.updateOverlay(object.id) { $0.anchor = id } }
                    }
                } label: {
                    Label(recipe.anchor == nil ? "Follow an object" : "Follows \(editor.baseScene.objects[recipe.anchor!]?.name ?? "?")",
                          systemImage: "link").pillLabel()
                }
            }
            Text("Drag it in the frame, pinch to size, twist to turn. Try Typewriter: text types itself, arrows draw themselves.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Particles

    private func particleSection(_ recipe: ParticleRecipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: recipe.preset.title)
            slider("Amount", value: object.transform.scale.x, range: 0.1 ... 4) { value in
                editor.perform(.setProperties([PropertyChange(object: object.id, key: .scale, value: .vec3(Vec3(value, value, value)))]),
                               coalesceKey: "amount-\(object.id.raw)")
            }
            slider("Size", value: recipe.size, range: 0.01 ... 1.5) { value in editor.updateParticles(object.id) { $0.size = value } }
            slider("Speed", value: recipe.speed, range: 0 ... 12) { value in editor.updateParticles(object.id) { $0.speed = value } }
            slider("Spread", value: recipe.spread, range: 0 ... 180) { value in editor.updateParticles(object.id) { $0.spread = value } }
            ColorPicker("Colour", selection: Binding(get: { recipe.colors.first?.color ?? .white }, set: { color in
                editor.updateParticles(object.id) { recipe in
                    guard !recipe.colors.isEmpty else { return }
                    let new = RGBA(color)
                    let old = recipe.colors[0]
                    // Tint the whole gradient by the change of its first colour (keeps the fade-out).
                    recipe.colors = recipe.colors.map { RGBA(min($0.r * new.r / max(old.r, 0.05), 1), min($0.g * new.g / max(old.g, 0.05), 1),
                                                             min($0.b * new.b / max(old.b, 0.05), 1), $0.a) }
                }
            }), supportsOpacity: false)
            if recipe.burst {
                HStack {
                    Text("Goes off at \(TimelineDrawer.format(recipe.burstTime))").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    PillButton(title: "At the playhead", systemName: "arrow.down.to.line") {
                        editor.updateParticles(object.id) { $0.burstTime = editor.time }
                    }
                }
            } else {
                Text("Animate “Emission” (Perform slider or keys) to start and stop it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            PillButton(title: "New variation", systemName: "dice") { editor.updateParticles(object.id) { $0.seed = UInt64.random(in: 1 ... 999_999) } }
        }
    }

    private func slider(_ title: String, value: Double, range: ClosedRange<Double>, set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold)).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range) { editing in
                if !editing { editor.endGesture() }
            }
            Text(NumberFormat.short(value)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.secondaryText).frame(width: 44)
        }
    }
}

/// Look panel: post-processing (applied identically in the live view and in exports).
struct PostSection: View {
    @Bindable var editor: EditorModel

    private var post: PostSettings { editor.look.post }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Finish (post)")
                Toggle("Preview", isOn: $editor.previewPost).toggleStyle(.button).font(.system(size: 12, weight: .semibold))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PostSettings.Preset.allCases) { preset in
                        PillButton(title: preset.title, prominent: post == preset.settings) {
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
            row("Exposure", \.exposure, range: -2 ... 2)
            row("Contrast", \.contrast, range: -1 ... 1)
            row("Colour", \.saturation, range: -1 ... 1)
            row("Warmth", \.temperature, range: -1 ... 1)
            row("Ink lines", \.outline)
            row("Colour fringe", \.chromaticAberration)
            row("Retro", \.retro)
            Picker("Texture", selection: Binding(get: { post.texture }, set: { texture in editor.updatePost { $0.texture = texture } })) {
                ForEach(PostSettings.Texture.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if post.texture != .none { row("Texture", \.textureStrength) }
            Toggle("Depth of field from the camera", isOn: Binding(get: { post.depthOfField }, set: { value in editor.updatePost { $0.depthOfField = value } }))
                .font(.system(size: 13, weight: .semibold))
        }
    }

    private func row(_ title: String, _ key: WritableKeyPath<PostSettings, Double>, range: ClosedRange<Double> = 0 ... 1) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold)).frame(width: 96, alignment: .leading)
            Slider(value: Binding(get: { post[keyPath: key] }, set: { value in editor.updatePost(coalesce: "post-\(title)") { $0[keyPath: key] = value } }),
                   in: range) { editing in
                if !editing { editor.endGesture() }
            }
        }
    }
}

/// Animate panel: flashes, shakes and friends at the playhead, and captions from the transcript.
struct ScreenAndCaptionSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Screen effects (at the playhead)")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(ScreenEffect.Kind.allCases) { kind in
                    Button { editor.addScreenEffect(kind) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: kind.systemImage).font(.system(size: 18))
                            Text(kind.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .foregroundStyle(Theme.text)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("effect-\(kind.rawValue)")
                }
            }
            ForEach(editor.timeline.effects) { effect in
                HStack {
                    Image(systemName: effect.kind.systemImage)
                    Text("\(effect.kind.title) · \(TimelineDrawer.format(effect.start))").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Slider(value: Binding(get: { effect.strength }, set: { value in
                        editor.updateScreenEffect(effect.id, coalesce: "fx-\(effect.id)") { $0.strength = value }
                    }), in: 0 ... 2) { editing in if !editing { editor.endGesture() } }
                        .frame(width: 90)
                    Button { editor.setTime(effect.start) } label: { Image(systemName: "arrow.right.circle") }
                    Button(role: .destructive) { editor.removeScreenEffect(effect.id) } label: { Image(systemName: "trash") }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.text)
            }
            SectionHeader(title: "Captions")
            let settings = editor.captions
            Toggle("Captions from the voiceover", isOn: Binding(get: { settings?.enabled ?? false }, set: { on in
                var new = settings ?? CaptionSettings()
                new.enabled = on
                editor.setCaptions(new)
            }))
            .font(.system(size: 14, weight: .semibold))
            .accessibilityIdentifier("captions-toggle")
            if let settings, settings.enabled {
                Picker("Style", selection: Binding(get: { settings.style }, set: { style in
                    var new = settings
                    new.style = style
                    editor.setCaptions(new)
                })) {
                    ForEach(CaptionSettings.Style.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Where", selection: Binding(get: { settings.position }, set: { position in
                    var new = settings
                    new.position = position
                    editor.setCaptions(new)
                })) {
                    ForEach(CaptionSettings.Position.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Size").font(.system(size: 13, weight: .semibold))
                    Slider(value: Binding(get: { settings.size }, set: { value in
                        var new = settings
                        new.size = value
                        editor.setCaptions(new, coalesce: "caption-size")
                    }), in: 0.03 ... 0.14) { editing in if !editing { editor.endGesture() } }
                }
                Toggle("Light up the spoken word", isOn: Binding(get: { settings.karaoke }, set: { value in
                    var new = settings
                    new.karaoke = value
                    editor.setCaptions(new)
                }))
                Toggle("CAPITALS", isOn: Binding(get: { settings.uppercase }, set: { value in
                    var new = settings
                    new.uppercase = value
                    editor.setCaptions(new)
                }))
                Toggle("Burn into the video", isOn: Binding(get: { settings.burnIn }, set: { value in
                    var new = settings
                    new.burnIn = value
                    editor.setCaptions(new)
                }))
                if editor.words.isEmpty {
                    Text("Transcribe the voiceover (waveform button in the timeline) and captions appear.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }
}

/// Timeline lane with the screen effects: drag a chip to retime it, tap to jump there, long-press to delete.
struct EffectsRow: View {
    @Bindable var editor: EditorModel
    let width: CGFloat
    let x: (Double) -> CGFloat
    let pps: Double
    @State private var drag: (id: String, delta: Double)?

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").font(.system(size: 11))
                Text("Effects").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Theme.secondaryText)
            .padding(.leading, 10)
            .frame(width: TimelineDrawer.labelWidth)
            ZStack(alignment: .leading) {
                ForEach(editor.timeline.effects) { effect in
                    let offset = drag?.id == effect.id ? drag?.delta ?? 0 : 0
                    Label(effect.kind.title, systemImage: effect.kind.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .frame(width: max(CGFloat(effect.duration * pps), 18), height: TimelineDrawer.wordsRowHeight - 4, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.pink.opacity(0.45)))
                        .offset(x: x(effect.start + offset))
                        .gesture(DragGesture(minimumDistance: 3)
                            .onChanged { value in drag = (effect.id, Double(value.translation.width) / pps) }
                            .onEnded { value in
                                let start = editor.wordSnapped(max(0, effect.start + Double(value.translation.width) / pps), tolerance: 8 / pps)
                                editor.updateScreenEffect(effect.id) { $0.start = start }
                                drag = nil
                            })
                        .onTapGesture { editor.setTime(effect.start) }
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { editor.removeScreenEffect(effect.id) }
                        }
                }
            }
            .frame(width: width, alignment: .leading)
            .clipped()
        }
    }
}

/// Camera panel: how the cut at the playhead hands over, and the match-cut helper.
struct TransitionSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Transition")
            if let cut = editor.cutAtPlayhead {
                let current = cut.transition?.kind ?? .cut
                Text("Cut to \(editor.baseScene.objects[cut.camera]?.name ?? "camera") at \(TimelineDrawer.format(cut.time))")
                    .font(.system(size: 13, weight: .semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TransitionSpec.Kind.allCases) { kind in
                            PillButton(title: kind.title, prominent: kind == current) {
                                editor.setTransition(kind, duration: cut.transition?.duration ?? 0.6, forCutAt: cut.time)
                            }
                        }
                    }
                }
                if let transition = cut.transition {
                    HStack {
                        Text("Length \(NumberFormat.short(transition.duration)) s").font(.system(size: 13, weight: .semibold))
                        Slider(value: Binding(get: { transition.duration }, set: { value in
                            editor.setTransition(transition.kind, duration: value, forCutAt: cut.time)
                        }), in: 0.1 ... 3)
                    }
                }
                PillButton(title: "Match cut on the selection", systemName: "rectangle.2.swap") { editor.matchCut() }
                Text("Match cut turns the new camera so what you selected sits exactly where it was in the last shot.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Add a cut (Cut here) to choose how the shots hand over.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// Add menu: words in the world, words and shapes on the frame, and effects.
struct AddStorySection: View {
    let editor: EditorModel
    let tile: (String, String, @escaping () -> Void) -> AnyView

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Characters")
            LazyVGrid(columns: columns, spacing: 10) {
                tile("Blob", "face.smiling") { editor.showBlobBuilder = true }
                    .accessibilityIdentifier("add-blob")
                tile("Me", "person.crop.circle") { editor.buildBlob(.hesham) }
                    .accessibilityIdentifier("add-me")
                tile("Character", "person.fill") {
                    editor.characterBuilderTarget = nil
                    editor.showCharacterBuilder = true
                }
                .accessibilityIdentifier("add-character")
            }
            SectionHeader(title: "Text")
            LazyVGrid(columns: columns, spacing: 10) {
                tile("3D text", "textformat") { editor.addText3D() }
                    .accessibilityIdentifier("add-text3d")
                tile("Title", "textformat.size") { editor.addOverlay(.title) }
                tile("Label", "tag") { editor.addOverlay(.label) }
            }
            SectionHeader(title: "On the frame")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach([OverlayRecipe.Shape.cross, .question, .arrow, .highlight, .exclamation, .check, .circle, .star], id: \.self) { shape in
                    tile(shape.title, shape.systemImage) { editor.addOverlay(shape) }
                        .accessibilityIdentifier("add-overlay-\(shape.rawValue)")
                }
            }
            SectionHeader(title: "Effects")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ParticleRecipe.Preset.allCases) { preset in
                    tile(preset.title, preset.systemImage) { editor.addParticles(preset) }
                        .accessibilityIdentifier("add-fx-\(preset.rawValue)")
                }
            }
        }
    }
}
