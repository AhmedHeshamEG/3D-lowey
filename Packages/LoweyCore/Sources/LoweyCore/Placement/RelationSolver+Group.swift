import Foundation

extension RelationSolver {
    /// Several targets laid out together relative to the reference.
    func group(_ targets: [ObjectID], _ relation: Relation, ref: Frame, reference: ObjectID?, offset: Vec3) throws -> [Placement] {
        let refName = reference.flatMap { scene.objects[$0]?.name } ?? "the reference"
        let shapes = targets.map { shape(of: $0) }
        let floor = floorUnder(ref.box, excluding: Set(targets + (reference.map { [$0] } ?? [])))
        switch relation {
        case let .around(radius):
            // Turned to face the middle, a target's box can be as wide as its diagonal.
            let widest = shapes.map { ($0.size.x * $0.size.x + $0.size.z * $0.size.z).squareRoot() }.max() ?? 0.5
            // Never so tight that neighbours touch: the chord between two must fit the widest.
            let apart = targets.count > 1 ? (widest + gap * 2) / (2 * sin(.pi / Double(targets.count))) : 0
            let ring = max(radius ?? (max(ref.box.size.x, ref.box.size.z) / 2 + widest / 2 + gap * 3), apart)
            let center = Vec3(ref.box.center.x, floor, ref.box.center.z)
            return targets.enumerated().map { index, target in
                let angle = ref.yaw + Double(index) / Double(targets.count) * 2 * .pi
                let point = center + Vec3(sin(angle), 0, cos(angle)) * ring
                var world = scene.worldTransform(of: target)
                world.rotation = facingRotation(of: target, toward: center, from: point)
                let turned = shape(of: target, rotation: world.rotation)
                world.position = Vec3(point.x - (turned.min.x + turned.max.x) / 2, floor - turned.min.y, point.z - (turned.min.z + turned.max.z) / 2)
                return Placement(object: target, world: world, note: "“\(name(of: target))” around “\(refName)”")
            }
        case let .row(spacing):
            var along = Self.reach(ref.box, along: ref.right) + gap
            return targets.enumerated().map { index, target in
                let shape = shapes[index]
                let width = Self.reach(shape, along: ref.right)
                along += width
                let point = Vec3(ref.box.center.x, 0, ref.box.center.z) + ref.right * along + ref.front * offset.z
                along += width + (spacing ?? gap * 2)
                return Placement(object: target, world: grounded(target, shape: shape, at: point, floor: floor),
                                 note: "“\(name(of: target))” in a row from “\(refName)”")
            }
        case let .grid(columns, spacing):
            let perRow = max(columns ?? Int(Double(targets.count).squareRoot().rounded(.up)), 1)
            let cell = spacing ?? ((shapes.map { max($0.size.x, $0.size.z) }.max() ?? 0.5) + gap * 3)
            let start = Vec3(ref.box.center.x, 0, ref.box.center.z) + ref.front * (Self.reach(ref.box, along: ref.front) + cell / 2 + gap)
            return targets.enumerated().map { index, target in
                let column = Double(index % perRow) - Double(perRow - 1) / 2
                let row = Double(index / perRow)
                let point = start + ref.right * (column * cell) + ref.front * (row * cell)
                return Placement(object: target, world: grounded(target, shape: shapes[index], at: point, floor: floor),
                                 note: "“\(name(of: target))” in a grid before “\(refName)”")
            }
        case let .scatterIn(seed):
            return scatter(targets, shapes: shapes, ref: ref, seed: seed, refName: refName)
        case .stack:
            var height = ref.box.max.y
            return targets.enumerated().map { index, target in
                let shape = shapes[index]
                var world = scene.worldTransform(of: target)
                world.position = Vec3(ref.box.center.x - (shape.min.x + shape.max.x) / 2, height - shape.min.y,
                                      ref.box.center.z - (shape.min.z + shape.max.z) / 2)
                height += shape.size.y
                return Placement(object: target, world: world, note: "“\(name(of: target))” stacked on “\(refName)”")
            }
        default:
            return []
        }
    }

    func name(of id: ObjectID) -> String { scene.objects[id]?.name ?? id.raw }

    /// The floor under a box: the highest top (or Kit surface) below it, else the ground (0). Things grouped around a
    /// floating reference still stand on the floor.
    func floorUnder(_ box: Bounds, excluding: Set<ObjectID>) -> Double {
        var floor = 0.0
        for other in scene.roots where !excluding.contains(other) {
            guard let below = bounds.worldBounds(of: other, in: scene), below.max.x > box.min.x, below.min.x < box.max.x,
                  below.max.z > box.min.z, below.min.z < box.max.z, let frame = frame(of: other) else { continue }
            let heights = kitInfo(other)?.surfaces.isEmpty == false ? surfaces(of: other, frame: frame).map(\.height) : [below.max.y]
            for height in heights where height <= box.min.y + 0.01 {
                floor = max(floor, height)
            }
        }
        return floor
    }

    /// The target with its box's middle at `point` and its bottom on `floor`.
    func grounded(_ target: ObjectID, shape: Bounds, at point: Vec3, floor: Double) -> Transform {
        var world = scene.worldTransform(of: target)
        world.position = Vec3(point.x - (shape.min.x + shape.max.x) / 2, floor - shape.min.y, point.z - (shape.min.z + shape.max.z) / 2)
        return world
    }

    func facingRotation(of target: ObjectID, toward point: Vec3, from position: Vec3) -> Quat {
        let local = kitInfo(target)?.front ?? Vec3(0, 0, 1)
        return Quat(angle: atan2(point.x - position.x, point.z - position.z) - atan2(local.x, local.z), axis: .unitY)
    }

    /// Scattered over a flat reference's footprint (a lawn, a floor), or in a circle round anything else; turned at
    /// random, never on top of each other.
    func scatter(_ targets: [ObjectID], shapes _: [Bounds], ref: Frame, seed: UInt64, refName: String) -> [Placement] {
        var random = SeededRandom(seed: seed)
        let flat = ref.box.size.y < 0.1
        let floor = flat ? ref.box.max.y : ref.box.min.y
        var taken: [Bounds] = flat ? [] : [ref.box]
        return targets.map { target in
            var world = scene.worldTransform(of: target)
            for _ in 0 ..< 30 {
                let point = scatterPoint(ref, flat: flat, random: &random)
                let rotation = Quat(angle: random.range(0, 2 * .pi), axis: .unitY)
                let shape = shape(of: target, rotation: rotation)
                world = grounded(target, shape: shape, at: point, floor: floor)
                world.rotation = rotation
                let box = Bounds(min: shape.min + world.position, max: shape.max + world.position)
                if !taken.contains(where: { Self.overlap($0, box) }) {
                    taken.append(box)
                    break
                }
            }
            return Placement(object: target, world: world, note: "“\(name(of: target))” scattered by “\(refName)”")
        }
    }

    /// A random point on a flat reference, or in a ring round a standing one.
    func scatterPoint(_ ref: Frame, flat: Bool, random: inout SeededRandom) -> Vec3 {
        if flat {
            return Vec3(random.range(ref.box.min.x, ref.box.max.x), 0, random.range(ref.box.min.z, ref.box.max.z))
        }
        let angle = random.range(0, 2 * .pi)
        let size = max(ref.box.size.x, ref.box.size.z)
        let distance = random.range(size * 0.7, size * 1.6)
        return Vec3(ref.box.center.x + cos(angle) * distance, 0, ref.box.center.z + sin(angle) * distance)
    }
}
