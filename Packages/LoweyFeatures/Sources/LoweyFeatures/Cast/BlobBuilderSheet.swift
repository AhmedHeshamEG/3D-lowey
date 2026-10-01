import HmmDesign
import LoweyCore
import SwiftUI

/// A Blob: pick who (or start blank), then the clues (hat, name on the hat, hair, accessories, what it holds).
struct BlobBuilderSheet: View {
    let editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var recipe = BlobRecipe.hesham
    @State private var who = "hesham"

    private static let order = ["hesham", "newton", "einstein", "turing", "curie", "darwin", "tesla", "lovelace", "edison", "sherlock", "wizard"]

    var body: some View {
        HmmSheet("Blob", primary: ("Add", {
            editor.buildBlob(recipe)
            dismiss()
        })) {
            TextField("Name", text: $recipe.name)
                .font(.hmm(.title3, weight: .semibold))
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("blob-name")
            section("Who") {
                chips(Self.order + ["blank"], selected: who, title: { $0 == "blank" ? "Blank" : Likeness.people[$0]?.name ?? $0 }) { key in
                    who = key
                    recipe = key == "blank" ? BlobRecipe(name: "Blob") : Likeness.people[key] ?? BlobRecipe()
                }
            }
            section("Hat") {
                chips(BlobRecipe.Hat.allCases, selected: recipe.hat, title: { $0.rawValue.spacedTitle }) { recipe.hat = $0 }
                if recipe.hat != .none {
                    TextField("Name on the hat", text: $recipe.hatLabel).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    colorWell("Hat colour", \.hatColor)
                }
            }
            section("Hair") {
                chips(BlobRecipe.Hair.allCases, selected: recipe.hair, title: { $0.rawValue.spacedTitle }) { recipe.hair = $0 }
                if recipe.hair != .none { colorWell("Hair colour", \.hairColor) }
            }
            section("Accessories") {
                FlowChips(items: BlobRecipe.Accessory.allCases.map { ($0.rawValue, $0.rawValue.spacedTitle) },
                          isOn: { key in recipe.accessories.contains { $0.rawValue == key } }) { key in
                    guard let accessory = BlobRecipe.Accessory(rawValue: key) else { return }
                    if let index = recipe.accessories.firstIndex(of: accessory) {
                        recipe.accessories.remove(at: index)
                    } else {
                        recipe.accessories.append(accessory)
                    }
                }
                if !recipe.accessories.isEmpty { colorWell("Accessory colour", \.accessoryColor) }
            }
            section("Holding") {
                chips(BlobRecipe.Prop.allCases, selected: recipe.prop, title: { $0.rawValue.spacedTitle }) { recipe.prop = $0 }
            }
            section("Look") {
                colorWell("Skin", \.skin)
                Toggle("Blush", isOn: $recipe.blush)
                Toggle("Hover glow", isOn: $recipe.hover)
            }
            HmmPillButton("Add to the scene", systemName: "checkmark", prominent: true) {
                editor.buildBlob(recipe)
                dismiss()
            }
            .accessibilityIdentifier("blob-add")
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            HmmSectionHeader(title)
            content()
        }
    }

    private func chips<Item: Hashable>(_ items: [Item], selected: Item, title: @escaping (Item) -> String, pick: @escaping (Item) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HmmSpacing.xs) {
                ForEach(items, id: \.self) { item in
                    ChoiceChip(title: title(item), isOn: item == selected) { pick(item) }
                }
            }
        }
    }

    private func colorWell(_ label: String, _ key: WritableKeyPath<BlobRecipe, ColorValue>) -> some View {
        ColorPicker(label, selection: Binding(get: { recipe[keyPath: key].resolved(in: editor.look.palette).color },
                                              set: { recipe[keyPath: key] = .rgba(RGBA($0)) }), supportsOpacity: false)
            .fixedSize()
    }
}

