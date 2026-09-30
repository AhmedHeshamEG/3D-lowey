import Foundation

/// The shot vocabulary of the Frame shot solver (the same words the AI uses).
public enum ShotType: String, Codable, Sendable, CaseIterable, Identifiable {
    case extremeWide, wide, full, medium, closeUp, extremeCloseUp, overTheShoulder, twoShot, insert

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .extremeWide: "Extreme wide"
        case .wide: "Wide"
        case .full: "Full"
        case .medium: "Medium"
        case .closeUp: "Close-up"
        case .extremeCloseUp: "Extreme close-up"
        case .overTheShoulder: "Over the shoulder"
        case .twoShot: "Two-shot"
        case .insert: "Insert"
        }
    }

    /// The lens a cinematographer would reach for (35 mm equivalent), when none is given.
    public var defaultFocalLength: Double {
        switch self {
        case .extremeWide: 18
        case .wide: 24
        case .full, .twoShot: 35
        case .medium, .overTheShoulder: 50
        case .insert: 65
        case .closeUp: 85
        case .extremeCloseUp: 100
        }
    }

    /// Of the subject's height: the part the frame shows (from the top for characters) and how full it is.
    var coverage: (fraction: Double, fill: Double) {
        switch self {
        case .extremeWide: (1, 0.1)
        case .wide: (1, 0.32)
        case .full, .twoShot: (1, 0.84)
        case .medium, .overTheShoulder: (0.55, 0.92)
        case .closeUp: (0.28, 0.95)
        case .extremeCloseUp: (0.13, 1.0)
        case .insert: (1, 0.8)
        }
    }
}

/// Where the subject sits in the frame, and the camera's height.
public enum Composition: String, Codable, Sendable, CaseIterable, Identifiable {
    case center, leftThird, rightThird, lowAngle, highAngle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .center: "Centre"
        case .leftThird: "Left third"
        case .rightThird: "Right third"
        case .lowAngle: "Low angle"
        case .highAngle: "High angle"
        }
    }

    /// Horizontal frame position of the subject (−1 left … 1 right).
    var frameX: Double {
        switch self {
        case .leftThird: -1.0 / 3.0
        case .rightThird: 1.0 / 3.0
        default: 0
        }
    }

    /// Camera elevation in degrees (positive = looking down).
    var elevation: Double {
        switch self {
        case .lowAngle: -14
        case .highAngle: 28
        default: 6
        }
    }
}

/// What to frame.
public struct ShotSubject: Hashable, Sendable {
    /// World bounds of the subject.
    public var bounds: Bounds
    /// The way the subject faces (world, horizontal); the camera goes in front, turned to a three-quarter view.
    public var front: Vec3
    /// Characters are framed from the head down; props from their centre.
    public var isCharacter: Bool

    public init(bounds: Bounds, front: Vec3 = Vec3(0, 0, 1), isCharacter: Bool = false) {
        self.bounds = bounds
        self.front = front
        self.isCharacter = isCharacter
    }
}

/// A placed camera.
public struct ShotSolution: Hashable, Sendable {
    public var position: Vec3
    public var rotation: Quat
    /// Vertical field of view (degrees) of the 16:9 frame.
    public var fieldOfView: Double
    public var focusDistance: Double

    public var focalLength: Double { CameraLens(fieldOfView: fieldOfView).focalLength }
}

