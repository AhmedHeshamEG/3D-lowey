import Foundation

/// 2D face landmarks from the front camera (Vision), normalised to the face box (0…1, y up), plus head angles.
/// The iPad Air has no TrueDepth camera, so the face is read from ordinary video.
public struct FaceLandmarks: Hashable, Sendable {
    public var leftEye: [Vec2]
    public var rightEye: [Vec2]
    public var leftBrow: [Vec2]
    public var rightBrow: [Vec2]
    public var outerLips: [Vec2]
    public var innerLips: [Vec2]
    public var leftPupil: Vec2?
    public var rightPupil: Vec2?
    /// Nose points: with them the head's turn, nod and tilt come from the face's own geometry (sure of their direction
    /// in a mirrored picture), else from the tracker's angles.
    public var nose: [Vec2]
    /// Radians (Vision's yaw / pitch / roll).
    public var yaw: Double
    public var pitch: Double
    public var roll: Double

    public init(leftEye: [Vec2], rightEye: [Vec2], leftBrow: [Vec2], rightBrow: [Vec2], outerLips: [Vec2], innerLips: [Vec2],
                leftPupil: Vec2? = nil, rightPupil: Vec2? = nil, nose: [Vec2] = [], yaw: Double = 0, pitch: Double = 0, roll: Double = 0) {
        self.nose = nose
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.leftBrow = leftBrow
        self.rightBrow = rightBrow
        self.outerLips = outerLips
        self.innerLips = innerLips
        self.leftPupil = leftPupil
        self.rightPupil = rightPupil
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }
}

/// Raw measurements of a face (ratios, so distance to the camera doesn't matter).
public struct FaceMeasure: Hashable, Sendable, Codable {
    public var eyeOpenLeft: Double
    public var eyeOpenRight: Double
    public var browHeight: Double
    public var mouthOpen: Double
    public var mouthWidth: Double
    public var smile: Double

    public init(eyeOpenLeft: Double, eyeOpenRight: Double, browHeight: Double, mouthOpen: Double, mouthWidth: Double, smile: Double) {
        self.eyeOpenLeft = eyeOpenLeft
        self.eyeOpenRight = eyeOpenRight
        self.browHeight = browHeight
        self.mouthOpen = mouthOpen
        self.mouthWidth = mouthWidth
        self.smile = smile
    }
}

/// Face capture → character channels (the Adobe Character Animator idea, on an iPad without TrueDepth).
///
/// Sides are as the picture shows them (y up): `blinkLeft` is the eye on the left of the picture, `lookX` > 0 looks to the
/// picture's right, `headYaw` > 0 turns to the picture's right, `headRoll` > 0 tips the top of the head to the picture's
/// left. Trackers' own "left eye" labels aren't trusted: in a mirrored selfie picture they swap.
public enum FaceSolver {
    /// The two eyes (and pupils) ordered left to right in the picture.
    static func ordered(_ face: FaceLandmarks) -> (left: [Vec2], right: [Vec2], leftPupil: Vec2?, rightPupil: Vec2?) {
        let swap = !face.leftEye.isEmpty && !face.rightEye.isEmpty && center(face.leftEye).x > center(face.rightEye).x
        var pupils = [face.leftPupil, face.rightPupil]
        if let a = face.leftPupil, let b = face.rightPupil, a.x > b.x { pupils = [b, a] }
        return swap ? (face.rightEye, face.leftEye, pupils[0], pupils[1]) : (face.leftEye, face.rightEye, pupils[0], pupils[1])
    }

    static func box(_ points: [Vec2]) -> (min: Vec2, max: Vec2)? {
        guard let first = points.first else { return nil }
        var lo = first
        var hi = first
        for point in points {
            lo = Vec2(min(lo.x, point.x), min(lo.y, point.y))
            hi = Vec2(max(hi.x, point.x), max(hi.y, point.y))
        }
        return (lo, hi)
    }

    static func center(_ points: [Vec2]) -> Vec2 {
        guard !points.isEmpty else { return Vec2(0, 0) }
        let sum = points.reduce(Vec2(0, 0)) { Vec2($0.x + $1.x, $0.y + $1.y) }
        return Vec2(sum.x / Double(points.count), sum.y / Double(points.count))
    }

