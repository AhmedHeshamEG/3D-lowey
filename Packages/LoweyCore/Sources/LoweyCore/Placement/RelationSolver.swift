import Foundation

/// Where to put something, said the way a director says it. The solver turns it into numbers using what the Kit
/// knows (real sizes, the surfaces things stand on, which way things face), grounds everything and moves things apart
/// that would intersect.
public enum Relation: Hashable, Sendable {
    /// On the reference's top surface (a desk's top, a shelf).
    case on
    /// Beside it, as seen from its front (for something facing the camera: screen left / right).
    case besideLeft, besideRight
    case inFrontOf, behind
    /// Over it, in the air (a ceiling lamp over a table).
    case above
    /// Under it (a bag under a desk).
    case under
    /// In its middle (a plant in a pot, a robot in a cave).
    case inside
    /// Turned to face it (stays where it is).
    case facing
    /// The targets in a ring around it, facing it.
    case around(radius: Double?)
    /// The targets in a line, starting next to the reference, along its left-right.
    case row(spacing: Double?)
    /// The targets in a grid in front of the reference.
    case grid(columns: Int?, spacing: Double?)
    /// The targets scattered over the reference's footprint (or a circle round it).
    case scatterIn(seed: UInt64)
    /// The targets piled on the reference, one on another.
    case stack

    /// From the Scene Script names (`on`, `beside_left`, `around`…); parameters come from the action.
    public init?(name: String, radius: Double? = nil, spacing: Double? = nil, columns: Int? = nil, seed: UInt64 = 1) {
        switch name.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "on", "on_top_of", "onto": self = .on
        case "beside_left", "left_of", "left": self = .besideLeft
        case "beside_right", "right_of", "right", "beside", "next_to": self = .besideRight
        case "in_front_of", "front": self = .inFrontOf
        case "behind", "back": self = .behind
        case "above", "over": self = .above
        case "under", "below", "beneath": self = .under
        case "inside", "in": self = .inside
        case "facing", "face", "look_at": self = .facing
        case "around": self = .around(radius: radius)
        case "row", "line": self = .row(spacing: spacing)
        case "grid": self = .grid(columns: columns, spacing: spacing)
        case "scatter_in", "scatter": self = .scatterIn(seed: seed)
        case "stack", "pile": self = .stack
        default: return nil
        }
    }

    public static let names = ["on", "beside_left", "beside_right", "in_front_of", "behind", "above", "under", "inside", "facing",
                               "around", "row", "grid", "scatter_in", "stack"]
}

/// One placed object: where it went (world), and in words.
public struct Placement: Hashable, Sendable {
    public var object: ObjectID
    public var world: Transform
    public var note: String
}

public struct RelationSolver {
    public var scene: Scene
    public var bounds: SceneBounds
    /// Gap kept between things that are side by side (metres).
    public var gap = 0.04

    public init(scene: Scene, library: LibraryManifest) {
        self.scene = scene
        bounds = SceneBounds(library: library)
    }

    /// A frame for an object: its pivot, its front and right (as seen from its front), its world box.
    struct Frame {
        var position: Vec3
        var front: Vec3
        var right: Vec3
        var box: Bounds
        var yaw: Double
    }

    func frame(of id: ObjectID) -> Frame? {
        guard scene.objects[id] != nil, let box = bounds.worldBounds(of: id, in: scene) else { return nil }
        let world = scene.worldTransform(of: id)
        let localFront = kitInfo(id)?.front ?? Vec3(0, 0, 1)
        var front = world.rotation.act(localFront)
        front.y = 0
        front = front.length > 1e-6 ? front.normalized : Vec3(0, 0, 1)
        // Seen from the front, looking back at it (as a camera in front of it sees it): right is up × front.
        let right = Vec3.unitY.cross(front).normalized
        return Frame(position: world.position, front: front, right: right, box: box, yaw: atan2(front.x, front.z))
    }

    func kitInfo(_ id: ObjectID) -> KitInfo? {
        scene.objects[id]?.kind.assetID.flatMap { bounds.library.asset($0)?.kit }
    }

