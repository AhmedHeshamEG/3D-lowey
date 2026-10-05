import Foundation

/// A library model taken apart into objects you can model: Model ▸ Shape ▸ Make editable on a placed model.
public extension ModelingOperations {
    enum ImportFailure: Error, Equatable, CustomStringConvertible {
        case tooBig(Int)
        case empty

        public var description: String {
            switch self {
            case let .tooBig(count): "That model has \(count) triangles: too many to edit. It stays a library model."
            case .empty: "That model has no shapes to edit."
            }
        }
    }

    /// Each part of a model as a modelled mesh with its material (model space, so they sit where the model's parts did).
    static func editableParts(of model: ImportedModel, ids: inout IDFactory) throws(ImportFailure) -> SceneFragment {
        guard model.triangleCount <= GLTFSceneReader.triangleLimit else { throw .tooBig(model.triangleCount) }
        var objects: [SceneObject] = []
        for part in model.parts where !part.isSkinned {
            let mesh = MeshBuilder.mesh(from: part.mesh)
            guard !mesh.isEmpty else { continue }
            var object = SceneObject(id: ids.next(), name: part.name, kind: .mesh(mesh))
            if model.materials.indices.contains(part.material) {
                let material = model.materials[part.material]
                object[.color] = .color(.rgba(material.baseColor))
                object[.roughness] = .float(material.roughness)
                object[.metallic] = .float(material.metallic)
            }
            objects.append(object)
        }
        guard !objects.isEmpty else { throw .empty }
        return SceneFragment(objects: objects, roots: objects.map(\.id))
    }

    /// Swaps a placed model for its parts: a group with the model's id, name, place and keys (so its animation and
    /// anything pointing at it still work) holding the parts. One undo step, with the parts' own animation if any.
    static func replace(_ id: ObjectID, withParts parts: SceneFragment, tracks: [Track] = [], in scene: Scene) -> EditCommand? {
        guard let object = scene.objects[id] else { return nil }
        var group = object
        group.kind = .group
        group.children = parts.roots
        var objects = [group]
        for var part in parts.objects {
            if parts.roots.contains(part.id) { part.parent = id }
            objects.append(part)
        }
        let siblings = object.parent.flatMap { scene.objects[$0]?.children } ?? scene.roots
        var commands: [EditCommand] = [
            .delete([id]),
            .insert(SceneFragment(objects: objects, roots: [id]), parent: object.parent, index: siblings.firstIndex(of: id))
        ]
        if !tracks.isEmpty { commands.append(.setTracks(tracks.map(TrackEdit.init))) }
        return .batch("Make editable", commands)
    }
}
