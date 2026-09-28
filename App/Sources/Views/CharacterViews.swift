import LoweyCore
import LoweyRender
import SwiftUI

/// The character builder: a handful of picks with a live preview. Few decisions, a whole character.
struct CharacterBuilderSheet: View {
    @Bindable var editor: EditorModel
    /// Editing an existing character (its root), or nil for a new one.
    let editing: ObjectID?
    @State private var recipe = CharacterRecipe()
    @State private var preview: UIImage?
    @State private var renderTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 0) {
            VStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(Theme.raised)
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFit().padding(10)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                TextField("Name", text: $recipe.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(width: 360)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(editing == nil ? "New character" : "Edit character").font(.system(size: 22, weight: .bold, design: .rounded))
                        Spacer()
                        PillButton(title: "Cancel") { dismiss() }
                        PillButton(title: editing == nil ? "Add to scene" : "Update", systemName: "checkmark", prominent: true) {
                            if let editing { editor.rebuildCharacter(editing, with: recipe) } else { editor.buildCharacter(recipe) }
                            dismiss()
                        }
                        .accessibilityIdentifier("character-done")
                    }
                    picker("Head", \.head, CharacterRecipe.Head.allCases)
                    picker("Hair", \.hair, CharacterRecipe.Hair.allCases)
                    picker("Eyes", \.eyes, CharacterRecipe.Eyes.allCases)
                    picker("Body", \.body, CharacterRecipe.Body.allCases)
                    picker("Top", \.top, CharacterRecipe.Top.allCases)
                    picker("Bottom", \.bottom, CharacterRecipe.Bottom.allCases)
                    SectionHeader(title: "Extras")
                    HStack {
                        ForEach(CharacterRecipe.Extra.allCases) { extra in
                            let on = recipe.extras.contains(extra)
                            PillButton(title: extra.rawValue.capitalized, prominent: on) {
                                if on {
                                    recipe.extras.removeAll { $0 == extra }
                                } else {
                                    recipe.extras.append(extra)
                                }
                            }
                        }
                    }
                    SectionHeader(title: "Colours")
                    colorRow("Skin", \.skin, swatches: ["#F3D2B8", "#E0AC82", "#C68A5E", "#9A6440", "#6B4329", "#45291A"])
                    colorRow("Hair", \.hairColor, swatches: ["#231812", "#5A3825", "#A8743D", "#E3C37A", "#B8B8B8", "#C0392B"])
                    colorRow("Top", \.topColor, swatches: nil)
                    colorRow("Bottom", \.bottomColor, swatches: nil)
                    colorRow("Shoes", \.shoeColor, swatches: nil)
                    HStack {
                        Text("Height").font(.system(size: 13, weight: .semibold))
                        Slider(value: $recipe.height, in: 0.6 ... 1.4)
                    }
                    Text(
                        "Built on the Humanoid standard: it plays every humanoid clip (built-in and imported), and its face is ready for "
                            + "lip sync and face capture. Save it to your library to reuse it everywhere."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                }
                .padding(20)
            }
        }
        .onAppear {
            if let editing, let existing = editor.recipe(of: editing) { recipe = existing }
            renderPreview()
        }
        .onChange(of: recipe) { _, _ in renderPreview() }
    }

    private func picker<T: RawRepresentable & Hashable & Identifiable>(_ title: String, _ key: WritableKeyPath<CharacterRecipe, T>,
                                                                       _ options: [T]) -> some View where T.RawValue == String {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options) { option in
                        PillButton(title: option.rawValue.capitalized, prominent: recipe[keyPath: key] == option) { recipe[keyPath: key] = option }
                    }
                }
            }
        }
    }

    private func colorRow(_ title: String, _ key: WritableKeyPath<CharacterRecipe, ColorValue>, swatches: [String]?) -> some View {
        let palette = editor.look.palette
        let colors: [ColorValue] = swatches.map { $0.compactMap { RGBA(hex: $0).map(ColorValue.rgba) } }
            ?? palette.visibleSlots.map { ColorValue.palette($0) }
        return HStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).frame(width: 60, alignment: .leading)
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                let selected = recipe[keyPath: key] == color
                Circle()
                    .fill(color.resolved(in: palette).color)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(selected ? Theme.accent : Color.white.opacity(0.2), lineWidth: selected ? 3 : 1))
                    .onTapGesture { recipe[keyPath: key] = color }
            }
            ColorPicker("", selection: Binding(get: { recipe[keyPath: key].resolved(in: palette).color },
                                               set: { recipe[keyPath: key] = .rgba(RGBA($0)) }), supportsOpacity: false)
                .labelsHidden()
        }
    }

    /// A portrait of the character (offscreen render of just the character, facing the camera).
    private func renderPreview() {
        renderTask?.cancel()
        let recipe = recipe
        let look = editor.look
        renderTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            preview = await CharacterPreview.render(recipe, look: look)
        }
    }
}

