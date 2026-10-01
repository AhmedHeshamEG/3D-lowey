import Foundation
import LoweyCore
import os
import Synchronization

/// What we learn about a model the first time it loads (stored back into the library manifest).
public struct AssetInfo: Sendable, Hashable {
    public var bounds: Bounds
    public var triangleCount: Int
    public var jointNames: [String]
    public var clips: [String]

    public var rig: RigType { RigClassifier.classify(jointNames: jointNames) }
}

public enum AssetLoadError: Error, Equatable, CustomStringConvertible {
    case unsupported(String)
    case empty

    public var description: String {
        switch self {
        case let .unsupported(ext): "Can't open .\(ext) files (use USDZ, glTF, GLB or OBJ)."
        case .empty: "The model has no visible geometry."
        }
    }
}

/// Library models read once and shared by every renderer (the stage, snapshots, an export running in the
/// background): parts and materials (`ImportedModel`) and the rig the animator uses (`RigAsset`). Loading happens
/// off the main thread; until a model is in, `model(_:)` returns nil and the scene shows a placeholder.
public final class ModelLibrary: Sendable {
    private struct State {
        var models: [AssetID: ImportedModel] = [:]
        var rigs: [AssetID: RigAsset] = [:]
        var loading: Set<AssetID> = []
        var failed: [AssetID: String] = [:]
    }

    private let state = Mutex(State())
    private let logger = Logger(subsystem: "studio.hmm.lowey", category: "assets")
    private let loadedHandler: Mutex<(@MainActor @Sendable (AssetID, AssetInfo?) -> Void)?> = Mutex(nil)

    public init() {}

    /// Called on the main actor when a model finished loading (the stage redraws, the library stores its info).
    public func onLoaded(_ handler: @escaping @MainActor @Sendable (AssetID, AssetInfo?) -> Void) {
        loadedHandler.withLock { $0 = handler }
    }

    public static let shared = ModelLibrary()

    /// The model if it's loaded; otherwise starts loading it and returns nil.
    public func model(_ asset: LibraryAsset, catalog: AssetCatalog) -> ImportedModel? {
        let (cached, shouldLoad): (ImportedModel?, Bool) = state.withLock { state in
            if let model = state.models[asset.id] { return (model, false) }
            guard !state.loading.contains(asset.id), state.failed[asset.id] == nil else { return (nil, false) }
            state.loading.insert(asset.id)
            return (nil, true)
        }
        if shouldLoad { startLoading(asset, url: catalog.fileURL(asset)) }
        return cached
    }

    public func rig(_ id: AssetID) -> RigAsset? {
        state.withLock { $0.rigs[id] }
    }

    public func failure(_ id: AssetID) -> String? {
        state.withLock { $0.failed[id] }
    }

    public var isLoading: Bool {
        state.withLock { !$0.loading.isEmpty }
    }

    /// Loads now and waits (export, thumbnails): never renders placeholders.
    public func load(_ asset: LibraryAsset, catalog: AssetCatalog) async -> ImportedModel? {
        if let model = state.withLock({ $0.models[asset.id] }) { return model }
        let url = catalog.fileURL(asset)
        let format = asset.format
        let result = await Task.detached(priority: .userInitiated) { Result { try Self.read(url: url, format: format) } }.value
        return store(result, for: asset)
    }

    /// Loads a model (if needed) and measures it: bounds, triangles, rig and clips (an import fills its library entry
    /// with these).
    public func inspect(_ asset: LibraryAsset, catalog: AssetCatalog) async -> AssetInfo? {
        guard let model = await load(asset, catalog: catalog) else { return nil }
        return Self.info(model, rig: rig(asset.id))
    }

    /// Waits until every model that started loading is in.
    public func waitUntilLoaded(timeout: Duration = .seconds(30)) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while isLoading, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    /// Puts a model made in code into the library (the benchmark's walker): it counts as loaded from the start.
    public func seed(_ id: AssetID, model: ImportedModel, rig: RigAsset?) {
        state.withLock { state in
            state.models[id] = model
            state.rigs[id] = rig
            state.failed[id] = nil
            state.loading.remove(id)
        }
    }

    /// Forgets a model (re-imported or removed).
    public func evict(_ id: AssetID) {
        state.withLock { state in
            state.models[id] = nil
            state.rigs[id] = nil
            state.failed[id] = nil
        }
    }

    private func startLoading(_ asset: LibraryAsset, url: URL) {
        let format = asset.format
        Task.detached(priority: .userInitiated) { [self] in
            let result = Result { try Self.read(url: url, format: format) }
            let model = store(result, for: asset)
            let info = model.map { Self.info($0, rig: rig(asset.id)) }
            let callback = loadedHandler.withLock { $0 }
            await MainActor.run { callback?(asset.id, info) }
        }
    }

    @discardableResult
    private func store(_ result: Result<(ImportedModel, RigAsset?), Error>, for asset: LibraryAsset) -> ImportedModel? {
        switch result {
        case let .success((model, rig)):
            state.withLock { state in
                state.models[asset.id] = model
                state.rigs[asset.id] = rig
                state.loading.remove(asset.id)
            }
            return model
        case let .failure(error):
            logger.error("Loading \(asset.name) failed: \(String(describing: error))")
            state.withLock { state in
                state.failed[asset.id] = String(describing: error)
                state.loading.remove(asset.id)
            }
            return nil
        }
    }

    /// Reads a model file: glTF / GLB and OBJ in pure Swift (LoweyCore), USDZ through ModelIO.
    static func read(url: URL, format: AssetFormat) throws -> (ImportedModel, RigAsset?) {
        let model: ImportedModel
        var rig: RigAsset?
        switch format {
        case .gltf, .glb:
            let data = try Data(contentsOf: url)
            model = try GLTFMeshReader.model(data: data, baseURL: url.deletingLastPathComponent())
            rig = try GLTFReader.rig(data: data, baseURL: url.deletingLastPathComponent())
        case .obj:
            model = try ImportedModel(mesh: OBJParser.parse(String(contentsOf: url, encoding: .utf8)), name: url.deletingPathExtension().lastPathComponent)
        case .usdz:
            model = try ModelIOImporter.model(url: url)
        }
        guard model.triangleCount > 0 else { throw AssetLoadError.empty }
        return (model, rig)
    }

    static func info(_ model: ImportedModel, rig: RigAsset?) -> AssetInfo {
        AssetInfo(bounds: model.bounds ?? .unitBase, triangleCount: model.triangleCount,
                  jointNames: rig?.skeleton.joints.map(\.name) ?? model.skin?.joints ?? [], clips: rig?.clipNames ?? [])
    }
}
