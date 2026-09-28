import LoweyCore
import SwiftUI

/// The blob character sheet: pick who (or start blank), then the clues (hat, name on the hat, hair, accessories, prop).
struct BlobBuilderSheet: View {
    let editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var recipe = BlobRecipe.hesham
    @State private var who = "hesham"

    private static let order = ["hesham", "newton", "einstein", "turing", "curie", "darwin", "tesla", "lovelace", "edison", "sherlock", "wizard"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TextField("Name", text: $recipe.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("blob-name")
                    section("Who") {
                        chips(Self.order + ["blank"], selected: who, title: { $0 == "blank" ? "Blank" : Likeness.people[$0]?.name ?? $0 }) { key in
                            who = key
                            recipe = key == "blank" ? BlobRecipe(name: "Blob") : Likeness.people[key] ?? BlobRecipe()
                        }
                    }
                    section("Hat") {
                        chips(BlobRecipe.Hat.allCases, selected: recipe.hat, title: Self.title) { recipe.hat = $0 }
                        if recipe.hat != .none {
                            HStack(spacing: 12) {
                                TextField("Name on the hat", text: $recipe.hatLabel)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 260)
                                colorWell("Hat", \.hatColor)
                            }
                        }
                    }
                    section("Hair") {
                        chips(BlobRecipe.Hair.allCases, selected: recipe.hair, title: Self.title) { recipe.hair = $0 }
                        if recipe.hair != .none { colorWell("Hair", \.hairColor) }
                    }
                    section("Accessories") {
                        FlowChips(items: BlobRecipe.Accessory.allCases.map { ($0.rawValue, Self.title($0)) },
                                  isOn: { key in recipe.accessories.contains { $0.rawValue == key } }) { key in
                            guard let accessory = BlobRecipe.Accessory(rawValue: key) else { return }
                            if let index = recipe.accessories.firstIndex(of: accessory) {
                                recipe.accessories.remove(at: index)
                            } else {
                                recipe.accessories.append(accessory)
                            }
                        }
                        if !recipe.accessories.isEmpty { colorWell("Accessories", \.accessoryColor) }
                    }
                    section("Holding") {
                        chips(BlobRecipe.Prop.allCases, selected: recipe.prop, title: Self.title) { recipe.prop = $0 }
                    }
                    section("Look") {
                        HStack(spacing: 18) {
                            colorWell("Skin", \.skin)
                            Toggle("Blush", isOn: $recipe.blush).fixedSize()
                            Toggle("Hover glow", isOn: $recipe.hover).fixedSize()
                        }
                        .font(.system(size: 14))
                    }
                }
                .padding(24)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        editor.buildBlob(recipe)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("blob-add")
                }
            }
        }
    }

    // MARK: Pieces

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.secondaryText)
            content()
        }
    }

    private func chips<Item: Hashable>(_ items: [Item], selected: Item, title: @escaping (Item) -> String, pick: @escaping (Item) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Chip(title: title(item), isOn: item == selected) { pick(item) }
                }
            }
        }
    }

    private func colorWell(_ label: String, _ key: WritableKeyPath<BlobRecipe, ColorValue>) -> some View {
        ColorPicker(label, selection: Binding(
            get: { recipe[keyPath: key].resolved(in: editor.look.palette).color },
            set: { recipe[keyPath: key] = .rgba(RGBA($0)) }
        ), supportsOpacity: false)
            .font(.system(size: 14))
            .fixedSize()
    }

    /// camelCase → "Camel case".
    static func title(_ value: some RawRepresentable<String>) -> String {
        var result = ""
        for character in value.rawValue {
            if character.isUppercase { result += " " }
            result += String(character)
        }
        return result.prefix(1).uppercased() + result.dropFirst().lowercased()
    }
}

/// One selectable pill.
private struct Chip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(isOn ? Color.black : Theme.text)
                .background(Capsule().fill(isOn ? Theme.accent : Theme.raised))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Toggle chips that wrap onto new lines.
private struct FlowChips: View {
    let items: [(key: String, title: String)]
    let isOn: (String) -> Bool
    let toggle: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.key) { item in
                Chip(title: item.title, isOn: isOn(item.key)) { toggle(item.key) }
            }
        }
    }
}
