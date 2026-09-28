import Foundation

/// One bone: name, parent (index into the skeleton), rest pose relative to the parent.
public struct Joint: Codable, Hashable, Sendable {
    public var name: String
    public var parent: Int?
    public var rest: Transform

    public init(name: String, parent: Int?, rest: Transform) {
        self.name = name
        self.parent = parent
        self.rest = rest
    }
}

/// A character skeleton, parents before children.
public struct Skeleton: Codable, Hashable, Sendable {
    public var joints: [Joint]

    public init(joints: [Joint]) {
        self.joints = joints
    }

    public var isEmpty: Bool { joints.isEmpty }
    public var names: [String] { joints.map(\.name) }
    public var restPose: [Transform] { joints.map(\.rest) }

    public func index(of name: String) -> Int? {
        joints.firstIndex { $0.name == name }
    }

    public func children(of index: Int) -> [Int] {
        joints.indices.filter { joints[$0].parent == index }
    }

    /// Model-space transforms from local ones (forward kinematics).
    public func modelSpace(_ local: [Transform]) -> [Transform] {
        var result = [Transform](repeating: .identity, count: joints.count)
        for index in joints.indices {
            let own = index < local.count ? local[index] : joints[index].rest
            if let parent = joints[index].parent, parent < index {
                result[index] = result[parent] * own
            } else {
                result[index] = own
            }
        }
        return result
    }

    public var modelRest: [Transform] { modelSpace(restPose) }

    /// Height of a joint above the lowest joint in the rest pose (hip height for retarget scaling).
    public func restHeight(of index: Int) -> Double {
        let model = modelRest
        let lowest = model.map(\.position.y).min() ?? 0
        return model[index].position.y - lowest
    }
}

/// Which part of a joint transform a channel animates.
public enum ChannelPath: String, Codable, Sendable {
    case translation, rotation, scale
}

/// Keyed values of one joint property over time.
public struct JointChannel: Codable, Hashable, Sendable {
    public var joint: String
    public var path: ChannelPath
    public var times: [Double]
    /// Translation / scale values (same count as `times`).
    public var vectors: [Vec3]
    /// Rotation values (same count as `times`).
    public var rotations: [Quat]
    public var step: Bool

    public init(joint: String, path: ChannelPath, times: [Double], vectors: [Vec3] = [], rotations: [Quat] = [], step: Bool = false) {
        self.joint = joint
        self.path = path
        self.times = times
        self.vectors = vectors
        self.rotations = rotations
        self.step = step
    }

    private func segment(_ time: Double) -> (Int, Int, Double) {
        guard times.count > 1, time > times[0] else { return (0, 0, 0) }
        if time >= times[times.count - 1] { return (times.count - 1, times.count - 1, 0) }
        var lo = 0
        var hi = times.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if times[mid] <= time { lo = mid } else { hi = mid }
        }
        let span = times[hi] - times[lo]
        let t = span > 0 ? (time - times[lo]) / span : 0
        return (lo, hi, step ? 0 : t)
    }

    public func vector(at time: Double) -> Vec3? {
        guard !vectors.isEmpty, vectors.count == times.count else { return nil }
        let (a, b, t) = segment(time)
        return vectors[a].lerp(to: vectors[b], t)
    }

    public func rotation(at time: Double) -> Quat? {
        guard !rotations.isEmpty, rotations.count == times.count else { return nil }
        let (a, b, t) = segment(time)
        return rotations[a].slerp(to: rotations[b], t).normalized
    }
}

/// A skeletal animation clip (walk, run, idle, type…).
public struct MotionClip: Codable, Hashable, Sendable {
    public var name: String
    public var duration: Double
    public var channels: [JointChannel]

    public init(name: String, duration: Double, channels: [JointChannel]) {
        self.name = name
        self.duration = duration
        self.channels = channels
    }

    /// Local joint transforms at `time` (rest pose where the clip doesn't animate a joint).
    public func pose(at time: Double, skeleton: Skeleton) -> [Transform] {
        var pose = skeleton.restPose
        var lookup: [String: Int] = [:]
        for (index, joint) in skeleton.joints.enumerated() where lookup[joint.name] == nil {
            lookup[joint.name] = index
        }
        for channel in channels {
            guard let index = lookup[channel.joint] else { continue }
            switch channel.path {
            case .translation: if let value = channel.vector(at: time) { pose[index].position = value }
            case .rotation: if let value = channel.rotation(at: time) { pose[index].rotation = value }
            case .scale: if let value = channel.vector(at: time) { pose[index].scale = value }
            }
        }
        return pose
    }
}

public enum PoseMath {
    /// Blends two local poses (translation/scale lerp, rotation slerp).
    public static func blend(_ a: [Transform], _ b: [Transform], _ t: Double) -> [Transform] {
        guard t > 0 else { return a }
        guard t < 1 else { return b }
        return zip(a, b).map { x, y in
            Transform(position: x.position.lerp(to: y.position, t), rotation: x.rotation.slerp(to: y.rotation, t),
                      scale: x.scale.lerp(to: y.scale, t))
        }
    }
}

