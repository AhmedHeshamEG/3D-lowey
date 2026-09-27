import Foundation

/// The global library folder (outside any project):
///
///     Lowey Library/
///       library.json
///       assets/<asset-id>/<model files>
///       thumbnails/<id>.png
public struct LibraryStore: Sendable {
    public let root: URL
    public var coder: SchemaCoder

    public static let manifestFile = "library.json"
    public static let assetsFolder = "assets"
    public static let thumbnailsFolder = "thumbnails"

    public init(root: URL, coder: SchemaCoder = .shared) {
        self.root = root
        self.coder = coder
    }

    public var manifestURL: URL { root.appendingPathComponent(Self.manifestFile) }

    public func assetFolder(_ id: AssetID) -> URL {
        root.appendingPathComponent(Self.assetsFolder).appendingPathComponent(id.raw)
    }

    public func fileURL(for asset: LibraryAsset) -> URL {
        assetFolder(asset.id).appendingPathComponent(asset.file)
    }

    public func thumbnailURL(for item: LibraryItem) -> URL {
        root.appendingPathComponent(Self.thumbnailsFolder).appendingPathComponent(item.thumbnailName)
    }

    public func thumbnailURL(named name: String) -> URL {
        root.appendingPathComponent(Self.thumbnailsFolder).appendingPathComponent(name)
    }

    public func load() throws -> LibraryManifest {
        guard FileManager.default.fileExists(atPath: manifestURL.path)
            || FileManager.default.fileExists(atPath: SafeFileWriter.backupURL(for: manifestURL).path)
        else { return LibraryManifest() }
        var manifest: LibraryManifest?
        _ = try SafeFileWriter.read(manifestURL) { data in
            manifest = try coder.decode(LibraryManifest.self, kind: .library, from: data)
        }
        return manifest ?? LibraryManifest()
    }

    public func save(_ manifest: LibraryManifest) throws {
        try SafeFileWriter.write(coder.encode(manifest, kind: .library), to: manifestURL)
    }

    /// Copies a model (and, for .gltf, its referenced .bin/textures) into the library.
    /// Returns the new manifest entry (bounds/rig/clips are filled in by the render layer).
    public func importModel(from source: URL, name: String? = nil, tags: [String] = [], id: AssetID = .make()) throws -> LibraryAsset {
        guard let format = AssetFormat(fileExtension: source.pathExtension) else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSFilePathErrorKey: source.path])
        }
        let fileManager = FileManager.default
        let folder = assetFolder(id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileName = source.lastPathComponent
        let destination = folder.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: source, to: destination)
        if format == .gltf, let json = try? Data(contentsOf: source) {
            let base = source.deletingLastPathComponent()
            for uri in GLTFDependencies.referencedURIs(in: json) {
                let from = base.appendingPathComponent(uri)
                let to = folder.appendingPathComponent(uri)
                guard fileManager.fileExists(atPath: from.path) else { continue }
                try fileManager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fileManager.fileExists(atPath: to.path) { try fileManager.copyItem(at: from, to: to) }
            }
        }
        let displayName = name ?? Self.displayName(for: source)
        return LibraryAsset(
            id: id, name: displayName, tags: tags.isEmpty ? Self.guessTags(from: displayName) : tags,
            format: format, file: fileName
        )
    }

    public func removeAsset(_ id: AssetID) {
        try? FileManager.default.removeItem(at: assetFolder(id))
        try? FileManager.default.removeItem(at: thumbnailURL(named: "\(id.raw).png"))
    }

    public func writeThumbnail(_ png: Data, named name: String) throws {
        let url = thumbnailURL(named: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
    }

    /// "Tiger_Walk-v2.glb" → "Tiger Walk v2".
    public static func displayName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let spaced = base.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        let collapsed = spaced.split(separator: " ").joined(separator: " ")
        return collapsed.isEmpty ? "Model" : collapsed.prefix(1).uppercased() + collapsed.dropFirst()
    }

    /// Lowercased words of the name become starter tags (so search finds them immediately).
    public static func guessTags(from name: String) -> [String] {
        let words = name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 3 }
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }
}

