import HmmDesign
import HmmDocuments
import LoweyCore
import SwiftUI

/// The gallery's grid of cards, shared by Home and the Home benchmark so the benchmark measures the real thing.
/// Projects turn while `playing`; dropping a card on another stacks them.
struct GalleryGrid<ProjectMenu: View, StackMenu: View>: View {
    let entries: [GalleryEntry]
    let zoom: Namespace.ID
    let playing: Bool
    /// Nil when not selecting; otherwise the chosen projects' ids.
    let selected: Set<String>?
    var newProject: (() -> Void)?
    var open: (ProjectSummary) -> Void = { _ in }
    var openStack: (GalleryStack) -> Void = { _ in }
    var drop: (String, GalleryEntry) -> Void = { _, _ in }
    @ViewBuilder var projectMenu: (ProjectSummary) -> ProjectMenu
    @ViewBuilder var stackMenu: (GalleryStack) -> StackMenu
    @Environment(AppModel.self) private var app

    static var columns: [GridItem] { [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: HmmSpacing.l)] }

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: HmmSpacing.l) {
            if let newProject { NewProjectCard(action: newProject) }
            ForEach(entries) { entry in
                card(entry)
                    .dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first else { return false }
                        drop(id, entry)
                        return true
                    }
            }
        }
    }

    @ViewBuilder
    private func card(_ entry: GalleryEntry) -> some View {
        switch entry {
        case let .item(item):
            if let project = app.project(item.id) {
                ProjectCard(project: project, zoom: zoom, playing: playing, selection: selected.map { $0.contains(item.id) })
                    .onTapGesture { open(project) }
                    .draggable(item.id)
                    .contextMenu { projectMenu(project) }
                    .accessibilityIdentifier("project-\(project.info.name)")
            }
        case let .stack(stack, members):
            StackCard(stack: stack, members: members.compactMap { app.project($0.id) })
                .onTapGesture { openStack(stack) }
                .contextMenu { stackMenu(stack) }
                .accessibilityIdentifier("stack-\(stack.name)")
        }
    }
}
