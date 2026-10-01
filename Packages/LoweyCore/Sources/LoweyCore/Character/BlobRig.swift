import Foundation

public extension PropertyKey {
    /// 0…1 eyes pop wide open (surprise, shock).
    static let eyeWide: PropertyKey = "eyeWide"
    /// 0…1 eyes squeeze into happy crescents (^ ^).
    static let eyeHappy: PropertyKey = "eyeHappy"
    /// −1 worried (inner ends up) … +1 angry (inner ends down).
    static let browAngle: PropertyKey = "browAngle"
    /// −1 squashed … +1 stretched (the whole head, from the neck).
    static let squash: PropertyKey = "squash"
    /// 0…1 how cartoony the in-betweens are: 0 = no overshoot, 1 = rubbery Looney Tunes.
    static let cartoon: PropertyKey = "cartoon"
    /// Blinks on its own every few seconds (unless blinks are keyed or performed).
    static let autoBlink: PropertyKey = "autoBlink"
}

/// Poses a face in one tap (Character Animator's triggers): the rig's springs do the in-betweens, overshoot and settle.
public enum FaceExpression: String, Codable, Sendable, CaseIterable, Identifiable {
    case neutral, happy, laugh, smug, surprised, shocked, scared, sad, angry, sleepy, wink, thinking
    public var id: String { rawValue }

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    public var symbol: String {
        switch self {
        case .neutral: "face.smiling"
        case .happy: "face.smiling.inverse"
        case .laugh: "mouth"
        case .smug: "sparkle"
        case .surprised: "exclamationmark"
        case .shocked: "exclamationmark.2"
        case .scared: "bolt"
        case .sad: "cloud.drizzle"
        case .angry: "flame"
        case .sleepy: "moon.zzz"
        case .wink: "eye.half.closed"
        case .thinking: "ellipsis.bubble"
        }
    }

    /// The channels this expression sets (every expression sets them all, so one replaces the last).
    public var values: [PropertyKey: PropertyValue] {
        var mouth = "X"
        var f: [PropertyKey: Double] = [.smile: 0, .jawOpen: 0, .brows: 0, .browAngle: 0, .eyeWide: 0, .eyeHappy: 0, .blinkLeft: 0,
                                        .blinkRight: 0, .squash: 0]
        switch self {
        case .neutral: break
        case .happy: mouth = "smile"; f[.smile] = 0.8; f[.brows] = 0.35; f[.eyeHappy] = 0.65; f[.squash] = 0.2
        case .laugh: mouth = "grin"; f[.jawOpen] = 0.6; f[.smile] = 1; f[.eyeHappy] = 1; f[.brows] = 0.55; f[.squash] = 0.35
        case .smug: mouth = "smirk"; f[.smile] = 0.3; f[.brows] = 0.15; f[.browAngle] = 0.35; f[.blinkLeft] = 0.35; f[.blinkRight] = 0.35
        case .surprised: mouth = "E"; f[.jawOpen] = 0.4; f[.brows] = 1; f[.eyeWide] = 0.8; f[.squash] = 0.5
        case .shocked: mouth = "D"; f[.jawOpen] = 1; f[.brows] = 1; f[.eyeWide] = 1; f[.squash] = 0.8
        case .scared: mouth = "G"; f[.smile] = -0.5; f[.brows] = 0.8; f[.browAngle] = -0.9; f[.eyeWide] = 0.7; f[.squash] = -0.35
        case .sad: mouth = "frown"; f[.smile] = -0.8; f[.brows] = -0.1; f[.browAngle] = -1; f[.squash] = -0.2
        case .angry: mouth = "B"; f[.smile] = -0.5; f[.brows] = -0.7; f[.browAngle] = 1; f[.squash] = -0.3
        case .sleepy: mouth = "A"; f[.blinkLeft] = 0.72; f[.blinkRight] = 0.72; f[.brows] = -0.2; f[.browAngle] = -0.3
        case .wink: mouth = "smile"; f[.smile] = 0.7; f[.blinkRight] = 1; f[.eyeHappy] = 0.3; f[.brows] = 0.4; f[.squash] = 0.15
        case .thinking: mouth = "F"; f[.lookX] = 0.6; f[.lookY] = 0.6; f[.browAngle] = -0.3; f[.brows] = 0.3
        }
        var result = f.mapValues { PropertyValue.float($0) }
        result[.mouth] = .enumeration(mouth)
        return result
    }
}

