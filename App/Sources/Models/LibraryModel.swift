import Foundation
import LoweyCore
import LoweyRender
import Observation
import os
import RealityKit
import SwiftUI
import UniformTypeIdentifiers

/// The global library: models, things you built (prefabs) and looks. "Build once, reuse forever."
@Observable
@MainActor
final class LibraryModel: LibraryProviding {
    let store: LibraryStore
    private(set) var manifest = LibraryManifest()
    private(set) var thumbnails: [String: UIImage] = [:]
    private(set) var importing = 0
    /// Bumped when a prefab changes so open scenes refresh their instances.
    private(set) var prefabRevision = 0

    @ObservationIgnored private let loader = AssetLoader()
    @ObservationIgnored private let offscreen = OffscreenRenderer()
    @ObservationIgnored private var studioEnvironment: EnvironmentResource?
    @ObservationIgnored private let logger = Logger(subsystem: "com.hesham.lowey", category: "library")
    /// Called when a prefab was updated (instances must rebuild).
    @ObservationIgnored var onPrefabChanged: ((PrefabID) -> Void)?

    static let importTypes: [UTType] = {
        var types: [UTType] = [.usdz, .usd, .folder]
        for ext in ["glb", "gltf", "obj", "usdc", "usda"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }()

    init(store: LibraryStore) {
        self.store = store
    }

    func load() {
        do {
            manifest = try store.load()
        } catch {
            logger.error("Library failed to load: \(String(describing: error))")
        }
        for item in LibrarySearch.items(in: manifest, filter: .all) {
            loadThumbnail(for: item)
        }
    }

    private func save() {
        do {
            try store.save(manifest)
        } catch {
            logger.error("Library failed to save: \(String(describing: error))")
        }
    }

    func replaceManifest(_ manifest: LibraryManifest) {
        self.manifest = manifest
        save()
        for item in LibrarySearch.items(in: manifest, filter: .all) where thumbnails[item.thumbnailName] == nil {
            loadThumbnail(for: item)
        }
    }

    // MARK: LibraryProviding

    func fileURL(for asset: LibraryAsset) -> URL { store.fileURL(for: asset) }

    func didMeasure(_ asset: AssetID, info: AssetInfo) {
        guard let index = manifest.assets.firstIndex(where: { $0.id == asset }) else { return }
        manifest.assets[index].bounds = info.bounds
        manifest.assets[index].triangleCount = info.triangleCount
        if manifest.assets[index].rig == .none { manifest.assets[index].rig = info.rig }
        if manifest.assets[index].clips.isEmpty { manifest.assets[index].clips = info.clips }
        save()
    }

    // MARK: Thumbnails

    func thumbnail(for item: LibraryItem) -> UIImage? { thumbnails[item.thumbnailName] }

    private func loadThumbnail(for item: LibraryItem) {
        let url = store.thumbnailURL(for: item)
        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            thumbnails[item.thumbnailName] = image
        }
    }

    private func studio() async -> EnvironmentResource? {
        if let studioEnvironment { return studioEnvironment }
        let look = MoodPresets.look(for: .studio)
        guard let image = EnvironmentRig.skyImage(look: look, width: 256, height: 128, stars: false) else { return nil }
        studioEnvironment = try? await EnvironmentResource(equirectangular: image, withName: "studio")
        return studioEnvironment
    }

    private func storeThumbnail(_ image: CGImage, named name: String) {
        guard let png = OffscreenRenderer.pngData(image) else { return }
        try? store.writeThumbnail(png, named: name)
        thumbnails[name] = UIImage(cgImage: image)
    }

    // MARK: Import

    /// Imports model files and folders (glTF packs). Returns how many models were added.
    @discardableResult
    func importFiles(_ urls: [URL]) async -> Int {
        var files: [URL] = []
        var scoped: [URL] = []
        for url in urls {
            if url.startAccessingSecurityScopedResource() { scoped.append(url) }
            files += Self.modelFiles(in: url)
        }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        var added = 0
        importing += files.count
        for file in files {
            defer { importing -= 1 }
            do {
                var asset = try store.importModel(from: file)
                let prototype = try await AssetLoader.load(url: store.fileURL(for: asset), format: asset.format)
                let info = AssetLoader.info(for: prototype)
                asset.bounds = info.bounds
                asset.triangleCount = info.triangleCount
                asset.rig = info.rig
                asset.clips = info.clips
                if asset.rig.isRigged, !asset.tags.contains("rigged") { asset.tags.append("rigged") }
                manifest.assets.append(asset)
                save()
                if let image = try? await offscreen.thumbnail(of: prototype, environment: studio()) {
                    storeThumbnail(image, named: LibraryItem.asset(asset).thumbnailName)
                }
                added += 1
            } catch {
                logger.error("Import of \(file.lastPathComponent) failed: \(String(describing: error))")
            }
        }
        return added
    }

