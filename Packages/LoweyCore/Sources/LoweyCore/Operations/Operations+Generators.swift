import Foundation

public extension Operations {
    // MARK: Generators

    /// Copies of `source` laid out as an array, grouped (source included as the first element).
    mutating func array(_ source: ObjectID, layout: ArrayLayout, in scene: Scene) -> (EditCommand, ObjectID)? {
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
    mutating func scatter(_ source: ObjectID, center: Vec3, settings: ScatterSettings, in scene: Scene) -> (EditCommand, ObjectID)? {
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

    func align(_ ids: [ObjectID], axis: Axis, mode: AlignMode, in scene: Scene) -> EditCommand? {
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
    func distribute(_ ids: [ObjectID], axis: Axis, in scene: Scene) -> EditCommand? {
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
    func swap(_ id: ObjectID, with asset: LibraryAsset, in scene: Scene) -> EditCommand? {
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

    func setColor(_ ids: [ObjectID], _ color: ColorValue?, in scene: Scene) -> EditCommand {
        .setProperties(ids.filter { scene.objects[$0]?.kind.hasSurface == true }.map {
            PropertyChange(object: $0, key: .color, value: color.map(PropertyValue.color))
        })
    }

    func setFlag(_ ids: [ObjectID], key: PropertyKey, _ value: Bool) -> EditCommand {
        .setProperties(ids.map { PropertyChange(object: $0, key: key, value: .bool(value)) })
    }
}