public extension FaceExpression {
    /// `timeline` with this expression keyed on `character` at `time`: step keys (a held pose; the rig's springs do the
    /// in-betweens). A channel keyed for the first time also gets a neutral key at 0, so the face starts calm.
    func keyed(on character: ObjectID, at time: Double, in timeline: Timeline, ids: inout IDFactory) -> Timeline {
        var result = timeline
        let neutral = FaceExpression.neutral.values
        for (property, value) in values.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            var track = result.tracks.first { $0.target == character && $0.property == property }
                ?? Track(id: ids.next(TrackID.self), target: character, property: property)
            if track.keyframes.isEmpty, time > 1e-6 {
                track.setKey(Keyframe(time: 0, value: neutral[property] ?? .float(0), easing: .step))
            }
            track.setKey(Keyframe(time: time, value: value, easing: .step))
            result.tracks.removeAll { $0.id == track.id }
            result.tracks.append(track)
        }
        return result
    }
}

/// The blob face as a real cartoon face: eyes, brows and mouth are redrawn from continuous dials every frame (they bend,
/// squeeze and stretch instead of swapping), and every dial runs through a spring, so a pose keyed in one step
/// overshoots and settles like a Looney Tunes take. The head squashes and stretches with the hits, the hat follows
/// through, the eyes blink on their own, and the hover glow stays on the ground. Deterministic: the springs are a
/// convolution over the keyed past, so preview and export always match.
public enum BlobRig {
    // MARK: Springs

    struct Spring {
        var omega: Double
        var zeta: Double

        /// Impulse response of a damped spring (integrates to 1).
        func impulse(_ t: Double) -> Double {
            let d = (1 - zeta * zeta).squareRoot()
            return omega / d * exp(-zeta * omega * t) * sin(omega * d * t)
        }

        /// `f` (the keyed target over time) as the spring follows it, at `time`.
        func filter(at time: Double, step: Double, _ f: (Double) -> Double) -> Double {
            let window = min(5 / (zeta * omega), 1.6)
            var sum = 0.0
            var weight = 0.0
            var tau = step / 2
            while tau <= window {
                let w = impulse(tau)
                sum += w * f(max(time - tau, 0))
                weight += w
                tau += step
            }
            return weight > 1e-9 ? sum / weight : f(time)
        }
    }

    /// A spring's value in steps of 1/512 (far below a pixel), exactly the goal once it's that close: a settling face
    /// stops making new shapes, and shapes it has made before come from the renderer's cache.
    static func settled(_ value: Double, _ goal: Double) -> Double {
        abs(value - goal) < 1.0 / 512 ? goal : (value * 512).rounded() / 512
    }

    static func springs(cartoon: Double) -> (face: Spring, mouth: Spring) {
        let c = min(max(cartoon, 0), 1)
        // About half the old bounce: at the default (0.8) a pose overshoots ~14% and settles, instead of wobbling.
        return (Spring(omega: 15, zeta: 0.85 - 0.4 * c), Spring(omega: 34, zeta: 0.95 - 0.3 * c))
    }

    // MARK: Mouth poses

    /// A mouth as numbers, so any two can blend (and overshoot): open, width, roundness, smile, teeth, tongue, smirk.
    struct MouthPose {
        var open = 0.0
        var wide = 1.0
        var round = 0.0
        var smile = 0.0
        var teeth = 0.0
        var tongueUp = 0.0
        var bite = 0.0
        /// 1 = his smirk with its curl (the smug face).
        var smirk = 0.0

        /// The rest mouth ("X", Rhubarb's idle): a short, level, relaxed line. Neutral, so every expression reads.
        static let rest = MouthPose(wide: 0.62, smile: 0.06)

