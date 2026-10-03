import Foundation

extension RelationSolver {
    /// A surface in world space: its height and its rectangle on the ground plane.
    struct WorldSurface {
        var height: Double
        var minX: Double
        var maxX: Double
        var minZ: Double
        var maxZ: Double

        var area: Double { (maxX - minX) * (maxZ - minZ) }
        var center: Vec3 { Vec3((minX + maxX) / 2, height, (minZ + maxZ) / 2) }
    }

    /// The reference's surfaces in world space, highest first (its box's top when the Kit says nothing).
    func surfaces(of reference: ObjectID, frame: Frame) -> [WorldSurface] {
        let world = scene.worldTransform(of: reference)
        let known = kitInfo(reference)?.surfaces ?? []
        guard !known.isEmpty else {
            return [WorldSurface(height: frame.box.max.y, minX: frame.box.min.x, maxX: frame.box.max.x, minZ: frame.box.min.z, maxZ: frame.box.max.z)]
        }
        return known.map { surface in
            let corners = [Vec3(surface.minX, surface.height, surface.minZ), Vec3(surface.maxX, surface.height, surface.minZ),
                           Vec3(surface.minX, surface.height, surface.maxZ), Vec3(surface.maxX, surface.height, surface.maxZ)].map(world.apply)
            return WorldSurface(height: corners[0].y, minX: corners.map(\.x).min() ?? 0, maxX: corners.map(\.x).max() ?? 0,
                                minZ: corners.map(\.z).min() ?? 0, maxZ: corners.map(\.z).max() ?? 0)
        }.sorted { $0.height > $1.height }
    }

    /// Half the box's extent along a ground direction.
    static func reach(_ box: Bounds, along direction: Vec3) -> Double {
        abs(direction.x) * box.size.x / 2 + abs(direction.z) * box.size.z / 2
    }

    func single(_ target: ObjectID, _ relation: Relation, ref: Frame, reference: ObjectID, offset: Vec3, index: Int) throws -> Placement {
        let rotation = scene.worldTransform(of: target).rotation
        var turned = rotation
        if relation == .facing {
            turned = facingRotation(of: target, toward: ref.position)
        } else if relation == .on {
            // Things put on furniture face the way it faces (a monitor on a desk, books on a shelf).
            turned = facingRotation(of: target, toward: scene.worldTransform(of: target).position + ref.front, from: scene.worldTransform(of: target).position)
        }
        let shape = shape(of: target, rotation: turned)
        let shapeCenter = Vec3((shape.min.x + shape.max.x) / 2, 0, (shape.min.z + shape.max.z) / 2)
        let nudge = ref.right * offset.x + Vec3(0, offset.y, 0) + ref.front * offset.z
        let name = scene.objects[target]?.name ?? target.raw
        let refName = scene.objects[reference]?.name ?? reference.raw
        var position: Vec3
        var note: String
        var push: Vec3?
        switch relation {
        case .on:
            let (spot, surface) = try spotOn(reference, ref: ref, target: target, shape: shape, nudge: nudge)
            position = Vec3(spot.x, 0, spot.z) - shapeCenter + Vec3(0, surface.height - shape.min.y, 0)
            note = "“\(name)” on “\(refName)” (\(Int((surface.height * 100).rounded())) cm up)"
        case .besideLeft, .besideRight, .inFrontOf, .behind:
            let direction: Vec3 = switch relation {
            case .besideLeft: -ref.right
            case .besideRight: ref.right
            case .inFrontOf: ref.front
            default: -ref.front
            }
            let distance = Self.reach(ref.box, along: direction) + Self.reach(shape, along: direction) + gap + Double(index) * gap
            let center = Vec3(ref.box.center.x, 0, ref.box.center.z) + direction * distance
            position = center - shapeCenter + Vec3(0, ref.box.min.y - shape.min.y, 0) + nudge
            push = direction
            note = "“\(name)” \(Self.words(relation)) “\(refName)”"
        case .above:
            position = Vec3(ref.box.center.x, ref.box.max.y + 0.2 - shape.min.y, ref.box.center.z) - shapeCenter + nudge
            note = "“\(name)” above “\(refName)” (in the air, on purpose)"
        case .under:
            position = Vec3(ref.box.center.x, ref.box.min.y - shape.min.y, ref.box.center.z) - shapeCenter + nudge
            note = "“\(name)” under “\(refName)”"
        case .inside:
            position = Vec3(ref.box.center.x, ref.box.min.y + 0.02 - shape.min.y, ref.box.center.z) - shapeCenter + nudge
            note = "“\(name)” inside “\(refName)”"
        default:
            position = scene.worldTransform(of: target).position + nudge
            note = "“\(name)” faces “\(refName)”"
        }
        if let push {
            position = separated(target, at: position, shape: shape, along: push, ignoring: [reference])
        }
        var world = scene.worldTransform(of: target)
        world.position = position
        world.rotation = turned
        return Placement(object: target, world: world, note: note, airborne: relation == .above)
    }

