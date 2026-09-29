import Foundation
import LoweyCore
import LoweyRender
import Observation
import os
import SwiftUI
import UniformTypeIdentifiers

/// App-wide state: where things live on disk, the project list, the library and the open editor.
@Observable
@MainActor
final class AppModel {
    let projectStore: ProjectStore
    let library: LibraryModel
    private(set) var projects: [ProjectSummary] = []
    private(set) var thumbnails: [ProjectID: UIImage] = [:]
    private(set) var editor: EditorModel?
    var toast: String?
    /// The 60-second interactive tour (first launch, or ⋯ → Take the tour).
    var showTour = false
    /// The gestures & shortcuts page.
    var showGestures = false
    /// The AI & laptop bridge (starts with the app unless switched off).
    @ObservationIgnored lazy var bridge = BridgeModel(app: self)

    private var toastTask: Task<Void, Never>?
    private var started = false
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "app")

    /// UI tests launch with a clean sandbox folder so runs are repeatable.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    /// A UI test that walks through the first-launch tour.
    static let isTestingTour = ProcessInfo.processInfo.arguments.contains("-ui-testing-tour")
    /// Unit / render tests hosted in the app: no bridge (no network listener, no notification prompt).
    static let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base = Self.isUITesting ? documents.appendingPathComponent("UITest-\(UUID().uuidString)") : documents
        let projectsRoot = base.appendingPathComponent("Projects")
        let libraryRoot = base.appendingPathComponent("Lowey Library")
        try? FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        projectStore = ProjectStore(root: projectsRoot)
        library = LibraryModel(store: LibraryStore(root: libraryRoot))
    }

    func start() async {
        guard !started else { return }
        started = true
        Diagnostics.shared.start()
        // The iPad never auto-locks while 3D-lowey is on screen.
        ScreenAwake.hold("app", true)
        if Diagnostics.shared.previousSessionCrashed, !Self.isUITesting {
            show("3D-lowey quit unexpectedly last time — your work was autosaved. ⋯ → Export diagnostics if it keeps happening.")
        }
        library.load()
        refreshProjects()
        // First launch: the Enigma sets are there to explore and to prove the tool.
        let wantsSample = !Self.isUITesting || ProcessInfo.processInfo.arguments.contains("-ui-testing-sample")
        if projects.isEmpty, wantsSample {
            createIslandSample(open: false)
            createSampleProject(open: false)
            showTour = !Self.isUITesting || Self.isTestingTour
        }
        refreshArchived()
        if !Self.isUITesting, !Self.isHostingTests { bridge.restoreIfWanted() }
    }

    // MARK: Projects

    func refreshProjects() {
        projects = projectStore.listProjects()
        for project in projects {
            if let data = try? Data(contentsOf: project.thumbnailURL), let image = UIImage(data: data) {
                thumbnails[project.id] = image
            }
        }
    }

    func createProject(named name: String, preset: LightingPreset) {
        do {
            let look = Look.default.applying(preset)
            let (url, document) = try projectStore.createProject(name: name.isEmpty ? "Untitled" : name, look: look)
            refreshProjects()
            open(url: url, document: document)
        } catch {
            show("Couldn't create the project: \(error.localizedDescription)")
        }
    }

    func createSampleProject(open shouldOpen: Bool) {
        do {
            let (info, scenes) = try EnigmaSample.buildFull(ids: .random)
            var fresh = info
            fresh.id = .make()
            fresh.created = Date()
            fresh.modified = Date()
            let url = try projectStore.writeProject(info: fresh, scenes: scenes)
            refreshProjects()
            // A placeholder narrator for the story scene (the device's voice, at each sentence's time).
            let voice = url.appendingPathComponent(ProjectLayout.audioFolder).appendingPathComponent(EnigmaSample.voiceoverFile)
            Task {
                try? await PlaceholderVoice.render(EnigmaSample.narration.map { ($0.sentence, $0.start) }, duration: 12.6, to: voice)
                if shouldOpen { open(url: url) }
            }
        } catch {
            show("Couldn't create the sample: \(error.localizedDescription)")
        }
    }

    func open(url: URL, document: Document? = nil) {
        do {
            let doc = try document ?? projectStore.openDocument(at: url)
            editor = EditorModel(app: self, projectURL: url, document: doc)
        } catch {
            show("Couldn't open the project: \(error.localizedDescription)")
        }
    }

    func closeEditor() {
        guard let editor else { return }
        Task {
            await editor.saveNow(thumbnail: true)
            self.editor = nil
            self.refreshProjects()
        }
    }

    func duplicate(_ project: ProjectSummary) {
        do {
            _ = try projectStore.duplicateProject(at: project.url)
            refreshProjects()
        } catch {
            show("Couldn't duplicate: \(error.localizedDescription)")
        }
    }

    func rename(_ project: ProjectSummary, to name: String) {
        guard !name.isEmpty else { return }
        do {
            _ = try projectStore.renameProject(at: project.url, to: name)
            refreshProjects()
        } catch {
            show("Couldn't rename: \(error.localizedDescription)")
        }
    }

    func delete(_ project: ProjectSummary) {
        do {
            try projectStore.deleteProject(at: project.url)
            thumbnails[project.id] = nil
            refreshProjects()
        } catch {
            show("Couldn't delete: \(error.localizedDescription)")
        }
    }

    func setThumbnail(_ image: UIImage, for id: ProjectID) {
        thumbnails[id] = image
    }

    /// Copies the project's library assets into it and returns the folder to share.
    func exportProject(_ project: ProjectSummary) -> URL? {
        do {
            let info = try projectStore.loadProjectInfo(at: project.url).info
            let scenes = info.sceneOrder.compactMap { try? projectStore.loadScene($0, in: project.url).scene }
            _ = try ProjectAssets.embed(scenes: scenes, library: library.manifest, libraryStore: library.store, into: project.url)
            show("Library assets copied into the project")
            return project.url
        } catch {
            show("Export failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Archive, packages, welcome island

    private(set) var archived: [ProjectSummary] = []

    func refreshArchived() {
        archived = projectStore.listArchived()
    }

    func archive(_ project: ProjectSummary) {
        do {
            _ = try projectStore.archiveProject(at: project.url)
            refreshProjects()
            refreshArchived()
            show("Archived — find it under ⋯ → Archive")
        } catch {
            show("Couldn't archive: \(error.localizedDescription)")
        }
    }

    func unarchive(_ project: ProjectSummary) {
        do {
            _ = try projectStore.unarchiveProject(at: project.url)
            refreshProjects()
            refreshArchived()
        } catch {
            show("Couldn't restore: \(error.localizedDescription)")
        }
    }

    /// One `.loweypack` file (the project with its library assets embedded) to share or back up.
    func packageProject(_ project: ProjectSummary) -> URL? {
        guard exportProject(project) != nil else { return nil }
        do {
            let data = try ProjectPackage.archive(project.url)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(ProjectStore.sanitize(project.info.name))
                .appendingPathExtension(ProjectPackage.fileExtension)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            show("Couldn't package the project: \(error.localizedDescription)")
            return nil
        }
    }

    func importPackage(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let destination = try ProjectPackage.unpack(Data(contentsOf: url), into: projectStore)
            var manifest = library.manifest
            let added = try ProjectAssets.adopt(from: destination, into: &manifest, libraryStore: library.store)
            library.replaceManifest(manifest)
            refreshProjects()
            show(added > 0 ? "Project imported with \(added) library items" : "Project imported")
        } catch {
            show("Couldn't import: \(error)")
        }
    }

    /// Copies a scene of the open project into another project.
    func copyScene(_ scene: SceneID, from source: URL, to project: ProjectSummary) {
        do {
            let copied = try projectStore.copyScene(scene, from: source, to: project.url)
            show("“\(copied.name)” copied to \(project.info.name)")
        } catch {
            show("Couldn't copy the scene: \(error.localizedDescription)")
        }
    }

    func createIslandSample(open shouldOpen: Bool) {
        do {
            let (info, scenes) = try IslandSample.build(ids: .random)
            var fresh = info
            fresh.id = .make()
            let url = try projectStore.writeProject(info: fresh, scenes: scenes)
            refreshProjects()
            if shouldOpen { open(url: url) }
        } catch {
            show("Couldn't create the island: \(error.localizedDescription)")
        }
    }

    // MARK: Incoming files (share sheet, "Open in…", drag & drop)

    func handleOpenedFile(_ url: URL) {
        if url.pathExtension == ProjectLayout.fileExtension {
            importProjectFolder(url)
            return
        }
        if url.pathExtension == ProjectPackage.fileExtension {
            importPackage(url)
            return
        }
        if url.pathExtension.lowercased() == "json", let data = try? Data(contentsOf: url), let editor {
            editor.importScript(data, source: url.lastPathComponent)
            return
        }
        Task {
            let imported = await library.importFiles([url])
            if imported > 0 {
                show(imported == 1 ? "Added to your library" : "Added \(imported) models to your library")
            }
        }
    }

    private func importProjectFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let destination = projectStore.uniqueURL(for: url.deletingPathExtension().lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            var manifest = library.manifest
            let added = try ProjectAssets.adopt(from: destination, into: &manifest, libraryStore: library.store)
            library.replaceManifest(manifest)
            refreshProjects()
            show(added > 0 ? "Project imported with \(added) library items" : "Project imported")
        } catch {
            show("Couldn't import the project: \(error.localizedDescription)")
        }
    }

    // MARK: Toast

    func show(_ message: String) {
        logger.info("\(message)")
        Diagnostics.shared.log(message)
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { toast = nil }
        }
    }
}
