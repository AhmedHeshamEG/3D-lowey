import Foundation
import LoweyCore
import LoweyEngine
import UIKit

/// Making, copying and moving projects (Theater actions), the samples, and files coming in from elsewhere.
extension AppModel {
    /// A new project: a name, a Mood and a Look (the only two choices).
    func createProject(named name: String, mood: LightingPreset, look presetID: String) {
        do {
            var look = Look.default.applying(mood)
            look.presetID = presetID
            let (url, document) = try projectStore.createProject(name: name.isEmpty ? "Untitled" : name, look: look)
            refreshProjects()
            open(url: url, document: document)
        } catch {
            show("Couldn't create the project: \(error.localizedDescription)", kind: .error)
        }
    }

    func duplicate(_ project: ProjectSummary) {
        perform("duplicate") { _ = try projectStore.duplicateProject(at: project.url) }
    }

    func rename(_ project: ProjectSummary, to name: String) {
        guard !name.isEmpty else { return }
        perform("rename") { _ = try projectStore.renameProject(at: project.url, to: name) }
    }

    func delete(_ project: ProjectSummary) {
        perform("delete") {
            try projectStore.deleteProject(at: project.url)
            thumbnails[project.id] = nil
        }
    }

    func archive(_ project: ProjectSummary) {
        perform("archive") { _ = try projectStore.archiveProject(at: project.url) }
        show("Archived. Find it in Theater ▸ Archive")
    }

    func unarchive(_ project: ProjectSummary) {
        perform("restore") { _ = try projectStore.unarchiveProject(at: project.url) }
    }

    /// The project with its library assets copied in, as a folder (Files, AirDrop).
    func exportFolder(_ project: ProjectSummary) -> URL? {
        do {
            let info = try projectStore.loadProjectInfo(at: project.url).info
            let scenes = info.sceneOrder.compactMap { try? projectStore.loadScene($0, in: project.url).scene }
            _ = try ProjectAssets.embed(scenes: scenes, library: library.manifest, libraryStore: library.store, into: project.url)
            return project.url
        } catch {
            show("Couldn't prepare the project: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    /// One `.loweypack` file to share or back up (library assets included).
    func package(_ project: ProjectSummary) -> URL? {
        guard exportFolder(project) != nil else { return nil }
        do {
            let data = try ProjectPackage.archive(project.url)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(ProjectStore.sanitize(project.info.name))
                .appendingPathExtension(ProjectPackage.fileExtension)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            show("Couldn't package the project: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    func importPackage(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let destination = try ProjectPackage.unpack(Data(contentsOf: url), into: projectStore)
            adoptAssets(of: destination)
        } catch {
            show("Couldn't import: \(String(describing: error))", kind: .error)
        }
    }

    /// Copies a scene of the open project into another project.
    func copyScene(_ scene: SceneID, from source: URL, to project: ProjectSummary) {
        do {
            let copied = try projectStore.copyScene(scene, from: source, to: project.url)
            show("“\(copied.name)” copied to \(project.info.name)")
        } catch {
            show("Couldn't copy the scene: \(error.localizedDescription)", kind: .error)
        }
    }

    // MARK: Samples

    func createIslandSample(open shouldOpen: Bool) {
        do {
            let (info, scenes) = try Showcase.island(kit: library.manifest.kit, ids: .random)
            var fresh = info
            fresh.id = .make()
            let url = try projectStore.writeProject(info: fresh, scenes: scenes)
            refreshProjects()
            if shouldOpen { open(url: url) }
        } catch {
            show("Couldn't add the island: \(error.localizedDescription)", kind: .error)
        }
    }

    /// The Enigma sets (Ink, Comic, Sketch) and the narrated story (a placeholder narrator speaks each sentence at its time).
    func createEnigmaSample(open shouldOpen: Bool) {
        do {
            let (info, scenes) = try Showcase.enigma(kit: library.manifest.kit, ids: .random)
            var fresh = info
            fresh.id = .make()
            fresh.created = Date()
            fresh.modified = Date()
            let url = try projectStore.writeProject(info: fresh, scenes: scenes)
            refreshProjects()
            let voice = url.appendingPathComponent(ProjectLayout.audioFolder).appendingPathComponent(EnigmaSample.voiceoverFile)
            Task {
                try? await PlaceholderVoice.render(EnigmaSample.narration.map { ($0.sentence, $0.start) }, duration: 12.6, to: voice)
                if shouldOpen { open(url: url) }
            }
        } catch {
            show("Couldn't add the sample: \(error.localizedDescription)", kind: .error)
        }
    }

    /// The 60-second tour happens on the welcome island (added if it isn't there).
    func startTour() {
        if let island = projects.first(where: { $0.info.name == Showcase.islandName }) {
            open(url: island.url)
        } else {
            createIslandSample(open: true)
        }
        showTour = true
    }

    // MARK: Incoming files (share sheet, Open in…, drag and drop)

    public func handleOpenedFile(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case ProjectLayout.fileExtension:
            importProjectFolder(url)
        case ProjectPackage.fileExtension:
            importPackage(url)
        case "json" where editor != nil:
            if let data = try? Data(contentsOf: url) { editor?.importScript(data, source: url.lastPathComponent) }
        default:
            Task {
                let imported = await library.importFiles([url])
                if imported > 0 { show(imported == 1 ? "Added to your library" : "Added \(imported) models to your library") }
            }
        }
    }

    private func importProjectFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let destination = projectStore.uniqueURL(for: url.deletingPathExtension().lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            adoptAssets(of: destination)
        } catch {
            show("Couldn't import the project: \(error.localizedDescription)", kind: .error)
        }
    }

    /// Library assets that came inside an imported project join the library.
    private func adoptAssets(of project: URL) {
        do {
            var manifest = library.manifest
            let added = try ProjectAssets.adopt(from: project, into: &manifest, libraryStore: library.store)
            library.replaceManifest(manifest)
            refreshProjects()
            show(added > 0 ? "Project imported with \(added) library items" : "Project imported")
        } catch {
            show("Imported, but its library items couldn't be read: \(error.localizedDescription)", kind: .error)
        }
    }

    private func perform(_ verb: String, _ body: () throws -> Void) {
        do {
            try body()
            refreshProjects()
            refreshArchived()
        } catch {
            show("Couldn't \(verb) it: \(error.localizedDescription)", kind: .error)
        }
    }
}
