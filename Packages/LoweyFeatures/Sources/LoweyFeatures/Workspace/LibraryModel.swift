import Foundation
import LoweyCore
import LoweyEngine
import Observation
import os
import UIKit
import UniformTypeIdentifiers

/// The library every project shares: imported models, builds saved for reuse (prefabs), Looks and scripts.
/// "Build once, reuse forever."
@Observable
@MainActor
final class LibraryModel {
    let store: LibraryStore
    private(set) var manifest = LibraryManifest()
    private(set) var thumbnails: [String: UIImage] = [:]
    private(set) var importing = 0
    /// The Kit's Sets (Room & Desk, City Street…), shipped with the app.
    private(set) var kitSets: [KitSet] = []
    @ObservationIgnored private var kitIndex = KitIndex()
    @ObservationIgnored private var thumbnailQueue: [LibraryItem] = []
    @ObservationIgnored private var renderingThumbnails = false
    /// Bumped when a prefab changes, so open scenes redraw its instances.
    private(set) var prefabRevision = 0
    @ObservationIgnored let models: ModelLibrary
    @ObservationIgnored private let thumbnailer = Thumbnailer()
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.subsystem, category: "library")

    static let importTypes: [UTType] = {
        var types: [UTType] = [.usdz, .usd, .folder]
        for ext in ["glb", "gltf", "obj", "usdc", "usda", "stl", "3mf"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }()

    init(store: LibraryStore, models: ModelLibrary = .shared) {
        self.store = store
        self.models = models
        models.onLoaded { [weak self] id, info in
            guard let info else { return }
            self?.didMeasure(id, info: info)
        }
    }

    /// What the renderer needs to find model files (the Kit's live in the app).
    var catalog: AssetCatalog {
        let store = store
        let kitRoot = Self.kitRoot
        return AssetCatalog(manifest: manifest) { asset in
            asset.isKit ? kitRoot.appendingPathComponent(asset.file) : store.fileURL(for: asset)
        }
    }

    /// The Kit folder in the app bundle.
    static var kitRoot: URL { Bundle.main.url(forResource: "Kit", withExtension: nil) ?? Bundle.main.bundleURL.appendingPathComponent("Kit") }

    func load() {
        do {
            manifest = try store.load()
        } catch {
            logger.error("Library failed to load: \(String(describing: error))")
        }
        loadKit()
        for item in LibrarySearch.items(in: manifest, filter: .all) {
            loadThumbnail(for: item)
        }
    }

    private func loadKit() {
        do {
            kitIndex = try KitIndex.load(from: Self.kitRoot)
            kitSets = kitIndex.sets
            manifest.kit = kitIndex.assets
        } catch {
            logger.error("The Kit failed to load: \(String(describing: error))")
        }
    }

    /// A Set's assets by category.
    func browse(_ set: String) -> [(category: String, assets: [LibraryAsset])] { kitIndex.browse(set) }

    private func save() {
        do {
            try store.save(manifest)
        } catch {
            logger.error("Library failed to save: \(String(describing: error))")
        }
    }

    func replaceManifest(_ manifest: LibraryManifest) {
        var manifest = manifest
        manifest.kit = kitIndex.assets
        self.manifest = manifest
        save()
        for item in LibrarySearch.items(in: manifest, filter: .all) where thumbnails[item.thumbnailName] == nil {
            loadThumbnail(for: item)
        }
    }

    /// A model finished loading for the first time: keep what we learned about it.
    func didMeasure(_ asset: AssetID, info: AssetInfo) {
        guard let index = manifest.assets.firstIndex(where: { $0.id == asset }) else { return }
        var entry = manifest.assets[index]
        entry.bounds = info.bounds
        entry.triangleCount = info.triangleCount
        if entry.rig == .none { entry.rig = info.rig }
        if entry.clips.isEmpty { entry.clips = info.clips }
        guard entry != manifest.assets[index] else { return }
        manifest.assets[index] = entry
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

    /// PNG of a model's thumbnail for the bridge (rendered now when it hasn't been yet).
    func thumbnailPNG(for item: LibraryItem) async -> Data? {
        if thumbnails[item.thumbnailName] == nil { loadThumbnail(for: item) }
        if thumbnails[item.thumbnailName] == nil, case let .asset(asset) = item {
            let object = SceneObject(id: .make(), name: asset.name, kind: .asset(asset.id))
            await renderThumbnail(of: SceneFragment(objects: [object], roots: [object.id]), named: item.thumbnailName)
        }
        return thumbnails[item.thumbnailName]?.pngData()
    }

    /// A Kit tile came on screen: its thumbnail is rendered in the Ink Look (once, then cached), one at a time.
    func requestThumbnail(for item: LibraryItem) {
        guard thumbnails[item.thumbnailName] == nil, case let .asset(asset) = item, asset.isKit else { return }
        loadThumbnail(for: item)
        guard thumbnails[item.thumbnailName] == nil, !thumbnailQueue.contains(item) else { return }
        thumbnailQueue.append(item)
        renderQueuedThumbnails()
    }

    private func renderQueuedThumbnails() {
        guard !renderingThumbnails, !thumbnailQueue.isEmpty else { return }
        renderingThumbnails = true
        let item = thumbnailQueue.removeFirst()
        Task { @MainActor in
            if case let .asset(asset) = item {
                let object = SceneObject(id: .make(), name: asset.name, kind: .asset(asset.id))
                await renderThumbnail(of: SceneFragment(objects: [object], roots: [object.id]), named: item.thumbnailName)
            }
            renderingThumbnails = false
            renderQueuedThumbnails()
        }
    }

    private func storeThumbnail(_ image: CGImage, named name: String) {
        if let png = UIImage(cgImage: image).pngData() { try? store.writeThumbnail(png, named: name) }
        thumbnails[name] = UIImage(cgImage: image)
    }

    private func renderThumbnail(of fragment: SceneFragment, named name: String) async {
        do {
            let image = try await thumbnailer.portrait(of: fragment, catalog: catalog, models: models)
            storeThumbnail(image, named: name)
        } catch {
            logger.error("Thumbnail failed: \(String(describing: error))")
        }
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
            if await importModel(file) { added += 1 }
        }
        return added
    }

    private func importModel(_ file: URL) async -> Bool {
        do {
            var asset = try store.importModel(from: file)
            manifest.assets.append(asset)
            guard let info = await models.inspect(asset, catalog: catalog) else {
                manifest.assets.removeAll { $0.id == asset.id }
                store.removeAsset(asset.id)
                return false
            }
            asset.bounds = info.bounds
            asset.triangleCount = info.triangleCount
            asset.rig = info.rig
            asset.clips = info.clips
            if asset.rig.isRigged, !asset.tags.contains("rigged") { asset.tags.append("rigged") }
            if let index = manifest.assets.firstIndex(where: { $0.id == asset.id }) { manifest.assets[index] = asset }
            save()
            let object = SceneObject(id: .make(), name: asset.name, kind: .asset(asset.id))
            await renderThumbnail(of: SceneFragment(objects: [object], roots: [object.id]), named: LibraryItem.asset(asset).thumbnailName)
            return true
        } catch {
            logger.error("Import of \(file.lastPathComponent) failed: \(String(describing: error))")
            return false
        }
    }

    /// Model files inside a URL (itself, or anything inside a folder).
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
        update(item) { $0.toggleFavorite() }
    }

    func rename(_ item: LibraryItem, to name: String) {
        guard !name.isEmpty else { return }
        update(item) { $0.rename(name) }
    }

    func setTags(_ item: LibraryItem, _ tags: [String]) {
        let cleaned = tags.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        update(item) { $0.setTags(cleaned) }
    }

    func markUsed(_ item: LibraryItem) {
        update(item) { $0.markUsed(Date()) }
    }

    private func update(_ item: LibraryItem, _ change: (inout LibraryEntryEditor) -> Void) {
        var editor = LibraryEntryEditor(manifest: manifest, item: item)
        change(&editor)
        manifest = editor.manifest
        save()
    }

    func remove(_ item: LibraryItem) {
        switch item {
        case let .asset(asset):
            manifest.assets.removeAll { $0.id == asset.id }
            store.removeAsset(asset.id)
            models.evict(asset.id)
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

    // MARK: Builds, Looks and scripts

    /// Saves (or updates) a build. Updating bumps its version so every instance redraws.
    func savePrefab(name: String, fragment: SceneFragment, replacing existing: PrefabID? = nil) async -> Prefab {
        let prefab: Prefab
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
        await renderThumbnail(of: fragment, named: LibraryItem.prefab(prefab).thumbnailName)
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

    func saveLook(_ look: Look, name: String) async {
        let saved = SavedLook(id: .make(), name: name, look: look)
        manifest.looks.append(saved)
        save()
        if let image = try? await thumbnailer.lookSwatch(look) {
            storeThumbnail(image, named: LibraryItem.look(saved).thumbnailName)
        }
    }
}

/// Edits one library entry whichever kind it is (favourite, name, tags, last used).
struct LibraryEntryEditor {
    var manifest: LibraryManifest
    let item: LibraryItem

    mutating func toggleFavorite() {
        switch item {
        case let .asset(asset): edit(\.assets, asset.id) { $0.favorite.toggle() }
        case let .prefab(prefab): edit(\.prefabs, prefab.id) { $0.favorite.toggle() }
        case let .look(look): edit(\.looks, look.id) { $0.favorite.toggle() }
        case let .script(script): edit(\.scripts, script.id) { $0.favorite.toggle() }
        }
    }

    mutating func rename(_ name: String) {
        switch item {
        case let .asset(asset): edit(\.assets, asset.id) { $0.name = name }
        case let .prefab(prefab): edit(\.prefabs, prefab.id) { $0.name = name }
        case let .look(look): edit(\.looks, look.id) { $0.name = name }
        case let .script(script): edit(\.scripts, script.id) { $0.name = name }
        }
    }

    mutating func setTags(_ tags: [String]) {
        switch item {
        case let .asset(asset): edit(\.assets, asset.id) { $0.tags = tags }
        case let .prefab(prefab): edit(\.prefabs, prefab.id) { $0.tags = tags }
        case let .script(script): edit(\.scripts, script.id) { $0.tags = tags }
        case .look: break
        }
    }

    mutating func markUsed(_ date: Date) {
        switch item {
        case let .asset(asset): edit(\.assets, asset.id) { $0.lastUsed = date }
        case let .prefab(prefab): edit(\.prefabs, prefab.id) { $0.lastUsed = date }
        case let .look(look): edit(\.looks, look.id) { $0.lastUsed = date }
        case let .script(script): edit(\.scripts, script.id) { $0.lastUsed = date }
        }
    }

    private mutating func edit<Entry: Identifiable>(_ path: WritableKeyPath<LibraryManifest, [Entry]>, _ id: Entry.ID,
                                                    _ change: (inout Entry) -> Void) {
        guard let index = manifest[keyPath: path].firstIndex(where: { $0.id == id }) else { return }
        change(&manifest[keyPath: path][index])
    }
}
