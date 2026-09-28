import Foundation

/// Post-processing of the whole picture — part of the project's Look (no house style: every value is the project's).
/// All strengths are 0…1 with 0 = off, so a new look changes nothing until you ask for it.
public struct PostSettings: Codable, Hashable, Sendable {
    public enum Texture: String, Codable, Sendable, CaseIterable, Identifiable {
        case none, paper, collage, film

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .none: "None"
            case .paper: "Paper"
            case .collage: "Collage"
            case .film: "Old film"
            }
        }
    }

    /// Glow around bright things (lamps, screens, fire).
    public var bloom: Double
    public var vignette: Double
    public var grain: Double
    /// Stops, −2…2.
    public var exposure: Double
    /// −1…1 around neutral.
    public var contrast: Double
    public var saturation: Double
    /// −1 (cool) … 1 (warm).
    public var temperature: Double
    /// Ink lines around shapes (from depth).
    public var outline: Double
    public var outlineColor: RGBA
    public var chromaticAberration: Double
    /// Chunky pixels + fewer colours (PS1 / retro).
    public var retro: Double
    /// Render the camera's depth of field (aperture > 0 on the camera).
    public var depthOfField: Bool
    public var texture: Texture
    public var textureStrength: Double

    public init(
        bloom: Double = 0, vignette: Double = 0, grain: Double = 0, exposure: Double = 0, contrast: Double = 0, saturation: Double = 0,
        temperature: Double = 0, outline: Double = 0, outlineColor: RGBA = RGBA(0.08, 0.07, 0.1), chromaticAberration: Double = 0,
        retro: Double = 0, depthOfField: Bool = true, texture: Texture = .none, textureStrength: Double = 0.5
    ) {
        self.bloom = bloom
        self.vignette = vignette
        self.grain = grain
        self.exposure = exposure
        self.contrast = contrast
        self.saturation = saturation
        self.temperature = temperature
        self.outline = outline
        self.outlineColor = outlineColor
        self.chromaticAberration = chromaticAberration
        self.retro = retro
        self.depthOfField = depthOfField
        self.texture = texture
        self.textureStrength = textureStrength
    }

    public static let none = PostSettings()

    /// Nothing to do (the fast path skips the compositor's post stage).
    public var isNeutral: Bool {
        bloom == 0 && vignette == 0 && grain == 0 && exposure == 0 && contrast == 0 && saturation == 0 && temperature == 0
            && outline == 0 && chromaticAberration == 0 && retro == 0 && (texture == .none || textureStrength == 0)
    }

    public var needsDepth: Bool { outline > 0 || depthOfField }

    /// One-tap looks (a starting point; every slider stays editable).
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case clean, cinematic, dreamy, retro, comic, collage, oldFilm

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .clean: "Clean"
            case .cinematic: "Cinematic"
            case .dreamy: "Dreamy"
            case .retro: "Retro (PS1)"
            case .comic: "Ink outlines"
            case .collage: "Collage"
            case .oldFilm: "Old film"
            }
        }

        public var settings: PostSettings {
            switch self {
            case .clean: PostSettings()
            case .cinematic: PostSettings(bloom: 0.35, vignette: 0.35, grain: 0.15, contrast: 0.15, saturation: -0.05, temperature: 0.1)
            case .dreamy: PostSettings(bloom: 0.7, vignette: 0.2, contrast: -0.1, saturation: 0.1, chromaticAberration: 0.2)
            case .retro: PostSettings(grain: 0.1, contrast: 0.1, retro: 0.6)
            case .comic: PostSettings(contrast: 0.1, saturation: 0.15, outline: 0.6)
            case .collage: PostSettings(vignette: 0.2, grain: 0.35, saturation: -0.1, texture: .collage, textureStrength: 0.7)
            case .oldFilm: PostSettings(vignette: 0.55, grain: 0.6, contrast: 0.2, saturation: -0.6, temperature: 0.35, texture: .film,
                                        textureStrength: 0.6)
            }
        }
    }
}

/// A timed effect on the whole frame: flash, shake, speed lines, zoom blur, glitch.
public struct ScreenEffect: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case flash, shake, speedLines, zoomBlur, glitch

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .flash: "Flash"
            case .shake: "Screen shake"
            case .speedLines: "Speed lines"
            case .zoomBlur: "Zoom blur"
            case .glitch: "Glitch"
            }
        }

        public var systemImage: String {
            switch self {
            case .flash: "bolt.fill"
            case .shake: "waveform.path"
            case .speedLines: "rays"
            case .zoomBlur: "scope"
            case .glitch: "tv"
            }
        }

        public var defaultDuration: Double {
            switch self {
            case .flash: 0.35
            case .shake: 0.5
            case .speedLines: 1
            case .zoomBlur: 0.4
            case .glitch: 0.5
            }
        }
    }

    public var id: String
    public var kind: Kind
    public var start: Double
    public var duration: Double
    public var strength: Double
    public var color: RGBA

    public init(id: String, kind: Kind, start: Double, duration: Double? = nil, strength: Double = 1, color: RGBA = RGBA(1, 1, 1)) {
        self.id = id
        self.kind = kind
        self.start = start
        self.duration = duration ?? kind.defaultDuration
        self.strength = strength
        self.color = color
    }

    public var end: Double { start + duration }
}

/// How one camera hands over to the next.
public struct TransitionSpec: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case cut, fade, dipToBlack, wipe, zoomThrough

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .cut: "Cut"
            case .fade: "Fade"
            case .dipToBlack: "Dip to black"
            case .wipe: "Wipe"
            case .zoomThrough: "Zoom through"
            }
        }
    }

    public var kind: Kind
    /// Seconds, centred on the cut.
    public var duration: Double

    public init(kind: Kind, duration: Double = 0.6) {
        self.kind = kind
        self.duration = duration
    }
}

