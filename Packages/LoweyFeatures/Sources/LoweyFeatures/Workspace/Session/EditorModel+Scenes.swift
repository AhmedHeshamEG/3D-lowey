import Foundation
import HmmDesign
import LoweyCore

/// Scenes of the project: switch, add, duplicate, rename; builds saved to the library and unpacked again.
extension EditorModel {
    var sceneList: [(id: SceneID, name: String)] {
        document.project.sceneOrder.map { ($0, document.project.sceneNames[$0] ?? "Scene") }
    }

    func switchScene(_ id: SceneID) {
        Task { await openScene(id) }
    }

    /// Saves the open scene, then opens `id`.
    func openScene(_ id: SceneID) async {
        guard id != baseScene.id else { return }
        await saveNow(thumbnail: false)
        do {
            let opened = try ProjectHistory.open(projectURL, scene: id, store: store, onError: app.journalErrorHandler)
            let loaded = opened.session.document.scene
            adopt(opened)
            selection = []
            selectedKeys = []
            pause()
            time = 0
            previousAnimated = []
            refreshDisplay()
            stage?.setViewpoint(loaded.viewpoint, notify: false)
            viewYaw = loaded.viewpoint.yaw
            refreshSelectionOverlay()
            refreshGuide()
        } catch {
            app.show("Couldn't open that scene: \(error.localizedDescription)", kind: .error)
        }
    }

    func addScene() {
        Task { await newScene(named: nil) }
    }

    /// Adds a scene to the project and opens it (nil when the project couldn't be written).
    @discardableResult
    func newScene(named name: String?) async -> SceneID? {
        await saveNow(thumbnail: false)
        do {
            let new = try store.addScene(named: name ?? "Scene \(document.project.sceneOrder.count + 1)", to: projectURL)
            session.updateProjectInfo { info in
                info.sceneOrder.append(new.id)
                info.sceneNames[new.id] = new.name
            }
            await checkpointNow()
            await openScene(new.id)
            return new.id
        } catch {
            app.show("Couldn't add a scene: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    func duplicateScene() {
        Task {
            await saveNow(thumbnail: false)
            do {
                let copy = try store.duplicateScene(baseScene.id, in: projectURL)
                let info = try store.loadProjectInfo(at: projectURL).info
                session.updateProjectInfo { $0 = info }
                await checkpointNow()
                switchScene(copy.id)
            } catch {
                app.show("Couldn't duplicate the scene: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    func renameScene(_ name: String) {
        guard !name.isEmpty else { return }
        perform(.renameScene(name))
    }

    // MARK: Builds in the library

    func saveSelectionAsPrefab(name: String, replaceSelection: Bool) {
        refreshOperationsLibrary()
        guard let fragment = operations.prefabFragment(selection, in: scene) else { return }
        let finalName = name.isEmpty ? (singleSelection?.name ?? "My build") : name
        Task {
            let prefab = await library.savePrefab(name: finalName, fragment: fragment)
            refreshOperationsLibrary()
            if replaceSelection, let (command, instance) = operations.replaceWithPrefab(selection, prefab: prefab, in: scene) {
                if perform(command) { setSelection([instance]) }
            }
            HmmHaptics.play(.commit)
            app.show("Saved “\(prefab.name)” to your library")
        }
    }

    /// Pushes edits of an unpacked build back into its library entry (every copy updates).
    func updatePrefab(_ prefabID: PrefabID) {
        refreshOperationsLibrary()
        guard let fragment = operations.prefabFragment(selection, in: scene), let existing = library.manifest.prefab(prefabID) else { return }
        Task {
            _ = await library.savePrefab(name: existing.name, fragment: fragment, replacing: prefabID)
            stage?.redraw()
            app.show("Updated “\(existing.name)” everywhere")
        }
    }

    func unpackSelection() {
        refreshOperationsLibrary()
        guard let object = singleSelection, let prefabID = object.kind.prefabID, let prefab = library.manifest.prefab(prefabID),
              let command = operations.unpack(object.id, prefab: prefab, in: scene) else { return }
        if perform(command) { setSelection(Array(baseScene.roots.suffix(prefab.fragment.roots.count))) }
    }
}
