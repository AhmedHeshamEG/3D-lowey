import Foundation

/// Humanoid clips that ship with the app, so a built character moves the moment it exists: idle, walk, run,
/// talk, wave, point, type, nod, shrug, celebrate. They're ordinary `MotionClip`s on a T-pose humanoid skeleton,
/// so they retarget onto any humanoid (built puppets and imported rigs alike), and imported clips work the same way.
public enum BuiltinClips {
    public static let assetID: AssetID = "builtin.humanoid"

    public static let names = ["Idle", "Walk", "Run", "Talk", "Wave", "Point", "Type", "Nod", "Shrug", "Celebrate"]

    /// The reference rig (the default character's skeleton) with every clip.
    public static let rig: RigAsset = {
        var ids = IDFactory.sequential("ref")
        let fragment = CharacterBuilder.build(CharacterRecipe(), ids: &ids)
        var scene = Scene(id: "ref", name: "Reference")
        for object in fragment.objects {
            scene.objects[object.id] = object
        }
        scene.roots = fragment.roots
        guard let root = fragment.roots.first, let puppet = PuppetRig.build(root, in: scene) else {
            return RigAsset(skeleton: Skeleton(joints: []), clips: [], standard: .humanoid, boneMap: [:])
        }
        let skeleton = puppet.rig.skeleton
        let clips = names.map { makeClip($0, skeleton: skeleton) }
        return RigAsset(skeleton: skeleton, clips: clips, standard: .humanoid, boneMap: puppet.rig.boneMap)
    }()

    /// Rigs every evaluation knows about (built-in clips can be played on any humanoid).
    public static var rigs: [AssetID: RigAsset] { [assetID: rig] }

    // MARK: Authoring

    /// A pose: per bone, a rotation in the (rest-aligned) world axes, applied at that joint and carried by its children;
    /// plus an optional hips offset.
    struct Pose {
        var rotations: [String: Quat] = [:]
        var hips = Vec3.zero
    }

    static func rx(_ degrees: Double) -> Quat { Quat(angle: degrees * .pi / 180, axis: .unitX) }
    static func ry(_ degrees: Double) -> Quat { Quat(angle: degrees * .pi / 180, axis: .unitY) }
    static func rz(_ degrees: Double) -> Quat { Quat(angle: degrees * .pi / 180, axis: .unitZ) }

    /// Arms relaxed at the sides (from the T-pose).
    static func armsDown(_ pose: inout Pose, left: Quat = .identity, right: Quat = .identity) {
        pose.rotations["leftUpperArm"] = (left * rz(-78)).normalized
        pose.rotations["rightUpperArm"] = (right * rz(78)).normalized
    }

    static func makeClip(_ name: String, skeleton: Skeleton) -> MotionClip {
        let (duration, function) = definition(name)
        let fps = 30.0
        let frames = max(Int((duration * fps).rounded()), 1)
        let modelRest = skeleton.modelRest
        var rotations: [String: [Quat]] = [:]
        var hips: [Vec3] = []
        var times: [Double] = []
        for frame in 0 ... frames {
            let t = Double(frame) / fps
            times.append(t)
            let pose = function(t / duration)
            for (index, joint) in skeleton.joints.enumerated() {
                let delta = pose.rotations[joint.name] ?? .identity
                let parentRest = joint.parent.map { modelRest[$0].rotation } ?? .identity
                // local = restModel(parent)⁻¹ · delta · restModel(joint)
                rotations[joint.name, default: []].append((parentRest.inverse * delta * modelRest[index].rotation).normalized)
            }
            if let hipsIndex = skeleton.index(of: "hips") { hips.append(skeleton.joints[hipsIndex].rest.position + pose.hips) }
        }
        var channels = skeleton.joints.map { joint in
            JointChannel(joint: joint.name, path: .rotation, times: times, rotations: rotations[joint.name] ?? [])
        }
        if !hips.isEmpty { channels.append(JointChannel(joint: "hips", path: .translation, times: times, vectors: hips)) }
        return MotionClip(name: name, duration: duration, channels: channels)
    }

    static let tau = 2 * Double.pi

    static func definition(_ name: String) -> (Double, (Double) -> Pose) {
        switch name {
        case "Walk": (1.05, { walk($0, run: false) })
        case "Run": (0.66, { walk($0, run: true) })
        case "Talk": (3.2, talk)
        case "Wave": (1.6, wave)
        case "Point": (1.5, point)
        case "Type": (0.9, typing)
        case "Nod": (1, nod)
        case "Shrug": (1.3, shrug)
        case "Celebrate": (1.1, celebrate)
        default: (4, idle) // Idle
        }
    }

