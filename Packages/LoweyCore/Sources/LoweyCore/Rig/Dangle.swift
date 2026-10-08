import Foundation

public extension PropertyKey {
    /// How loosely a joint dangles (`dangle.<joint name>`, 0…1, on the character). Absent or 0: it doesn't.
    static func dangle(_ joint: String) -> PropertyKey { PropertyKey("dangle.\(joint)") }

    /// The joint a `dangle.` key loosens, if it is one.
    var dangleJoint: String? {
        rawValue.hasPrefix("dangle.") ? String(rawValue.dropFirst(7)) : nil
    }
}

/// What was performed live a moment ago, so things that follow through (dangling bones) can follow a face or a hand
/// that isn't keyed yet. Without it the keyed past is all there is, which is what an export sees.
public struct LivePast: Sendable {
    public struct Moment: Sendable {
        /// Seconds before now.
        public var ago: Double
        public var overrides: [ObjectID: [PropertyKey: PropertyValue]]

        public init(ago: Double, overrides: [ObjectID: [PropertyKey: PropertyValue]]) {
            self.ago = ago
            self.overrides = overrides
        }
    }

    /// Newest first.
    public var moments: [Moment]
    /// Whether the playhead was moving: then a moment `ago` is also that much earlier on the timeline.
    public var playing: Bool

    public init(moments: [Moment], playing: Bool) {
        self.moments = moments.sorted { $0.ago < $1.ago }
        self.playing = playing
    }

    /// The live values `ago` seconds back: the newest moment at least that old (the oldest one beyond what's kept).
    public func overrides(ago: Double) -> [ObjectID: [PropertyKey: PropertyValue]]? {
        (moments.first { $0.ago >= ago - 1e-9 } ?? moments.last)?.overrides
    }
}

/// Dangle: a bone that hangs loose and follows through (hair, ears, tails, a scarf). The bone's tip lags behind where
/// its body carries it and swings past when the body stops, like a weight on a spring.
///
/// Deterministic: the tip is a damped spring's answer to where the rest pose put it over the last second or so (a
/// convolution over the past, as the Blob's face springs are), so the same time always gives the same picture and
/// preview and export match. Nothing is simulated forward and nothing is stored.
public enum Dangle {
    struct Dangler {
        var joint: Int
        var amount: Double
        /// The end of the bone, in the joint's own space.
        var tip: Vec3
    }

    static let step = 1.0 / 30
    public static let longestWindow = 1.2
    static let widestSwing = 85.0 * Double.pi / 180

    /// Loose is slow and bouncy, tight is quick and nearly dead.
    static func spring(_ amount: Double) -> BlobRig.Spring {
        let loose = min(max(amount, 0), 1)
        return BlobRig.Spring(omega: 24 - 16 * loose, zeta: 0.55 - 0.3 * loose)
    }

    /// The characters with a dangling joint (cheap: only things that can have a skeleton are asked).
    static func characters(in scene: Scene, rigs: [AssetID: RigAsset]) -> [ObjectID] {
        scene.objects.values.filter { object in
            guard object.rig != nil || object[.rigStandard] != nil || object.kind.assetID.map({ rigs[$0] != nil }) == true else { return false }
            return object.properties.contains { $0.key.dangleJoint != nil && ($0.value.floatValue ?? 0) > 0 }
        }.map(\.id).sorted { $0.raw < $1.raw }
    }

    /// A character's dangling joints, parents first.
    static func danglers(of object: SceneObject, rig: CharacterRig, tips: [String: Vec3]) -> [Dangler] {
        let skeleton = rig.skeleton
        let rest = skeleton.modelRest
        return skeleton.joints.indices.compactMap { index in
            let joint = skeleton.joints[index]
            guard let amount = object[.dangle(joint.name)]?.floatValue, amount > 0 else { return nil }
            var tip: Vec3?
            if let child = skeleton.children(of: index).first {
                tip = skeleton.joints[child].rest.position
            } else if let end = tips[joint.name] {
                tip = rest[index].inverseApply(to: end)
            } else if let parent = joint.parent {
                tip = rest[index].rotation.inverse.act(rest[index].position - rest[parent].position)
            }
            guard let tip, tip.length > 1e-9 else { return nil }
            return Dangler(joint: index, amount: amount, tip: tip)
        }
    }

