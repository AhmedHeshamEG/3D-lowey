import Foundation

/// The built-in clips (Idle, Walk, Run, Talk, Wave, Point, Type, Nod, Shrug, Celebrate) played by a Blob. A Blob has no
/// skeleton, so each clip is written for its dials instead: the hands' reach, the head's turn, the jaw, squash, and a
/// lift and lean of the whole character. Same names, same clip tracks, same crossfades as on built and imported
/// characters. Clip values add to whatever is keyed.
public enum BlobClips {
    /// What a clip does at a moment.
    public struct Pose: Hashable, Sendable {
        public var dials: [PropertyKey: Double] = [:]
        /// Up (metres, character scale).
        public var lift = 0.0
        /// Lean in degrees (x forward, z sideways).
        public var lean = Vec3.zero

        mutating func add(_ other: Pose, weight: Double) {
            for (key, value) in other.dials {
                dials[key, default: 0] += value * weight
            }
            lift += other.lift * weight
            lean += other.lean * weight
        }
    }

    /// Clip length in seconds (loops repeat it).
    public static func duration(_ name: String) -> Double {
        switch name {
        case "Idle": 2.4
        case "Walk": 1.0
        case "Run": 0.6
        case "Talk": 2.0
        case "Wave": 1.6
        case "Point", "Shrug": 1.2
        case "Type", "Nod": 1.0
        case "Celebrate": 1.4
        default: 1
        }
    }

    /// The blended pose of a Blob's clip track at `time` (nil when no clip plays).
    public static func pose(_ track: ClipTrack, at time: Double) -> Pose? {
        let weights = track.weights(at: time)
        guard !weights.isEmpty else { return nil }
        var result = Pose()
        var total = 0.0
        for (segment, weight) in weights where weight > 0 && BuiltinClips.names.contains(segment.clip.name) {
            let length = duration(segment.clip.name)
            let local = segment.clipTime(at: time, clipDuration: length, extendPastEnd: true)
            result.add(pose(segment.clip.name, at: local, duration: length), weight: weight)
            total += weight
        }
        return total > 0 ? result : nil
    }

    /// One clip at clip-local time `t`.
    public static func pose(_ name: String, at t: Double, duration: Double) -> Pose {
        let phase = t / max(duration, 1e-6) * 2 * .pi
        var pose = Pose()
        switch name {
        case "Idle":
            pose.dials = [.squash: 0.06 * sin(phase), .handLeftY: 0.05 * sin(phase + 0.6), .handRightY: 0.05 * sin(phase + 0.9),
                          .headRoll: 2 * sin(phase * 0.5)]
        case "Walk":
            pose.lift = 0.035 * abs(sin(phase))
            pose.lean = Vec3(6, 0, 3 * sin(phase))
            pose.dials = [.handLeftX: 0.18 * sin(phase), .handRightX: -0.18 * sin(phase), .handLeftY: 0.08 + 0.08 * sin(phase),
                          .handRightY: 0.08 - 0.08 * sin(phase)]
        case "Run":
            pose.lift = 0.08 * abs(sin(phase))
            pose.lean = Vec3(14, 0, 4 * sin(phase))
            pose.dials = [.handLeftY: 0.3 + 0.35 * sin(phase), .handRightY: 0.3 - 0.35 * sin(phase), .squash: 0.1 * cos(phase * 2)]
        case "Talk":
            let syllable = 0.5 + 0.5 * sin(phase * 3) * sin(phase * 1.7 + 0.4)
            pose.dials = [.jawOpen: 0.15 + 0.3 * syllable, .headPitch: 4 * sin(phase), .handRightY: 0.25 + 0.2 * sin(phase * 1.5),
                          .handRightX: 0.15 + 0.1 * sin(phase * 0.75)]
        case "Wave":
            pose.dials = [.handRightY: 0.95, .handRightX: 0.3 + 0.28 * sin(phase * 2), .headRoll: 6, .smile: 0.5]
        case "Point":
            let reach = ease(min(t / 0.3, 1))
            pose.dials = [.handRightX: 0.9 * reach, .handRightY: 0.45 * reach, .headYaw: 15 * reach]
        case "Type":
            pose.dials = [.handLeftY: 0.22 + 0.05 * sin(phase * 6), .handRightY: 0.22 + 0.05 * sin(phase * 6 + 2), .handLeftX: -0.15,
                          .handRightX: -0.15, .headPitch: -6]
        case "Nod":
            pose.dials = [.headPitch: 12 * sin(phase * 2) * sin(phase / 2)]
        case "Shrug":
            let bell = sin(min(t / duration, 1) * .pi)
            pose.dials = [.handLeftX: 0.5 * bell, .handRightX: 0.5 * bell, .handLeftY: 0.45 * bell, .handRightY: 0.45 * bell,
                          .headRoll: 8 * bell, .browAngle: -0.3 * bell, .brows: 0.4 * bell]
        case "Celebrate":
            pose.lift = 0.12 * abs(sin(phase))
            pose.dials = [.handLeftY: 1, .handRightY: 1, .handLeftX: 0.3 * sin(phase * 2), .handRightX: -0.3 * sin(phase * 2),
                          .squash: 0.15 * cos(phase * 2), .smile: 1, .eyeHappy: 0.8]
        default:
            break
        }
        return pose
    }

    static func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    /// Plays every Blob clip track: dials go to the face rig as live values (on top of keys and performances), the
    /// lift and lean move the character.
    static func apply(to scene: inout Scene, document: Document, sampleTime: (ObjectID) -> Double,
                      overrides: inout [ObjectID: [PropertyKey: PropertyValue]], animated: inout Set<ObjectID>) {
        for track in document.scene.timeline.clipTracks {
            guard scene.objects[track.target]?[.rigStandard]?.stringValue == "blob", let pose = pose(track, at: sampleTime(track.target)),
                  var root = scene.objects[track.target] else { continue }
            var live = overrides[track.target] ?? [:]
            for (key, value) in pose.dials {
                let keyed = live[key]?.floatValue ?? root[key]?.floatValue ?? 0
                live[key] = .float(keyed + value)
            }
            overrides[track.target] = live
            let scale = abs(root.transform.scale.y)
            root.transform.position.y += pose.lift * scale
            root.transform.rotation = (root.transform.rotation * Quat(eulerDegrees: pose.lean)).normalized
            scene.objects[track.target] = root
            animated.insert(track.target)
        }
    }
}
