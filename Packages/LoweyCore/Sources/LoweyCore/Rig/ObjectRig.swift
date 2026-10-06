import Foundation

/// A skeleton drawn into an object: its joints in the object's own space and the weights that make the surface follow
/// them. Drawn bones (a Pencil stroke through a limb), "Rig as a person" and 2D drawn puppets all make one of these;
/// the object's pose lives in its `bone.<joint>` properties, so posing, keys and clips work as for any property.
public struct ObjectRig: Codable, Hashable, Sendable {
    /// Joints, parents first. Rest transforms are relative to the parent with no turn of their own: a drawn joint is
    /// a point, and its bone runs to its child.
    public var skeleton: Skeleton
    /// The standard its joint names follow: humanoid after "Rig as a person" (built-in clips play), else custom.
    public var standard: SkeletonStandard
    /// Where a leaf joint's bone ends (object space), by joint name: the top of the head, the fingertips. A leaf with
    /// no tip is the end of a chain and moves nothing of its own.
    public var tips: [String: Vec3]
    /// The weights of a solid: a `.skin` file in the project (`RigFiles`), named by its content.
    public var skin: String?
    /// The weights of a drawing, one per stroke point in order (a few hundred, so they live here).
    public var points: SkinWeights?
    /// The fingerprint of the surface the weights were made for (`PaintMesh.fingerprint`, or the drawing's points).
    public var surface: String?

    public init(skeleton: Skeleton, standard: SkeletonStandard = .custom, tips: [String: Vec3] = [:], skin: String? = nil,
                points: SkinWeights? = nil, surface: String? = nil) {
        self.skeleton = skeleton
        self.standard = standard
        self.tips = tips
        self.skin = skin
        self.points = points
        self.surface = surface
    }

    private enum CodingKeys: String, CodingKey { case skeleton, standard, tips, skin, points, surface }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        skeleton = try c.decode(Skeleton.self, forKey: .skeleton)
        standard = try c.decodeIfPresent(SkeletonStandard.self, forKey: .standard) ?? .custom
        tips = try c.decodeIfPresent([String: Vec3].self, forKey: .tips) ?? [:]
        skin = try c.decodeIfPresent(String.self, forKey: .skin)
        points = try c.decodeIfPresent(SkinWeights.self, forKey: .points)
        surface = try c.decodeIfPresent(String.self, forKey: .surface)
    }

    /// A rig from joint positions in the object's space (parents first).
    public init(names: [String], parents: [Int?], positions: [Vec3], standard: SkeletonStandard = .custom, tips: [String: Vec3] = [:]) {
        let joints = names.indices.map { index in
            let offset = parents[index].map { positions[index] - positions[$0] } ?? positions[index]
            return Joint(name: names[index], parent: parents[index], rest: Transform(position: offset))
        }
        self.init(skeleton: Skeleton(joints: joints), standard: standard, tips: tips)
    }

    /// Each joint's rest position in the object's space.
    public var restPositions: [Vec3] { skeleton.modelRest.map(\.position) }

    /// The bones that carry weight: each joint to each of its children, and a leaf to its tip.
    public var segments: [BoneSegment] {
        let rest = restPositions
        var result: [BoneSegment] = []
        for index in skeleton.joints.indices {
            let children = skeleton.children(of: index)
            for child in children {
                result.append(BoneSegment(joint: index, head: rest[index], tail: rest[child]))
            }
            if children.isEmpty, let tip = tips[skeleton.joints[index].name] {
                result.append(BoneSegment(joint: index, head: rest[index], tail: tip))
            }
        }
        return result
    }

    /// The rig as the animator plays it. A humanoid's arms are turned out to a T-pose for retargeting (clips are made
    /// for T-poses), exactly as built puppets are.
    public var rigAsset: RigAsset {
        let names = skeleton.names
        let skeleton = standard == .humanoid ? TPose.straightenArms(skeleton) : skeleton
        let map = standard == .custom ? [:] : Dictionary(names.map { ($0, $0) }, uniquingKeysWith: { first, _ in first })
        return RigAsset(skeleton: skeleton, clips: [], standard: standard, boneMap: map)
    }

    /// A fresh joint name ("j1", "j2", …).
    public func newJointName() -> String {
        let used = Set(skeleton.names)
        var index = skeleton.joints.count
        while used.contains("j\(index)") {
            index += 1
        }
        return "j\(index)"
    }
}

/// A bone as a line segment in the object's space; the weight it gathers belongs to `joint`.
public struct BoneSegment: Hashable, Sendable {
    public var joint: Int
    public var head: Vec3
    public var tail: Vec3

    public init(joint: Int, head: Vec3, tail: Vec3) {
        self.joint = joint
        self.head = head
        self.tail = tail
    }

    /// The closest point of the segment to `point`.
    public func closest(to point: Vec3) -> Vec3 {
        let axis = tail - head
        let lengthSquared = axis.lengthSquared
        guard lengthSquared > 1e-12 else { return head }
        let t = min(max((point - head).dot(axis) / lengthSquared, 0), 1)
        return head + axis * t
    }

    public func distance(to point: Vec3) -> Double { closest(to: point).distance(to: point) }
}

/// Up to four joints and their weights per vertex (or stroke point), as the GPU skins them.
public struct SkinWeights: Hashable, Sendable {
    public var joints: [SIMD4<UInt16>]
    public var weights: [SIMD4<Float>]

    public init(joints: [SIMD4<UInt16>] = [], weights: [SIMD4<Float>] = []) {
        self.joints = joints
        self.weights = weights
    }

    public var count: Int { joints.count }