    /// Model files inside a URL (itself, or recursively inside a folder). For a glTF next to a
    /// same-named GLB, both are kept (they may differ).
    static func modelFiles(in url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if !isDirectory.boolValue {
            return AssetFormat(fileExtension: url.pathExtension) != nil ? [url] : []
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var result: [URL] = []
        for case let file as URL in enumerator where AssetFormat(fileExtension: file.pathExtension) != nil {
            result.append(file)
        }
        return result.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: Editing items

    func toggleFavorite(_ item: LibraryItem) {
        switch item {
        case let .asset(asset):
            if let index = manifest.assets.firstIndex(where: { $0.id == asset.id }) { manifest.assets[index].favorite.toggle() }
        case let .prefab(prefab):
            if let index = manifest.prefabs.firstIndex(where: { $0.id == prefab.id }) { manifest.prefabs[index].favorite.toggle() }
        case let .look(look):
            if let index = manifest.looks.firstIndex(where: { $0.id == look.id }) { manifest.looks[index].favorite.toggle() }
        case let .script(script):
            if let index = manifest.scripts.firstIndex(where: { $0.id == script.id }) { manifest.scripts[index].favorite.toggle() }
        }
        save()
    }

    func rename(_ item: LibraryItem, to name: String) {
        guard !name.isEmpty else { return }
        switch item {
        case let .asset(asset):
            if let index = manifest.assets.firstIndex(where: { $0.id == asset.id }) { manifest.assets[index].name = name }
        case let .prefab(prefab):
            if let index = manifest.prefabs.firstIndex(where: { $0.id == prefab.id }) { manifest.prefabs[index].name = name }
        case let .look(look):
            if let index = manifest.looks.firstIndex(where: { $0.id == look.id }) { manifest.looks[index].name = name }
        case let .script(script):
            if let index = manifest.scripts.firstIndex(where: { $0.id == script.id }) { manifest.scripts[index].name = name }
        }
        save()
    }

    func setTags(_ item: LibraryItem, _ tags: [String]) {
        let cleaned = tags.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        switch item {
        case let .asset(asset):
            if let index = manifest.assets.firstIndex(where: { $0.id == asset.id }) { manifest.assets[index].tags = cleaned }
        case let .prefab(prefab):
            if let index = manifest.prefabs.firstIndex(where: { $0.id == prefab.id }) { manifest.prefabs[index].tags = cleaned }
        case let .script(script):
            if let index = manifest.scripts.firstIndex(where: { $0.id == script.id }) { manifest.scripts[index].tags = cleaned }
        case .look:
            break
        }
        save()
    }

    func remove(_ item: LibraryItem) {
        switch item {
        case let .asset(asset):
            manifest.assets.removeAll { $0.id == asset.id }
            store.removeAsset(asset.id)
            loader.evict(asset.id)
        case let .prefab(prefab):
            manifest.prefabs.removeAll { $0.id == prefab.id }
        case let .look(look):
            manifest.looks.removeAll { $0.id == look.id }
        case let .script(script):
            manifest.scripts.removeAll { $0.id == script.id }
        }
        thumbnails[item.thumbnailName] = nil
        try? FileManager.default.removeItem(at: store.thumbnailURL(for: item))
        save()
    }

    func markUsed(_ item: LibraryItem) {
        let now = Date()
        switch item {
        case let .asset(asset):
            if let index = manifest.assets.firstIndex(where: { $0.id == asset.id }) { manifest.assets[index].lastUsed = now }
        case let .prefab(prefab):
            if let index = manifest.prefabs.firstIndex(where: { $0.id == prefab.id }) { manifest.prefabs[index].lastUsed = now }
        case let .look(look):
            if let index = manifest.looks.firstIndex(where: { $0.id == look.id }) { manifest.looks[index].lastUsed = now }
        case let .script(script):
            if let index = manifest.scripts.firstIndex(where: { $0.id == script.id }) { manifest.scripts[index].lastUsed = now }
        }
        save()
    }

    // MARK: Prefabs & looks

    /// Saves (or updates) a prefab. Updating bumps its version so every instance rebuilds.
    func savePrefab(name: String, fragment: SceneFragment, replacing existing: PrefabID? = nil, thumbnailFrom entity: Entity?) async -> Prefab {
        var prefab: Prefab
        if let existing, let index = manifest.prefabs.firstIndex(where: { $0.id == existing }) {
            manifest.prefabs[index].fragment = fragment
            manifest.prefabs[index].version += 1
            prefab = manifest.prefabs[index]
        } else {
            prefab = Prefab(id: .make(), name: name, tags: LibraryStore.guessTags(from: name), fragment: fragment)
            manifest.prefabs.append(prefab)
        }
        save()
        prefabRevision += 1
        onPrefabChanged?(prefab.id)
        if let entity, let image = try? await offscreen.thumbnail(of: entity, environment: studio()) {
            storeThumbnail(image, named: LibraryItem.prefab(prefab).thumbnailName)
        }
        return prefab
    }

    /// Saves a script (a new one, or updates the one with the same name).
    func saveScript(name: String, source: String) {
        if let index = manifest.scripts.firstIndex(where: { $0.name == name }) {
            manifest.scripts[index].source = source
        } else {
            manifest.scripts.append(ScriptAsset(id: .make(), name: name, source: source))
        }
        save()
    }

    func saveLook(_ look: Look, name: String) {
        let preset = SavedLook(id: .make(), name: name, look: look)
        manifest.looks.append(preset)
        save()
        if let image = EnvironmentRig.skyImage(look: look, width: 256, height: 256, stars: true) {
            storeThumbnail(image, named: LibraryItem.look(preset).thumbnailName)
        }
    }
}
