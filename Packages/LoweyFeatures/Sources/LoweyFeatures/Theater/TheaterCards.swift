import HmmDesign
import LoweyCore
import SwiftUI
import UIKit

struct NewProjectCard: View {
    let action: () -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: HmmSpacing.s) {
                Image(systemName: "plus").font(.system(size: 40, weight: .semibold)).foregroundStyle(theme.accent)
                Text("New project").font(.hmm(.headline, weight: .semibold)).foregroundStyle(theme.text)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 11, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: HmmRadius.panel, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("new-project")
        .hoverEffect(.lift)
    }
}

/// A project: its looping preview (or still), name, scenes and when it changed.
struct ProjectCard: View {
    let project: ProjectSummary
    let thumbnail: UIImage?
    let loop: [CGImage]?
    let inICloud: Bool
    @Environment(\.hmmTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            preview
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous).stroke(theme.line))
                .overlay(alignment: .topTrailing) {
                    if inICloud {
                        Image(systemName: "icloud")
                            .font(.hmm(.caption, weight: .semibold))
                            .padding(HmmSpacing.xs)
                            .hmmGlass(in: Circle(), interactive: false)
                            .padding(HmmSpacing.xs)
                            .accessibilityLabel("In iCloud Drive")
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(project.info.name).font(.hmm(.headline, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                Text(subtitle).font(.hmm(.footnote)).foregroundStyle(theme.text2)
            }
            .padding(.horizontal, HmmSpacing.xxs)
        }
        .contentShape(Rectangle())
        .hoverEffect(.lift)
    }

    private var subtitle: String {
        let scenes = project.info.sceneOrder.count
        return "\(scenes) scene\(scenes == 1 ? "" : "s") · \(project.info.modified.formatted(.relative(presentation: .named)))"
    }

    @ViewBuilder private var preview: some View {
        if let loop, loop.count > 1, !reduceMotion {
            TimelineView(.periodic(from: .now, by: 1.0 / 8)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate * 8) % loop.count
                Image(decorative: loop[index], scale: 1).resizable().scaledToFill()
            }
        } else if let thumbnail {
            Image(uiImage: thumbnail).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [theme.surface2, theme.surface], startPoint: .top, endPoint: .bottom)
                Image(systemName: "cube.transparent").font(.system(size: 40)).foregroundStyle(theme.text3)
            }
        }
    }
}

/// New project: a name and two picks (Mood and Look). Nothing else.
struct NewProjectSheet: View {
    let create: (String, LightingPreset, String) -> Void
    @State private var name = ""
    @State private var mood: LightingPreset = .day
    @State private var look = LookPreset.ink.id
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HmmSheet("New project", primary: ("Create", { create(name, mood, look) })) {
            TextField("Name (e.g. Enigma)", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.hmm(.title3))
                .accessibilityIdentifier("project-name")
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
            HmmPillButton("Create", systemName: "sparkles", prominent: true) { create(name, mood, look) }
                .accessibilityIdentifier("create-project")
        }
    }
}
