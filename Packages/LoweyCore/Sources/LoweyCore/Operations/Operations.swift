import Foundation

/// High-level editing actions. Each returns a single `EditCommand` (one undo step)
/// built from the primitive commands, so the UI, scripts and AI share them.
public struct Operations: Sendable {
    public var ids: IDFactory
    public var bounds: SceneBounds

    public init(ids: IDFactory = .random, library: LibraryManifest = LibraryManifest()) {
        self.ids = ids
        bounds = SceneBounds(library: library)
    }

    // MARK: Add

    /// Adds an object at the top level (or under `parent`).
    public func add(_ object: SceneObject, parent: ObjectID? = nil) -> EditCommand {
        .insert(SceneFragment(object: object), parent: parent, index: nil)
    }

    /// Places a library asset / prefab / primitive so it sits on the ground at `point`.
    public func placeOnGround(_ object: SceneObject, at point: Vec3) -> SceneObject {
        var placed = object
        var transform = placed.transform
        transform.position = point
        if let local = bounds.localBounds(of: object) {
            transform.position.y = point.y - local.min.y * transform.scale.y
        }
        placed.transform = transform
        return placed
    }

    /// Moves a new object sideways until its footprint doesn't overlap anything already standing
    /// there, so adding twice in a row never hides the second object inside the first.
    public func nudgedToFreeSpot(_ object: SceneObject, in scene: Scene) -> SceneObject {
        guard let local = bounds.localBounds(of: object) else { return object }
        let others = scene.roots.compactMap { bounds.worldBounds(of: $0, in: scene) }
        guard !others.isEmpty else { return object }
        let start = object.transform
        let footprint = local.transformed(by: start)
        let step = max(footprint.size.x, footprint.size.z, 0.25) * 1.1
        func overlaps(_ box: Bounds) -> Bool {
            others.contains { other in
                box.min.x < other.max.x - 1e-6 && box.max.x > other.min.x + 1e-6
                    && box.min.z < other.max.z - 1e-6 && box.max.z > other.min.z + 1e-6
                    && box.min.y < other.max.y && box.max.y > other.min.y
            }
        }
        if !overlaps(footprint) { return object }
        // Rings of candidate offsets, nearest first: right, left, front, back, diagonals…
        for ring in 1 ... 6 {
            let r = Double(ring) * step
            let candidates = [Vec3(r, 0, 0), Vec3(-r, 0, 0), Vec3(0, 0, r), Vec3(0, 0, -r),
                              Vec3(r, 0, r), Vec3(-r, 0, r), Vec3(r, 0, -r), Vec3(-r, 0, -r)]
            for offset in candidates {
                let moved = Bounds(min: footprint.min + offset, max: footprint.max + offset)
                if !overlaps(moved) {
                    var result = object
                    result.transform.position = start.position + offset
                    return result
                }
            }
        }
        return object
    }

    // MARK: Duplicate / delete

    /// Duplicates objects (with their children), offset so the copy is visible.
    public mutating func duplicate(_ ids: [ObjectID], in scene: Scene, offset: Vec3 = Vec3(0.5, 0, 0.5)) -> (EditCommand, [ObjectID])? {
        let fragment = FragmentTools.extract(ids, from: scene)
        guard !fragment.isEmpty else { return nil }
        var (copy, _) = FragmentTools.reidentified(fragment, ids: &self.ids)
        copy = FragmentTools.transformRoots(copy) { transform in
            var moved = transform
            moved.position += offset
            return moved
        }
        copy.objects = copy.objects.map { object in
            var renamed = object
            if copy.roots.contains(object.id) { renamed.name = ObjectFactory.uniqueName(object.name, in: scene) }
            return renamed
        }
        let insert = EditCommand.insert(copy, parent: nil, index: nil)
        // Duplicating animated objects duplicates their animation.
        var idMap: [ObjectID: ObjectID] = [:]
        for (original, duplicate) in zip(fragment.objects.map(\.id), copy.objects.map(\.id)) {
            idMap[original] = duplicate
        }
        var offsets: [ObjectID: Vec3] = [:]
        for root in fragment.roots where scene.objects[root]?.parent == nil {
            offsets[root] = offset
        }
        if let animation = TimelineTools.copyAnimation(from: scene.timeline, mapping: idMap, offsets: offsets, ids: &self.ids) {
            return (.batch("Duplicate", [insert, animation]), copy.roots)
        }
        return (insert, copy.roots)
    }