/// Everything a project needs to be portable: which library assets and prefabs it uses.
public enum ProjectAssets {
    /// Asset ids used by a scene, following prefab instances (recursively) through the library.
    public static func assetIDs(in scene: Scene, library: LibraryManifest) -> Set<AssetID> {
        var result = Set<AssetID>()
        var visitedPrefabs = Set<PrefabID>()
        func visit(_ objects: some Sequence<SceneObject>) {
            for object in objects {
                switch object.kind {
                case let .asset(id):
                    result.insert(id)
                case let .prefab(id):
                    guard visitedPrefabs.insert(id).inserted, let prefab = library.prefab(id) else { continue }
                    visit(prefab.fragment.objects)
                default:
                    break
                }
            }
        }
        visit(scene.objects.values)
        return result
    }

    public static func prefabIDs(in scene: Scene, library: LibraryManifest) -> Set<PrefabID> {
        var result = Set<PrefabID>()
        func visit(_ objects: some Sequence<SceneObject>) {
            for object in objects {
                if case let .prefab(id) = object.kind, result.insert(id).inserted, let prefab = library.prefab(id) {
                    visit(prefab.fragment.objects)
                }
            }
        }
        visit(scene.objects.values)
        return result
    }

    /// Manifest embedded in an exported project (`assets/assets.json`) so it can be
    /// re-imported into another library.
    public static let embeddedManifestName = "assets.json"

    /// Copies used assets and prefabs into `<project>/assets/` ("Export project").
    public static func embed(scenes: [Scene], library: LibraryManifest, libraryStore: LibraryStore, into projectURL: URL) throws -> LibraryManifest {
        var assetIDs = Set<AssetID>()
        var prefabIDs = Set<PrefabID>()
        for scene in scenes {
            assetIDs.formUnion(Self.assetIDs(in: scene, library: library))
            prefabIDs.formUnion(Self.prefabIDs(in: scene, library: library))
        }
        let fileManager = FileManager.default
        let target = projectURL.appendingPathComponent(ProjectLayout.assetsFolder)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        var embedded = LibraryManifest()
        for id in assetIDs.sorted() {
            guard let asset = library.asset(id) else { continue }
            let source = libraryStore.assetFolder(id)
            let destination = target.appendingPathComponent(id.raw)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            if fileManager.fileExists(atPath: source.path) { try fileManager.copyItem(at: source, to: destination) }
            embedded.assets.append(asset)
        }
        embedded.prefabs = prefabIDs.sorted().compactMap { library.prefab($0) }
        try SafeFileWriter.write(
            SchemaCoder.shared.encode(embedded, kind: .library),
            to: target.appendingPathComponent(embeddedManifestName), keepBackup: false
        )
        return embedded
    }

    /// Adds a project's embedded assets/prefabs to the library (skipping ones already present).
    public static func adopt(from projectURL: URL, into library: inout LibraryManifest, libraryStore: LibraryStore) throws -> Int {
        let source = projectURL.appendingPathComponent(ProjectLayout.assetsFolder)
        let manifestURL = source.appendingPathComponent(embeddedManifestName)
        guard let data = try? Data(contentsOf: manifestURL) else { return 0 }
        let embedded = try SchemaCoder.shared.decode(LibraryManifest.self, kind: .library, from: data)
        let fileManager = FileManager.default
        var added = 0
        for asset in embedded.assets where library.asset(asset.id) == nil {
            let from = source.appendingPathComponent(asset.id.raw)
            let to = libraryStore.assetFolder(asset.id)
            try fileManager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: from.path), !fileManager.fileExists(atPath: to.path) {
                try fileManager.copyItem(at: from, to: to)
            }
            library.assets.append(asset)
            added += 1
        }
        for prefab in embedded.prefabs where library.prefab(prefab.id) == nil {
            library.prefabs.append(prefab)
            added += 1
        }
        return added
    }
}
