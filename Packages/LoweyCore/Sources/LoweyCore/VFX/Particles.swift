import Foundation

/// A particle effect (fire, sparks, rain…). Few controls: amount, size, speed, colour — the preset does the rest.
/// Particles are a pure function of time (every particle's life is computed from its index and the seed), so
/// scrubbing, looping and export are exact, and the same frame always looks the same.
public struct ParticleRecipe: Codable, Hashable, Sendable {
    public enum Preset: String, Codable, Sendable, CaseIterable, Identifiable {
        case fire, sparks, smoke, dust, magic, rain, snow, confetti, embers, explosion

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .fire: "Fire"
            case .sparks: "Sparks"
            case .smoke: "Smoke"
            case .dust: "Dust"
            case .magic: "Magic"
            case .rain: "Rain"
            case .snow: "Snow"
            case .confetti: "Confetti"
            case .embers: "Embers"
            case .explosion: "Explosion"
            }
        }

        public var systemImage: String {
            switch self {
            case .fire: "flame"
            case .sparks: "sparkle"
            case .smoke: "smoke"
            case .dust: "aqi.low"
            case .magic: "wand.and.stars"
            case .rain: "cloud.rain"
            case .snow: "snowflake"
            case .confetti: "party.popper"
            case .embers: "flame.circle"
            case .explosion: "burst"
            }
        }
    }

    public enum Shape: String, Codable, Sendable {
        /// Camera-facing low-poly diamond.
        case diamond
        /// Stretched along its motion (rain, sparks).
        case streak
        /// Little tumbling card (confetti).
        case card
        /// Soft round puff (smoke, dust).
        case puff
    }

    public var preset: Preset
    /// Particles per second (a burst's total count for explosions).
    public var rate: Double
    public var lifetime: Double
    public var speed: Double
    /// Emission cone half-angle in degrees (0 = straight up).
    public var spread: Double
    public var size: Double
    /// Size at the end of life relative to the start.
    public var endSize: Double
    /// m/s² (negative falls).
    public var gravity: Double
    /// Air drag (1/s).
    public var drag: Double
    /// Emitter radius (a disc in the local XZ plane).
    public var radius: Double
    /// Height of the spawn box above the emitter (rain, snow).
    public var height: Double
    /// Sideways swirl/flutter strength.
    public var turbulence: Double
    /// Colour over life (evenly spaced stops).
    public var colors: [RGBA]
    public var glow: Double
    public var shape: Shape
    /// Explosions emit everything at `burstTime` (timeline seconds) instead of continuously.
    public var burst: Bool
    public var burstTime: Double
    public var seed: UInt64

    public init(
        preset: Preset, rate: Double, lifetime: Double, speed: Double, spread: Double, size: Double, endSize: Double = 1,
        gravity: Double = 0, drag: Double = 0, radius: Double = 0.1, height: Double = 0, turbulence: Double = 0, colors: [RGBA],
        glow: Double = 0, shape: Shape = .diamond, burst: Bool = false, burstTime: Double = 0, seed: UInt64 = 1
    ) {
        self.preset = preset
        self.rate = rate
        self.lifetime = lifetime
        self.speed = speed
        self.spread = spread
        self.size = size
        self.endSize = endSize
        self.gravity = gravity
        self.drag = drag
        self.radius = radius
        self.height = height
        self.turbulence = turbulence
        self.colors = colors.isEmpty ? [RGBA(1, 1, 1)] : colors
        self.glow = glow
        self.shape = shape
        self.burst = burst
        self.burstTime = burstTime
        self.seed = seed
    }

    /// Tuned defaults per preset.
    public static func preset(_ preset: Preset, seed: UInt64 = 1) -> ParticleRecipe {
        switch preset {
        case .fire:
            ParticleRecipe(preset: .fire, rate: 70, lifetime: 0.9, speed: 1.4, spread: 14, size: 0.16, endSize: 0.2, gravity: 0.8, drag: 1.2,
                           radius: 0.18, turbulence: 0.35,
                           colors: [RGBA(1, 0.95, 0.55), RGBA(1, 0.55, 0.12), RGBA(0.85, 0.15, 0.05), RGBA(0.25, 0.08, 0.05, 0)],
                           glow: 3, seed: seed)
        case .sparks:
            ParticleRecipe(preset: .sparks, rate: 40, lifetime: 0.7, speed: 4, spread: 55, size: 0.05, endSize: 0.3, gravity: -9.8, drag: 0.6,
                           radius: 0.05, colors: [RGBA(1, 0.95, 0.7), RGBA(1, 0.6, 0.15), RGBA(1, 0.3, 0.05, 0)], glow: 5, shape: .streak, seed: seed)
        case .smoke:
            ParticleRecipe(preset: .smoke, rate: 14, lifetime: 3.5, speed: 0.6, spread: 18, size: 0.35, endSize: 3.2, gravity: 0.15, drag: 0.4,
                           radius: 0.2, turbulence: 0.4, colors: [RGBA(0.35, 0.35, 0.37, 0.7), RGBA(0.5, 0.5, 0.52, 0.35), RGBA(0.6, 0.6, 0.62, 0)],
                           shape: .puff, seed: seed)
        case .dust:
            ParticleRecipe(preset: .dust, rate: 25, lifetime: 5, speed: 0.08, spread: 90, size: 0.04, endSize: 1, gravity: -0.02, radius: 3,
                           height: 2, turbulence: 0.25, colors: [RGBA(1, 0.95, 0.8, 0), RGBA(1, 0.95, 0.8, 0.6), RGBA(1, 0.95, 0.8, 0)],
                           glow: 0.5, shape: .puff, seed: seed)
        case .magic:
            ParticleRecipe(preset: .magic, rate: 45, lifetime: 1.6, speed: 0.9, spread: 30, size: 0.07, endSize: 0.1, gravity: 0.3, drag: 0.8,
                           radius: 0.3, turbulence: 1.2, colors: [RGBA(0.6, 1, 1), RGBA(0.55, 0.45, 1), RGBA(1, 0.4, 0.9, 0)], glow: 4, seed: seed)
        case .rain:
            ParticleRecipe(preset: .rain, rate: 400, lifetime: 0.9, speed: 9, spread: 3, size: 0.03, gravity: -4, radius: 8, height: 8,
                           colors: [RGBA(0.75, 0.82, 0.95, 0.55)], shape: .streak, seed: seed)
        case .snow:
            ParticleRecipe(preset: .snow, rate: 120, lifetime: 7, speed: 0.6, spread: 5, size: 0.06, gravity: -0.35, drag: 0.6, radius: 8,
                           height: 6, turbulence: 0.5, colors: [RGBA(1, 1, 1, 0.95)], seed: seed)
        case .confetti:
            ParticleRecipe(preset: .confetti, rate: 160, lifetime: 3, speed: 6, spread: 35, size: 0.09, gravity: -5, drag: 1.6, radius: 0.2,
                           turbulence: 1.4,
                           colors: [RGBA(0.95, 0.3, 0.35), RGBA(1, 0.8, 0.2), RGBA(0.3, 0.75, 0.95), RGBA(0.4, 0.85, 0.4), RGBA(0.75, 0.45, 1)],
                           shape: .card, burst: true, seed: seed)
        case .embers:
            ParticleRecipe(preset: .embers, rate: 12, lifetime: 3.2, speed: 0.7, spread: 25, size: 0.035, endSize: 0.3, gravity: 0.25, drag: 0.5,
                           radius: 0.35, turbulence: 0.8, colors: [RGBA(1, 0.75, 0.3), RGBA(1, 0.4, 0.1), RGBA(0.7, 0.15, 0.05, 0)], glow: 4, seed: seed)
        case .explosion:
            ParticleRecipe(preset: .explosion, rate: 220, lifetime: 1.4, speed: 7, spread: 180, size: 0.22, endSize: 2.2, gravity: -2, drag: 3,
                           radius: 0.2, turbulence: 0.3,
                           colors: [RGBA(1, 0.95, 0.7), RGBA(1, 0.55, 0.1), RGBA(0.6, 0.18, 0.06, 0.8), RGBA(0.2, 0.2, 0.2, 0)],
                           glow: 4, burst: true, seed: seed)
        }
    }

    /// Colour at `life` (0…1) through the gradient stops.
    public func color(at life: Double) -> RGBA {
        guard colors.count > 1 else { return colors.first ?? RGBA(1, 1, 1) }
        let scaled = min(max(life, 0), 1) * Double(colors.count - 1)
        let index = min(Int(scaled), colors.count - 2)
        return colors[index].lerp(to: colors[index + 1], scaled - Double(index))
    }
}