    /// Deletes objects (and their children). Their animation (tracks, behaviours, clips, cuts)
    /// goes with them in the same undo step.
    public func delete(_ ids: [ObjectID], in scene: Scene) -> EditCommand? {
        let existing = ids.filter { scene.objects[$0] != nil && !scene.isEffectivelyLocked($0) }
        guard !existing.isEmpty else { return nil }
        var removed = Set<ObjectID>()
        for id in existing {
            removed.formUnion(scene.subtree(of: id))
        }
        let cleaned = TimelineTools.removingReferences(to: removed, from: scene.timeline)
        if cleaned != scene.timeline {
            return .batch(existing.count == 1 ? "Delete" : "Delete \(existing.count) objects", [.setTimeline(cleaned), .delete(existing)])
        }
        return .delete(existing)
    }

    // MARK: Transform

    /// Moves objects by a world-space delta (children follow their parents).
    public func translate(_ ids: [ObjectID], by delta: Vec3, in scene: Scene) -> EditCommand {
        let movable = topLevel(ids, in: scene).filter { !scene.isEffectivelyLocked($0) }
        let changes = movable.compactMap { id -> PropertyChange? in
            guard let object = scene.objects[id] else { return nil }
            let parentWorld = object.parent.map { scene.worldTransform(of: $0) } ?? .identity
            let world = parentWorld * object.transform
            var movedWorld = world
            movedWorld.position += delta
            let local = Transform.relative(world: movedWorld, toParent: parentWorld)
            return PropertyChange(object: id, key: .position, value: .vec3(local.position))
        }
        return .setProperties(changes)
    }

    /// Rotates objects around a world pivot by `rotation`.
    public func rotate(_ ids: [ObjectID], by rotation: Quat, around pivot: Vec3, in scene: Scene) -> EditCommand {
        let movable = topLevel(ids, in: scene).filter { !scene.isEffectivelyLocked($0) }
        var changes: [PropertyChange] = []
        for id in movable {
            guard let object = scene.objects[id] else { continue }
            let parentWorld = object.parent.map { scene.worldTransform(of: $0) } ?? .identity
            var world = parentWorld * object.transform
            world.position = pivot + rotation.act(world.position - pivot)
            world.rotation = (rotation * world.rotation).normalized
            let local = Transform.relative(world: world, toParent: parentWorld)
            changes.append(PropertyChange(object: id, key: .position, value: .vec3(local.position)))
            changes.append(PropertyChange(object: id, key: .rotation, value: .quat(local.rotation)))
        }
        return .setProperties(changes)
    }

    /// Scales objects by `factor` around a world pivot.
    public func scale(_ ids: [ObjectID], by factor: Vec3, around pivot: Vec3, in scene: Scene) -> EditCommand {
        let movable = topLevel(ids, in: scene).filter { !scene.isEffectivelyLocked($0) }
        var changes: [PropertyChange] = []
        for id in movable {
            guard let object = scene.objects[id] else { continue }
            let parentWorld = object.parent.map { scene.worldTransform(of: $0) } ?? .identity
            var world = parentWorld * object.transform
            world.position = pivot + (world.position - pivot).scaled(by: factor)
            world.scale = world.scale.scaled(by: factor).map { max($0, 0.001) }
            let local = Transform.relative(world: world, toParent: parentWorld)
            changes.append(PropertyChange(object: id, key: .position, value: .vec3(local.position)))
            changes.append(PropertyChange(object: id, key: .scale, value: .vec3(local.scale)))
        }
        return .setProperties(changes)
    }

    /// Sets a local transform exactly (inspector numeric entry).
    public func setTransform(_ id: ObjectID, _ transform: Transform) -> EditCommand {
        .setProperties([
            PropertyChange(object: id, key: .position, value: .vec3(transform.position)),
            PropertyChange(object: id, key: .rotation, value: .quat(transform.rotation)),
            PropertyChange(object: id, key: .scale, value: .vec3(transform.scale))
        ])
    }