    static func words(_ relation: Relation) -> String {
        switch relation {
        case .besideLeft: "left of"
        case .besideRight: "right of"
        case .inFrontOf: "in front of"
        case .behind: "behind"
        default: "by"
        }
    }

    /// The level turn that points the target's front at a point.
    func facingRotation(of target: ObjectID, toward point: Vec3) -> Quat {
        let from = scene.worldTransform(of: target).position
        let local = kitInfo(target)?.front ?? Vec3(0, 0, 1)
        let wanted = atan2(point.x - from.x, point.z - from.z)
        let own = atan2(local.x, local.z)
        return Quat(angle: wanted - own, axis: .unitY)
    }

    /// A free spot on the reference's best surface: as near its middle (plus the nudge) as the things already there allow.
    func spotOn(_ reference: ObjectID, ref: Frame, target: ObjectID, shape: Bounds, nudge: Vec3) throws -> (Vec3, WorldSurface) {
        let all = surfaces(of: reference, frame: ref)
        let footprint = shape.size.x * shape.size.z
        guard let surface = all.first(where: { $0.area >= footprint * 0.6 }) ?? all.first else {
            throw PlacementError.noRoom(scene.objects[reference]?.name ?? reference.raw)
        }
        let halfX = shape.size.x / 2
        let halfZ = shape.size.z / 2
        let start = surface.center + Vec3(nudge.x, 0, nudge.z)
        let step = max(min(max(shape.size.x, shape.size.z) * 0.5, 0.25), 0.03)
        let others = restingOn(surface, excluding: [target, reference])
        for ring in 0 ... 12 {
            for candidate in Self.ring(start, radius: Double(ring) * step) {
                let x = min(max(candidate.x, surface.minX + halfX), surface.maxX - halfX)
                let z = min(max(candidate.z, surface.minZ + halfZ), surface.maxZ - halfZ)
                let spot = Vec3(surface.minX + halfX > surface.maxX - halfX ? surface.center.x : x, surface.height,
                                surface.minZ + halfZ > surface.maxZ - halfZ ? surface.center.z : z)
                let footprintBox = Bounds(min: Vec3(spot.x - halfX, surface.height, spot.z - halfZ),
                                          max: Vec3(spot.x + halfX, surface.height + shape.size.y, spot.z + halfZ))
                if !others.contains(where: { Self.overlap($0, footprintBox) }) { return (spot, surface) }
            }
        }
        return (start, surface)
    }

    /// Points on a ring (the start itself for radius 0).
    static func ring(_ center: Vec3, radius: Double) -> [Vec3] {
        guard radius > 0 else { return [center] }
        let count = 8
        return (0 ..< count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi
            return center + Vec3(cos(angle) * radius, 0, sin(angle) * radius)
        }
    }

    /// Boxes of the things standing on a surface.
    func restingOn(_ surface: WorldSurface, excluding: Set<ObjectID>) -> [Bounds] {
        scene.roots.flatMap { scene.subtree(of: $0) }.compactMap { id -> Bounds? in
            guard !excluding.contains(id), !excluding.contains(where: { scene.isAncestor($0, of: id) || scene.isAncestor(id, of: $0) }),
                  scene.objects[id]?.kind.hasSurface == true, let box = bounds.worldBounds(of: id, in: scene) else { return nil }
            let onIt = abs(box.min.y - surface.height) < 0.05 && box.max.x > surface.minX && box.min.x < surface.maxX
                && box.max.z > surface.minZ && box.min.z < surface.maxZ
            return onIt ? box : nil
        }
    }

    static func overlap(_ a: Bounds, _ b: Bounds, margin: Double = 0.005) -> Bool {
        a.min.x < b.max.x - margin && a.max.x > b.min.x + margin && a.min.y < b.max.y - margin && a.max.y > b.min.y + margin
            && a.min.z < b.max.z - margin && a.max.z > b.min.z + margin
    }

    /// Pushes a placed box along `direction` until it no longer intersects anything (besides `ignoring`).
    func separated(_ target: ObjectID, at position: Vec3, shape: Bounds, along direction: Vec3, ignoring: Set<ObjectID>) -> Vec3 {
        let blockers = scene.roots.compactMap { root -> Bounds? in
            guard root != target, !ignoring.contains(root), !scene.isAncestor(root, of: target), !scene.isAncestor(target, of: root),
                  !ignoring.contains(where: { scene.isAncestor(root, of: $0) }) else { return nil }
            return bounds.worldBounds(of: root, in: scene)
        }
        var current = position
        for _ in 0 ..< 60 {
            let box = Bounds(min: shape.min + current, max: shape.max + current)
            guard blockers.contains(where: { Self.overlap($0, box) }) else { return current }
            current += direction * 0.05
        }
        return current
    }
}
