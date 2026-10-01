import Foundation

// MARK: - Posing one blob

extension BlobRig {
    static func pose(_ root: ObjectID, in scene: inout Scene, document: Document, time: Double, live: [PropertyKey: PropertyValue],
                     animated: inout Set<ObjectID>) {
        guard let character = scene.objects[root] else { return }
        let poser = BlobPoser(root: root, character: character, document: document, time: time, live: live)
        let face = poser.face()
        var mouthLayerCache: [String: DrawingRecipe]?
        for id in scene.subtree(of: root) where id != root {
            guard let part = scene.objects[id], let role = part[.faceRole]?.stringValue,
                  let rest = document.scene.objects[id] else { continue }
            let updated: SceneObject? = switch role {
            case "hand.L", "hand.R":
                poser.hand(part, left: role == "hand.L")
            case "hover":
                hoverGlow(part, rest: rest, root: root, scene: scene, document: document)
            default:
                posedFace(part, role: role, rest: rest, face: face, poser: poser, mouthLayers: &mouthLayerCache)
            }
            if let updated, updated != part {
                scene.objects[id] = updated
                animated.insert(id)
            }
        }
    }

    /// The head, hat, eyes, pupils, brows and mouth from the face's dials (nil when the part stays as it is).
    static func posedFace(_ part: SceneObject, role: String, rest: SceneObject, face: BlobFace, poser: BlobPoser,
                          mouthLayers cache: inout [String: DrawingRecipe]?) -> SceneObject? {
        var updated = part
        switch role {
        case "head":
            let k = abs(face.stretch) < 1.0 / 512 ? 0 : face.stretch
            let angles = Vec3(-poser.target(.headPitch), poser.target(.headYaw), poser.target(.headRoll))
            guard abs(k) > 1e-6 || angles.length > 1e-6 else { return nil }
            updated.transform.rotation = (rest.transform.rotation * Quat(eulerDegrees: angles)).normalized
            updated.transform.scale = Vec3(1 / (1 + k).squareRoot(), 1 + k, 1 / (1 + k).squareRoot())
        case "hat":
            // Follow-through: the hat lags the head's squash and wobbles back.
            guard abs(face.stretch) > 1.0 / 512 else { return nil }
            updated.transform.rotation = (rest.transform.rotation * Quat(angle: -face.stretch * 1.2, axis: .unitZ)).normalized
        case "eye.L", "eye.R":
            let blink = role == "eye.L" ? face.blinkL : face.blinkR
            let side: Double = role == "eye.L" ? -1 : 1
            let open = max((1 - blink) * (1 + 0.32 * face.wide), 0)
            updated.kind = .drawing(BlobCharacter.slab(eyeOutline(open: open, happy: face.happy, wide: face.wide, side: side), depth: 0.008))
        case "pupil.L", "pupil.R":
            let blink = role == "pupil.L" ? face.blinkL : face.blinkR
            let visible = min(max((1 - blink) * 2.2 - 0.35, 0), 1) * min(max(1 - (face.happy - 0.35) * 3, 0), 1)
            let size = 0.72 + 0.28 * visible + 0.18 * max(face.wide, 0)
            updated.transform.position = rest.transform.position + Vec3(face.lookX * 0.022, face.lookY * 0.018 + 0.012 * max(face.wide, 0), 0)
            let s = max(size * visible, 0.001)
            updated.transform.scale = Vec3(s, s, s)
        case "brow.L", "brow.R":
            let side: Double = role == "brow.L" ? -1 : 1
            updated.kind = .drawing(browRecipe(side: side, raise: face.brows, angle: face.browAngle, arch: max(face.wide, 0),
                                               origin: rest.transform.position))
        case "mouth.lips", "mouth.curl", "mouth.inside", "mouth.teeth", "mouth.tongue":
            let layers = cache ?? mouthLayers(face.mouth, origin: BlobCharacter.onHead(0, BlobCharacter.mouthY, lift: 0))
            cache = layers
            if let layer = layers[role] {
                updated.kind = .drawing(layer)
                updated[.visible] = .bool(true)
            } else {
                updated[.visible] = .bool(false)
            }
        default:
            return nil
        }
        return updated
    }

