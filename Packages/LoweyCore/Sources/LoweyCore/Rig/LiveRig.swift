import Foundation

public extension PropertyKey {
    /// On a character with a custom skeleton: the joint that turns with the head channels (humanoids use their head).
    static let liveHead: PropertyKey = "liveHead"
    /// On a part of a rigged character (its child): the joint it rides, so it moves when the bone does.
    static let attachBone: PropertyKey = "attachBone"
    /// 0…1 how deeply a character breathes on its own.
    static let breathe: PropertyKey = "breathe"
}

/// The face and hand channels on skeletons. Performed or keyed, the same channels a Blob and a built Puppet already
/// answer to now turn the head and move the hands of drawn rigs (3D and 2D), "Rig as a person" rigs and rigged models,
/// so one performance drives any of them.
public enum LiveRig {
    static let headKeys: [PropertyKey] = [.headYaw, .headPitch, .headRoll]

    static func apply(to state: inout Animator.Posed, rigs: [AssetID: RigAsset]) {
        for (id, object) in state.scene.objects {
            let head = headKeys.map { object[$0]?.floatValue ?? 0 }
            let hands = PropertyKey.handChannels.map { object[$0]?.floatValue ?? 0 }
            let turnsHead = head.contains { abs($0) > 1e-6 }
            let movesHands = hands.contains { abs($0) > 1e-6 }
            guard turnsHead || movesHands, let rig = CharacterRig.of(id, in: state.scene, rigs: rigs), rig.body != .blob else { continue }
            var local = rig.localPose(in: state.scene, pose: state.poses[id])
            var turned = Set<Int>()
            // A built Puppet's head is a part with a face role: `FaceRig` turns it.
            if turnsHead, rig.body == .bones {
                turnHead(of: object, rig: rig, yaw: head[0], pitch: head[1], roll: head[2], local: &local, turned: &turned)
            }
            if movesHands, rig.standard == .humanoid {
                reach(rig, left: (hands[0], hands[1]), right: (hands[2], hands[3]), local: &local, turned: &turned)
            }
            guard !turned.isEmpty else { continue }
            put(Dictionary(turned.map { ($0, local[$0].rotation) }, uniquingKeysWith: { first, _ in first }), local: local, on: rig, in: &state)
        }
    }

    /// Stores turned joints where the character keeps its pose: the animator's pose (skeletons of bones) or the joint
    /// objects (built Puppets).
    static func put(_ turns: [Int: Quat], local: [Transform], on rig: CharacterRig, in state: inout Animator.Posed) {
        switch rig.body {
        case .blob:
            return
        case .bones:
            state.poses[rig.character] = local
        case .joints:
            for change in rig.changes(turning: turns) {
                guard case let .quat(rotation)? = change.value else { continue }
                state.scene.objects[change.object]?.transform.rotation = rotation
                state.animated.insert(change.object)
            }
        }
        state.animated.insert(rig.character)
    }

    // MARK: Head

    /// The joint that carries the head: a humanoid's, else the one the character names.
    public static func headJoint(of object: SceneObject, rig: CharacterRig) -> Int? {
        if let name = object[.liveHead]?.stringValue, let index = rig.skeleton.index(of: name) { return index }
        return rig.standard == .humanoid ? rig.joint("head") : nil
    }

    static func turnHead(of object: SceneObject, rig: CharacterRig, yaw: Double, pitch: Double, roll: Double, local: inout [Transform],
                         turned: inout Set<Int>) {
        guard let head = headJoint(of: object, rig: rig) else { return }
        var parts: [(joint: Int, share: Double)] = [(head, 1)]
        // A neck takes a third of the turn, as necks do.
        if rig.standard == .humanoid, let neck = rig.joint("neck"), neck != head { parts = [(neck, 0.35), (head, 0.65)] }
        for part in parts {
            let turn: Quat = if case .drawing = object.kind {
                // A drawing lives on its plane: it tilts in it (a turn of the head leans it a little too).
                Quat(angle: (roll + yaw * 0.5) * part.share * .pi / 180, axis: planeNormal(of: rig.skeleton))
            } else {
                Quat(eulerDegrees: Vec3(-pitch, yaw, roll) * part.share)
            }
            let model = rig.skeleton.modelSpace(local)
            let parent = rig.skeleton.joints[part.joint].parent.map { model[$0].rotation } ?? .identity
            local[part.joint].rotation = (parent.inverse * turn * model[part.joint].rotation).normalized
            turned.insert(part.joint)
        }
    }