    /// The target's box relative to its pivot (its own size, as turned now).
    func shape(of id: ObjectID, rotation: Quat? = nil) -> Bounds {
        guard let object = scene.objects[id] else { return .unitBase }
        let world = scene.worldTransform(of: id)
        if object.children.isEmpty, let local = bounds.localBounds(of: object) {
            return local.transformed(by: Transform(position: .zero, rotation: rotation ?? world.rotation, scale: world.scale))
        }
        var local = scene
        var moved = object
        moved.parent = nil
        moved.transform = Transform(position: .zero, rotation: rotation ?? scene.worldTransform(of: id).rotation,
                                    scale: scene.worldTransform(of: id).scale)
        local.objects[id] = moved
        if !local.roots.contains(id) { local.roots.append(id) }
        return bounds.worldBounds(of: id, in: local) ?? .unitBase
    }

    /// Places `targets` by `relation` to `reference`. `offset` (metres, in the reference's frame: x right, y up, z front)
    /// nudges the result.
    public func place(_ targets: [ObjectID], _ relation: Relation, reference: ObjectID?, offset: Vec3 = .zero) throws -> [Placement] {
        guard !targets.isEmpty else { return [] }
        for target in targets where scene.objects[target] == nil {
            throw PlacementError.missing(target.raw)
        }
        let ref: Frame? = try reference.map { id in
            guard let frame = frame(of: id) else { throw PlacementError.missing(id.raw) }
            return frame
        }
        switch relation {
        case .around, .row, .grid, .scatterIn, .stack:
            guard let ref else { throw PlacementError.needsReference }
            return try group(targets, relation, ref: ref, reference: reference, offset: offset)
        default:
            guard let ref, let reference else { throw PlacementError.needsReference }
            return try targets.enumerated().map { index, target in
                try single(target, relation, ref: ref, reference: reference, offset: offset, index: index)
            }
        }
    }
}

public extension RelationSolver {
    /// The placements as one property change per object (local to each object's parent).
    func command(for placements: [Placement]) -> EditCommand {
        .setProperties(placements.flatMap { placement -> [PropertyChange] in
            let parentWorld = scene.objects[placement.object]?.parent.map { scene.worldTransform(of: $0) } ?? .identity
            let local = Transform.relative(world: placement.world, toParent: parentWorld)
            return [PropertyChange(object: placement.object, key: .position, value: .vec3(local.position)),
                    PropertyChange(object: placement.object, key: .rotation, value: .quat(local.rotation))]
        })
    }

    /// Whether an object stands on something (the ground or another object's top), within a centimetre.
    func isGrounded(_ id: ObjectID) -> (grounded: Bool, gap: Double) {
        guard let box = bounds.worldBounds(of: id, in: scene) else { return (true, 0) }
        var support = 0.0
        for other in scene.roots where other != id && !scene.isAncestor(other, of: id) && !scene.isAncestor(id, of: other) {
            guard let below = bounds.worldBounds(of: other, in: scene), below.max.x > box.min.x, below.min.x < box.max.x,
                  below.max.z > box.min.z, below.min.z < box.max.z, let frame = frame(of: other) else { continue }
            // Its top, or (for Kit furniture) every shelf and top it has.
            let heights = kitInfo(other)?.surfaces.isEmpty == false ? surfaces(of: other, frame: frame).map(\.height) : [below.max.y]
            for height in heights where height <= box.min.y + 0.01 {
                support = max(support, height)
            }
        }
        let gap = box.min.y - support
        return (abs(gap) < 0.01, gap)
    }
}

public enum PlacementError: Error, Equatable, CustomStringConvertible {
    case missing(String)
    case needsReference
    case noRoom(String)

    public var description: String {
        switch self {
        case let .missing(name): "No object called “\(name)”"
        case .needsReference: "This relation needs a reference object"
        case let .noRoom(name): "There's no room on “\(name)”"
        }
    }
}