    /// Swings every dangling joint of `state` (the scene as posed at `time`, before anything dangles).
    static func apply(to state: inout Animator.Posed, document: Document, time: Double, rigs: [AssetID: RigAsset],
                      overrides: [ObjectID: [PropertyKey: PropertyValue]], live: LivePast?) {
        let characters = characters(in: state.scene, rigs: rigs)
        guard !characters.isEmpty else { return }
        let past = pastDocument(document, keeping: characters)
        let samples = Int((longestWindow / step).rounded())
        // Where the rest pose put every character at each past moment (shared by all its joints).
        var history: [[ObjectID: (frame: Transform, model: [Transform])]] = []
        history.reserveCapacity(samples)
        for index in 0 ..< samples {
            let ago = (Double(index) + 0.5) * step
            let moment = live?.playing == false ? time : max(time - ago, 0)
            let posed = Animator.posed(past, at: moment, rigs: rigs, overrides: live?.overrides(ago: ago) ?? overrides)
            var entry: [ObjectID: (frame: Transform, model: [Transform])] = [:]
            for id in characters {
                guard let rig = CharacterRig.of(id, in: posed.scene, rigs: rigs) else { continue }
                entry[id] = (rig.frame(in: posed.scene), rig.skeleton.modelSpace(rig.localPose(in: posed.scene, pose: posed.poses[id])))
            }
            history.append(entry)
        }
        for id in characters {
            swing(id, in: &state, history: history, rigs: rigs)
        }
    }

    private static func swing(_ id: ObjectID, in state: inout Animator.Posed, history: [[ObjectID: (frame: Transform, model: [Transform])]],
                              rigs: [AssetID: RigAsset]) {
        guard let object = state.scene.objects[id], let rig = CharacterRig.of(id, in: state.scene, rigs: rigs), rig.body != .blob else { return }
        let danglers = danglers(of: object, rig: rig, tips: object.rig?.tips ?? [:])
        guard !danglers.isEmpty else { return }
        let skeleton = rig.skeleton
        let frame = rig.frame(in: state.scene)
        var local = rig.localPose(in: state.scene, pose: state.poses[id])
        var turns: [Int: Quat] = [:]
        for dangler in danglers {
            let spring = spring(dangler.amount)
            let window = min(5 / (spring.zeta * spring.omega), longestWindow)
            var sum = Vec3.zero
            var weight = 0.0
            for (index, entry) in history.enumerated() {
                let ago = (Double(index) + 0.5) * step
                guard ago <= window, let then = entry[id], then.model.indices.contains(dangler.joint) else { continue }
                let w = spring.impulse(ago)
                sum += then.frame.apply(to: then.model[dangler.joint].apply(to: dangler.tip)) * w
                weight += w
            }
            guard weight > 1e-9 else { continue }
            let model = skeleton.modelSpace(local)
            let pivot = frame.apply(to: model[dangler.joint].position)
            let resting = frame.apply(to: model[dangler.joint].apply(to: dangler.tip)) - pivot
            let hanging = sum / weight - pivot
            guard resting.length > 1e-9, hanging.length > 1e-9 else { continue }
            var turn = Quat.rotation(from: resting.normalized, to: hanging.normalized)
            let angle = 2 * acos(min(abs(turn.w), 1))
            if angle > widestSwing { turn = Quat.identity.slerp(to: turn, widestSwing / angle) }
            // The swing is in the world; the joint turns in its parent's space.
            let inModel = (frame.rotation.inverse * turn * frame.rotation).normalized
            let parent = skeleton.joints[dangler.joint].parent.map { model[$0].rotation } ?? .identity
            let turned = (parent.inverse * inModel * model[dangler.joint].rotation).normalized
            local[dangler.joint].rotation = turned
            turns[dangler.joint] = turned
        }
        guard !turns.isEmpty else { return }
        LiveRig.put(turns, local: local, on: rig, in: &state)
    }

    /// `document` with only what moves these characters: themselves, what they stand in, and their own animation.
    static func pastDocument(_ document: Document, keeping characters: [ObjectID]) -> Document {
        var keep = Set<ObjectID>()
        for id in characters {
            keep.formUnion(document.scene.subtree(of: id))
            keep.formUnion(document.scene.ancestors(of: id))
        }
        var result = document
        result.scene.objects = document.scene.objects.filter { keep.contains($0.key) }
        result.scene.roots = document.scene.roots.filter(keep.contains)
        var timeline = Timeline(fps: document.scene.timeline.fps, duration: document.scene.timeline.duration,
                                stepping: document.scene.timeline.stepping)
        timeline.tracks = document.scene.timeline.tracks.filter { keep.contains($0.target) }
        timeline.behaviors = document.scene.timeline.behaviors.filter { keep.contains($0.target) }
        timeline.clipTracks = document.scene.timeline.clipTracks.filter { keep.contains($0.target) }
        result.scene.timeline = timeline
        return result
    }
}