        static func named(_ name: String) -> MouthPose {
            switch name {
            case "A": MouthPose(wide: 0.85)
            case "B": MouthPose(open: 0.18, wide: 1.05, teeth: 1)
            case "C": MouthPose(open: 0.45, teeth: 1)
            case "D": MouthPose(open: 0.95, wide: 1.15, teeth: 1)
            case "E": MouthPose(open: 0.5, wide: 0.85, round: 0.55)
            case "F": MouthPose(open: 0.22, wide: 0.6, round: 1)
            case "G": MouthPose(open: 0.14, wide: 0.95, teeth: 1, bite: 1)
            case "H": MouthPose(open: 0.42, tongueUp: 1)
            case "smile": MouthPose(wide: 1.2, smile: 1)
            case "grin": MouthPose(open: 0.6, wide: 1.3, smile: 1, teeth: 1)
            case "frown": MouthPose(smile: -1)
            case "smirk": MouthPose(smirk: 1)
            default: rest
            }
        }
    }

    // MARK: Apply

    /// Poses every blob in `scene` at `time` (after keys, behaviours and overrides were applied).
    public static func apply(to scene: inout Scene, document: Document, time: Double, overrides: [ObjectID: [PropertyKey: PropertyValue]],
                             animated: inout Set<ObjectID>) {
        for (root, object) in scene.objects where object[.rigStandard]?.stringValue == "blob" {
            pose(root, in: &scene, document: document, time: time, live: overrides[root] ?? [:], animated: &animated)
        }
    }