    /// Ratios from landmarks (nil when a region is missing).
    public static func measure(_ face: FaceLandmarks) -> FaceMeasure? {
        let eyes = ordered(face)
        guard let leftEye = box(eyes.left), let rightEye = box(eyes.right), let outer = box(face.outerLips),
              let inner = box(face.innerLips), !face.leftBrow.isEmpty, !face.rightBrow.isEmpty else { return nil }
        func openness(_ eye: (min: Vec2, max: Vec2)) -> Double {
            let width = eye.max.x - eye.min.x
            return width > 1e-6 ? (eye.max.y - eye.min.y) / width : 0
        }
        let eyeCenterY = (center(eyes.left).y + center(eyes.right).y) / 2
        let browY = (center(face.leftBrow).y + center(face.rightBrow).y) / 2
        let eyeSpan = max(center(eyes.right).x - center(eyes.left).x, 1e-6)
        let mouthCenter = center(face.outerLips)
        // Corners: the outer-lip points furthest left and right.
        let leftCorner = face.outerLips.min { $0.x < $1.x } ?? mouthCenter
        let rightCorner = face.outerLips.max { $0.x < $1.x } ?? mouthCenter
        let cornerLift = ((leftCorner.y + rightCorner.y) / 2 - mouthCenter.y) / abs(eyeSpan)
        return FaceMeasure(
            eyeOpenLeft: openness(leftEye), eyeOpenRight: openness(rightEye),
            browHeight: (browY - eyeCenterY) / abs(eyeSpan),
            mouthOpen: (inner.max.y - inner.min.y) / abs(eyeSpan),
            mouthWidth: (outer.max.x - outer.min.x) / abs(eyeSpan),
            smile: cornerLift
        )
    }

    /// Head turn, nod and tilt in degrees. From the face's geometry when the nose is known: the nose sliding towards a
    /// side of the eyes is a turn to that side, the eye line's slope is the tilt, the nose rising towards the eyes is
    /// looking up. The zero point doesn't matter (the rest pose is subtracted), the directions do.
    static func headAngles(_ face: FaceLandmarks) -> [PropertyKey: Double] {
        let eyes = ordered(face)
        guard !face.nose.isEmpty, !eyes.left.isEmpty, !eyes.right.isEmpty, !face.outerLips.isEmpty else {
            return [.headYaw: face.yaw * 180 / .pi, .headPitch: face.pitch * 180 / .pi, .headRoll: face.roll * 180 / .pi]
        }
        let left = center(eyes.left)
        let right = center(eyes.right)
        let nose = center(face.nose)
        let mouth = center(face.outerLips)
        let span = max(hypot(right.x - left.x, right.y - left.y), 1e-6)
        let middle = Vec2((left.x + right.x) / 2, (left.y + right.y) / 2)
        let yaw = min(max((nose.x - middle.x) / span * 120, -70), 70)
        let roll = atan2(right.y - left.y, right.x - left.x) * 180 / .pi
        let drop = max(middle.y - mouth.y, 1e-6)
        let pitch = -((middle.y - nose.y) / drop) * 150
        return [.headYaw: yaw, .headPitch: pitch, .headRoll: roll]
    }

    /// Channel values (the character's face properties) relative to a neutral face.
    public static func channels(_ face: FaceLandmarks, neutral: FaceMeasure) -> [PropertyKey: Double] {
        guard let now = measure(face) else { return [:] }
        func clamp(_ value: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(max(value, lo), hi) }
        var result: [PropertyKey: Double] = [
            .blinkLeft: clamp(1 - now.eyeOpenLeft / max(neutral.eyeOpenLeft, 1e-6) * 1.15 + 0.15),
            .blinkRight: clamp(1 - now.eyeOpenRight / max(neutral.eyeOpenRight, 1e-6) * 1.15 + 0.15),
            .brows: clamp((now.browHeight - neutral.browHeight) / max(neutral.browHeight * 0.25, 1e-6), -1, 1),
            .jawOpen: clamp((now.mouthOpen - neutral.mouthOpen) / 0.45),
            .mouthWide: clamp((now.mouthWidth - neutral.mouthWidth) / max(neutral.mouthWidth * 0.3, 1e-6), -1, 1),
            .smile: clamp((now.smile - neutral.smile) / 0.12, -1, 1)
        ]
        for (key, value) in headAngles(face) {
            result[key] = value
        }
        let eyes = ordered(face)
        if let leftPupil = eyes.leftPupil, let rightPupil = eyes.rightPupil, let leftEye = box(eyes.left), let rightEye = box(eyes.right) {
            func look(_ pupil: Vec2, _ eye: (min: Vec2, max: Vec2)) -> (Double, Double) {
                let w = max(eye.max.x - eye.min.x, 1e-6)
                let h = max(eye.max.y - eye.min.y, 1e-6)
                return ((pupil.x - (eye.min.x + eye.max.x) / 2) / (w / 2), (pupil.y - (eye.min.y + eye.max.y) / 2) / (h / 2))
            }
            let l = look(leftPupil, leftEye)
            let r = look(rightPupil, rightEye)
            result[.lookX] = clamp((l.0 + r.0) / 2, -1, 1)
            result[.lookY] = clamp((l.1 + r.1) / 2, -1, 1)
        }
        return result
    }
}

