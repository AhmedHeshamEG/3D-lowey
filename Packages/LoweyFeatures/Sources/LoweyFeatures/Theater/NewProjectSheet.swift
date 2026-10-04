import HmmDesign
import LoweyCore
import SwiftUI

/// New project: a name and a starter template, nothing else needed. The template suggests a Mood and a Look; both
/// can be changed here or any time later from Look.
struct NewProjectSheet: View {
    let create: (String, StarterTemplate, LightingPreset, String) -> Void
    @State private var name = ""
    @State private var template = StarterTemplate.blank
    @State private var mood: LightingPreset = StarterTemplate.blank.mood
    @State private var look = StarterTemplate.blank.lookPresetID
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HmmSheet("New project", primary: ("Create", { create(name, template, mood, look) })) {
            TextField("Name (e.g. Enigma)", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.hmm(.title3))
                .accessibilityIdentifier("project-name")
            HmmSectionHeader("Start from")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: HmmSpacing.s)], spacing: HmmSpacing.s) {
                ForEach(StarterTemplate.all) { item in
                    TemplateCard(template: item, selected: item.kind == template.kind) { choose(item) }
                }
            }
            HmmSectionHeader("Mood")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.s) {
                    ForEach(LightingPreset.allCases, id: \.self) { item in
                        Button {
                            HmmHaptics.play(.selection)
                            mood = item
                        } label: {
                            MoodCard(mood: item, selected: item == mood)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HmmSectionHeader("Look")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.s) {
                    ForEach(LookPreset.builtIns) { preset in
                        Button {
                            HmmHaptics.play(.selection)
                            look = preset.id
                        } label: {
                            LookCard(preset: preset, selected: preset.id == look, mood: mood)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Hint("Both change any time from the Look button.")
            HmmPillButton("Create", systemName: "sparkles", prominent: true) { create(name, template, mood, look) }
                .accessibilityIdentifier("create-project")
        }
    }

    private func choose(_ item: StarterTemplate) {
        HmmHaptics.play(.selection)
        withHmmAnimation(.snappy) {
            template = item
            mood = item.mood
            look = item.lookPresetID
        }
    }
}

/// A starter template: what it's for, in a line.
private struct TemplateCard: View {
    let template: StarterTemplate
    let selected: Bool
    let action: () -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                Image(systemName: template.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(selected ? theme.accent : theme.text)
                Text(LocalizedStringKey(template.title)).font(.hmm(.body, weight: .semibold)).foregroundStyle(theme.text)
                Text(LocalizedStringKey(template.subtitle)).font(.hmm(.caption)).foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(HmmSpacing.s)
            .background(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous).fill(theme.surface2))
            .overlay(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous).stroke(selected ? theme.accent : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(template.title)))
        .accessibilityHint(Text(LocalizedStringKey(template.subtitle)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("template-\(template.kind.rawValue)")
    }
}