    static func pose(_ root: ObjectID, in scene: inout Scene, document: Document, time: Double, live: [PropertyKey: PropertyValue],
                     animated: inout Set<ObjectID>) {
        guard let character = scene.objects[root] else { return }
        let timeline = document.scene.timeline
        var tracks: [PropertyKey: Track] = [:]
        for track in timeline.tracks where track.target == root {
            tracks[track.property] = track
        }
        let (faceSpring, mouthSpring) = springs(cartoon: character[.cartoon]?.floatValue ?? 0.8)
        let base = document.scene.objects[root]

        /// A channel's keyed target at a moment (live values are taken as they are).
        func target(_ key: PropertyKey, _ t: Double) -> Double {
            if let value = live[key]?.floatValue { return value }
            if let track = tracks[key], let value = track.value(at: t)?.floatValue { return value }
            return base?[key]?.floatValue ?? 0
        }
        /// The channel as the spring shows it now.
        func sprung(_ key: PropertyKey) -> (now: Double, target: Double) {
            let goal = target(key, time)
            guard live[key] == nil, tracks[key] != nil else { return (goal, goal) }
            return (settled(faceSpring.filter(at: time, step: 1.0 / 120) { target(key, $0) }, goal), goal)
        }
        let brows = sprung(.brows)
        let browAngle = sprung(.browAngle)
        let wide = sprung(.eyeWide)
        let happy = sprung(.eyeHappy)
        let squashChannel = sprung(.squash)
        let lookX = sprung(.lookX).now
        let lookY = sprung(.lookY).now
        var blinkL = sprung(.blinkLeft).now
        var blinkR = sprung(.blinkRight).now
        if character[.autoBlink]?.boolValue != false, tracks[.blinkLeft] == nil, tracks[.blinkRight] == nil,
           live[.blinkLeft] == nil, live[.blinkRight] == nil {
            // In 64 steps: every blink reuses the same few eye shapes (built once, then cached).
            let auto = (autoBlink(at: time, seed: root.raw) * 64).rounded() / 64
            blinkL = max(blinkL, auto)
            blinkR = max(blinkR, auto)
        }

        // Mouth: the named shape (lip sync, expressions) plus the smile and jaw dials, all springy.
        // Every part of the mouth filters the same moments, so each moment is worked out once.
        var mouthSamples: [Double: MouthPose] = [:]
        func mouthTarget(_ t: Double) -> MouthPose {
            if let pose = mouthSamples[t] { return pose }
            let pose = mouthTargetUncached(t)
            mouthSamples[t] = pose
            return pose
        }
        func mouthTargetUncached(_ t: Double) -> MouthPose {
            let name = live[.mouth]?.stringValue ?? tracks[.mouth]?.value(at: t)?.stringValue ?? base?[.mouth]?.stringValue ?? "X"
            var pose = MouthPose.named(name)
            pose.smile = min(max(pose.smile + target(.smile, t), -1.2), 1.2)
            pose.open = max(pose.open, target(.jawOpen, t))
            if pose.open > 0.05 || abs(pose.smile) > 0.45 { pose.smirk *= 0.3 }
            return pose
        }
        let mouthMoves = tracks[.mouth] != nil || tracks[.smile] != nil || tracks[.jawOpen] != nil
        func mouthPart(_ path: KeyPath<MouthPose, Double>) -> Double {
            guard mouthMoves, live[.mouth] == nil else { return mouthTarget(time)[keyPath: path] }
            return settled(mouthSpring.filter(at: time, step: 1.0 / 240) { mouthTarget($0)[keyPath: path] }, mouthTarget(time)[keyPath: path])
        }
        var mouth = MouthPose(open: max(mouthPart(\.open), 0), wide: mouthPart(\.wide), round: mouthPart(\.round), smile: mouthPart(\.smile),
                              teeth: mouthPart(\.teeth), tongueUp: mouthPart(\.tongueUp), bite: mouthPart(\.bite), smirk: mouthPart(\.smirk))
        mouth.smirk = min(max(mouth.smirk, 0), 1)

        /// How fast the face is changing (its springs' speed), signed: opening up (wide eyes, brows up, smile, a keyed
        /// stretch) is positive, closing down is negative. Zero once the springs have settled.
        func takeStretch(_ spring: Spring, cartoon: Double) -> Double {
            let keys: [(PropertyKey, Double)] = [(.eyeWide, 0.5), (.brows, 0.4), (.smile, 0.25), (.squash, 0.3)]
            guard keys.contains(where: { tracks[$0.0] != nil && live[$0.0] == nil }) else { return 0 }
            func drive(_ t: Double) -> Double {
                keys.reduce(0) { $0 + $1.1 * target($1.0, t) }
            }
            let h = 1.0 / 60
            let speed = (spring.filter(at: time, step: 1.0 / 120, drive) - spring.filter(at: max(time - h, 0), step: 1.0 / 120, drive)) / h
            return speed * 0.012 * min(max(cartoon, 0), 1)
        }
        // Squash & stretch as a quick take, not a new head shape: the head stretches a little in the direction the face
        // is moving (how fast the springs travel), then it's round again. A held expression keeps only a hint of it.
        let stretch = min(max(0.04 * squashChannel.now + takeStretch(faceSpring, cartoon: character[.cartoon]?.floatValue ?? 0.8), -0.08), 0.1)
        var mouthLayerCache: [String: DrawingRecipe]?

        for id in scene.subtree(of: root) where id != root {
            guard let part = scene.objects[id], let role = part[.faceRole]?.stringValue,
                  let rest = document.scene.objects[id] else { continue }
            var updated = part
            switch role {
            case "head":
                let k = abs(stretch) < 1.0 / 512 ? 0 : stretch
                let angles = Vec3(-target(.headPitch, time), target(.headYaw, time), target(.headRoll, time))
                guard abs(k) > 1e-6 || angles.length > 1e-6 else { continue }
                updated.transform.rotation = (rest.transform.rotation * Quat(eulerDegrees: angles)).normalized
                updated.transform.scale = Vec3(1 / (1 + k).squareRoot(), 1 + k, 1 / (1 + k).squareRoot())
            case "hat":
                // Follow-through: the hat lags the head's squash and wobbles back.
                guard abs(stretch) > 1.0 / 512 else { continue }
                updated.transform.rotation = (rest.transform.rotation * Quat(angle: -stretch * 1.2, axis: .unitZ)).normalized
            case "eye.L", "eye.R":
                let blink = role == "eye.L" ? blinkL : blinkR
                let side: Double = role == "eye.L" ? -1 : 1
                let open = max((1 - blink) * (1 + 0.32 * wide.now), 0)
                let recipe = BlobCharacter.slab(eyeOutline(open: open, happy: happy.now, wide: wide.now, side: side), depth: 0.008)
                updated.kind = .drawing(recipe)
            case "pupil.L", "pupil.R":
                let blink = role == "pupil.L" ? blinkL : blinkR
                let visible = min(max((1 - blink) * 2.2 - 0.35, 0), 1) * min(max(1 - (happy.now - 0.35) * 3, 0), 1)
                let size = 0.72 + 0.28 * visible + 0.18 * max(wide.now, 0)
                updated.transform.position = rest.transform.position
                    + Vec3(lookX * 0.022, lookY * 0.018 + 0.012 * max(wide.now, 0), 0)
                let s = max(size * visible, 0.001)
                updated.transform.scale = Vec3(s, s, s)
            case "brow.L", "brow.R":
                let side: Double = role == "brow.L" ? -1 : 1
                updated.kind = .drawing(browRecipe(side: side, raise: brows.now, angle: browAngle.now, arch: max(wide.now, 0),
                                                   origin: rest.transform.position))
            case "mouth.lips", "mouth.curl", "mouth.inside", "mouth.teeth", "mouth.tongue":
                let layers = mouthLayerCache ?? mouthLayers(mouth, origin: BlobCharacter.onHead(0, BlobCharacter.mouthY, lift: 0))
                mouthLayerCache = layers
                if let layer = layers[role] {
                    updated.kind = .drawing(layer)
                    updated[.visible] = .bool(true)
                } else {
                    updated[.visible] = .bool(false)
                }
            case "hand.L", "hand.R":
                // Body tracking: the hand leaves its rest spot (out and up); the rubber-hose arm follows.
                let left = role == "hand.L"
                let xKey: PropertyKey = left ? .handLeftX : .handRightX
                let yKey: PropertyKey = left ? .handLeftY : .handRightY
                guard live[xKey] != nil || live[yKey] != nil || tracks[xKey] != nil || tracks[yKey] != nil else { continue }
                let out = min(max(target(xKey, time), -1), 1)
                let up = min(max(target(yKey, time), -1), 1)
                let side: Double = left ? -1 : 1
                updated.transform.position = part.transform.position + Vec3(side * out * handReach.x, up * handReach.y, max(up, 0) * 0.06)
                // A raised hand turns palm-forward instead of hanging at the side.
                let lift = min(max(up, 0), 1)
                updated.transform.rotation = (part.transform.rotation * Quat(angle: -side * 0.78 * lift, axis: .unitZ)).normalized
            case "hover":
                // The glow stays on the ground under him and tightens as he floats up.
                let lift = scene.worldTransform(of: root).position.y - document.scene.worldTransform(of: root).position.y
                let scale = min(max(1 - 1.6 * lift, 0.6), 1.3)
                let parentScale = max(scene.objects[root]?.transform.scale.y ?? 1, 1e-6)
                updated.transform.position = rest.transform.position - Vec3(0, lift / parentScale, 0)
                updated.transform.scale = rest.transform.scale * scale
            default:
                continue
            }
            if updated != part {
                scene.objects[id] = updated
                animated.insert(id)
            }
        }
    }

