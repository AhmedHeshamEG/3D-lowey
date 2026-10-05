import HmmDesign
import HmmDocuments
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

/// A project, alive: the model turning in its Look while the card is on screen, its name and when it changed. Tapping
/// it grows it into the stage (the zoom source is its picture).
struct ProjectCard: View {
    let project: ProjectSummary
    let zoom: Namespace.ID
    let playing: Bool
    var selection: Bool?
    @Environment(AppModel.self) private var app
    @Environment(\.hmmTheme) private var theme
    @State private var still: UIImage?

    var body: some View {
        let revision = app.cardRevisions[project.id] ?? 0
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            TurntableView(url: project.url.appendingPathComponent(Thumbnailer.loopFile), still: still, revision: revision, playing: playing)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous).stroke(theme.line))
                .overlay(alignment: .topTrailing) { badge }
                .matchedTransitionSource(id: project.id.raw, in: zoom)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.info.name).font(.hmm(.headline, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                Text(subtitle).font(.hmm(.footnote)).foregroundStyle(theme.text2)
            }
            .padding(.horizontal, HmmSpacing.xxs)
        }
        .contentShape(Rectangle())
        .hoverEffect(.lift)
        .task(id: revision) { still = await app.cardImage(for: project) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selection == true ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var badge: some View {
        if let selection {
            Image(systemName: selection ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(selection ? theme.onAccent : theme.text, selection ? theme.accent : theme.surface.opacity(0.6))
                .padding(HmmSpacing.xs)
        } else if app.storage.isICloud {
            Image(systemName: "icloud")
                .font(.hmm(.caption, weight: .semibold))
                .padding(HmmSpacing.xs)
                .hmmGlass(in: Circle(), interactive: false)
                .padding(HmmSpacing.xs)
                .accessibilityLabel("In iCloud Drive")
        }
    }

    private var subtitle: String {
        let scenes = project.info.sceneOrder.count
        return "\(scenes) scene\(scenes == 1 ? "" : "s") · \(project.info.modified.formatted(.relative(presentation: .named)))"
    }
}

/// A stack: its projects fanned like cards on a table, its name and how many it holds. Tap to open it.
struct StackCard: View {
    let stack: GalleryStack
    let members: [ProjectSummary]
    @Environment(AppModel.self) private var app
    @Environment(\.hmmTheme) private var theme
    @State private var stills: [ProjectID: UIImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            ZStack {
                ForEach(Array(members.prefix(3).enumerated().reversed()), id: \.element.id) { index, project in
                    picture(project)
                        .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous).stroke(theme.line))
                        .scaleEffect(1 - CGFloat(index) * 0.06)
                        .offset(y: CGFloat(index) * -HmmSpacing.xs)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            VStack(alignment: .leading, spacing: 2) {
                Text(stack.name).font(.hmm(.headline, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                Text("\(members.count) projects").font(.hmm(.footnote)).foregroundStyle(theme.text2)
            }
            .padding(.horizontal, HmmSpacing.xxs)
        }
        .contentShape(Rectangle())
        .hoverEffect(.lift)
        .task(id: members.map(\.id)) {
            for project in members.prefix(3) {
                stills[project.id] = await app.cardImage(for: project)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func picture(_ project: ProjectSummary) -> some View {
        if let still = stills[project.id] {
            Color.clear.overlay(Image(uiImage: still).resizable().scaledToFill())
        } else {
            LinearGradient(colors: [theme.surface2, theme.surface], startPoint: .top, endPoint: .bottom)
        }
    }
}
