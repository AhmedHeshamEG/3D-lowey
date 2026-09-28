import Foundation

/// Skeleton standards. Any clip made for a standard plays on any character of that standard.
public enum SkeletonStandard: String, Codable, Sendable, CaseIterable {
    case humanoid, quadruped, bird, custom

    public init(rig: RigType) {
        switch rig {
        case .humanoid: self = .humanoid
        case .quadruped: self = .quadruped
        case .bird: self = .bird
        default: self = .custom
        }
    }

    /// Standard bone names, parents first.
    public var bones: [String] {
        switch self {
        case .humanoid:
            ["hips", "spine", "chest", "neck", "head",
             "leftShoulder", "leftUpperArm", "leftLowerArm", "leftHand",
             "rightShoulder", "rightUpperArm", "rightLowerArm", "rightHand",
             "leftUpperLeg", "leftLowerLeg", "leftFoot", "leftToes",
             "rightUpperLeg", "rightLowerLeg", "rightFoot", "rightToes"]
        case .quadruped:
            ["hips", "spine", "chest", "neck", "head", "tail",
             "frontLeftUpper", "frontLeftLower", "frontLeftFoot",
             "frontRightUpper", "frontRightLower", "frontRightFoot",
             "backLeftUpper", "backLeftLower", "backLeftFoot",
             "backRightUpper", "backRightLower", "backRightFoot"]
        case .bird:
            ["hips", "spine", "neck", "head", "tail",
             "leftWing", "leftWingTip", "rightWing", "rightWingTip",
             "leftLeg", "leftFoot", "rightLeg", "rightFoot"]
        case .custom:
            []
        }
    }

    /// Limb chains: (upper, lower, end) — used for IK and foot-speed estimation.
    public var legs: [(String, String, String)] {
        switch self {
        case .humanoid: [("leftUpperLeg", "leftLowerLeg", "leftFoot"), ("rightUpperLeg", "rightLowerLeg", "rightFoot")]
        case .quadruped: [("frontLeftUpper", "frontLeftLower", "frontLeftFoot"), ("frontRightUpper", "frontRightLower", "frontRightFoot"),
                          ("backLeftUpper", "backLeftLower", "backLeftFoot"), ("backRightUpper", "backRightLower", "backRightFoot")]
        case .bird: [("leftLeg", "leftFoot", "leftFoot"), ("rightLeg", "rightFoot", "rightFoot")]
        case .custom: []
        }
    }

    public func arm(left: Bool) -> (String, String, String)? {
        guard self == .humanoid else { return nil }
        return left ? ("leftUpperArm", "leftLowerArm", "leftHand") : ("rightUpperArm", "rightLowerArm", "rightHand")
    }
}

/// Everything the animator needs about a rigged library model.
public struct RigAsset: Hashable, Sendable {
    public var skeleton: Skeleton
    public var clips: [String: MotionClip]
    public var standard: SkeletonStandard
    /// Standard bone → joint name.
    public var boneMap: [String: String]

    public init(skeleton: Skeleton, clips: [MotionClip], standard: SkeletonStandard? = nil, boneMap: [String: String]? = nil) {
        self.skeleton = skeleton
        var byName: [String: MotionClip] = [:]
        for clip in clips {
            byName[clip.name] = clip
        }
        self.clips = byName
        let detected = standard ?? SkeletonStandard(rig: RigClassifier.classify(jointNames: skeleton.names))
        self.standard = detected
        self.boneMap = boneMap ?? BoneMapper.map(skeleton, to: detected)
    }

    public var clipNames: [String] { clips.keys.sorted() }

    /// Joint index for a standard bone.
    public func joint(_ bone: String) -> Int? {
        boneMap[bone].flatMap { skeleton.index(of: $0) }
    }

