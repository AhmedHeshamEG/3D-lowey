import HmmDesign
import HmmDocuments
import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// Home's top row: the title (or the open stack, with the way back), search, sort, Select, and the long tail.
struct TheaterHeader: View {
    @Bindable var state: GalleryState
    @Environment(AppModel.self) private var app
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: HmmSpacing.s) {
            title
            Spacer(minLength: HmmSpacing.m)
            search
            sortMenu
            Button(state.selecting ? "Done" : "Select") {
                withHmmAnimation(.snappy) {
                    if state.selecting {
                        state.endSelecting()
                    } else {
                        state.selecting = true
                    }
                }
            }
            .font(.hmm(.body, weight: .semibold))
            .frame(minHeight: 44)
            .accessibilityIdentifier("gallery-select")
            Menu {
                Button("Import a project (.maquettepack)", systemImage: "square.and.arrow.down") { state.importing = true }
                Button("Archive (\(app.archived.count))", systemImage: "archivebox") { state.showArchive = true }
                Button("Take the tour", systemImage: "hand.wave") { app.startTour() }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 24)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("theater-menu")
            HmmButton("gearshape", label: "Settings") { app.showsSettings = true }
        }
    }

    @ViewBuilder private var title: some View {
        if let stack = state.openStack.flatMap({ id in app.gallery.stacks.first { $0.id == id } }) {
            HStack(spacing: HmmSpacing.xs) {
                HmmButton("chevron.backward", label: "Home") {
                    withHmmAnimation(.gentle) {
                        state.openStack = nil
                        state.endSelecting()
                    }
                }
                .accessibilityIdentifier("gallery-back")
                Button {
                    state.nameText = stack.name
                    state.renamingStack = stack
                } label: {
                    Text(stack.name).font(.hmm(.title1, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Rename the stack")
            }
        } else {
            VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                Text(AppIdentity.displayName).font(.hmm(.title1, weight: .semibold)).foregroundStyle(theme.text)
                Text("Build a world. Direct it. Make the video.").font(.hmm(.headline)).foregroundStyle(theme.text2).lineLimit(1)
            }
        }
    }

    private var search: some View {
        HStack(spacing: HmmSpacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.text2)
            TextField("Search", text: $state.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("gallery-search")
            if !state.query.isEmpty {
                Button {
                    state.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, HmmSpacing.s)
        .frame(width: 220, height: 40)
        .background(Capsule().fill(theme.surface2))
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: Binding(get: { app.gallery.sort }, set: { sort in withHmmAnimation(.standard) { app.setGallerySort(sort) } })) {
                ForEach(GallerySort.allCases, id: \.self) { sort in
                    Text(LocalizedStringKey(sort.title)).tag(sort)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Sort")
        .accessibilityIdentifier("gallery-sort")
    }
}

/// While selecting: what to do with the chosen projects.
struct GallerySelectionBar: View {
    @Bindable var state: GalleryState
    @Environment(AppModel.self) private var app
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let chosen = Array(state.selected)
        HStack(spacing: HmmSpacing.s) {
            Text(chosen.isEmpty ? "Tap projects to select them" : "\(chosen.count) selected")
                .font(.hmm(.body, weight: .semibold))
                .foregroundStyle(theme.text2)
                .accessibilityIdentifier("gallery-selected-count")
            Spacer()
            if state.openStack == nil {
                HmmPillButton("Stack", systemName: "square.stack") {
                    state.nameText = ""
                    state.naming = chosen
                }
                .accessibilityIdentifier("gallery-stack")
            } else {
                HmmPillButton("Move out", systemName: "arrow.up.square") {
                    app.moveOutOfStacks(chosen)
                    state.endSelecting()
                }
            }
            HmmPillButton("Duplicate", systemName: "plus.square.on.square") {
                app.duplicate(chosen)
                state.endSelecting()
            }
            HmmPillButton("Archive", systemName: "archivebox") {
                app.archive(chosen)
                state.endSelecting()
            }
            HmmPillButton("Delete", systemName: "trash", role: .destructive) { state.deleting = chosen }
        }
        .disabled(chosen.isEmpty)
        .padding(HmmSpacing.s)
        .hmmPanelBackground()
        .padding(.horizontal, HmmSpacing.xl)
        .padding(.bottom, HmmSpacing.s)
    }
}

/// Home's sheets and prompts.
struct TheaterDialogs: ViewModifier {
    @Bindable var state: GalleryState
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $state.showNewProject) {
                NewProjectSheet { name, template, mood, look in
                    state.showNewProject = false
                    app.createProject(named: name, template: template, mood: mood, look: look, inStack: state.openStack)
                }
                .presentationDetents([.large])
            }
            .alert("Rename project", isPresented: present($state.renaming)) {
                TextField("Name", text: $state.nameText)
                Button("Rename") { if let project = state.renaming { app.rename(project, to: state.nameText) } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename stack", isPresented: present($state.renamingStack)) {
                TextField("Name", text: $state.nameText)
                Button("Rename") { if let stack = state.renamingStack { app.renameStack(stack.id, to: state.nameText) } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("New stack", isPresented: present($state.naming)) {
                TextField("Name", text: $state.nameText)
                Button("Stack") {
                    if let ids = state.naming { withHmmAnimation(.standard) { _ = app.stackProjects(ids, named: state.nameText) } }
                    state.endSelecting()
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(state.deleting.count == 1 ? "Delete this project?" : "Delete \(state.deleting.count) projects?",
                                isPresented: Binding(get: { !state.deleting.isEmpty }, set: { if !$0 { state.deleting = [] } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    app.delete(state.deleting)
                    state.deleting = []
                    state.endSelecting()
                }
            } message: {
                Text("Their scenes and renders are removed. Library items stay in your library.")
            }
            .sheet(item: Binding(get: { state.sharing.map(IdentifiedURL.init) }, set: { state.sharing = $0?.url })) { ShareSheet(items: [$0.url]) }
            .fileImporter(isPresented: $state.importing, allowedContentTypes: [.item]) { result in
                if case let .success(url) = result { app.importPackage(url) }
            }
            .sheet(isPresented: $state.showArchive) { ArchiveSheet().presentationDetents([.medium]) }
            .onChange(of: app.gallery.stacks.map(\.id)) { _, ids in
                if let open = state.openStack, !ids.contains(open) { state.openStack = nil }
            }
    }

    /// A Bool binding for "something is being edited", clearing it on dismiss.
    private func present<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}

/// Archived projects, ready to restore.
struct ArchiveSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HmmSheet("Archive") {
            if app.archived.isEmpty {
                Hint("Nothing archived. Archive a project from its menu (touch and hold) to tidy Home without deleting it.")
            }
            ForEach(app.archived) { project in
                HStack {
                    Text(project.info.name).font(.hmm(.headline, weight: .semibold))
                    Spacer()
                    HmmPillButton("Restore", systemName: "arrow.uturn.backward") { app.unarchive(project) }
                }
            }
        }
    }
}
