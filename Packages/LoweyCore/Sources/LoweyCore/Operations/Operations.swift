import Foundation

/// Array layouts ("20 fence posts in a line", "a grid of desks", "chairs around a table").
public enum ArrayLayout: Hashable, Sendable, Codable {
    case line(count: Int, step: Vec3)
    case grid(columns: Int, rows: Int, spacingX: Double, spacingZ: Double)
    case circle(count: Int, radius: Double, faceCenter: Bool)
}

/// Scatter settings. Defaults give good results with no tweaking.
public struct ScatterSettings: Hashable, Sendable, Codable {
    public var count: Int
    public var radius: Double
    /// Random yaw range in degrees (0...360).
    public var rotationJitter: Double
    /// Uniform scale range.
    public var scaleMin: Double
    public var scaleMax: Double
    /// Minimum distance between copies relative to the object's footprint (0 = allow overlap).
    public var spacing: Double
    public var seed: UInt64

    public init(count: Int = 20, radius: Double = 5, rotationJitter: Double = 360, scaleMin: Double = 0.8,
                scaleMax: Double = 1.25, spacing: Double = 0.8, seed: UInt64 = 1) {
        self.count = count
        self.radius = radius
        self.rotationJitter = rotationJitter
        self.scaleMin = scaleMin
        self.scaleMax = scaleMax
        self.spacing = spacing
        self.seed = seed
    }
}

public enum AlignMode: String, Sendable, Codable, CaseIterable {
    case min, center, max
}

/// Snapping configuration.
public struct SnapSettings: Hashable, Sendable, Codable {
    public var grid: Bool
    public var gridSize: Double
    public var rotation: Bool
    public var rotationStep: Double
    public var ground: Bool
    public var objects: Bool
    /// How close (m) a face must be to snap to another object.
    public var objectThreshold: Double

    public init(grid: Bool = false, gridSize: Double = 0.25, rotation: Bool = true, rotationStep: Double = 15,
                ground: Bool = true, objects: Bool = true, objectThreshold: Double = 0.12) {
        self.grid = grid
        self.gridSize = gridSize
        self.rotation = rotation
        self.rotationStep = rotationStep
        self.ground = ground
        self.objects = objects
        self.objectThreshold = objectThreshold
    }
}

public enum Snapping {
    public static func snapToGrid(_ value: Double, size: Double) -> Double {
        guard size > 0 else { return value }
        return (value / size).rounded() * size
    }

    public static func snapToGrid(_ point: Vec3, size: Double, includeY: Bool = false) -> Vec3 {
        Vec3(snapToGrid(point.x, size: size), includeY ? snapToGrid(point.y, size: size) : point.y, snapToGrid(point.z, size: size))
    }

    public static func snapAngle(_ degrees: Double, step: Double) -> Double {
        guard step > 0 else { return degrees }
        return (degrees / step).rounded() * step
    }