    /// Ground speed the clip was made for (m/s at speed 1): root motion if the hips travel,
    /// otherwise estimated from how far the feet sweep during a cycle. `nil` for in-place clips
    /// without legs (the tool then plays at speed 1).
    public func strideSpeed(of clip: MotionClip) -> Double? {
        guard clip.duration > 0 else { return nil }
        if let hips = joint("hips") {
            let start = clip.pose(at: 0, skeleton: skeleton)[hips].position
            let end = clip.pose(at: clip.duration, skeleton: skeleton)[hips].position
            let travel = Vec3(end.x - start.x, 0, end.z - start.z).length
            if travel > 0.05 { return travel / clip.duration }
        }
        var best = 0.0
        for (_, lowerBone, footBone) in standard.legs {
            // Two-bone legs (no separate foot) use the lower leg's tip.
            guard let foot = joint(footBone) ?? joint(lowerBone) else { continue }
            var lo = Double.infinity
            var hi = -Double.infinity
            let samples = 24
            for index in 0 ... samples {
                let t = clip.duration * Double(index) / Double(samples)
                let z = skeleton.modelSpace(clip.pose(at: t, skeleton: skeleton))[foot].position.z
                lo = min(lo, z)
                hi = max(hi, z)
            }
            best = max(best, hi - lo)
        }
        return best > 0.02 ? 2 * best / clip.duration : nil
    }
}

/// Maps joint names from common rigs (Mixamo, Quaternius-style, generic, Blender) to a standard.
public enum BoneMapper {
    /// Lowercase, strip rig prefixes, unify separators.
    static func normalize(_ name: String) -> String {
        var n = name.lowercased()
        for prefix in ["mixamorig:", "mixamorig_", "mixamorig", "armature|", "armature/", "def-", "def_", "bip01 ", "bip01_", "j_bip_c_", "j_bip_"]
            where n.hasPrefix(prefix) {
            n.removeFirst(prefix.count)
        }
        if let slash = n.lastIndex(of: "/") { n = String(n[n.index(after: slash)...]) }
        return n
    }

    /// -1 left, 1 right, 0 centre.
    static func side(_ normalized: String) -> Int {
        let n = normalized
        if n.hasPrefix("left") || n.contains("left") || n.hasSuffix(".l") || n.hasSuffix("_l") || n.hasSuffix(" l")
            || n.hasPrefix("l_") || n.hasPrefix("l.") || n.contains("_l_") || n.hasSuffix("-l") { return -1 }
        if n.hasPrefix("right") || n.contains("right") || n.hasSuffix(".r") || n.hasSuffix("_r") || n.hasSuffix(" r")
            || n.hasPrefix("r_") || n.hasPrefix("r.") || n.contains("_r_") || n.hasSuffix("-r") { return 1 }
        return 0
    }