/// One particle at one moment, in the emitter's local space.
public struct Particle: Hashable, Sendable {
    public var position: Vec3
    public var velocity: Vec3
    public var size: Double
    public var color: RGBA
    /// Spin angle (radians) for cards and diamonds.
    public var spin: Double
    /// 0…1 through its life.
    public var life: Double
}

public enum ParticleSimulator {
    /// Hard ceiling so a slider can't bring the iPad to its knees.
    public static let maxParticles = 2500

    /// Every live particle at `time` (timeline seconds). `emission(t)` scales the spawn rate at time t (0…1+);
    /// `amount` scales the preset's rate.
    public static func particles(_ recipe: ParticleRecipe, at time: Double, amount: Double = 1,
                                 emission: (Double) -> Double = { _ in 1 }) -> [Particle] {
        let rate = max(recipe.rate * amount, 0)
        guard rate > 0, recipe.lifetime > 0 else { return [] }
        let maxLife = recipe.lifetime * 1.3
        var result: [Particle] = []
        if recipe.burst {
            let age = time - recipe.burstTime
            guard age >= 0, age <= maxLife else { return [] }
            let count = min(Int(rate.rounded()), maxParticles)
            result.reserveCapacity(count)
            for index in 0 ..< count {
                if let particle = particle(recipe, index: index, birth: recipe.burstTime, at: time) { result.append(particle) }
            }
            return result
        }
        let first = max(Int(((time - maxLife) * rate).rounded(.down)), 0)
        let last = Int((time * rate).rounded(.down))
        guard last >= first else { return [] }
        let span = min(last - first + 1, maxParticles)
        result.reserveCapacity(span)
        for index in (last - span + 1) ... last {
            let birth = Double(index) / rate
            // Emission below 1 thins the stream deterministically (the same particles skip every time).
            let strength = emission(birth)
            if strength < 1, unit(recipe.seed, index, 9) >= strength { continue }
            if let particle = particle(recipe, index: index, birth: birth, at: time) { result.append(particle) }
        }
        return result
    }