/// Places and aims a camera from a subject, a shot type and a composition: the Camera panel's Frame shot and the
/// AI's `frame_shot` use the same solver.
public enum FrameShot {
    /// - Parameters:
    ///   - other: the second subject (over-the-shoulder: the shoulder in the foreground; two-shot: the partner).
    ///   - side: which side of the subject's front the camera goes (+1 right, −1 left) for the three-quarter view.
    public static func solve(_ subject: ShotSubject, type: ShotType, composition: Composition, focalLength: Double? = nil,
                             other: ShotSubject? = nil, side: Double = 1, aspect: Double = 16.0 / 9.0) -> ShotSolution {
        let fieldOfView = CameraLens.fieldOfView(focalLength: focalLength ?? type.defaultFocalLength)
        let halfV = fieldOfView * .pi / 360
        let halfH = atan(tan(halfV) * aspect)
        var framed = type == .twoShot ? (other.map { subject.bounds.union($0.bounds) } ?? subject.bounds) : subject.bounds
        if type == .insert {
            framed = subject.bounds
        }
        let size = framed.size
        let (fraction, fill) = type.coverage
        let height = max(size.y, 0.05)
        let shown = height * fraction
        // Aim: the middle of what's shown (characters from the head down; props from the centre).
        let top = framed.max.y
        let aimY = subject.isCharacter || type == .medium || type == .closeUp || type == .extremeCloseUp
            ? top - shown / 2 - shown * 0.04
            : framed.center.y
        let aim = Vec3(framed.center.x, aimY, framed.center.z)
        let width = max(size.x, size.z) * (type == .twoShot ? 1.1 : 1)
        let byHeight = shown / 2 / tan(halfV) / fill
        let byWidth = width / 2 / tan(halfH) / min(fill * 1.15, 0.95)
        let distance = max(byHeight, type == .extremeCloseUp || type == .closeUp ? 0 : byWidth, 0.25)
        let direction = viewDirection(subject: subject, type: type, composition: composition, other: other, side: side)
        var position = aim + direction * distance
        if type == .overTheShoulder, let other {
            // Behind the other subject's shoulder: pull back past it and to its side.
            let shoulder = Vec3(other.bounds.center.x, other.bounds.max.y * 0.85 + other.bounds.min.y * 0.15, other.bounds.center.z)
            let away = (shoulder - aim).normalized
            position = shoulder + away * max(other.bounds.size.length * 0.35, 0.3) + Vec3(0, 0.05, 0)
        }
        let rotation = aimed(from: position, at: aim, frameX: composition.frameX, halfHorizontal: halfH)
        return ShotSolution(position: position, rotation: rotation, fieldOfView: fieldOfView, focusDistance: (aim - position).length)
    }

    /// Unit vector from the subject toward the camera.
    static func viewDirection(subject: ShotSubject, type: ShotType, composition: Composition, other: ShotSubject?,
                              side: Double) -> Vec3 {
        var front = Vec3(subject.front.x, 0, subject.front.z)
        if front.length < 1e-6 { front = Vec3(0, 0, 1) }
        front = front.normalized
        if type == .twoShot, let other {
            // Perpendicular to the line between the two, on the subject's front side.
            let between = Vec3(other.bounds.center.x - subject.bounds.center.x, 0, other.bounds.center.z - subject.bounds.center.z)
            if between.length > 1e-6 {
                var perpendicular = Vec3(-between.z, 0, between.x).normalized
                if perpendicular.dot(front) < 0 { perpendicular = perpendicular * -1 }
                front = perpendicular
            }
        }
        // A three-quarter view reads as 3D; straight-on only for inserts and extreme close-ups.
        let yaw = type == .insert || type == .extremeCloseUp ? 0.0 : 30.0 * (side >= 0 ? 1 : -1)
        let turned = Quat(angle: yaw * .pi / 180, axis: .unitY).act(front)
        let elevation = composition.elevation * .pi / 180
        return (turned * cos(elevation) + Vec3(0, sin(elevation), 0)).normalized
    }

    /// A level camera rotation at `position` looking at `target`, turned so the target lands at `frameX`.
    static func aimed(from position: Vec3, at target: Vec3, frameX: Double, halfHorizontal: Double) -> Quat {
        let forward = (target - position).normalized
        let yaw = atan2(-forward.x, -forward.z)
        let pitch = asin(max(-1, min(1, forward.y)))
        // Turning left (positive yaw) by this much puts the target at `frameX` of the half-width (right of centre).
        let offset = atan(tan(halfHorizontal) * frameX)
        return (Quat(angle: yaw + offset, axis: .unitY) * Quat(angle: pitch, axis: .unitX)).normalized
    }
}