/// Renders a character alone for the builder's preview.
@MainActor
enum CharacterPreview {
    private static let offscreen = OffscreenRenderer()

    static func render(_ recipe: CharacterRecipe, look: Look) async -> UIImage? {
        var ids = IDFactory.random
        let fragment = CharacterBuilder.build(recipe, ids: &ids)
        var scene = CoreScene(id: .make(), name: "Preview")
        for object in fragment.objects {
            scene.objects[object.id] = object
        }
        scene.roots = fragment.roots
        var previewLook = look
        previewLook.ground.visible = false
        previewLook.fog.enabled = false
        previewLook.post = PostSettings()
        scene.look = previewLook
        let document = Document(project: ProjectInfo(id: .make(), name: "Preview", look: previewLook), scene: scene)
        let renderer = SceneRenderer()
        renderer.showsHelpers = false
        renderer.load(document)
        let height = 1.7 * recipe.height
        let viewpoint = Viewpoint(target: Vec3(0, height * 0.55, 0), yaw: 18, pitch: 6, distance: height * 2.4, fieldOfView: 35)
        guard let image = try? await offscreen.snapshot(of: renderer, viewpoint: viewpoint, framing: .portrait, longSide: 720) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Animate panel: a built character — clips, lip sync, face.
struct PuppetSection: View {
    @Bindable var editor: EditorModel
    let character: ObjectID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Character · \(editor.baseScene.objects[character]?.name ?? "")")
            HStack {
                Menu {
                    ForEach(editor.puppetClips(), id: \.self) { clip in
                        Button(clip.asset == BuiltinClips.assetID ? clip
                            .name : "\(clip.name) — \(editor.library.manifest.asset(clip.asset)?.name ?? "library")") {
                                editor.addClip(clip)
                            }
                    }
                } label: {
                    Label("Play a clip", systemImage: "figure.walk").pillLabel()
                }
                .accessibilityIdentifier("puppet-clip")
                PillButton(title: "Edit look", systemName: "person.crop.circle") {
                    editor.characterBuilderTarget = character
                    editor.showCharacterBuilder = true
                }
            }
            if let track = editor.clipTrack(for: character) {
                ForEach(track.segments) { segment in
                    Text("\(segment.clip.name) from \(TimelineDrawer.format(segment.start))").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                Toggle("Feet stay on the ground", isOn: Binding(get: { track.ik.feetOnGround }, set: { value in editor.setIK { $0.feetOnGround = value } }))
                    .font(.system(size: 13))
            }
            FaceSection(editor: editor, character: character)
        }
    }
}

/// Lip sync and face performance (built characters and rigged models).
struct FaceSection: View {
    @Bindable var editor: EditorModel
    let character: ObjectID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Voice & face")
            HStack {
                PillButton(title: editor.wordSelection == nil ? "Lip sync to the voiceover" : "Lip sync these words", systemName: "mouth",
                           prominent: !editor.words.isEmpty) { editor.lipSync(character) }
                    .accessibilityIdentifier("lip-sync")
            }
            if editor.faceActive {
                HStack {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                    Text(editor.faceStatus ?? "Face on").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    PillButton(title: "Neutral", systemName: "face.smiling") { editor.facePerformer.recalibrate() }
                    PillButton(title: "Stop", systemName: "stop.fill") { editor.stopFaceCapture() }
                }
                Toggle("Mirror", isOn: Binding(get: { editor.facePerformer.mirror }, set: { editor.facePerformer.mirror = $0 }))
                    .font(.system(size: 13))
                Text("Your face drives the character live. Press Record (Timeline → Perform) to capture a take.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                HStack {
                    PillButton(title: "Face (front camera)", systemName: "camera.fill") { editor.startFaceCapture(useIPhone: false) }
                        .accessibilityIdentifier("face-camera")
                    PillButton(title: "Use my iPhone", systemName: "iphone") { editor.startFaceCapture(useIPhone: true) }
                }
            }
        }
    }
}