    /// The glow stays on the ground under him and tightens as he floats up.
    static func hoverGlow(_ part: SceneObject, rest: SceneObject, root: ObjectID, scene: Scene, document: Document) -> SceneObject {
        var updated = part
        let lift = scene.worldTransform(of: root).position.y - document.scene.worldTransform(of: root).position.y
        let scale = min(max(1 - 1.6 * lift, 0.6), 1.3)
        let parentScale = max(scene.objects[root]?.transform.scale.y ?? 1, 1e-6)
        updated.transform.position = rest.transform.position - Vec3(0, lift / parentScale, 0)
        updated.transform.scale = rest.transform.scale * scale
        return updated
    }
}

/// A blob's face at one moment, after the springs.
struct BlobFace {
    var brows: Double
    var browAngle: Double
    var wide: Double
    var happy: Double
    var lookX: Double
    var lookY: Double
    var blinkL: Double
    var blinkR: Double
    /// The quick squash-and-stretch take (signed).
    var stretch: Double
    var mouth: BlobRig.MouthPose
}

/// One blob's dials at one moment: keyed targets, live values and the springs that follow them.
struct BlobPoser {
    let root: ObjectID
    let time: Double
    let live: [PropertyKey: PropertyValue]
    let tracks: [PropertyKey: Track]
    let base: SceneObject?
    let character: SceneObject
    let cartoon: Double
    let faceSpring: BlobRig.Spring
    let mouthSpring: BlobRig.Spring

    init(root: ObjectID, character: SceneObject, document: Document, time: Double, live: [PropertyKey: PropertyValue]) {
        self.root = root
        self.time = time
        self.live = live
        self.character = character
        var tracks: [PropertyKey: Track] = [:]
        for track in document.scene.timeline.tracks where track.target == root {
            tracks[track.property] = track
        }
        self.tracks = tracks
        base = document.scene.objects[root]
        cartoon = character[.cartoon]?.floatValue ?? 0.8
        (faceSpring, mouthSpring) = BlobRig.springs(cartoon: cartoon)
    }

    /// A channel's keyed target at a moment (live values are taken as they are).
    func target(_ key: PropertyKey, _ t: Double? = nil) -> Double {
        if let value = live[key]?.floatValue { return value }
        if let track = tracks[key], let value = track.value(at: t ?? time)?.floatValue { return value }
        return base?[key]?.floatValue ?? 0
    }

    /// The channel as the spring shows it now.
    func sprung(_ key: PropertyKey) -> Double {
        let goal = target(key)
        guard live[key] == nil, tracks[key] != nil else { return goal }
        return BlobRig.settled(faceSpring.filter(at: time, step: 1.0 / 120) { target(key, $0) }, goal)
    }

    func face() -> BlobFace {
        var blinkL = sprung(.blinkLeft)
        var blinkR = sprung(.blinkRight)
        if character[.autoBlink]?.boolValue != false, tracks[.blinkLeft] == nil, tracks[.blinkRight] == nil,
           live[.blinkLeft] == nil, live[.blinkRight] == nil {
            // In 64 steps: every blink reuses the same few eye shapes (built once, then cached).
            let auto = (BlobRig.autoBlink(at: time, seed: root.raw) * 64).rounded() / 64
            blinkL = max(blinkL, auto)
            blinkR = max(blinkR, auto)
        }
        // Squash & stretch as a quick take, not a new head shape: the head stretches a little in the direction the face
        // is moving (how fast the springs travel), then it's round again. A held expression keeps only a hint of it.
        let stretch = min(max(0.04 * sprung(.squash) + takeStretch(), -0.08), 0.1)
        return BlobFace(brows: sprung(.brows), browAngle: sprung(.browAngle), wide: sprung(.eyeWide), happy: sprung(.eyeHappy),
                        lookX: sprung(.lookX), lookY: sprung(.lookY), blinkL: blinkL, blinkR: blinkR, stretch: stretch, mouth: mouth())
    }

