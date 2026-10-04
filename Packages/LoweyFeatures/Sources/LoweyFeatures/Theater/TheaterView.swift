import HmmDesign
import LoweyCore
import SwiftUI

/// Home: project cards with looping previews, New project (a name, a Mood and a Look), the samples, and the
/// touch-and-hold menu (share, duplicate, rename, archive, delete).
struct TheaterView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.hmmTheme) private var theme
    @State private var showNewProject = false
    @State private var renaming: ProjectSummary?
    @State private var renameText = ""
    @State private var deleting: ProjectSummary?
    @State private var sharing: URL?
    @State private var importing = false
    @State private var showArchive = false

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: HmmSpacing.l)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HmmSpacing.xl) {
                header
                LazyVGrid(columns: columns, spacing: HmmSpacing.l) {
                    NewProjectCard { showNewProject = true }
                    ForEach(app.projects) { project in
                        ProjectCard(project: project, thumbnail: app.thumbnails[project.id], loop: app.loops[project.id],
                                    inICloud: app.storage.isICloud)
                            .onTapGesture { app.open(url: project.url) }
                            .accessibilityAddTraits(.isButton)
                            .contextMenu { menu(for: project) }
                            .accessibilityIdentifier("project-\(project.info.name)")
                    }
                }
                samples
            }
            .padding(HmmSpacing.xl)
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet { name, mood, look in
                showNewProject = false
                app.createProject(named: name, mood: mood, look: look)
            }
            .presentationDetents([.large])
        }
        .alert("Rename project", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let renaming { app.rename(renaming, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete this project?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete \(deleting?.info.name ?? "")", role: .destructive) {
                if let deleting { app.delete(deleting) }
                deleting = nil
            }
        } message: {
            Text("Its scenes and renders are removed. Library items stay in your library.")
        }
        .sheet(item: Binding(get: { sharing.map(IdentifiedURL.init) }, set: { sharing = $0?.url })) { ShareSheet(items: [$0.url]) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            if case let .success(url) = result { app.importPackage(url) }
        }
        .sheet(isPresented: $showArchive) { ArchiveSheet().presentationDetents([.medium]) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                Text(AppIdentity.displayName).font(.hmm(.title1, weight: .semibold)).foregroundStyle(theme.text)
                Text("Build a world. Direct it. Make the video.").font(.hmm(.headline)).foregroundStyle(theme.text2)
            }
            Spacer()
            Menu {
                Button("Import a project (.loweypack)", systemImage: "square.and.arrow.down") { importing = true }
                Button("Archive (\(app.archived.count))", systemImage: "archivebox") { showArchive = true }
                Button("Take the tour", systemImage: "hand.wave") { app.startTour() }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 24)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("theater-menu")
            HmmButton("gearshape", label: "Settings") { app.showsSettings = true }
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

    @ViewBuilder
    private func menu(for project: ProjectSummary) -> some View {
        Button("Open", systemImage: "arrow.up.forward.app") { app.open(url: project.url) }
        Button("Rename", systemImage: "pencil") {
            renameText = project.info.name
            renaming = project
        }
        Button("Duplicate", systemImage: "plus.square.on.square") { app.duplicate(project) }
        Button("Share as one file (.loweypack)", systemImage: "square.and.arrow.up") { sharing = app.package(project) }
        Button("Export folder (with library items)", systemImage: "folder") { sharing = app.exportFolder(project) }
        Button("Archive", systemImage: "archivebox") { app.archive(project) }
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = project }
    }
}

/// Archived projects, ready to restore.
private struct ArchiveSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HmmSheet("Archive") {
            if app.archived.isEmpty {
                Hint("Nothing archived. Archive a project from its menu (touch and hold) to tidy the Theater without deleting it.")
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
