import Foundation

/// Every character's skeleton through one door. Posing by dragging, IK, the pose library and clips all go through it,
/// whatever made the character:
/// - a built **Puppet**: each joint is an object (its `bone` property names the joint);
/// - a **drawn rig** (drawn bones, "Rig as a person", 2D drawn puppets) or an imported **Rigged** model: the joints
///   live in the character's `bone.<joint>` properties and the renderer bends the surface;
/// - the **Blob**: its two mitten hands, stored as its reach dials (its rubber-hose arms follow them).
public struct CharacterRig: Sendable {
    public enum Body: Hashable, Sendable {
        case blob
        /// The object behind each joint, in skeleton order.
        case joints([ObjectID])
        /// `bone.<joint>` properties on the character.
        case bones
    }

    public let character: ObjectID
    /// The skeleton in its rest pose (as made, not straightened for clips).
    public let skeleton: Skeleton
    public let standard: SkeletonStandard
    /// Standard bone → joint name (humanoids).
    public let boneMap: [String: String]
    public let body: Body

    /// The character's skeleton, if it has one. `rigs` are the library's rigged models.
    public static func of(_ id: ObjectID, in scene: Scene, rigs: [AssetID: RigAsset] = [:]) -> CharacterRig? {
        guard let object = scene.objects[id] else { return nil }
        if object[.rigStandard]?.stringValue == "blob" {
            return CharacterRig(character: id, skeleton: Skeleton(joints: []), standard: .custom, boneMap: [:], body: .blob)
        }
        if let rig = object.rig, !rig.skeleton.isEmpty {
            let map = rig.standard == .custom ? [:] : Dictionary(rig.skeleton.names.map { ($0, $0) }, uniquingKeysWith: { first, _ in first })
            return CharacterRig(character: id, skeleton: rig.skeleton, standard: rig.standard, boneMap: map, body: .bones)
        }
        if let asset = object.kind.assetID, let rig = rigs[asset] {
            return CharacterRig(character: id, skeleton: rig.skeleton, standard: rig.standard, boneMap: rig.boneMap, body: .bones)
        }
        if object[.rigStandard] != nil, object.kind == .group {
            return puppet(id, in: scene)
        }
        return nil
    }

    /// A built puppet: its joint objects, with their rest pose as they stand in `scene`.
    static func puppet(_ id: ObjectID, in scene: Scene) -> CharacterRig? {
        var ids: [ObjectID] = []
        var joints: [Joint] = []
        let frame = scene.worldTransform(of: id)
        func visit(_ object: ObjectID, parent: Int?) {
            guard let node = scene.objects[object] else { return }
            var next = parent
            if let bone = node[.bone]?.stringValue {
                let model = Transform.relative(world: scene.worldTransform(of: object), toParent: frame)
                let parentModel = parent.map { Transform.relative(world: scene.worldTransform(of: ids[$0]), toParent: frame) } ?? .identity
                ids.append(object)
                joints.append(Joint(name: bone, parent: parent, rest: Transform.relative(world: model, toParent: parentModel)))
                next = joints.count - 1
            }
            for child in node.children {
                visit(child, parent: next)
            }
        }
        for child in scene.objects[id]?.children ?? [] {
            visit(child, parent: nil)
        }
        guard !joints.isEmpty else { return nil }
        let map = Dictionary(joints.map { ($0.name, $0.name) }, uniquingKeysWith: { first, _ in first })
        let standard: SkeletonStandard = Set(joints.map(\.name)).isSubset(of: SkeletonStandard.humanoid.bones) ? .humanoid : .custom
        return CharacterRig(character: id, skeleton: Skeleton(joints: joints), standard: standard, boneMap: map, body: .joints(ids))
    }

    /// The joint playing a standard bone.
    public func joint(_ bone: String) -> Int? {
        skeleton.index(of: boneMap[bone] ?? bone)
    }

    /// Where the character's skeleton stands in the world (its model space).
    public func frame(in scene: Scene) -> Transform {
        switch body {
        case .bones: RigSpace.frame(of: character, in: scene)
        case .blob, .joints: scene.worldTransform(of: character)
        }
    }

    /// Each joint's local transform as `scene` shows it. `pose` is the animator's pose for skeletons of bones.
    public func localPose(in scene: Scene, pose: [Transform]?) -> [Transform] {
        switch body {
        case .blob:
            return []
        case .bones:
            let base = pose.flatMap { $0.count == skeleton.joints.count ? $0 : nil } ?? skeleton.restPose
            return scene.objects[character].map { RigPoses.posed(base, skeleton: skeleton, by: $0) } ?? base
        case let .joints(ids):
            let frame = frame(in: scene)
            let model = ids.map { Transform.relative(world: scene.worldTransform(of: $0), toParent: frame) }
            return skeleton.joints.indices.map { index in
                Transform.relative(world: model[index], toParent: skeleton.joints[index].parent.map { model[$0] } ?? .identity)
            }
        }
    }

