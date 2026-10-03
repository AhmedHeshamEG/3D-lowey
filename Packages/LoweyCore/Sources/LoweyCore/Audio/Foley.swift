import Foundation

/// The built-in foley: the five sounds an explainer reaches for, synthesised (so they're ours, CC0, the same on every
/// device, and weigh nothing in the app). Each one is shaped like the move it sells: a whoosh rises and falls with a
/// fast pass, a pop is a bright blip that drops, an impact is a low thump with a crack on top, a click is a dry tick,
/// a swell builds into a reveal.
public enum Foley: String, Codable, Sendable, CaseIterable, Identifiable {
    case whoosh, pop, impact, click, swell

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .whoosh: "Whoosh"
        case .pop: "Pop"
        case .impact: "Impact"
        case .click: "Click"
        case .swell: "Swell"
        }
    }

    public var duration: Double {
        switch self {
        case .whoosh: 0.7
        case .pop: 0.18
        case .impact: 0.65
        case .click: 0.06
        case .swell: 1.6
        }
    }

    /// Where the sound "lands" (the peak), so it can be placed with its hit on a word, not its start.
    public var hit: Double {
        switch self {
        case .whoosh: 0.38
        case .swell: 1.5
        default: 0
        }
    }

    public static let sampleRate = 44100

    /// Mono samples (−1…1).
    public func samples(sampleRate: Int = Foley.sampleRate) -> [Float] {
        let count = Int(duration * Double(sampleRate))
        var noise = SeededRandom(seed: UInt64(rawValue.utf8.reduce(7) { $0 &* 31 &+ UInt64($1) }))
        let rate = Double(sampleRate)
        var output = [Float](repeating: 0, count: count)
        switch self {
        case .whoosh:
            var filter = BandPass()
            for index in 0 ..< count {
                let t = Double(index) / rate
                let u = t / duration
                let sweep = 350 + 2600 * sin(.pi * min(u * 1.1, 1))
                filter.tune(frequency: sweep, q: 1.4, sampleRate: rate)
                let envelope = pow(sin(.pi * min(u, 1)), 1.6) * (u < 0.55 ? 1 : 1 - (u - 0.55) * 0.6)
                output[index] = Float(filter.process(noise.range(-1, 1)) * envelope * 1.6)
            }
        case .pop:
            var phase = 0.0
            for index in 0 ..< count {
                let t = Double(index) / rate
                let frequency = 180 + 620 * exp(-t * 45)
                phase += 2 * .pi * frequency / rate
                let click = t < 0.004 ? noise.range(-0.4, 0.4) : 0
                output[index] = Float((sin(phase) * 0.8 + click) * exp(-t * 26))
            }
        case .impact:
            var phase = 0.0
            var low = OnePole(cutoff: 900, sampleRate: rate)
            for index in 0 ..< count {
                let t = Double(index) / rate
                phase += 2 * .pi * (45 + 60 * exp(-t * 18)) / rate
                let thump = sin(phase) * exp(-t * 7)
                let crack = low.process(noise.range(-1, 1)) * exp(-t * 60) * 1.4
                output[index] = Float(tanh((thump + crack) * 1.6) * 0.9)
            }
        case .click:
            var high = OnePole(cutoff: 3000, sampleRate: rate)
            for index in 0 ..< count {
                let t = Double(index) / rate
                let raw = noise.range(-1, 1)
                let hiss = raw - high.process(raw)
                output[index] = Float((hiss * 0.6 + sin(2 * .pi * 2200 * t) * 0.5) * exp(-t * 140))
            }
        case .swell:
            var filter = BandPass()
            var phases = [0.0, 0.0, 0.0]
            let chord = [220.0, 277.18, 329.63]
            for index in 0 ..< count {
                let t = Double(index) / rate
                let u = t / duration
                filter.tune(frequency: 400 + 3200 * u * u, q: 0.9, sampleRate: rate)
                var tone = 0.0
                for voice in chord.indices {
                    phases[voice] += 2 * .pi * chord[voice] * (1 + 0.003 * sin(t * 5 + Double(voice))) / rate
                    tone += sin(phases[voice])
                }
                let envelope = pow(min(u / 0.94, 1), 2.4) * (u > 0.94 ? max(1 - (u - 0.94) / 0.06, 0) : 1)
                output[index] = Float((filter.process(noise.range(-1, 1)) * 0.9 + tone / 3 * 0.35) * envelope)
            }
        }
        return Self.normalised(output, peak: 0.89)
    }

    /// A 16-bit WAV of the sound.
    public func wav() -> Data {
        WAV.data(samples(), channels: 1, sampleRate: Self.sampleRate)
    }

    static func normalised(_ samples: [Float], peak: Float) -> [Float] {
        let loudest = samples.map(abs).max() ?? 0
        guard loudest > 0 else { return samples }
        return samples.map { $0 / loudest * peak }
    }
}

/// A biquad band-pass (RBJ cookbook), retunable per sample.
struct BandPass {
    private var b0 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    mutating func tune(frequency: Double, q: Double, sampleRate: Double) {
        let omega = 2 * .pi * min(frequency, sampleRate * 0.45) / sampleRate
        let alpha = sin(omega) / (2 * q)
        let a0 = 1 + alpha
        b0 = alpha / a0
        b2 = -alpha / a0
        a1 = -2 * cos(omega) / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}

/// A one-pole low-pass.
struct OnePole {
    private let coefficient: Double
    private var state = 0.0

    init(cutoff: Double, sampleRate: Double) {
        coefficient = exp(-2 * .pi * cutoff / sampleRate)
    }

    mutating func process(_ x: Double) -> Double {
        state = x * (1 - coefficient) + state * coefficient
        return state
    }
}