    /// Drops objects so their lowest point touches the ground (y = 0) or the top of what's below.
    public func dropToGround(_ ids: [ObjectID], in scene: Scene) -> EditCommand {
        let targets = topLevel(ids, in: scene)
        let others = scene.objects.keys.filter { id in
            !targets.contains(id) && !targets.contains(where: { scene.isAncestor($0, of: id) })
                && scene.objects[id]?.kind.hasSurface == true
        }
        var changes: [PropertyChange] = []
        for id in targets {
            guard let object = scene.objects[id], let world = bounds.worldBounds(of: id, in: scene) else { continue }
            var floor = 0.0
            for other in others {
                guard let otherBounds = bounds.worldBounds(of: other, in: scene) else { continue }
                let overlapsXZ = world.min.x < otherBounds.max.x && world.max.x > otherBounds.min.x
                    && world.min.z < otherBounds.max.z && world.max.z > otherBounds.min.z
                if overlapsXZ, otherBounds.max.y <= world.min.y + 1e-6 { floor = max(floor, otherBounds.max.y) }
            }
            let delta = floor - world.min.y
            guard abs(delta) > 1e-9 else { continue }
            let parentWorld = object.parent.map { scene.worldTransform(of: $0) } ?? .identity
            var worldTransform = parentWorld * object.transform
            worldTransform.position.y += delta
            let local = Transform.relative(world: worldTransform, toParent: parentWorld)
            changes.append(PropertyChange(object: id, key: .position, value: .vec3(local.position)))
        }
        return .setProperties(changes)
    }

    // MARK: Groups & hierarchy

    /// Groups objects under a new group at their combined base center. World transforms are kept.
    /// With a `pivot`, the group turns around that point: a puppet joint (an arm pivoting at the shoulder).
    public mutating func group(_ ids: [ObjectID], in scene: Scene, name: String = "Group", pivot custom: Vec3? = nil) -> (EditCommand, ObjectID)? {
        let members = topLevel(ids, in: scene)
        guard !members.isEmpty else { return nil }
        let box = bounds.worldBounds(of: members, in: scene)
        let pivot = custom ?? box.map { Vec3($0.center.x, $0.min.y, $0.center.z) } ?? .zero
        // New group goes where the first member was.
        let firstParent = scene.objects[members[0]]?.parent
        let firstIndex = scene.childIDs(of: firstParent).firstIndex(of: members[0])
        let parentWorld = firstParent.map { scene.worldTransform(of: $0) } ?? .identity
        let groupID: ObjectID = self.ids.next()
        let groupWorld = Transform(position: pivot)
        let groupLocal = Transform.relative(world: groupWorld, toParent: parentWorld)
        let groupObject = SceneObject(id: groupID, name: ObjectFactory.uniqueName(name, in: scene), kind: .group,
                                      parent: firstParent, transform: groupLocal)
        let groupFullWorld = parentWorld * groupLocal
        var entries: [ReparentEntry] = []
        for member in members {
            let world = scene.worldTransform(of: member)
            entries.append(ReparentEntry(object: member, parent: groupID, index: nil,
                                         transform: Transform.relative(world: world, toParent: groupFullWorld)))
        }
        let command = EditCommand.batch("Group", [
            .insert(SceneFragment(object: groupObject), parent: firstParent, index: firstIndex),
            .reparent(entries)
        ])
        return (command, groupID)
    }

    /// Dissolves a group: children move to the group's parent keeping their world transforms.
    public func ungroup(_ id: ObjectID, in scene: Scene) -> EditCommand? {
        guard let group = scene.objects[id] else { return nil }
        let parentWorld = group.parent.map { scene.worldTransform(of: $0) } ?? .identity
        let baseIndex = scene.childIDs(of: group.parent).firstIndex(of: id) ?? 0
        var entries: [ReparentEntry] = []
        for (offset, child) in group.children.enumerated() {
            let world = scene.worldTransform(of: child)
            entries.append(ReparentEntry(object: child, parent: group.parent, index: baseIndex + 1 + offset,
                                         transform: Transform.relative(world: world, toParent: parentWorld)))
        }
        return .batch("Ungroup", [.reparent(entries), .delete([id])])
    }

    /// Moves objects under a new parent (or to the top level) keeping world transforms.
    public func reparent(_ ids: [ObjectID], to parent: ObjectID?, in scene: Scene) -> EditCommand? {
        let parentWorld = parent.map { scene.worldTransform(of: $0) } ?? .identity
        let entries = topLevel(ids, in: scene).compactMap { id -> ReparentEntry? in
            if let parent, parent == id || scene.isAncestor(id, of: parent) { return nil }
            return ReparentEntry(object: id, parent: parent, index: nil,
                                 transform: Transform.relative(world: scene.worldTransform(of: id), toParent: parentWorld))
        }
        return entries.isEmpty ? nil : .reparent(entries)
    }

    // MARK: Helpers

    /// Drops ids whose ancestor is also listed (moving a parent moves its children).
    public func topLevel(_ ids: [ObjectID], in scene: Scene) -> [ObjectID] {
        let set = Set(ids)
        var seen = Set<ObjectID>()
        return ids.filter { id in
            scene.objects[id] != nil && !scene.ancestors(of: id).contains(where: set.contains) && seen.insert(id).inserted
        }
    }
}