    /// Auto-maps a skeleton to a standard. Limbs are found by their root bone, then followed down the chain.
    public static func map(_ skeleton: Skeleton, to standard: SkeletonStandard) -> [String: String] {
        let names = skeleton.joints.map { normalize($0.name) }
        var result: [String: String] = [:]
        var used = Set<Int>()

        func find(_ keywords: [String], side wanted: Int? = nil, excluding: [String] = [], from indices: [Int]? = nil) -> Int? {
            for index in indices ?? Array(names.indices) where !used.contains(index) {
                let n = names[index]
                guard keywords.contains(where: { n.contains($0) }), !excluding.contains(where: { n.contains($0) }) else { continue }
                if let wanted, side(n) != wanted { continue }
                return index
            }
            return nil
        }

        func assign(_ bone: String, _ index: Int?) {
            guard let index else { return }
            result[bone] = skeleton.joints[index].name
            used.insert(index)
        }

        /// Follows the first child chain below a limb root.
        func chain(from root: Int, length: Int) -> [Int] {
            var chain = [root]
            var current = root
            while chain.count < length {
                let kids = skeleton.children(of: current).filter { !used.contains($0) }
                guard let next = kids.first else { break }
                chain.append(next)
                current = next
            }
            return chain
        }

        switch standard {
        case .humanoid:
            assign("hips", find(["hips", "pelvis", "hip"], side: 0) ?? find(["root"], side: 0))
            assign("spine", find(["spine", "abdomen"], side: 0))
            assign("chest", find(["chest", "spine2", "spine1", "torso", "upperchest"], side: 0))
            assign("neck", find(["neck"], side: 0))
            assign("head", find(["head"], side: 0, excluding: ["end", "top", "nub"]))
            for (sideName, sideValue) in [("left", -1), ("right", 1)] {
                assign("\(sideName)Shoulder", find(["shoulder", "clavicle"], side: sideValue))
                if let upper = find(["upperarm", "arm"], side: sideValue, excluding: ["fore", "lower"]) {
                    let limb = chain(from: upper, length: 3)
                    assign("\(sideName)UpperArm", limb[0])
                    if limb.count > 1 { assign("\(sideName)LowerArm", limb[1]) }
                    if limb.count > 2 { assign("\(sideName)Hand", limb[2]) }
                }
                if let upper = find(["upleg", "upperleg", "thigh"], side: sideValue) {
                    let limb = chain(from: upper, length: 4)
                    assign("\(sideName)UpperLeg", limb[0])
                    if limb.count > 1 { assign("\(sideName)LowerLeg", limb[1]) }
                    if limb.count > 2 { assign("\(sideName)Foot", limb[2]) }
                    if limb.count > 3 { assign("\(sideName)Toes", limb[3]) }
                }
            }
        case .quadruped:
            assign("hips", find(["hips", "pelvis", "hip"], side: 0) ?? find(["root", "body"], side: 0))
            assign("spine", find(["spine"], side: 0))
            assign("chest", find(["chest", "spine2", "torso"], side: 0))
            assign("neck", find(["neck"], side: 0))
            assign("head", find(["head"], side: 0, excluding: ["end", "top", "nub"]))
            assign("tail", find(["tail"], side: 0))
            for (sideName, sideValue) in [("Left", -1), ("Right", 1)] {
                let front = find(["front", "fore", "arm", "shoulder"], side: sideValue, excluding: ["tail"])
                if let front {
                    let limb = chain(from: front, length: 3)
                    assign("front\(sideName)Upper", limb[0])
                    if limb.count > 1 { assign("front\(sideName)Lower", limb[1]) }
                    if limb.count > 2 { assign("front\(sideName)Foot", limb[2]) }
                }
                let back = find(["back", "hind", "rear", "thigh", "leg"], side: sideValue, excluding: ["tail"])
                if let back {
                    let limb = chain(from: back, length: 3)
                    assign("back\(sideName)Upper", limb[0])
                    if limb.count > 1 { assign("back\(sideName)Lower", limb[1]) }
                    if limb.count > 2 { assign("back\(sideName)Foot", limb[2]) }
                }
            }
        case .bird:
            assign("hips", find(["hips", "pelvis", "root", "body"], side: 0))
            assign("spine", find(["spine", "chest"], side: 0))
            assign("neck", find(["neck"], side: 0))
            assign("head", find(["head"], side: 0, excluding: ["end", "top"]))
            assign("tail", find(["tail"], side: 0))
            for (sideName, sideValue) in [("left", -1), ("right", 1)] {
                if let wing = find(["wing"], side: sideValue) {
                    let limb = chain(from: wing, length: 2)
                    assign("\(sideName)Wing", limb[0])
                    if limb.count > 1 { assign("\(sideName)WingTip", limb.last) }
                }
                if let leg = find(["leg", "thigh"], side: sideValue) {
                    let limb = chain(from: leg, length: 2)
                    assign("\(sideName)Leg", limb[0])
                    if limb.count > 1 { assign("\(sideName)Foot", limb.last) }
                }
            }
        case .custom:
            break
        }
        return result
    }
}

