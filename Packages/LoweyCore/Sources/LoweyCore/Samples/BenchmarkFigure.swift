import Foundation

/// The Night Market's walkers: a blocky skinned figure (one box per bone, rigid weights) with a looping walk,
/// generated in code so the benchmark needs nothing from the library and every run skins the same vertices.
public enum BenchmarkFigure {
    /// The library entry the benchmark adds to its catalog (the model itself is seeded, never read from a file).
    public static let asset = LibraryAsset(id: NightMarket.walkerAsset, name: "Benchmark walker", tags: ["benchmark"], format: .glb,
                                           file: "benchmark-walker.glb", rig: .humanoid, clips: [NightMarket.walkClip])
    /// Seconds per stride (two steps).
    public static let cycle = 1.0

    private struct Bone {
        var name: String
        var parent: Int?
        /// Rest position relative to the parent joint.
        var offset: Vec3
        /// The bone's box: centre relative to the joint, and size.
        var center: Vec3
        var size: Vec3
    }

    private static let bones: [Bone] = [
        Bone(name: "Hips", parent: nil, offset: Vec3(0, 0.95, 0), center: Vec3(0, 0, 0), size: Vec3(0.34, 0.16, 0.2)),
        Bone(name: "Spine", parent: 0, offset: Vec3(0, 0.08, 0), center: Vec3(0, 0.22, 0), size: Vec3(0.36, 0.44, 0.22)),
        Bone(name: "Head", parent: 1, offset: Vec3(0, 0.48, 0), center: Vec3(0, 0.13, 0.01), size: Vec3(0.24, 0.26, 0.24)),
        Bone(name: "LeftUpLeg", parent: 0, offset: Vec3(0.1, -0.06, 0), center: Vec3(0, -0.21, 0), size: Vec3(0.13, 0.42, 0.14)),
        Bone(name: "LeftLeg", parent: 3, offset: Vec3(0, -0.42, 0), center: Vec3(0, -0.235, 0.02), size: Vec3(0.11, 0.47, 0.16)),
        Bone(name: "RightUpLeg", parent: 0, offset: Vec3(-0.1, -0.06, 0), center: Vec3(0, -0.21, 0), size: Vec3(0.13, 0.42, 0.14)),
        Bone(name: "RightLeg", parent: 5, offset: Vec3(0, -0.42, 0), center: Vec3(0, -0.235, 0.02), size: Vec3(0.11, 0.47, 0.16)),
        Bone(name: "LeftArm", parent: 1, offset: Vec3(0.23, 0.4, 0), center: Vec3(0, -0.14, 0), size: Vec3(0.1, 0.3, 0.1)),
        Bone(name: "LeftForeArm", parent: 7, offset: Vec3(0, -0.28, 0), center: Vec3(0, -0.13, 0), size: Vec3(0.09, 0.28, 0.09)),
        Bone(name: "RightArm", parent: 1, offset: Vec3(-0.23, 0.4, 0), center: Vec3(0, -0.14, 0), size: Vec3(0.1, 0.3, 0.1)),
        Bone(name: "RightForeArm", parent: 9, offset: Vec3(0, -0.28, 0), center: Vec3(0, -0.13, 0), size: Vec3(0.09, 0.28, 0.09))
    ]

    public static let skeleton = Skeleton(joints: bones.map { Joint(name: $0.name, parent: $0.parent, rest: Transform(position: $0.offset)) })

    /// The figure's mesh and skin: one part, every vertex bound to its bone with full weight.
    public static func model() -> ImportedModel {
        let rest = skeleton.modelRest
        var mesh = MeshData()
        var joints: [SIMD4<UInt16>] = []
        var weights: [SIMD4<Float>] = []
        for (index, bone) in bones.enumerated() {
            let box = PrimitiveMesh.box(size: SIMD3<Float>(Float(bone.size.x), Float(bone.size.y), Float(bone.size.z)))
            let base = rest[index].position + bone.center - Vec3(0, bone.size.y / 2, 0)
            let placed = box.transformed(Transform(position: base))
            mesh.append(placed)
            joints += Array(repeating: SIMD4<UInt16>(UInt16(index), 0, 0, 0), count: placed.positions.count)
            weights += Array(repeating: SIMD4<Float>(1, 0, 0, 0), count: placed.positions.count)
        }
        // Rest rotations are identity, so each inverse bind matrix only undoes the joint's rest position.
        let inverseBind = rest.map { joint -> [Float] in
            let p = joint.position
            return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, Float(-p.x), Float(-p.y), Float(-p.z), 1]
        }
        let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        let material = ImportedMaterial(name: "Walker", baseColor: RGBA(0.86, 0.52, 0.34))
        return ImportedModel(parts: [ImportedPart(name: "Walker", mesh: mesh, material: 0, joints: joints, weights: weights)],
                             materials: [material], skin: ImportedSkin(joints: skeleton.names, inverseBindMatrices: inverseBind, armature: identity))
    }

    /// The rig with its one clip, "Walk": legs swing ±30°, knees bend on the passing leg, arms swing against the
    /// legs, and the hips bob twice per stride.
    public static func rig() -> RigAsset {
        RigAsset(skeleton: skeleton, clips: [walk()])
    }

    static func walk() -> MotionClip {
        let samples = 16
        let times = (0 ... samples).map { Double($0) / Double(samples) * cycle }
        func swing(_ amplitude: Double, phase: Double) -> [Quat] {
            times.map { Quat(angle: amplitude * sin(2 * .pi * ($0 / cycle + phase)), axis: .unitX) }
        }
        func knee(phase: Double) -> [Quat] {
            times.map { Quat(angle: 0.9 * max(0, sin(2 * .pi * ($0 / cycle + phase))), axis: .unitX) }
        }
        let hips = times.map { Vec3(0, 0.95 + 0.025 * cos(4 * .pi * $0 / cycle), 0) }
        let channels = [
            JointChannel(joint: "Hips", path: .translation, times: times, vectors: hips),
            JointChannel(joint: "LeftUpLeg", path: .rotation, times: times, rotations: swing(0.52, phase: 0)),
            JointChannel(joint: "RightUpLeg", path: .rotation, times: times, rotations: swing(0.52, phase: 0.5)),
            JointChannel(joint: "LeftLeg", path: .rotation, times: times, rotations: knee(phase: 0.75)),
            JointChannel(joint: "RightLeg", path: .rotation, times: times, rotations: knee(phase: 0.25)),
            JointChannel(joint: "LeftArm", path: .rotation, times: times, rotations: swing(0.4, phase: 0.5)),
            JointChannel(joint: "RightArm", path: .rotation, times: times, rotations: swing(0.4, phase: 0)),
            JointChannel(joint: "LeftForeArm", path: .rotation, times: times, rotations: swing(-0.25, phase: 0.25)),
            JointChannel(joint: "RightForeArm", path: .rotation, times: times, rotations: swing(-0.25, phase: 0.75))
        ]
        return MotionClip(name: NightMarket.walkClip, duration: cycle, channels: channels)
    }
}
