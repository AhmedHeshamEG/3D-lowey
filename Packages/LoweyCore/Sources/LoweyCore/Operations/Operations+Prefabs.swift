import Foundation

public extension Operations {
    // MARK: Prefabs

    /// Builds a prefab fragment from a selection, re-centred so its base center is the origin.
    mutating func prefabFragment(_ ids: [ObjectID], in scene: Scene) -> SceneFragment? {
        let fragment = FragmentTools.extract(ids, from: scene)
        guard !fragment.isEmpty else { return nil }
        let box = bounds.worldBounds(of: fragment.roots, in: scene)
        let pivot = box.map { Vec3($0.center.x, $0.min.y, $0.center.z) } ?? .zero
        let recentred = FragmentTools.transformRoots(fragment) { transform in
            var moved = transform
            moved.position -= pivot
            return moved
        }
        return FragmentTools.reidentified(recentred, ids: &self.ids).0
    }

    /// Replaces a selection with one instance of a freshly saved prefab.
    mutating func replaceWithPrefab(_ ids: [ObjectID], prefab: Prefab, in scene: Scene) -> (EditCommand, ObjectID)? {
        let members = topLevel(ids, in: scene)
        guard !members.isEmpty else { return nil }
        let box = bounds.worldBounds(of: members, in: scene)
        let pivot = box.map { Vec3($0.center.x, $0.min.y, $0.center.z) } ?? .zero
        var factory = ObjectFactory(ids: self.ids)
        let instance = factory.prefabInstance(prefab, at: pivot)
        self.ids = factory.ids
        let command = EditCommand.batch("Save as prefab", [.delete(members), .insert(SceneFragment(object: instance), parent: nil, index: nil)])
        return (command, instance.id)
    }

    /// Turns a prefab instance back into editable objects.
    mutating func unpack(_ id: ObjectID, prefab: Prefab, in scene: Scene) -> EditCommand? {
        guard let instance = scene.objects[id] else { return nil }
        let world = scene.worldTransform(of: id)
        var (copy, _) = FragmentTools.reidentified(prefab.fragment, ids: &ids)
        copy = FragmentTools.transformRoots(copy) { world * $0 }
        let parentIndex = scene.childIDs(of: instance.parent).firstIndex(of: id)
        let parentWorld = instance.parent.map { scene.worldTransform(of: $0) } ?? .identity
        copy = FragmentTools.transformRoots(copy) { Transform.relative(world: $0, toParent: parentWorld) }
        return .batch("Unpack \(instance.name)", [.delete([id]), .insert(copy, parent: instance.parent, index: parentIndex)])
    }
}
