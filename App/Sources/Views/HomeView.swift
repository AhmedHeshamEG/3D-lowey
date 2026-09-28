import LoweyCore
import LoweyRender
import SwiftUI

/// Project grid with thumbnails.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var showNewProject = false
    @State private var renaming: ProjectSummary?
    @State private var renameText = ""
    @State private var deleting: ProjectSummary?
    @State private var sharing: URL?
    @State private var importing = false
    @State private var showArchive = false
    @State private var showAcknowledgements = false

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 24)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                LazyVGrid(columns: columns, spacing: 24) {
                    NewProjectCard { showNewProject = true }
                    ForEach(app.projects) { project in
                        ProjectCard(project: project, thumbnail: app.thumbnails[project.id])
                            .onTapGesture { app.open(url: project.url) }
                            .contextMenu {
                                Button("Open", systemImage: "arrow.up.forward.app") { app.open(url: project.url) }
                                Button("Rename", systemImage: "pencil") {
                                    renameText = project.info.name
                                    renaming = project
                                }
                                Button("Duplicate", systemImage: "plus.square.on.square") { app.duplicate(project) }
                                Button("Share as one file (.loweypack)", systemImage: "square.and.arrow.up") {
                                    sharing = app.packageProject(project)
                                }
                                Button("Export folder (include library assets)", systemImage: "folder") {
                                    sharing = app.exportProject(project)
                                }
                                Button("Archive", systemImage: "archivebox") { app.archive(project) }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = project }
                            }
                            .accessibilityIdentifier("project-\(project.info.name)")
                    }
                }
            }
            .padding(40)
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet { name, preset in
                showNewProject = false
                app.createProject(named: name, preset: preset)
            }
            .presentationDetents([.medium, .large])
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
            Text("Its scenes and renders are removed. Library assets stay in your library.")
        }
        .sheet(item: Binding(get: { sharing.map(IdentifiedURL.init) }, set: { sharing = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            if case let .success(url) = result { app.importPackage(url) }
        }
        .sheet(isPresented: $showArchive) { ArchiveSheet().presentationDetents([.medium]) }
        .sheet(isPresented: $showAcknowledgements) { AcknowledgementsView() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Branding.appName)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("Build any world. Direct it. Make the video.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Menu {
                Button("Take the tour", systemImage: "hand.wave") { app.showTour = true }
                Button("Gestures & shortcuts", systemImage: "hand.draw") { app.showGestures = true }
                Button("Add the welcome island", systemImage: "tree") { app.createIslandSample(open: true) }
                Button("Add the Enigma sample", systemImage: "sparkles") { app.createSampleProject(open: true) }
                Button("Import a project (.loweypack)", systemImage: "square.and.arrow.down") { importing = true }
                Button("Archive (\(app.archived.count))", systemImage: "archivebox") { showArchive = true }
                Button("Export diagnostics", systemImage: "stethoscope") { sharing = Diagnostics.shared.exportArchive(app: app) }
                Button("Acknowledgements", systemImage: "doc.text") { showAcknowledgements = true }
                Text("Version \(Branding.version)")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityIdentifier("home-menu")
        }
    }
}

/// Archived projects: restore them.
struct ArchiveSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Archive").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                PillButton(title: "Done", prominent: true) { dismiss() }
            }
            if app.archived.isEmpty {
                Text("Nothing archived. Archive a project from its menu (touch and hold) to tidy the Home screen without deleting it.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            }
            ScrollView {
                ForEach(app.archived) { project in
                    HStack {
                        Text(project.info.name).font(.system(size: 16, weight: .semibold))
                        Spacer()
                        PillButton(title: "Restore", systemName: "arrow.uturn.backward") { app.unarchive(project) }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct NewProjectCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("New project")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity, minHeight: 170)
            .aspectRatio(16 / 11, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("new-project")
        .hoverEffect(.lift)
    }
}

private struct ProjectCard: View {
    let project: ProjectSummary
    let thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(red: 0.2, green: 0.23, blue: 0.35), Color(red: 0.1, green: 0.1, blue: 0.16)],
                                   startPoint: .top, endPoint: .bottom)
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.panelStroke))
            VStack(alignment: .leading, spacing: 2) {
                Text(project.info.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(
                    "\(project.info.sceneOrder.count) scene\(project.info.sceneOrder.count == 1 ? "" : "s") · \(project.info.modified.formatted(.relative(presentation: .named)))"
                )
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
        .hoverEffect(.lift)
    }
}

/// New project: a name and one decision — the starting mood.
private struct NewProjectSheet: View {
    let create: (String, LightingPreset) -> Void
    @State private var name = ""
    @State private var preset: LightingPreset = .day

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("New project")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            TextField("Name (e.g. Enigma)", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 20))
                .accessibilityIdentifier("project-name")
            SectionHeader(title: "Starting mood (change it any time)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(LightingPreset.allCases, id: \.self) { item in
                        Button {
                            Haptics.select()
                            preset = item
                        } label: {
                            PresetCard(preset: item, selected: item == preset)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("preset-\(item.rawValue)")
                    }
                }
            }
            Spacer()
            HStack {
                Spacer()
                PillButton(title: "Create", systemName: "sparkles", prominent: true) { create(name, preset) }
            }
        }
        .padding(32)
        .background(Theme.background)
    }
}

/// A lighting preset shown as its sky.
struct PresetCard: View {
    let preset: LightingPreset
    let selected: Bool

    var body: some View {
        let sky = LookPresets.sky(for: preset)
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [sky.top.color, sky.horizon.color, sky.bottom.color], startPoint: .top, endPoint: .bottom)
                if sky.stars > 0 {
                    Image(systemName: "sparkles").foregroundStyle(.white.opacity(0.8)).padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: 118, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Theme.accent : Theme.panelStroke, lineWidth: selected ? 3 : 1))
            Text(preset.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Theme.accent : Theme.text)
        }
        .accessibilityIdentifier("preset-\(preset.rawValue)")
    }
}

/// UIKit share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