    /// The property changes that turn these joints to these local rotations.
    public func changes(turning rotations: [Int: Quat]) -> [PropertyChange] {
        rotations.sorted { $0.key < $1.key }.compactMap { index, rotation in
            guard skeleton.joints.indices.contains(index) else { return nil }
            switch body {
            case .blob:
                return nil
            case .bones:
                return PropertyChange(object: character, key: .boneTurn(skeleton.joints[index].name), value: .quat(rotation.normalized))
            case let .joints(ids):
                return PropertyChange(object: ids[index], key: .rotation, value: .quat(rotation.normalized))
            }
        }
    }

    /// The changes that put every joint back as it was made (bones only: a puppet's rest is its objects).
    public func resetting(in scene: Scene) -> [PropertyChange] {
        guard body == .bones, let object = scene.objects[character] else { return [] }
        return object.properties.keys.filter { $0.boneJoint != nil }.sorted().map { PropertyChange(object: character, key: $0, value: nil) }
    }
}

/// Bringing the end of a chain of joints to a point: FABRIK (Aristidou & Lasenby) on the joints' positions, then
/// each joint turned so its bone points where its child went. The chain keeps the side it bends to; a straight chain
/// bends toward `pole`.
public enum ChainIK {
    /// New local rotations for the chain's joints (all but the last, whose own turn is kept), in skeleton order.
    /// `chain` runs from the joint that stays put to the one brought to `target` (model space).
    public static func solve(chain: [Int], skeleton: Skeleton, local: [Transform], target: Vec3, pole: Vec3? = nil) -> [Int: Quat] {
        guard chain.count >= 2 else { return [:] }
        let model = skeleton.modelSpace(local)
        var points = chain.map { model[$0].position }
        let lengths = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
        guard lengths.allSatisfy({ $0 > 1e-9 }) else { return [:] }
        bendIfStraight(&points, target: target, pole: pole)
        let root = points[0]
        let reach = lengths.reduce(0, +)
        if root.distance(to: target) >= reach {
            let direction = (target - root).normalized
            for index in 1 ..< points.count {
                points[index] = points[index - 1] + direction * lengths[index - 1]
            }
        } else {
            for _ in 0 ..< 24 {
                points[points.count - 1] = target
                for index in stride(from: points.count - 2, through: 0, by: -1) {
                    points[index] = points[index + 1] + (points[index] - points[index + 1]).normalized * lengths[index]
                }
                points[0] = root
                for index in 1 ..< points.count {
                    points[index] = points[index - 1] + (points[index] - points[index - 1]).normalized * lengths[index - 1]
                }
                if points[points.count - 1].distance(to: target) < reach * 1e-5 { break }
            }
        }
        // Turn each joint so its bone points along the new chain; children inherit their parent's turn.
        var newModel = model.map(\.rotation)
        var result: [Int: Quat] = [:]
        var inherited = Quat.identity
        for position in 0 ..< chain.count - 1 {
            let joint = chain[position]
            let old = model[chain[position + 1]].position - model[joint].position
            let turn = Quat.between(inherited.act(old), points[position + 1] - points[position])
            inherited = (turn * inherited).normalized
            newModel[joint] = (inherited * model[joint].rotation).normalized
            let parentRotation = skeleton.joints[joint].parent.map { newModel[$0] } ?? .identity
            result[joint] = (parentRotation.inverse * newModel[joint]).normalized
        }
        return result
    }

    /// A chain lying straight can't tell which way to fold: nudge its middle joints toward the pole (or toward the
    /// target's side) so it bends like a knee, not back on itself.
    static func bendIfStraight(_ points: inout [Vec3], target: Vec3, pole: Vec3?) {
        guard points.count >= 3 else { return }
        let axis = (points[points.count - 1] - points[0]).normalized
        let straight = (1 ..< points.count - 1).allSatisfy { index in
            let offset = points[index] - points[0]
            return (offset - axis * offset.dot(axis)).length < 1e-4 * max(points[0].distance(to: points[points.count - 1]), 1e-9)
        }
        guard straight else { return }
        var side = (pole ?? (target - points[0]))
        side -= axis * side.dot(axis)
        if side.length < 1e-9 { side = abs(axis.y) < 0.9 ? Vec3.unitY.cross(axis) : Vec3.unitZ.cross(axis) }
        let nudge = points[0].distance(to: points[points.count - 1]) * 0.01
        for index in 1 ..< points.count - 1 {
            points[index] += side.normalized * nudge
        }
    }
}