    /// Snaps the moving bounds' faces to nearby faces of other bounds (flush placement,
    /// like stacking Lego). Returns the correction to add to the position.
    public static func objectSnapOffset(moving: Bounds, others: [Bounds], threshold: Double) -> Vec3 {
        var correction = Vec3.zero
        for axis in Axis.allCases {
            var best: Double?
            for other in others {
                // Only consider objects overlapping on the other two axes (touching neighbours).
                let otherAxes = Axis.allCases.filter { $0 != axis }
                let overlaps = otherAxes.allSatisfy { a in
                    moving.min[a] <= other.max[a] + threshold && moving.max[a] >= other.min[a] - threshold
                }
                guard overlaps else { continue }
                let candidates = [
                    other.max[axis] - moving.min[axis], // sit against the far face
                    other.min[axis] - moving.max[axis], // sit against the near face
                    other.min[axis] - moving.min[axis], // align min faces
                    other.max[axis] - moving.max[axis], // align max faces
                    other.center[axis] - moving.center[axis] // align centers
                ]
                for delta in candidates where abs(delta) <= threshold {
                    if best == nil || abs(delta) < abs(best!) { best = delta }
                }
            }
            if let best { correction[axis] = best }
        }
        return correction
    }
}

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
        return (.insert(copy, parent: nil, index: nil), copy.roots)
    }

    public func delete(_ ids: [ObjectID], in scene: Scene) -> EditCommand? {
        let existing = ids.filter { scene.objects[$0] != nil && !scene.isEffectivelyLocked($0) }
        return existing.isEmpty ? nil : .delete(existing)
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
    public mutating func group(_ ids: [ObjectID], in scene: Scene, name: String = "Group") -> (EditCommand, ObjectID)? {
        let members = topLevel(ids, in: scene)
        guard !members.isEmpty else { return nil }
        let box = bounds.worldBounds(of: members, in: scene)
        let pivot = box.map { Vec3($0.center.x, $0.min.y, $0.center.z) } ?? .zero
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

    // MARK: Generators

    /// Copies of `source` laid out as an array, grouped (source included as the first element).
    public mutating func array(_ source: ObjectID, layout: ArrayLayout, in scene: Scene) -> (EditCommand, ObjectID)? {
        guard let object = scene.objects[source] else { return nil }
        let base = scene.worldTransform(of: source)
        var transforms: [Transform] = []
        switch layout {
        case let .line(count, step):
            for index in 1 ..< max(count, 1) {
                var t = base
                t.position += step * Double(index)
                transforms.append(t)
            }
        case let .grid(columns, rows, spacingX, spacingZ):
            for row in 0 ..< max(rows, 1) {
                for column in 0 ..< max(columns, 1) where !(row == 0 && column == 0) {
                    var t = base
                    t.position += Vec3(Double(column) * spacingX, 0, Double(row) * spacingZ)
                    transforms.append(t)
                }
            }
        case let .circle(count, radius, faceCenter):
            let center = base.position - Vec3(0, 0, radius)
            for index in 1 ..< max(count, 1) {
                let angle = Double(index) / Double(count) * 2 * .pi
                let yaw = Quat(angle: angle, axis: .unitY)
                var t = base
                t.position = center + yaw.act(base.position - center)
                if faceCenter { t.rotation = (yaw * base.rotation).normalized }
                transforms.append(t)
            }
        }
        return makeCopies(of: source, object: object, transforms: transforms, in: scene, groupName: "\(object.name) array")
    }

    /// Scatters copies of `source` over a disc ("20 trees here" in one gesture).
    public mutating func scatter(_ source: ObjectID, center: Vec3, settings: ScatterSettings, in scene: Scene) -> (EditCommand, ObjectID)? {
        guard let object = scene.objects[source] else { return nil }
        let base = scene.worldTransform(of: source)
        let sourceBounds = bounds.worldBounds(of: source, in: scene)
        let footprint = sourceBounds.map { max($0.size.x, $0.size.z) } ?? 1
        let minDistance = footprint * settings.spacing
        // Height of the pivot above the object's lowest point, so copies sit on the ground.
        let pivotHeight = base.position.y - (sourceBounds?.min.y ?? base.position.y)
        var random = SeededRandom(seed: settings.seed)
        var positions: [Vec3] = []
        var transforms: [Transform] = []
        var attempts = 0
        while transforms.count < settings.count, attempts < settings.count * 30 {
            attempts += 1
            // Uniform point in a disc.
            let r = settings.radius * random.unit().squareRoot()
            let theta = random.unit() * 2 * .pi
            let position = Vec3(center.x + r * cos(theta), center.y, center.z + r * sin(theta))
            if minDistance > 0, positions.contains(where: { $0.distance(to: position) < minDistance }) { continue }
            positions.append(position)
            let yaw = random.range(-settings.rotationJitter / 2, settings.rotationJitter / 2) * .pi / 180
            let s = random.range(settings.scaleMin, settings.scaleMax)
            var t = base
            t.position = Vec3(position.x, center.y + pivotHeight * s, position.z)
            t.rotation = (Quat(angle: yaw, axis: .unitY) * base.rotation).normalized
            t.scale = base.scale * s
            transforms.append(t)
        }
        return makeCopies(of: source, object: object, transforms: transforms, in: scene, groupName: "\(object.name) scatter",
                          includeSource: false)
    }

    private mutating func makeCopies(
        of source: ObjectID, object: SceneObject, transforms: [Transform], in scene: Scene, groupName: String,
        includeSource: Bool = true
    ) -> (EditCommand, ObjectID)? {
        guard !transforms.isEmpty else { return nil }
        let fragment = FragmentTools.extract([source], from: scene)
        let groupID: ObjectID = ids.next()
        var objects: [SceneObject] = []
        var children: [ObjectID] = []
        for transform in transforms {
            var (copy, _) = FragmentTools.reidentified(fragment, ids: &ids)
            copy = FragmentTools.transformRoots(copy) { _ in transform }
            for var copied in copy.objects {
                if copy.roots.contains(copied.id) { copied.parent = groupID }
                objects.append(copied)
            }
            children += copy.roots
        }
        var commands: [EditCommand] = []
        var group = SceneObject(id: groupID, name: ObjectFactory.uniqueName(groupName, in: scene), kind: .group)
        if includeSource {
            children.insert(source, at: 0)
        }
        group.children = children.filter { $0 != source }
        let groupFragment = SceneFragment(objects: [group] + objects, roots: [groupID])
        commands.append(.insert(groupFragment, parent: nil, index: nil))
        if includeSource {
            commands.append(.reparent([ReparentEntry(object: source, parent: groupID, index: 0,
                                                     transform: scene.worldTransform(of: source))]))
        }
        return (.batch(includeSource ? "Array" : "Scatter", commands), groupID)
    }

    // MARK: Align & distribute

    public func align(_ ids: [ObjectID], axis: Axis, mode: AlignMode, in scene: Scene) -> EditCommand? {
        let targets = topLevel(ids, in: scene)
        let boxes = targets.compactMap { id in bounds.worldBounds(of: id, in: scene).map { (id, $0) } }
        guard boxes.count >= 2 else { return nil }
        let reference: Double = switch mode {
        case .min: boxes.map { $0.1.min[axis] }.min() ?? 0
        case .max: boxes.map { $0.1.max[axis] }.max() ?? 0
        case .center: boxes.map { $0.1.center[axis] }.reduce(0, +) / Double(boxes.count)
        }
        var commands: [EditCommand] = []
        for (id, box) in boxes {
            let current: Double = switch mode {
            case .min: box.min[axis]
            case .max: box.max[axis]
            case .center: box.center[axis]
            }
            var delta = Vec3.zero
            delta[axis] = reference - current
            if abs(delta[axis]) > 1e-9 { commands.append(translate([id], by: delta, in: scene)) }
        }
        return .batch("Align", commands)
    }

    /// Spreads objects evenly between the two outermost ones along `axis`.
    public func distribute(_ ids: [ObjectID], axis: Axis, in scene: Scene) -> EditCommand? {
        let targets = topLevel(ids, in: scene)
        var boxes = targets.compactMap { id in bounds.worldBounds(of: id, in: scene).map { (id, $0) } }
        guard boxes.count >= 3 else { return nil }
        boxes.sort { $0.1.center[axis] < $1.1.center[axis] }
        let first = boxes[0].1.center[axis]
        let last = boxes[boxes.count - 1].1.center[axis]
        let step = (last - first) / Double(boxes.count - 1)
        var commands: [EditCommand] = []
        for (index, entry) in boxes.enumerated() where index > 0 && index < boxes.count - 1 {
            var delta = Vec3.zero
            delta[axis] = first + step * Double(index) - entry.1.center[axis]
            commands.append(translate([entry.0], by: delta, in: scene))
        }
        return .batch("Distribute", commands)
    }

    // MARK: Swap, color, state

    /// Replaces a blockout with a library asset, keeping position and rotation and fitting
    /// the asset into the blockout's size (uniform scale, so it's never distorted).
    public func swap(_ id: ObjectID, with asset: LibraryAsset, in scene: Scene) -> EditCommand? {
        guard let object = scene.objects[id] else { return nil }
        var commands: [EditCommand] = [.setKind(id, .asset(asset.id))]
        let oldLocal = bounds.localBounds(of: object)
        let newLocal = asset.bounds ?? .unitBase
        var transform = object.transform
        if let oldLocal {
            let target = oldLocal.size.scaled(by: transform.scale)
            let native = newLocal.size
            let ratios = Axis.allCases.compactMap { axis -> Double? in
                native[axis] > 1e-6 && target[axis] > 1e-6 ? target[axis] / native[axis] : nil
            }
            let uniform = ratios.min() ?? 1
            // Keep the base where the blockout's base was.
            let oldBaseY = oldLocal.min.y * transform.scale.y
            transform.scale = Vec3(uniform, uniform, uniform)
            transform.position.y += oldBaseY - newLocal.min.y * uniform
        }
        commands.append(setTransform(id, transform))
        commands.append(.rename(id, asset.name))
        // Assets keep their own materials unless the user tints them.
        commands.append(.setProperties([PropertyChange(object: id, key: .color, value: nil)]))
        return .batch("Swap for \(asset.name)", commands)
    }

    public func setColor(_ ids: [ObjectID], _ color: ColorValue?, in scene: Scene) -> EditCommand {
        .setProperties(ids.filter { scene.objects[$0]?.kind.hasSurface == true }.map {
            PropertyChange(object: $0, key: .color, value: color.map(PropertyValue.color))
        })
    }

    public func setFlag(_ ids: [ObjectID], key: PropertyKey, _ value: Bool) -> EditCommand {
        .setProperties(ids.map { PropertyChange(object: $0, key: key, value: .bool(value)) })
    }

    // MARK: Prefabs

    /// Builds a prefab fragment from a selection, re-centred so its base center is the origin.
    public mutating func prefabFragment(_ ids: [ObjectID], in scene: Scene) -> SceneFragment? {
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
    public mutating func replaceWithPrefab(_ ids: [ObjectID], prefab: Prefab, in scene: Scene) -> (EditCommand, ObjectID)? {
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
    public mutating func unpack(_ id: ObjectID, prefab: Prefab, in scene: Scene) -> EditCommand? {
        guard let instance = scene.objects[id] else { return nil }
        let world = scene.worldTransform(of: id)
        var (copy, _) = FragmentTools.reidentified(prefab.fragment, ids: &ids)
        copy = FragmentTools.transformRoots(copy) { world * $0 }
        let parentIndex = scene.childIDs(of: instance.parent).firstIndex(of: id)
        let parentWorld = instance.parent.map { scene.worldTransform(of: $0) } ?? .identity
        copy = FragmentTools.transformRoots(copy) { Transform.relative(world: $0, toParent: parentWorld) }
        return .batch("Unpack \(instance.name)", [.delete([id]), .insert(copy, parent: instance.parent, index: parentIndex)])
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
