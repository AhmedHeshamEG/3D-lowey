import HmmDesign
import HmmDocuments
import LoweyCore
import SwiftUI

/// Home, the living gallery (CONTEXT §4.2): Procreate's grid where each card is the real model turning in its own
/// light. Tap a card and it grows into the stage. Stacks keep projects together (drag one card onto another), search
/// finds them anywhere, the sort is remembered, and Select acts on several at once.
struct TheaterView: View {
    let zoom: Namespace.ID
    @Environment(AppModel.self) private var app
    @State private var state = GalleryState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HmmSpacing.xl) {
                TheaterHeader(state: state)
                grid
                if state.openStack == nil, state.query.isEmpty { samples }
            }
            .padding(HmmSpacing.xl)
        }
        .onScrollPhaseChange { _, phase in state.scrolling = phase.isScrolling }
        .safeAreaInset(edge: .bottom) {
            if state.selecting { GallerySelectionBar(state: state).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .hmmAnimation(.standard, value: state.selecting)
        .modifier(TheaterDialogs(state: state))
        .accessibilityIdentifier("home")
    }

    private var entries: [GalleryEntry] {
        app.gallery.entries(app.galleryItems, in: state.openStack, query: state.query)
    }

    /// Cards play only while the gallery rests and no project is open over it.
    private var playing: Bool { !state.scrolling && app.editor == nil }

    @ViewBuilder private var grid: some View {
        let entries = entries
        if entries.isEmpty, !state.query.isEmpty {
            HmmEmptyState("questionmark.folder", title: "Nothing called “\(state.query)”",
                          message: "Search looks through every project and stack by name.", actionTitle: "Clear the search") { state.query = "" }
        } else {
            GalleryGrid(entries: entries, zoom: zoom, playing: playing, selected: state.selecting ? state.selected : nil,
                        newProject: state.query.isEmpty && !state.selecting ? { state.showNewProject = true } : nil,
                        open: tap,
                        openStack: { stack in
                            withHmmAnimation(.gentle) {
                                state.query = ""
                                state.openStack = stack.id
                            }
                        },
                        drop: { id, entry in withHmmAnimation(.standard) { app.drop(id, onto: entry) } },
                        projectMenu: { ProjectMenu(project: $0, state: state) },
                        stackMenu: { StackMenu(stack: $0, state: state) })
        }
    }

    private func tap(_ project: ProjectSummary) {
        if state.selecting {
            HmmHaptics.play(.selection)
            state.selected.formSymmetricDifference([project.id.raw])
        } else {
            app.open(url: project.url)
        }
    }

    private var samples: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HmmSectionHeader("Samples")
            HStack(spacing: HmmSpacing.s) {
                HmmPillButton("Welcome island", systemName: "tree") { app.createIslandSample(open: true) }
                HmmPillButton("The Enigma story", systemName: "sparkles") { app.createEnigmaSample(open: true) }
            }
        }
    }
}

/// What Home is showing and doing: the open stack, the search, selecting, and the dialogs in flight.
@Observable
@MainActor
final class GalleryState {
    var query = ""
    var openStack: String?
    var selecting = false
    var selected: Set<String> = []
    var scrolling = false
    var showNewProject = false
    var showArchive = false
    var importing = false
    var sharing: URL?
    var renaming: ProjectSummary?
    var renamingStack: GalleryStack?
    var naming: [String]?
    var nameText = ""
    var deleting: [String] = []

    func endSelecting() {
        selecting = false
        selected = []
    }
}

/// A project's touch-and-hold menu.
private struct ProjectMenu: View {
    let project: ProjectSummary
    let state: GalleryState
    @Environment(AppModel.self) private var app

    var body: some View {
        let id = project.id.raw
        Button("Open", systemImage: "arrow.up.forward.app") { app.open(url: project.url) }
        Button("Rename", systemImage: "pencil") {
            state.nameText = project.info.name
            state.renaming = project
        }
        Button("Duplicate", systemImage: "plus.square.on.square") { app.duplicate(project) }
        Menu("Add to stack", systemImage: "square.stack") {
            Button("New stack…", systemImage: "plus") {
                state.nameText = ""
                state.naming = [id]
            }
            ForEach(app.gallery.stacks.filter { !$0.members.contains(id) }) { stack in
                Button(stack.name) { app.addToStack([id], stack: stack.id) }
            }
        }
        if app.gallery.stack(containing: id) != nil {
            Button("Move out of the stack", systemImage: "arrow.up.square") { app.moveOutOfStacks([id]) }
        }
        Button("Share as one file (.maquettepack)", systemImage: "square.and.arrow.up") { state.sharing = app.package(project) }
        Button("Export folder (with library items)", systemImage: "folder") { state.sharing = app.exportFolder(project) }
        Button("Archive", systemImage: "archivebox") { app.archive(project) }
        Button("Delete", systemImage: "trash", role: .destructive) { state.deleting = [id] }
    }
}

/// A stack's touch-and-hold menu.
private struct StackMenu: View {
    let stack: GalleryStack
    let state: GalleryState
    @Environment(AppModel.self) private var app

    var body: some View {
        Button("Open", systemImage: "square.stack") { state.openStack = stack.id }
        Button("Rename", systemImage: "pencil") {
            state.nameText = stack.name
            state.renamingStack = stack
        }
        Button("Unstack", systemImage: "square.stack.3d.down.right") { withHmmAnimation(.standard) { app.unstack(stack.id) } }
    }
}