/// A clip played on a character: which clip, when, from where, how fast, looping, crossfade.
public struct ClipRef: Codable, Hashable, Sendable {
    /// The library asset the clip comes from (may differ from the character: retargeting).
    public var asset: AssetID
    public var name: String

    public init(asset: AssetID, name: String) {
        self.asset = asset
        self.name = name
    }
}

public struct ClipSegment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var clip: ClipRef
    public var start: Double
    public var duration: Double
    /// Where in the clip playback starts (seconds of clip time).
    public var offset: Double
    public var speed: Double
    public var loop: Bool
    /// Crossfade from the previous segment (seconds).
    public var blend: Double

    public init(id: String, clip: ClipRef, start: Double, duration: Double, offset: Double = 0, speed: Double = 1,
                loop: Bool = true, blend: Double = 0.3) {
        self.id = id
        self.clip = clip
        self.start = start
        self.duration = duration
        self.offset = offset
        self.speed = speed
        self.loop = loop
        self.blend = blend
    }

    public var end: Double { start + duration }

    /// Clip-local time at timeline `time`. A segment fading out keeps playing past its end
    /// (`extendPastEnd`) so crossfades never freeze.
    public func clipTime(at time: Double, clipDuration: Double, extendPastEnd: Bool = false) -> Double {
        let clamped = extendPastEnd ? max(time, start) : min(max(time, start), end)
        let local = offset + (clamped - start) * speed
        guard clipDuration > 0 else { return 0 }
        if loop {
            let wrapped = local.truncatingRemainder(dividingBy: clipDuration)
            return wrapped < 0 ? wrapped + clipDuration : wrapped
        }
        return min(max(local, 0), clipDuration)
    }
}

/// Simple IK applied after the clips: feet on the ground, head looks at, a hand reaches.
public struct IKSettings: Codable, Hashable, Sendable {
    public var feetOnGround: Bool
    public var groundHeight: Double
    public var lookAt: ObjectID?
    public var reach: ObjectID?
    public var reachWithLeft: Bool
    /// Walk in place: the clip's forward travel (root motion) is removed, so a path (or keys) moves the
    /// character instead of the clip moving it a second time.
    public var inPlace: Bool

    public init(feetOnGround: Bool = false, groundHeight: Double = 0, lookAt: ObjectID? = nil, reach: ObjectID? = nil,
                reachWithLeft: Bool = false, inPlace: Bool = false) {
        self.feetOnGround = feetOnGround
        self.groundHeight = groundHeight
        self.lookAt = lookAt
        self.reach = reach
        self.reachWithLeft = reachWithLeft
        self.inPlace = inPlace
    }

    private enum CodingKeys: String, CodingKey { case feetOnGround, groundHeight, lookAt, reach, reachWithLeft, inPlace }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feetOnGround = try c.decodeIfPresent(Bool.self, forKey: .feetOnGround) ?? false
        groundHeight = try c.decodeIfPresent(Double.self, forKey: .groundHeight) ?? 0
        lookAt = try c.decodeIfPresent(ObjectID.self, forKey: .lookAt)
        reach = try c.decodeIfPresent(ObjectID.self, forKey: .reach)
        reachWithLeft = try c.decodeIfPresent(Bool.self, forKey: .reachWithLeft) ?? false
        inPlace = try c.decodeIfPresent(Bool.self, forKey: .inPlace) ?? false
    }

    public var isActive: Bool { feetOnGround || lookAt != nil || reach != nil || inPlace }
}

/// The clip track of one character.
public struct ClipTrack: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var target: ObjectID
    /// Sorted by start time.
    public var segments: [ClipSegment]
    public var ik: IKSettings

    public init(id: String, target: ObjectID, segments: [ClipSegment] = [], ik: IKSettings = IKSettings()) {
        self.id = id
        self.target = target
        self.segments = segments.sorted { $0.start < $1.start }
        self.ik = ik
    }

    private enum CodingKeys: String, CodingKey { case id, target, segments, ik }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        target = try c.decode(ObjectID.self, forKey: .target)
        segments = try c.decodeIfPresent([ClipSegment].self, forKey: .segments) ?? []
        ik = try c.decodeIfPresent(IKSettings.self, forKey: .ik) ?? IKSettings()
    }

    /// Which segments play at `time` and with what weight (the newer one fades in over its `blend`).
    /// Before the first segment the character holds its first frame; after the last, its last frame.
    public func weights(at time: Double) -> [(segment: ClipSegment, weight: Double)] {
        let sorted = segments.sorted { $0.start < $1.start }
        guard let first = sorted.first else { return [] }
        if time < first.start { return [(first, 1)] }
        let active = sorted.filter { time >= $0.start - 1e-9 && time <= $0.end + 1e-9 }
        guard let current = active.last else {
            // In a gap or after the end: hold the last segment that finished.
            let previous = sorted.last { $0.end <= time } ?? first
            return [(previous, 1)]
        }
        let earlier = active.dropLast().last ?? sorted.last { $0.end <= current.start + 1e-9 && $0.id != current.id }
        guard current.blend > 0, let earlier, time - current.start < current.blend else { return [(current, 1)] }
        let w = min(max((time - current.start) / current.blend, 0), 1)
        return [(earlier, 1 - w), (current, w)]
    }
}