    /// How far a tracked hand travels at full reach (character metres: sideways, up).
    static let handReach = (x: 0.26, y: 0.42)

    // MARK: Blinks

    /// 0…1 closedness of an automatic blink at `time`: every 2.2–5 s (the same every run), quick to close, slower to open.
    static func autoBlink(at time: Double, seed: String) -> Double {
        var state = UInt64(truncatingIfNeeded: seed.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ UInt64($1) })
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        var start = 1.2 + next() * 1.5
        while start + 0.3 < time {
            start += 2.2 + next() * 2.8
        }
        let t = time - start
        if t < 0 { return 0 }
        if t < 0.07 { return t / 0.07 }
        if t < 0.11 { return 1 }
        if t < 0.25 { return 1 - (t - 0.11) / 0.14 }
        return 0
    }

    // MARK: Shapes (the builder draws the rest pose with these, so a face at rest never needs rebuilding)

    /// An eye: an oval that closes into a curved line, squeezes into a happy crescent, or pops wide.
    static func eyeOutline(open: Double, happy: Double, wide: Double, side: Double) -> [Vec2] {
        let rx = BlobCharacter.eye.rx * (1 + 0.1 * max(wide, 0))
        let ry = BlobCharacter.eye.ry
        let o = min(max(open, 0), 1.4)
        let h = min(max(happy, 0), 1)
        let closed = max(1 - o, 0)
        let n = 24
        var upper: [Vec2] = []
        var lower: [Vec2] = []
        // Level eyes: the neutral face has no attitude (expressions bring it).
        let tilt = 0.0
        for index in 0 ... n {
            let u = -1 + 2 * Double(index) / Double(n)
            let arc = (1 - u * u).squareRoot()
            // Closing eyes curve down (content, asleep); happy eyes arch up (^).
            let bend = -closed * 0.35 * ry * (1 - u * u) + h * 0.25 * ry * arc
            let top = bend + ry * o * arc * (1 - 0.35 * h)
            let thickness = max(2 * ry * o * arc * (1 - h), h * 0.3 * ry * arc, 0.012 * arc + 0.004)
            upper.append(Vec2(u * rx, top))
            lower.append(Vec2(u * rx, top - thickness))
        }
        let outline = upper + lower.reversed().dropFirst().dropLast()
        return outline.map { p in Vec2(p.x * cos(tilt) - p.y * sin(tilt), p.x * sin(tilt) + p.y * cos(tilt)) }
    }

    /// A brow: raised, angled (angry or worried), arched (surprise), painted along the head.
    static func browRecipe(side: Double, raise: Double, angle: Double, arch: Double, origin: Vec3) -> DrawingRecipe {
        let x0 = side * BlobCharacter.brow.x
        let y0 = BlobCharacter.brow.y + 0.05 * raise
        // Rest shape (inner end first): a soft, level arc, both ends at the same height (calm, no attitude).
        let rest: [(Double, Double)] = [(-0.1, 0.0), (-0.035, 0.026), (0.035, 0.026), (0.1, 0.0)]
        let points = rest.enumerated().map { index, point -> (Double, Double) in
            let t = Double(index) / Double(rest.count - 1) // 0 inner … 1 outer
            let tiltY = angle * 0.045 * (0.5 - t) * -2 // angry: inner down, outer up
            let archY = arch * 0.03 * sin(t * .pi)
            return (x0 + side * point.0, y0 + point.1 + tiltY + archY)
        }
        let stroke = BlobCharacter.surfaceStroke(points, halfWidths: [0.021, 0.029, 0.028, 0.022], origin: origin, lift: 0.003)
        return DrawingRecipe(style: .ribbon, strokes: [stroke], normal: .unitZ)
    }

    /// The mouth's layers for a pose, keyed by role (a layer that isn't needed is absent: hidden).
    static func mouthLayers(_ pose: MouthPose, origin: Vec3) -> [String: DrawingRecipe] {
        let y0 = BlobCharacter.mouthY
        let halfWidth = 0.085 * max(pose.wide, 0.3) * (1 - 0.45 * min(max(pose.round, 0), 1))
        let corner = 0.032 * pose.smile
        let open = max(pose.open, 0)
        let n = 20
        func u(_ i: Int) -> Double { -1 + 2 * Double(i) / Double(n) }
        // Upper and lower lip lines (mouth space: x across, y up).
        let upper = (0 ... n).map { i -> (Double, Double) in
            let x = u(i)
            return (x * halfWidth, corner * x * x + 0.012 * open * (1 - x * x) - 0.012 * pose.smile * (1 - x * x))
        }
        let lower = (0 ... n).map { i -> (Double, Double) in
            let x = u(i)
            let depth = 0.09 * open * pow(max(1 - x * x, 0), 0.75) * (1 + 0.35 * max(pose.smile, 0))
            let roundDepth = (0.07 * open + 0.02 * pose.round) * (1 - x * x).squareRoot()
            let d = depth * (1 - pose.round) + roundDepth * pose.round
            return (x * halfWidth, corner * x * x - 0.012 * pose.smile * (1 - x * x) - d)
        }
        var layers: [String: DrawingRecipe] = [:]
        let closed = open < 0.04
        // The line: the smirk (smug face) blends into the drawn mouth; at rest it's the plain drawn line.
        let smirkLine = BlobCharacter.smirkLine.map { ($0.x + BlobCharacter.smirkShift, $0.y) }
        let line: [(Double, Double)] = closed ? blend(resample(smirkLine, n + 1), upper, pose.smirk) : upper + lower.reversed().dropFirst()
        let lineWidth = closed ? 0.0085 : 0.0075
        layers["mouth.lips"] = DrawingRecipe(style: .ribbon, strokes: [BlobCharacter.surfaceStroke(
            line.map { ($0.0, y0 + $0.1) }, halfWidths: Array(repeating: lineWidth, count: line.count), origin: origin, lift: 0.004, taper: closed
        )], normal: .unitZ)
        if pose.smirk > 0.5, closed {
            let curl = BlobCharacter.smirkCurl.map { ($0.x + BlobCharacter.smirkShift, y0 + $0.y) }
            layers["mouth.curl"] = DrawingRecipe(style: .ribbon, strokes: [BlobCharacter.surfaceStroke(
                curl, halfWidths: Array(repeating: 0.0065, count: curl.count), origin: origin, lift: 0.004, taper: true
            )], normal: .unitZ)
        }
        if !closed {
            let outline = (upper + lower.reversed()).map { Vec2($0.0, $0.1) }
            layers["mouth.inside"] = BlobCharacter.slab(outline, depth: 0.004)
            if pose.teeth > 0.3 {
                let top = upper.map { Vec2($0.0 * 0.82, $0.1 - 0.002) }
                let band = top + top.reversed().map { Vec2($0.x, $0.y - min(0.018, 0.25 * (0.09 * open + 0.01))) }
                layers["mouth.teeth"] = BlobCharacter.slab(band, depth: 0.005)
            }
            if open > 0.3 || pose.tongueUp > 0.3 {
                let tongueY = pose.tongueUp > 0.3 ? -0.01 : -0.07 * open
                layers["mouth.tongue"] = BlobCharacter.slab(
                    BlobCharacter.ellipse(rx: halfWidth * 0.5, ry: 0.012 + 0.012 * open, center: Vec2(0, tongueY), n: 20), depth: 0.005
                )
            }
        }
        return layers
    }

    static func resample(_ points: [(Double, Double)], _ count: Int) -> [(Double, Double)] {
        var lengths = [0.0]
        for (a, b) in zip(points, points.dropFirst()) {
            lengths.append(lengths[lengths.count - 1] + ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot())
        }
        let total = lengths.last ?? 0
        return (0 ..< count).map { i in
            let target = total * Double(i) / Double(max(count - 1, 1))
            let k = min(max((lengths.firstIndex { $0 >= target } ?? 1) - 1, 0), points.count - 2)
            let span = max(lengths[k + 1] - lengths[k], 1e-9)
            let t = min(max((target - lengths[k]) / span, 0), 1)
            return (points[k].0 + (points[k + 1].0 - points[k].0) * t, points[k].1 + (points[k + 1].1 - points[k].1) * t)
        }
    }

    static func blend(_ a: [(Double, Double)], _ b: [(Double, Double)], _ t: Double) -> [(Double, Double)] {
        zip(a, b).map { ($0.1.0 + ($0.0.0 - $0.1.0) * t, $0.1.1 + ($0.0.1 - $0.1.1) * t) }
    }
}