    /// Mouth: the named shape (lip sync, expressions) plus the smile and jaw dials, all springy.
    /// Every part of the mouth filters the same moments, so each moment is worked out once.
    func mouth() -> BlobRig.MouthPose {
        var samples: [Double: BlobRig.MouthPose] = [:]
        func mouthTarget(_ t: Double) -> BlobRig.MouthPose {
            if let pose = samples[t] { return pose }
            let pose = uncachedMouth(at: t)
            samples[t] = pose
            return pose
        }
        let moves = tracks[.mouth] != nil || tracks[.smile] != nil || tracks[.jawOpen] != nil
        func part(_ path: KeyPath<BlobRig.MouthPose, Double>) -> Double {
            guard moves, live[.mouth] == nil else { return mouthTarget(time)[keyPath: path] }
            return BlobRig.settled(mouthSpring.filter(at: time, step: 1.0 / 240) { mouthTarget($0)[keyPath: path] },
                                   mouthTarget(time)[keyPath: path])
        }
        var mouth = BlobRig.MouthPose(open: max(part(\.open), 0), wide: part(\.wide), round: part(\.round), smile: part(\.smile),
                                      teeth: part(\.teeth), tongueUp: part(\.tongueUp), bite: part(\.bite), smirk: part(\.smirk))
        mouth.smirk = min(max(mouth.smirk, 0), 1)
        return mouth
    }

    func uncachedMouth(at t: Double) -> BlobRig.MouthPose {
        let name = live[.mouth]?.stringValue ?? tracks[.mouth]?.value(at: t)?.stringValue ?? base?[.mouth]?.stringValue ?? "X"
        var pose = BlobRig.MouthPose.named(name)
        pose.smile = min(max(pose.smile + target(.smile, t), -1.2), 1.2)
        pose.open = max(pose.open, target(.jawOpen, t))
        if pose.open > 0.05 || abs(pose.smile) > 0.45 { pose.smirk *= 0.3 }
        return pose
    }

    /// How fast the face is changing (its springs' speed), signed: opening up (wide eyes, brows up, smile, a keyed
    /// stretch) is positive, closing down is negative. Zero once the springs have settled.
    func takeStretch() -> Double {
        let keys: [(PropertyKey, Double)] = [(.eyeWide, 0.5), (.brows, 0.4), (.smile, 0.25), (.squash, 0.3)]
        guard keys.contains(where: { tracks[$0.0] != nil && live[$0.0] == nil }) else { return 0 }
        func drive(_ t: Double) -> Double {
            keys.reduce(0) { $0 + $1.1 * target($1.0, t) }
        }
        let h = 1.0 / 60
        let speed = (faceSpring.filter(at: time, step: 1.0 / 120, drive) - faceSpring.filter(at: max(time - h, 0), step: 1.0 / 120, drive)) / h
        return speed * 0.012 * min(max(cartoon, 0), 1)
    }

    /// Body tracking: the hand leaves its rest spot (out and up); the rubber-hose arm follows.
    func hand(_ part: SceneObject, left: Bool) -> SceneObject? {
        let xKey: PropertyKey = left ? .handLeftX : .handRightX
        let yKey: PropertyKey = left ? .handLeftY : .handRightY
        guard live[xKey] != nil || live[yKey] != nil || tracks[xKey] != nil || tracks[yKey] != nil else { return nil }
        let out = min(max(target(xKey), -1), 1)
        let up = min(max(target(yKey), -1), 1)
        let side: Double = left ? -1 : 1
        var updated = part
        updated.transform.position = part.transform.position
            + Vec3(side * out * BlobRig.handReach.x, up * BlobRig.handReach.y, max(up, 0) * 0.06)
        // A raised hand turns palm-forward instead of hanging at the side.
        let lift = min(max(up, 0), 1)
        updated.transform.rotation = (part.transform.rotation * Quat(angle: -side * 0.78 * lift, axis: .unitZ)).normalized
        return updated
    }
}