/// One Euro filter: smooth when still, responsive when moving — for jittery face tracking.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var derivativeCutoff: Double
    private var previous: Double?
    private var previousDerivative: Double = 0
    private var previousTime: Double?

    public init(minCutoff: Double = 1.2, beta: Double = 0.02, derivativeCutoff: Double = 1) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    public mutating func filter(_ value: Double, at time: Double) -> Double {
        guard let last = previous, let lastTime = previousTime, time > lastTime else {
            previous = value
            previousTime = time
            return value
        }
        let dt = time - lastTime
        let derivative = (value - last) / dt
        let smoothedDerivative = previousDerivative + Self.alpha(derivativeCutoff, dt) * (derivative - previousDerivative)
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let result = last + Self.alpha(cutoff, dt) * (value - last)
        previous = result
        previousDerivative = smoothedDerivative
        previousTime = time
        return result
    }
}

/// Applies face channels (keyed, performed or lip-synced on a character's root) to its face parts.
/// Parts are found by their `faceRole`: "eye.L", "eye.R", "pupil.L", "pupil.R", "brow.L", "brow.R",
/// "mouth" (the mouth group), "mouth.A" … "mouth.X" (swappable shapes, Toonsquid-style), "jaw".
/// The head turns through the humanoid "head" bone (or a part with faceRole "head").
public enum FaceRig {
    static let channelKeys: [PropertyKey] = PropertyKey.faceChannels + [.mouth]

    /// Characters (objects carrying face channels) in `scene`.
    static func faces(in scene: Scene) -> [ObjectID] {
        scene.objects.values.filter { object in
            // Blobs have their own, cartoon rig (BlobRig).
            object[.rigStandard] != nil && object[.rigStandard]?.stringValue != "blob" && channelKeys.contains { object[$0] != nil }
        }.map(\.id)
    }

    public static func apply(to scene: inout Scene, base: Scene, animated: inout Set<ObjectID>) {
        for root in faces(in: scene) {
            guard let character = scene.objects[root] else { continue }
            func value(_ key: PropertyKey) -> Double { character[key]?.floatValue ?? 0 }
            let mouth = character[.mouth]?.stringValue ?? Viseme.X.rawValue
            let hasShapes = scene.subtree(of: root).contains { scene.objects[$0]?[.faceRole]?.stringValue?.hasPrefix("mouth.") == true }
            for id in scene.subtree(of: root) where id != root {
                guard let role = scene.objects[id]?[.faceRole]?.stringValue ?? scene.objects[id]?[.bone]?.stringValue,
                      let rest = base.objects[id]?.transform, var part = scene.objects[id] else { continue }
                var transform = part.transform
                switch role {
                case "eye.L", "eye.R":
                    let blink = role == "eye.L" ? value(.blinkLeft) : value(.blinkRight)
                    transform.scale.y = rest.scale.y * max(1 - blink * 0.92, 0.06)
                case "pupil.L", "pupil.R":
                    // A part's scale is its size for built puppets; true-size parts (blobs) say how far with `faceRange`.
                    let size = part[.faceRange]?.floatValue ?? rest.scale.x
                    transform.position = rest.position + Vec3(value(.lookX) * 0.35, value(.lookY) * 0.25, 0) * size
                case "brow.L", "brow.R":
                    let brows = value(.brows)
                    let sign: Double = role == "brow.L" ? 1 : -1
                    let size = part[.faceRange]?.floatValue ?? rest.scale.y
                    transform.position = rest.position + Vec3(0, brows * 0.6, 0) * size
                    transform.rotation = (rest.rotation * Quat(angle: -brows * 0.18 * sign, axis: .unitZ)).normalized
                case "mouth":
                    // Without a shape set the mouth itself opens and widens.
                    let jaw = value(.jawOpen)
                    let wide = value(.mouthWide) + value(.smile) * 0.4
                    transform.scale = Vec3(rest.scale.x * (1 + wide * 0.25), rest.scale.y * (hasShapes ? 1 : 1 + jaw * 2.2), rest.scale.z)
                case "jaw":
                    transform.rotation = (rest.rotation * Quat(angle: value(.jawOpen) * 0.35, axis: .unitX)).normalized
                case "head":
                    let turn = Quat(eulerDegrees: Vec3(-value(.headPitch), value(.headYaw), value(.headRoll)))
                    transform.rotation = (transform.rotation * turn).normalized
                default:
                    if role.hasPrefix("mouth.") {
                        let shape = String(role.dropFirst("mouth.".count))
                        let visible = shape == mouth || (shape == "X" && Viseme(rawValue: mouth) == nil)
                        if part[.visible]?.boolValue != visible {
                            part[.visible] = .bool(visible)
                        }
                    } else {
                        continue
                    }
                }
                part.transform = transform
                scene.objects[id] = part
                animated.insert(id)
            }
        }
    }
}

public extension PropertyKey {
    /// A part's job in a face ("eye.L", "mouth.A"…).
    static let faceRole: PropertyKey = "faceRole"
    /// A puppet joint's humanoid bone ("hips", "leftUpperArm"…).
    static let bone: PropertyKey = "bone"
    /// On a character root: its skeleton standard ("humanoid") — built puppets play humanoid clips.
    static let rigStandard: PropertyKey = "rigStandard"
}
