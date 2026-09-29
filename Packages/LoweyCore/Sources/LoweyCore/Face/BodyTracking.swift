import Foundation

/// Character Animator's "Set Rest Pose": the way you sit when relaxed becomes the character's neutral. Head angles, gaze
/// and the expressive dials are measured from it, so looking at the iPad from below or with a slight tilt doesn't leave
/// the character nodding or tilted. Blinks, the jaw and the hands are absolute (closed is closed).
public struct RestPose: Sendable, Hashable {
    public private(set) var values: [PropertyKey: Double] = [:]

    /// The channels measured from the rest pose.
    public static let relative: [PropertyKey] = [.headYaw, .headPitch, .headRoll, .lookX, .lookY, .brows, .smile, .mouthWide]

    public init() {}

    public var isSet: Bool { !values.isEmpty }

    /// Takes these channels as the rest pose.
    public mutating func capture(_ channels: [PropertyKey: Double]) {
        values = [:]
        for key in Self.relative {
            if let value = channels[key] { values[key] = value }
        }
        // An empty frame still counts as "set" (nothing to subtract).
        if values.isEmpty { values[.headYaw] = 0 }
    }

    public mutating func clear() {
        values = [:]
    }

    /// The channels relative to the rest pose (dials stay in their ranges).
    public func apply(_ channels: [PropertyKey: Double]) -> [PropertyKey: Double] {
        var result = channels
        for (key, rest) in values {
            guard let value = channels[key] else { continue }
            let relative = value - rest
            switch key {
            case .headYaw, .headPitch, .headRoll:
                result[key] = relative
            default:
                result[key] = min(max(relative, -1), 1)
            }
        }
        return result
    }
}

/// Upper-body tracking → the character's hands (Character Animator's body tracker, for rubber-hose arms).
/// Joints come in normalised image coordinates, y up, from the picture as you see it on screen (mirrored for a selfie
/// camera), so the hand on the left of the preview moves the hand on the left of the stage.
public enum BodySolver {
    public struct Joint: Sendable, Hashable {
        public var x: Double
        public var y: Double
        public var confidence: Double

        public init(x: Double, y: Double, confidence: Double) {
            self.x = x
            self.y = y
            self.confidence = confidence
        }
    }

    /// One arm, by its own shoulder and wrist (whatever the tracker called them).
    public struct Arm: Sendable, Hashable {
        public var shoulder: Joint?
        public var wrist: Joint?

        public init(shoulder: Joint?, wrist: Joint?) {
            self.shoulder = shoulder
            self.wrist = wrist
        }
    }

    static let minimumConfidence = 0.3

    /// Hand channels from two arms. The arm whose shoulder is further left on screen drives `handLeft…`.
    /// A wrist the camera can't see (hands in the lap, out of frame) lets that hand rest (0, 0).
    public static func channels(_ first: Arm, _ second: Arm) -> [PropertyKey: Double] {
        guard let a = first.shoulder, let b = second.shoulder, a.confidence >= minimumConfidence, b.confidence >= minimumConfidence else {
            return [.handLeftX: 0, .handLeftY: 0, .handRightX: 0, .handRightY: 0]
        }
        let width = abs(a.x - b.x) + abs(a.y - b.y) * 0.25
        guard width > 0.02 else { return [.handLeftX: 0, .handLeftY: 0, .handRightX: 0, .handRightY: 0] }
        let (left, right) = a.x <= b.x ? (first, second) : (second, first)
        let l = hand(left, outward: -1, width: width)
        let r = hand(right, outward: 1, width: width)
        return [.handLeftX: l.out, .handLeftY: l.up, .handRightX: r.out, .handRightY: r.up]
    }

    /// Out and up of one hand, 0 at rest (arm hanging a little away from the body), 1 at full reach.
    static func hand(_ arm: Arm, outward: Double, width: Double) -> (out: Double, up: Double) {
        guard let shoulder = arm.shoulder, let wrist = arm.wrist, wrist.confidence >= minimumConfidence else { return (0, 0) }
        let dx = (wrist.x - shoulder.x) * outward / width
        let dy = (wrist.y - shoulder.y) / width
        let up = min(max((dy + 1.5) / 2.3, 0), 1)
        let out = min(max((dx - 0.25) / 1.1, -1), 1)
        return (out, up)
    }
}