    /// One vertex's influences, heaviest first, from any number of (joint, weight) pairs: the four heaviest are kept,
    /// tiny ones dropped, and what's left adds up to one.
    public static func influence(_ pairs: [(joint: Int, weight: Double)]) -> (SIMD4<UInt16>, SIMD4<Float>) {
        let kept = pairs.filter { $0.weight > 1e-4 }.sorted { $0.weight > $1.weight }.prefix(4)
        let total = kept.reduce(0) { $0 + $1.weight }
        var joints = SIMD4<UInt16>(0, 0, 0, 0)
        var weights = SIMD4<Float>(0, 0, 0, 0)
        guard total > 0 else { return (joints, SIMD4<Float>(1, 0, 0, 0)) }
        for (slot, pair) in kept.enumerated() {
            joints[slot] = UInt16(clamping: pair.joint)
            weights[slot] = Float(pair.weight / total)
        }
        return (joints, weights)
    }

    /// The weight `joint` has on vertex `index`.
    public func weight(of joint: Int, at index: Int) -> Float {
        var total: Float = 0
        for slot in 0 ..< 4 where Int(joints[index][slot]) == joint {
            total += weights[index][slot]
        }
        return total
    }
}

extension SkinWeights: Codable {
    private enum CodingKeys: String, CodingKey { case joints, weights }

    /// Flat lists, four numbers a point.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let flatJoints = try c.decode([UInt16].self, forKey: .joints)
        let flatWeights = try c.decode([Float].self, forKey: .weights)
        guard flatJoints.count % 4 == 0, flatJoints.count == flatWeights.count else {
            throw DecodingError.dataCorruptedError(forKey: .weights, in: c, debugDescription: "four joints and weights a point")
        }
        joints = stride(from: 0, to: flatJoints.count, by: 4).map {
            SIMD4<UInt16>(flatJoints[$0], flatJoints[$0 + 1], flatJoints[$0 + 2], flatJoints[$0 + 3])
        }
        weights = stride(from: 0, to: flatWeights.count, by: 4).map {
            SIMD4<Float>(flatWeights[$0], flatWeights[$0 + 1], flatWeights[$0 + 2], flatWeights[$0 + 3])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(joints.flatMap { [$0.x, $0.y, $0.z, $0.w] }, forKey: .joints)
        try c.encode(weights.flatMap { [$0.x, $0.y, $0.z, $0.w] }, forKey: .weights)
    }
}

/// The `.skin` file: "MQSK", a version, the vertex count, then each vertex's four joints (UInt16) and four weights
/// (Float32), little-endian.
public extension SkinWeights {
    enum FileError: Error, Equatable { case corrupt }

    var data: Data {
        var data = Data("MQSK".utf8)
        func put(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        put(1)
        put(UInt32(count))
        for joint in joints {
            for slot in 0 ..< 4 {
                withUnsafeBytes(of: joint[slot].littleEndian) { data.append(contentsOf: $0) }
            }
        }
        for weight in weights {
            for slot in 0 ..< 4 {
                put(weight[slot].bitPattern)
            }
        }
        return data
    }

    init(data: Data) throws(FileError) {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, bytes[0 ..< 4] == [0x4D, 0x51, 0x53, 0x4B] else { throw .corrupt }
        func word(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        let count = Int(word(8))
        guard word(4) == 1, bytes.count == 12 + count * 24 else { throw .corrupt }
        var joints = [SIMD4<UInt16>](repeating: .zero, count: count)
        var offset = 12
        for index in 0 ..< count {
            for slot in 0 ..< 4 {
                joints[index][slot] = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
                offset += 2
            }
        }
        var weights = [SIMD4<Float>](repeating: .zero, count: count)
        for index in 0 ..< count {
            for slot in 0 ..< 4 {
                weights[index][slot] = Float(bitPattern: word(offset))
                offset += 4
            }
        }
        self.init(joints: joints, weights: weights)
    }
}

/// Where rig files live in a project (`assets/rigs/`).
public enum RigFiles {
    public static let folder = "rigs"

    public static func skinName(for data: Data) -> String {
        "\(folder)/\(BrushKey.hex(BrushKey.fnv(data))).skin"
    }
}

public extension PropertyKey {
    /// A drawn or imported skeleton's joint turn, relative to its parent joint (`bone.<joint name>`, a quaternion).
    static func boneTurn(_ joint: String) -> PropertyKey { PropertyKey("bone.\(joint)") }

    /// The joint a `bone.` key turns, if it is one.
    var boneJoint: String? {
        rawValue.hasPrefix("bone.") ? String(rawValue.dropFirst(5)) : nil
    }
}

/// Turning a humanoid's arms out to a T-pose, so clips made for T-poses retarget onto a skeleton made in any pose.
public enum TPose {
    /// The same skeleton with each upper arm turned (in model space) to point straight out sideways; everything below
    /// follows. Rest rotations change, positions don't.
    public static func straightenArms(_ skeleton: Skeleton) -> Skeleton {
        var joints = skeleton.joints
        var model = skeleton.modelRest
        for side in ["left", "right"] {
            guard let arm = skeleton.index(of: "\(side)UpperArm"), let child = skeleton.children(of: arm).first else { continue }
            let direction = model[arm].rotation.act(joints[child].rest.position).normalized
            guard direction.length > 0.5 else { continue }
            let correction = Quat.between(direction, Vec3(side == "left" ? 1 : -1, 0, 0))
            let parentRotation = joints[arm].parent.map { model[$0].rotation } ?? .identity
            let corrected = (correction * model[arm].rotation).normalized
            joints[arm].rest.rotation = (parentRotation.inverse * corrected).normalized
            model = Skeleton(joints: joints).modelRest
        }
        return Skeleton(joints: joints)
    }
}