    static func particle(_ recipe: ParticleRecipe, index: Int, birth: Double, at time: Double) -> Particle? {
        let seed = recipe.seed
        let lifetime = recipe.lifetime * (0.7 + 0.6 * unit(seed, index, 1))
        let age = time - birth
        guard age >= 0, age <= lifetime else { return nil }
        let life = age / lifetime
        // Where it's born: a disc (or a box above for rain and snow).
        let angle = unit(seed, index, 2) * 2 * .pi
        let radial = recipe.radius * unit(seed, index, 3).squareRoot()
        var origin = Vec3(cos(angle) * radial, recipe.height * unit(seed, index, 4), sin(angle) * radial)
        if recipe.height > 0, recipe.preset == .rain || recipe.preset == .snow { origin.y = recipe.height * (0.5 + 0.5 * unit(seed, index, 4)) }
        // Which way it flies: a cone around +Y (explosions: the whole sphere).
        let cone = recipe.spread * .pi / 180
        let polar = acos(1 - unit(seed, index, 5) * (1 - cos(min(cone, .pi))))
        let azimuth = unit(seed, index, 6) * 2 * .pi
        var direction = Vec3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth))
        if recipe.preset == .rain || recipe.preset == .snow { direction = Vec3(direction.x, -direction.y, direction.z) }
        let speed = recipe.speed * (0.6 + 0.8 * unit(seed, index, 7))
        let v0 = direction * speed
        // Ballistic motion with linear drag, in closed form.
        let k = recipe.drag
        let g = Vec3(0, recipe.gravity, 0)
        let position: Vec3
        let velocity: Vec3
        if k > 1e-6 {
            let decay = exp(-k * age)
            let terminal = g / k
            position = origin + terminal * age + (v0 - terminal) * ((1 - decay) / k)
            velocity = terminal + (v0 - terminal) * decay
        } else {
            position = origin + v0 * age + g * (0.5 * age * age)
            velocity = v0 + g * age
        }
        // Swirl: a per-particle lissajous drift that grows with age.
        var swirl = Vec3.zero
        if recipe.turbulence > 0 {
            let phase = unit(seed, index, 8) * 2 * .pi
            let frequency = 1.5 + unit(seed, index, 10) * 2
            swirl = Vec3(sin(age * frequency + phase), 0, cos(age * frequency * 0.8 + phase)) * (recipe.turbulence * min(age, 1.5) * 0.5)
        }
        let size = recipe.size * (0.7 + 0.6 * unit(seed, index, 11)) * (1 + (recipe.endSize - 1) * life)
        var color = recipe.color(at: life)
        if recipe.preset == .confetti { color = recipe.colors[Int(unit(seed, index, 12) * Double(recipe.colors.count)) % recipe.colors.count] }
        let spin = unit(seed, index, 13) * 2 * .pi + age * (recipe.shape == .card ? 9 : 2) * (unit(seed, index, 14) - 0.5)
        return Particle(position: position + swirl, velocity: velocity, size: max(size, 0), color: color, spin: spin, life: life)
    }

    /// Deterministic 0…1 from (seed, particle, channel) — a SplitMix64 hash.
    @inline(__always)
    static func unit(_ seed: UInt64, _ index: Int, _ channel: UInt64) -> Double {
        var z = seed &+ UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15 &+ channel &* 0xD1B5_4A32_D192_ED03
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    /// Local-space bounds a recipe can reach (selection box, framing).
    public static func bounds(_ recipe: ParticleRecipe) -> Bounds {
        let reach = max(recipe.speed * recipe.lifetime * 0.6, 0.3) + recipe.radius
        let up = recipe.gravity < 0 && recipe.preset != .fire ? reach * 0.6 : reach
        return Bounds(min: Vec3(-reach, 0, -reach), max: Vec3(reach, max(up, recipe.height), reach))
    }
}