/// Plays a clip made for one skeleton on another skeleton of the same standard.
///
/// Works in model space: each mapped bone's rotation change from its rest pose is transferred
/// as a model-space delta, so rigs whose bones point along different local axes (Mixamo vs
/// Quaternius) still match as long as both rest in a similar pose (T/A pose facing +Z).
/// The hips' travel is scaled by the ratio of hip heights.
public enum Retargeter {
    public static func retarget(pose sourceLocal: [Transform], from source: RigAsset, to target: RigAsset) -> [Transform] {
        let sourceModel = source.skeleton.modelSpace(sourceLocal)
        let sourceRest = source.skeleton.modelRest
        let targetRest = target.skeleton.modelRest
        var targetLocal = target.skeleton.restPose
        // Model-space rotation deltas per target joint (identity where unmapped).
        var targetModelRotation = targetRest.map(\.rotation)
        var mapped: [Int: Int] = [:]
        for (bone, targetName) in target.boneMap {
            guard let t = target.skeleton.index(of: targetName), let s = source.joint(bone) else { continue }
            mapped[t] = s
        }
        for index in target.skeleton.joints.indices {
            let parent = target.skeleton.joints[index].parent
            let parentModel = parent.map { targetModelRotation[$0] } ?? .identity
            if let s = mapped[index] {
                let delta = (sourceModel[s].rotation * sourceRest[s].rotation.inverse).normalized
                targetModelRotation[index] = (delta * targetRest[index].rotation).normalized
            } else {
                // Unmapped: keep the rest local rotation, following the (possibly animated) parent.
                targetModelRotation[index] = (parentModel * target.skeleton.joints[index].rest.rotation).normalized
            }
            targetLocal[index].rotation = (parentModel.inverse * targetModelRotation[index]).normalized
        }
        // Hips travel.
        if let sHips = source.joint("hips"), let tHips = target.joint("hips") {
            let sourceHeight = max(source.skeleton.restHeight(of: sHips), 1e-3)
            let targetHeight = max(target.skeleton.restHeight(of: tHips), 1e-3)
            let ratio = targetHeight / sourceHeight
            let travel = (sourceModel[sHips].position - sourceRest[sHips].position) * ratio
            let desiredModel = targetRest[tHips].position + travel
            if let parent = target.skeleton.joints[tHips].parent {
                let parentModel = target.skeleton.modelSpace(targetLocal)[parent]
                targetLocal[tHips].position = parentModel.inverseApply(to: desiredModel)
            } else {
                targetLocal[tHips].position = desiredModel
            }
        }
        return targetLocal
    }
}

