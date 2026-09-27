import Foundation
import GLTFKit2
import LoweyCore
import os
import RealityKit

/// What we learn about a model when it's loaded (stored back into the library manifest).
public struct AssetInfo: Sendable, Hashable {
    public var bounds: Bounds
    public var triangleCount: Int
    public var jointNames: [String]
    public var clips: [String]

    public var rig: RigType { RigClassifier.classify(jointNames: jointNames) }
}

public enum AssetLoadError: Error, CustomStringConvertible {
    case unsupported(String)
    case empty

    public var description: String {
        switch self {
        case let .unsupported(ext): "Can't open .\(ext) files (use USDZ, glTF, GLB or OBJ)"
        case .empty: "The model has no visible geometry"
        }
    }
}

/// Loads library models once and hands out cheap clones (clones share meshes and
/// materials, so repeated objects are instanced by RealityKit).
@MainActor
public final class AssetLoader {
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "assets")
    private var prototypes: [AssetID: Entity] = [:]
    private var facetedPrototypes: [AssetID: Entity] = [:]
    private var pending: [AssetID: Task<Entity, Error>] = [:]

    public init() {}

    /// Loads a model file into an entity (no caching).
    public static func load(url: URL, format: AssetFormat) async throws -> Entity {
        switch format {
        case .usdz:
            return try await Entity(contentsOf: url)
        case .gltf, .glb:
            return try await GLTFRealityKitLoader.load(from: url)
        case .obj:
            let text = try String(contentsOf: url, encoding: .utf8)
            let mesh = try OBJParser.parse(text)
            let resource = try MeshUpload.resource(from: mesh, name: url.lastPathComponent)
            return ModelEntity(mesh: resource, materials: [SimpleMaterial(color: .lightGray, roughness: 0.8, isMetallic: false)])
        }
    }

    /// The loaded prototype for an asset (loads on first use).
    public func prototype(for asset: LibraryAsset, url: URL) async throws -> Entity {
        if let cached = prototypes[asset.id] { return cached }
        if let task = pending[asset.id] { return try await task.value }
        let task = Task { @MainActor in
            try await Self.load(url: url, format: asset.format)
        }
        pending[asset.id] = task
        defer { pending[asset.id] = nil }
        let entity = try await task.value
        prototypes[asset.id] = entity
        return entity
    }

    public func cachedPrototype(_ id: AssetID) -> Entity? { prototypes[id] }

    /// Prototype with faceted normals (flat shading); falls back to the original for skinned models.
    public func facetedPrototype(_ id: AssetID) -> Entity? {
        if let cached = facetedPrototypes[id] { return cached }
        guard let original = prototypes[id] else { return nil }
        let copy = original.clone(recursive: true)
        var changed = false
        Self.visitModels(copy) { entity in
            guard var model = entity.components[ModelComponent.self] else { return }
            if let flat = MeshUpload.faceted(model.mesh) {
                model.mesh = flat
                entity.components.set(model)
                changed = true
            }
        }
        let result = changed ? copy : original
        facetedPrototypes[id] = result
        return result
    }

    /// Forgets a model (after it's removed from the library or re-imported).
    public func evict(_ id: AssetID) {
        prototypes[id] = nil
        facetedPrototypes[id] = nil
    }

    /// Measures a loaded model.
    public static func info(for entity: Entity) -> AssetInfo {
        let bounds = entity.visualBounds(recursive: true, relativeTo: entity)
        var triangles = 0
        var joints: [String] = []
        visitModels(entity) { node in
            if let model = node.components[ModelComponent.self] {
                for mdl in model.mesh.contents.models {
                    for part in mdl.parts {
                        triangles += (part.triangleIndices?.elements.count ?? 0) / 3
                    }
                }
            }
            if let modelEntity = node as? ModelEntity {
                joints += modelEntity.jointNames
            }
        }
        var clips = entity.availableAnimations.compactMap(\.name)
        visit(entity) { node in
            if let library = node.components[AnimationLibraryComponent.self] {
                for element in library.animations {
                    clips.append(element.key)
                }
            }
        }
        var seen = Set<String>()
        clips = clips.filter { !$0.isEmpty && seen.insert($0).inserted }
        let safeBounds = bounds.isEmpty
            ? Bounds.unitBase
            : bounds.loweyBounds
        return AssetInfo(bounds: safeBounds, triangleCount: triangles, jointNames: Array(Set(joints)).sorted(), clips: clips)
    }

    static func visit(_ entity: Entity, _ body: (Entity) -> Void) {
        body(entity)
        for child in entity.children {
            visit(child, body)
        }
    }

    static func visitModels(_ entity: Entity, _ body: (Entity) -> Void) {
        visit(entity) { node in
            if node.components.has(ModelComponent.self) { body(node) }
        }
    }
}
