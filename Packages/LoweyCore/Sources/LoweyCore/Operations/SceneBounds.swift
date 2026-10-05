import Foundation

/// Computes object bounds from Core data alone (primitives, drawings, library-known assets,
/// prefabs). Used by snapping, align/distribute, framing, swap-to-fit and scatter.
public struct SceneBounds: Sendable {
    public var library: LibraryManifest
    private var drawingCache: [DrawingRecipe: Bounds] = [:]

    public init(library: LibraryManifest = LibraryManifest()) {
        self.library = library
    }

    /// Bounds of the object's own geometry in its local space (children excluded).
    public func localBounds(of object: SceneObject) -> Bounds? {
        switch object.kind {
        case let .primitive(shape):
            return PrimitiveMesh.bounds(shape)
        case let .drawing(recipe):
            return drawingCache[recipe] ?? DrawingMesher.mesh(for: recipe).bounds
        case let .asset(id):
            return library.asset(id)?.bounds ?? .unitBase
        case let .prefab(id):
            guard let prefab = library.prefab(id) else { return .unitBase }
            return fragmentBounds(prefab.fragment, depth: 0)
        case .light, .camera:
            return Bounds(min: Vec3(-0.15, -0.15, -0.15), max: Vec3(0.15, 0.15, 0.15))
        case let .text(recipe):
            return recipe.coreMeshable ? (BlockFont.mesh(for: recipe).bounds ?? recipe.estimatedBounds) : recipe.estimatedBounds
        case let .particles(recipe):
            return ParticleSimulator.bounds(recipe)
        case let .card(recipe):
            return recipe.bounds
        case let .mesh(mesh):
            return mesh.bounds
        case .group, .overlay:
            return nil
        }
    }

    /// World-space bounds of an object and all its descendants.
    public func worldBounds(of id: ObjectID, in scene: Scene) -> Bounds? {
        var result: Bounds?
        for node in scene.subtree(of: id) {
            guard let object = scene.objects[node], let local = localBounds(of: object) else { continue }
            let world = local.transformed(by: scene.worldTransform(of: node))
            result = result.map { $0.union(world) } ?? world
        }
        return result
    }

    /// Combined world bounds of several objects.
    public func worldBounds(of ids: [ObjectID], in scene: Scene) -> Bounds? {
        ids.compactMap { worldBounds(of: $0, in: scene) }.reduce(nil as Bounds?) { partial, bounds in
            partial.map { $0.union(bounds) } ?? bounds
        }
    }

    /// Bounds of a fragment's roots in fragment space.
    public func fragmentBounds(_ fragment: SceneFragment, depth: Int) -> Bounds? {
        guard depth < 8 else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: fragment.objects.map { ($0.id, $0) })
        var result: Bounds?
        func visit(_ id: ObjectID, parentTransform: Transform) {
            guard let object = byID[id] else { return }
            let transform = parentTransform * object.transform
            let local: Bounds? = if case let .prefab(prefabID) = object.kind, let prefab = library.prefab(prefabID) {
                fragmentBounds(prefab.fragment, depth: depth + 1)
            } else {
                localBounds(of: object)
            }
            if let local {
                let world = local.transformed(by: transform)
                result = result.map { $0.union(world) } ?? world
            }
            for child in object.children {
                visit(child, parentTransform: transform)
            }
        }
        for root in fragment.roots {
            visit(root, parentTransform: .identity)
        }
        return result
    }
}