/// A Puppet (a humanoid made of rigid parts): a handful of picks with a live portrait.
struct CharacterBuilderSheet: View {
    let editor: EditorModel
    let editing: ObjectID?
    @State private var recipe = CharacterRecipe()
    @State private var preview: UIImage?
    @State private var renderTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HmmSheet(editing == nil ? "New puppet" : "Edit puppet", primary: (editing == nil ? "Add" : "Update", done)) {
            ZStack {
                RoundedRectangle(cornerRadius: HmmRadius.panel).fill(theme.surface2)
                if let preview { Image(uiImage: preview).resizable().scaledToFit().padding(HmmSpacing.s) } else { ProgressView() }
            }
            .frame(height: 300)
            TextField("Name", text: $recipe.name).font(.hmm(.title3, weight: .semibold))
            picker("Head", \.head, CharacterRecipe.Head.allCases)
            picker("Hair", \.hair, CharacterRecipe.Hair.allCases)
            picker("Eyes", \.eyes, CharacterRecipe.Eyes.allCases)
            picker("Body", \.body, CharacterRecipe.Body.allCases)
            picker("Top", \.top, CharacterRecipe.Top.allCases)
            picker("Bottom", \.bottom, CharacterRecipe.Bottom.allCases)
            HmmSectionHeader("Extras")
            FlowChips(items: CharacterRecipe.Extra.allCases.map { ($0.rawValue, $0.rawValue.spacedTitle) },
                      isOn: { key in recipe.extras.contains { $0.rawValue == key } }) { key in
                guard let extra = CharacterRecipe.Extra(rawValue: key) else { return }
                if let index = recipe.extras.firstIndex(of: extra) { recipe.extras.remove(at: index) } else { recipe.extras.append(extra) }
            }
            HmmSectionHeader("Colours")
            colorPicker("Skin", \.skin)
            colorPicker("Hair", \.hairColor)
            colorPicker("Top", \.topColor)
            colorPicker("Bottom", \.bottomColor)
            colorPicker("Shoes", \.shoeColor)
            LabeledSlider(title: "Height", value: recipe.height, range: 0.6 ... 1.4, format: NumberFormat.percent) { recipe.height = $0 }
            Hint("Built on the Humanoid standard: it plays every humanoid clip and its face is ready for lip sync and face capture.")
            HmmPillButton(editing == nil ? "Add to the scene" : "Update", systemName: "checkmark", prominent: true, action: done)
                .accessibilityIdentifier("character-done")
        }
        .onAppear {
            if let editing, let existing = editor.recipe(of: editing) { recipe = existing }
            renderPreview()
        }
        .onChange(of: recipe) { _, _ in renderPreview() }
    }

    private func done() {
        if let editing { editor.rebuildCharacter(editing, with: recipe) } else { editor.buildCharacter(recipe) }
        dismiss()
    }

    private func picker<T: RawRepresentable & Hashable & Identifiable>(_ title: String, _ key: WritableKeyPath<CharacterRecipe, T>,
                                                                       _ options: [T]) -> some View where T.RawValue == String {
        VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
            HmmSectionHeader(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.xs) {
                    ForEach(options) { option in
                        ChoiceChip(title: option.rawValue.spacedTitle, isOn: recipe[keyPath: key] == option) { recipe[keyPath: key] = option }
                    }
                }
            }
        }
    }

    private func colorPicker(_ title: String, _ key: WritableKeyPath<CharacterRecipe, ColorValue>) -> some View {
        ColorPicker(title, selection: Binding(get: { recipe[keyPath: key].resolved(in: editor.look.palette).color },
                                              set: { recipe[keyPath: key] = .rgba(RGBA($0)) }), supportsOpacity: false)
    }

    /// A portrait of the puppet alone, facing the camera.
    private func renderPreview() {
        renderTask?.cancel()
        let recipe = recipe
        let presetID = editor.look.presetID
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            var ids = IDFactory.random
            let fragment = CharacterBuilder.build(recipe, ids: &ids)
            if let image = try? await editor.app.thumbnailer.portrait(of: fragment, look: presetID, width: 600, height: 800, yaw: 18, pitch: 6) {
                preview = UIImage(cgImage: image)
            }
        }
    }
}