    /// The side a flat skeleton faces (towards +z when it can).
    static func planeNormal(of skeleton: Skeleton) -> Vec3 {
        let points = skeleton.modelRest.map(\.position)
        guard let first = points.first else { return .unitZ }
        var best = Vec3.zero
        for a in points.dropFirst() {
            for b in points.dropFirst() {
                let normal = (a - first).cross(b - first)
                if normal.length > best.length { best = normal }
            }
        }
        guard best.length > 1e-9 else { return .unitZ }
        let normal = best.normalized
        return normal.z < -1e-6 || (abs(normal.z) <= 1e-6 && normal.y < 0) ? normal * -1 : normal
    }

    // MARK: Hands

    /// A humanoid's hands brought where the hand channels say: out and up from the shoulder, the elbow following (IK).
    /// The channels use the picture's sides, so `left` is the arm on the model's −x side.
    static func reach(_ rig: CharacterRig, left: (out: Double, up: Double), right: (out: Double, up: Double), local: inout [Transform],
                      turned: inout Set<Int>) {
        let arms = ["left", "right"].compactMap { side -> [Int]? in
            let chain = ["\(side)UpperArm", "\(side)LowerArm", "\(side)Hand"].compactMap(rig.joint)
            return chain.count == 3 ? chain : nil
        }
        let rest = rig.skeleton.modelRest
        for chain in arms {
            let onLeft = rest[chain[0]].position.x < 0
            let hand = onLeft ? left : right
            let amount = min((abs(hand.out) + abs(hand.up)) * 6, 1)
            guard amount > 1e-6 else { continue }
            let model = rig.skeleton.modelSpace(local)
            let shoulder = model[chain[0]].position
            let length = model[chain[0]].position.distance(to: model[chain[1]].position) + model[chain[1]].position.distance(to: model[chain[2]].position)
            guard length > 1e-9 else { continue }
            let side: Double = onLeft ? -1 : 1
            var offset = Vec3(side * (0.15 + 0.75 * hand.out), -0.85 + 1.75 * hand.up, 0.2) * length
            let far = offset.length
            if far > 0.98 * length { offset *= 0.98 * length / far }
            if far < 0.2 * length, far > 1e-9 { offset *= 0.2 * length / far }
            let solved = ChainIK.solve(chain: chain, skeleton: rig.skeleton, local: local, target: shoulder + offset, pole: Vec3(0, 0, -1))
            for (joint, rotation) in solved {
                local[joint].rotation = local[joint].rotation.slerp(to: rotation, amount).normalized
                turned.insert(joint)
            }
        }
    }

    // MARK: Parts that ride a bone

    /// Children of a rigged object that name a joint (`attachBone`) move with it: an eye on a drawn head, a prop in a
    /// hand. Their own keys still place them; the bone carries the result.
    static func carryParts(in state: inout Animator.Posed, rigs: [AssetID: RigAsset]) {
        for (id, part) in state.scene.objects {
            guard let name = part[.attachBone]?.stringValue, let parentID = part.parent, let parent = state.scene.objects[parentID],
                  let skeleton = parent.rig?.skeleton ?? parent.kind.assetID.flatMap({ rigs[$0]?.skeleton }),
                  let joint = skeleton.index(of: name), let pose = state.poses[parentID], pose.count == skeleton.joints.count else { continue }
            let rest = skeleton.modelRest[joint]
            let now = skeleton.modelSpace(pose)[joint]
            // The rig's space is the object's, except for bevelled shapes (built at their size).
            let toObject = PaintSource.toObjectSpace(of: parent).map { Vec3(Double($0.x), Double($0.y), Double($0.z)) } ?? .one
            let inRig = Vec3(part.transform.position.x / toObject.x, part.transform.position.y / toObject.y, part.transform.position.z / toObject.z)
            let moved = now.apply(to: rest.inverseApply(to: inRig)).scaled(by: toObject)
            let turn = (now.rotation * rest.rotation.inverse).normalized
            guard !moved.isApproximately(part.transform.position, tolerance: 1e-12) || !turn.isApproximately(.identity, tolerance: 1e-12) else { continue }
            state.scene.objects[id]?.transform.position = moved
            state.scene.objects[id]?.transform.rotation = (turn * part.transform.rotation).normalized
            state.animated.insert(id)
        }
    }