/// Analytic IK helpers working on local poses.
public enum IKSolver {
    /// Two-bone IK: bends `upper → lower → end` so `end` reaches `target` (model space).
    public static func twoBone(
        _ local: inout [Transform], skeleton: Skeleton, upper: Int, lower: Int, end: Int, target: Vec3
    ) {
        guard upper != lower, lower != end else { return }
        var model = skeleton.modelSpace(local)
        let a = model[upper].position
        let b = model[lower].position
        let c = model[end].position
        let l1 = b.distance(to: a)
        let l2 = c.distance(to: b)
        guard l1 > 1e-6, l2 > 1e-6 else { return }
        let toTarget = target - a
        let distance = min(max(toTarget.length, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
        let direction = toTarget.normalized
        guard direction.length > 0.5 else { return }
        // Bend direction: keep the current knee/elbow side.
        var bend = (b - a) - direction * (b - a).dot(direction)
        if bend.length < 1e-6 { bend = Vec3(0, 0, 1) - direction * direction.z }
        bend = bend.normalized
        let cosA = min(max((l1 * l1 + distance * distance - l2 * l2) / (2 * l1 * distance), -1), 1)
        let sinA = (1 - cosA * cosA).squareRoot()
        let newB = a + direction * (l1 * cosA) + bend * (l1 * sinA)
        let newC = a + direction * distance

        // Upper bone: rotate so it points at newB.
        let upperDelta = Quat.rotation(from: b - a, to: newB - a)
        setModelRotation(&local, skeleton: skeleton, model: model, index: upper, rotation: (upperDelta * model[upper].rotation).normalized)
        model = skeleton.modelSpace(local)
        let lowerDelta = Quat.rotation(from: model[end].position - model[lower].position, to: newC - model[lower].position)
        setModelRotation(&local, skeleton: skeleton, model: model, index: lower, rotation: (lowerDelta * model[lower].rotation).normalized)
    }

    /// Turns a joint (head) so its forward (+Z in model space at rest) looks toward `target`, limited to `maxDegrees`.
    public static func lookAt(_ local: inout [Transform], skeleton: Skeleton, joint: Int, target: Vec3, maxDegrees: Double = 70) {
        let model = skeleton.modelSpace(local)
        let rest = skeleton.modelRest
        let currentForward = (model[joint].rotation * rest[joint].rotation.inverse).act(.unitZ)
        let desired = (target - model[joint].position).normalized
        guard desired.length > 0.5 else { return }
        var delta = Quat.rotation(from: currentForward, to: desired)
        let angle = 2 * acos(min(abs(delta.w), 1))
        let limit = maxDegrees * .pi / 180
        if angle > limit { delta = Quat.identity.slerp(to: delta, limit / angle) }
        setModelRotation(&local, skeleton: skeleton, model: model, index: joint, rotation: (delta * model[joint].rotation).normalized)
    }

    private static func setModelRotation(_ local: inout [Transform], skeleton: Skeleton, model: [Transform], index: Int, rotation: Quat) {
        let parentRotation = skeleton.joints[index].parent.map { model[$0].rotation } ?? .identity
        local[index].rotation = (parentRotation.inverse * rotation).normalized
    }
}

/// Computes a character's pose from its clip track (clips, crossfades, retargeting, IK).
public enum ClipMixer {
    /// `world` is the character's world transform (for IK targets given in world space).
    public static func pose(
        track: ClipTrack, character: RigAsset, rigs: [AssetID: RigAsset], at time: Double, world: Transform,
        targetPosition: (ObjectID) -> Vec3?
    ) -> [Transform]? {
        let weights = track.weights(at: time)
        guard !weights.isEmpty else { return nil }
        var result: [Transform]?
        var accumulated = 0.0
        for (segment, weight) in weights where weight > 0 {
            guard let source = rigs[segment.clip.asset], let clip = source.clips[segment.clip.name] else { continue }
            let fadingOut = weights.count > 1 && segment.id == weights[0].segment.id
            let clipTime = segment.clipTime(at: time, clipDuration: clip.duration, extendPastEnd: fadingOut)
            var pose = clip.pose(at: clipTime, skeleton: source.skeleton)
            if source.skeleton != character.skeleton {
                pose = Retargeter.retarget(pose: pose, from: source, to: character)
            }
            if let current = result {
                accumulated += weight
                result = PoseMath.blend(current, pose, weight / max(accumulated, 1e-9))
            } else {
                result = pose
                accumulated = weight
            }
        }
        guard var pose = result else { return nil }
        applyIK(track.ik, to: &pose, character: character, world: world, targetPosition: targetPosition)
        return pose
    }

    static func applyIK(_ ik: IKSettings, to pose: inout [Transform], character: RigAsset, world: Transform, targetPosition: (ObjectID) -> Vec3?) {
        guard ik.isActive else { return }
        let skeleton = character.skeleton
        if ik.inPlace, let hips = character.joint("hips") {
            // Keep the hips' height (the bounce of the walk) but not their forward travel.
            let rest = skeleton.joints[hips].rest.position
            pose[hips].position = Vec3(rest.x, pose[hips].position.y, rest.z)
        }
        if ik.feetOnGround {
            for (upperBone, lowerBone, footBone) in character.standard.legs {
                guard let upper = character.joint(upperBone), let lower = character.joint(lowerBone),
                      let foot = character.joint(footBone), upper != lower, lower != foot else { continue }
                let model = skeleton.modelSpace(pose)
                let footWorld = world.apply(to: model[foot].position)
                let restFootHeight = skeleton.modelRest[foot].position.y - (skeleton.modelRest.map(\.position.y).min() ?? 0)
                let floor = ik.groundHeight + restFootHeight * world.scale.y
                guard footWorld.y < floor else { continue }
                let targetWorld = Vec3(footWorld.x, floor, footWorld.z)
                IKSolver.twoBone(&pose, skeleton: skeleton, upper: upper, lower: lower, end: foot, target: world.inverseApply(to: targetWorld))
            }
        }
        if let reach = ik.reach, let targetWorld = targetPosition(reach), let arm = character.standard.arm(left: ik.reachWithLeft),
           let upper = character.joint(arm.0), let lower = character.joint(arm.1), let hand = character.joint(arm.2) {
            IKSolver.twoBone(&pose, skeleton: skeleton, upper: upper, lower: lower, end: hand, target: world.inverseApply(to: targetWorld))
        }
        if let look = ik.lookAt, let targetWorld = targetPosition(look), let head = character.joint("head") {
            IKSolver.lookAt(&pose, skeleton: skeleton, joint: head, target: world.inverseApply(to: targetWorld))
        }
    }
}