/// What the screen effects add at one moment (all zero = nothing).
public struct ScreenState: Hashable, Sendable {
    public var flash: Double = 0
    public var flashColor = RGBA(1, 1, 1)
    /// Frame offset as a fraction of the frame height, and a small roll (radians).
    public var shake = SIMD3<Double>(0, 0, 0)
    public var speedLines: Double = 0
    public var zoomBlur: Double = 0
    public var glitch: Double = 0
    /// Changes every frame while glitching (which blocks jump).
    public var glitchSeed: UInt64 = 0
    /// Speed lines flicker per frame.
    public var lineSeed: UInt64 = 0

    public init() {}

    public var isEmpty: Bool { flash == 0 && shake == .zero && speedLines == 0 && zoomBlur == 0 && glitch == 0 }
}

/// A transition in progress: `from` hands over to `to`, `progress` 0…1.
public struct TransitionState: Hashable, Sendable {
    public var kind: TransitionSpec.Kind
    public var from: ObjectID
    public var to: ObjectID
    public var progress: Double
}

public enum ScreenEffects {
    /// Sum of the effects at `time` (frame-exact: glitch and lines change once per frame at `fps`).
    public static func state(at time: Double, effects: [ScreenEffect], fps: Int) -> ScreenState {
        var state = ScreenState()
        let frame = UInt64(max(Int((time * Double(max(fps, 1))).rounded(.down)), 0))
        for effect in effects where time >= effect.start && time <= effect.end && effect.duration > 0 {
            let local = (time - effect.start) / effect.duration
            let strength = max(effect.strength, 0)
            switch effect.kind {
            case .flash:
                // Instant on, quick exponential fade.
                let amount = strength * exp(-local * 4.5) * (1 - local)
                if amount > state.flash {
                    state.flash = min(amount, 1)
                    state.flashColor = effect.color
                }
            case .shake:
                let decay = (1 - local) * (1 - local)
                let seed = Noise.seed(effect.id)
                let t = time * 38
                let amplitude = 0.035 * strength * decay
                state.shake.x += Noise.value(t, seed: seed) * amplitude
                state.shake.y += Noise.value(t, seed: seed &+ 17) * amplitude
                state.shake.z += Noise.value(t * 0.7, seed: seed &+ 31) * amplitude * 0.6
            case .speedLines:
                state.speedLines = max(state.speedLines, strength * envelope(local, attack: 0.15, release: 0.3))
                state.lineSeed = frame
            case .zoomBlur:
                state.zoomBlur = max(state.zoomBlur, strength * sin(local * .pi))
            case .glitch:
                // Stutters: on for most frames, off for a few.
                let on = ParticleSimulator.unit(Noise.seed(effect.id), Int(frame), 3) > 0.25
                state.glitch = max(state.glitch, on ? strength * envelope(local, attack: 0.05, release: 0.2) : 0)
                state.glitchSeed = frame &* 2_654_435_761 &+ Noise.seed(effect.id)
            }
        }
        return state
    }

    static func envelope(_ t: Double, attack: Double, release: Double) -> Double {
        if t < attack { return t / attack }
        if t > 1 - release { return max(0, (1 - t) / release) }
        return 1
    }

    /// The transition happening at `time`, if any (centred on its cut).
    public static func transition(at time: Double, timeline: Timeline, fallback: ObjectID?) -> TransitionState? {
        let cuts = timeline.cuts.sorted { $0.time < $1.time }
        for (index, cut) in cuts.enumerated() {
            guard let spec = cut.transition, spec.kind != .cut, spec.duration > 0 else { continue }
            let start = cut.time - spec.duration / 2
            let end = cut.time + spec.duration / 2
            guard time >= start, time < end else { continue }
            let previous = index > 0 ? cuts[index - 1].camera : fallback
            guard let from = previous, from != cut.camera else { continue }
            return TransitionState(kind: spec.kind, from: from, to: cut.camera, progress: (time - start) / spec.duration)
        }
        return nil
    }
}

/// Match cut: aim the next camera so the subject sits where it sat in the previous shot's frame.
public enum MatchCut {
    /// A rotation for a camera at `position` that puts `subject` at frame point (x, y) (−1…1, y up),
    /// keeping the camera upright.
    public static func aim(cameraAt position: Vec3, subject: Vec3, framePoint: (Double, Double), fieldOfView: Double, aspect: Double) -> Quat {
        let f = 1 / tan(fieldOfView * .pi / 360)
        // Direction of that frame point in camera space.
        let local = Vec3(framePoint.0 * aspect / f, framePoint.1 / f, -1).normalized
        let target = (subject - position).normalized
        // Pitch (about X) first: it sets the height of the direction; yaw (about Y) then keeps it.
        // y' = ly·cos p − lz·sin p must equal the target's y.
        let a = local.y
        let b = -local.z
        let radius = (a * a + b * b).squareRoot()
        let phi = atan2(b, a)
        let spread = acos(max(-1, min(1, target.y / max(radius, 1e-9))))
        let candidates = [phi + spread, phi - spread].map { atan2(sin($0), cos($0)) }
        let pitch = candidates.min { abs($0) < abs($1) } ?? 0
        let pitched = Quat(angle: pitch, axis: .unitX).act(local)
        let yaw = atan2(target.x, target.z) - atan2(pitched.x, pitched.z)
        return (Quat(angle: yaw, axis: .unitY) * Quat(angle: pitch, axis: .unitX)).normalized
    }
}

public extension Timeline {
    /// The transition in effect at `time`.
    func transition(at time: Double, fallback: ObjectID?) -> TransitionState? {
        ScreenEffects.transition(at: time, timeline: self, fallback: fallback)
    }
}