    /// The joint whose bone lies closest to `point` (the rig's space, rest pose): where a new part attaches.
    public static func nearestJoint(to point: Vec3, of rig: ObjectRig) -> String? {
        let closest = rig.segments.min { $0.distance(to: point) < $1.distance(to: point) }
        if let closest { return rig.skeleton.joints[closest.joint].name }
        let rest = rig.restPositions
        return rest.indices.min { rest[$0].distance(to: point) < rest[$1].distance(to: point) }.map { rig.skeleton.joints[$0].name }
    }
}

/// What a character does when nobody is driving it: it breathes, and it blinks. Both come from the time alone (each
/// character at its own moments), so they're the same on the stage and in every export.
public enum Idle {
    static let breath = 3.6

    /// −1…1: out to in, a little slower on the way out. Each character starts somewhere else in its breath.
    static func breathing(at time: Double, seed: String) -> Double {
        let offset = Double(seed.utf8.reduce(UInt64(7)) { ($0 &* 31) &+ UInt64($1) } % 1000) / 1000
        let phase = (time / breath + offset).truncatingRemainder(dividingBy: 1)
        let eased = phase < 0.4 ? phase / 0.4 : 1 - (phase - 0.4) / 0.6
        return -cos(eased * .pi)
    }

    static func breathe(in state: inout Animator.Posed, time: Double, rigs: [AssetID: RigAsset]) {
        for (id, object) in state.scene.objects {
            guard let depth = object[.breathe]?.floatValue, depth > 0 else { continue }
            let swell = breathing(at: time, seed: id.raw) * min(depth, 1)
            let rig = CharacterRig.of(id, in: state.scene, rigs: rigs)
            if let rig, rig.standard == .humanoid, let chest = rig.joint("chest") ?? rig.joint("spine") {
                // The chest fills; the shoulders ride on it.
                let scale = Vec3(1 + 0.03 * swell, 1 + 0.015 * swell, 1 + 0.045 * swell)
                switch rig.body {
                case .bones:
                    var pose = rig.localPose(in: state.scene, pose: state.poses[id])
                    pose[chest].scale = pose[chest].scale.scaled(by: scale)
                    state.poses[id] = pose
                case let .joints(ids):
                    if let old = state.scene.objects[ids[chest]]?.transform.scale {
                        state.scene.objects[ids[chest]]?.transform.scale = old.scaled(by: scale)
                        state.animated.insert(ids[chest])
                    }
                case .blob:
                    break
                }
            } else {
                // No chest to fill: the whole body rises and narrows a touch.
                let scale = Vec3(1 - 0.006 * swell, 1 + 0.012 * swell, 1 - 0.006 * swell)
                state.scene.objects[id]?.transform.scale = object.transform.scale.scaled(by: scale)
            }
            state.animated.insert(id)
        }
    }

    /// Characters with a face that asked for it blink on their own, unless their blinks are keyed or performed.
    static func blink(in state: inout Animator.Posed, timeline: Timeline, time: Double, overrides: [ObjectID: [PropertyKey: PropertyValue]]) {
        for (id, object) in state.scene.objects {
            guard object[.autoBlink]?.boolValue == true, object[.rigStandard]?.stringValue != "blob" else { continue }
            let live = overrides[id] ?? [:]
            guard live[.blinkLeft] == nil, live[.blinkRight] == nil,
                  !timeline.tracks.contains(where: { $0.target == id && ($0.property == .blinkLeft || $0.property == .blinkRight) }) else { continue }
            let closed = BlobRig.autoBlink(at: time, seed: id.raw)
            state.scene.objects[id]?[.blinkLeft] = .float(closed)
            state.scene.objects[id]?[.blinkRight] = .float(closed)
            state.animated.insert(id)
        }
    }
}