    static func walk(_ phase: Double, run: Bool) -> Pose {
        var pose = Pose()
        let s = sin(phase * tau)
        let c = cos(phase * tau)
        let legSwing = run ? 38.0 : 26.0
        pose.rotations["leftUpperLeg"] = rx(-s * legSwing)
        pose.rotations["rightUpperLeg"] = rx(s * legSwing)
        pose.rotations["leftLowerLeg"] = rx(max(0, c) * (run ? 70 : 40))
        pose.rotations["rightLowerLeg"] = rx(max(0, -c) * (run ? 70 : 40))
        pose.rotations["leftFoot"] = rx(max(0, -s) * 12)
        pose.rotations["rightFoot"] = rx(max(0, s) * 12)
        armsDown(&pose, left: rx(s * (run ? 40 : 22)), right: rx(-s * (run ? 40 : 22)))
        pose.rotations["leftLowerArm"] = ry(run ? -70 : -18)
        pose.rotations["rightLowerArm"] = ry(run ? 70 : 18)
        pose.rotations["spine"] = rx(run ? 10 : 3) * ry(s * 5)
        pose.rotations["chest"] = ry(-s * 6)
        pose.hips = Vec3(0, abs(c) * (run ? 0.05 : 0.025) - (run ? 0.05 : 0.015), 0)
        return pose
    }

    static func talk(_ phase: Double) -> Pose {
        var pose = Pose()
        let a = sin(phase * tau)
        let b = sin(phase * tau * 2 + 1)
        armsDown(&pose, left: rx(-12 - 10 * a), right: rx(-14 - 12 * b))
        pose.rotations["leftLowerArm"] = ry(-55 - 18 * b) * rx(-10 * a)
        pose.rotations["rightLowerArm"] = ry(50 + 20 * a)
        pose.rotations["leftHand"] = rz(10 * b)
        pose.rotations["rightHand"] = rz(-12 * a)
        pose.rotations["head"] = rx(4 * sin(phase * tau * 3)) * ry(6 * a)
        pose.rotations["chest"] = ry(4 * b)
        return pose
    }

    static func wave(_ phase: Double) -> Pose {
        var pose = Pose()
        armsDown(&pose)
        pose.rotations["rightUpperArm"] = rz(-55)
        pose.rotations["rightLowerArm"] = rz(-50 + 22 * sin(phase * tau * 2))
        pose.rotations["head"] = rz(-4) * ry(-5)
        return pose
    }

    static func point(_: Double) -> Pose {
        var pose = Pose()
        armsDown(&pose)
        pose.rotations["rightUpperArm"] = ry(78) * rx(8)
        pose.rotations["rightLowerArm"] = ry(4)
        pose.rotations["head"] = ry(-8)
        pose.rotations["chest"] = ry(-8)
        return pose
    }

    static func typing(_ phase: Double) -> Pose {
        var pose = Pose()
        armsDown(&pose, left: rx(-38), right: rx(-38))
        pose.rotations["leftLowerArm"] = ry(-72) * rx(4 * sin(phase * tau * 3))
        pose.rotations["rightLowerArm"] = ry(72) * rx(4 * sin(phase * tau * 3 + 2))
        pose.rotations["leftHand"] = rx(8 * max(0, sin(phase * tau * 4)))
        pose.rotations["rightHand"] = rx(8 * max(0, sin(phase * tau * 4 + 1.6)))
        pose.rotations["head"] = rx(12)
        pose.rotations["spine"] = rx(6)
        return pose
    }

    static func nod(_ phase: Double) -> Pose {
        var pose = Pose()
        armsDown(&pose)
        pose.rotations["head"] = rx(14 * sin(phase * tau * 2) * (1 - phase))
        return pose
    }

    static func shrug(_ phase: Double) -> Pose {
        var pose = Pose()
        let up = sin(min(phase * 2, 1) * .pi / 2) * (phase > 0.75 ? max(0, (1 - phase) * 4) : 1)
        armsDown(&pose, left: rz(18 * up) * rx(-20 * up), right: rz(-18 * up) * rx(-20 * up))
        pose.rotations["leftLowerArm"] = ry(-70 * up)
        pose.rotations["rightLowerArm"] = ry(70 * up)
        pose.rotations["leftShoulder"] = rz(10 * up)
        pose.rotations["rightShoulder"] = rz(-10 * up)
        pose.rotations["head"] = rz(8 * up)
        return pose
    }

    static func celebrate(_ phase: Double) -> Pose {
        var pose = Pose()
        let s = sin(phase * tau)
        pose.rotations["leftUpperArm"] = rz(62 + 12 * s)
        pose.rotations["rightUpperArm"] = rz(-62 - 12 * s)
        pose.rotations["leftLowerArm"] = rz(20)
        pose.rotations["rightLowerArm"] = rz(-20)
        pose.rotations["head"] = rx(-10)
        pose.rotations["leftUpperLeg"] = rx(-20 * max(0, s))
        pose.rotations["rightUpperLeg"] = rx(-20 * max(0, s))
        pose.rotations["leftLowerLeg"] = rx(35 * max(0, s))
        pose.rotations["rightLowerLeg"] = rx(35 * max(0, s))
        pose.hips = Vec3(0, 0.12 * max(0, s), 0)
        return pose
    }

    static func idle(_ phase: Double) -> Pose {
        var pose = Pose()
        let breathe = sin(phase * tau)
        armsDown(&pose, left: rz(-3 * breathe), right: rz(3 * breathe))
        pose.rotations["leftLowerArm"] = ry(-10)
        pose.rotations["rightLowerArm"] = ry(10)
        pose.rotations["chest"] = rx(-1.5 * breathe)
        pose.rotations["head"] = ry(6 * sin(phase * tau + 1)) * rx(2 * breathe)
        pose.hips = Vec3(0, 0.004 * breathe, 0)
        return pose
    }
}
