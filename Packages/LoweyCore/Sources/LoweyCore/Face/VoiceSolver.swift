import Foundation

/// Live voice → mouth: what the microphone hears becomes a mouth shape, a jaw and a width, a few dozen times a second,
/// with nothing recognised and nothing sent anywhere. Loudness opens the jaw; where the sound's energy sits picks the
/// shape (open vowels low-middle, "ee" high, "oo" low, hisses at the top). It's the shape of the sound, not of the
/// words: lip sync from a transcript (`LipSync`) is the exact one, and can replace this afterwards.
public struct VoiceSolver: Sendable {
    public struct Mouth: Hashable, Sendable {
        public var viseme: Viseme
        /// 0…1.
        public var jaw: Double
        /// −1 (puckered) … 1 (wide).
        public var wide: Double
        /// 0…1 how loud, measured against this room and this voice.
        public var level: Double

        public static let rest = Mouth(viseme: .X, jaw: 0, wide: 0, level: 0)
    }

    /// How much of the sound sits where.
    struct Spectrum: Sendable {
        var low = 0.0
        var openness = 0.0
        var bright = 0.0
        var hiss = 0.0
    }

    public let sampleRate: Double
    /// The quiet of the room and the loud of the voice, in decibels, learnt as it listens.
    private var floor = -60.0
    private var ceiling = -25.0
    private var last: Float = 0
    private var shown = Viseme.X
    private var candidate = Viseme.X
    private var agreed = 0
    private var jaw = 0.0

    public init(sampleRate: Double) {
        self.sampleRate = max(sampleRate, 8000)
    }

    /// One block of mono samples (20–40 ms works best) → the mouth to show now.
    public mutating func process(_ samples: [Float]) -> Mouth {
        guard samples.count >= 64 else { return Mouth(viseme: shown, jaw: jaw, wide: shown.width, level: 0) }
        var energy = 0.0
        for sample in samples {
            energy += Double(sample) * Double(sample)
        }
        let decibels = 10 * log10(max(energy / Double(samples.count), 1e-12))
        let seconds = Double(samples.count) / sampleRate
        // The floor falls at once and creeps up; the ceiling rises at once and sinks slowly.
        floor = decibels < floor ? decibels : min(floor + 3 * seconds, decibels)
        ceiling = max(decibels > ceiling ? decibels : ceiling - 1.5 * seconds, floor + 18)
        let level = min(max((decibels - floor - 8) / max(ceiling - floor - 8, 1), 0), 1)
        let heard = level > 0.12 ? Self.shape(spectrum(samples), level: level) : .X
        // A shape shows once two blocks in a row agree: no flicker between neighbours.
        if heard == candidate { agreed += 1 } else {
            candidate = heard
            agreed = 1
        }
        if agreed >= 2 || heard == shown { shown = candidate }
        let goal = shown == .X ? 0 : min(max(0.25 * shown.jaw + level * (0.3 + 0.7 * shown.jaw), 0), 1)
        // Opens fast, closes a little slower.
        jaw += (goal - jaw) * min(seconds * (goal > jaw ? 40 : 22), 1)
        return Mouth(viseme: shown, jaw: jaw, wide: shown.width, level: level)
    }

    /// The shape a sound makes.
    static func shape(_ spectrum: Spectrum, level: Double) -> Viseme {
        if spectrum.hiss > 0.5 { return .B }
        if spectrum.openness > 0.5 { return level > 0.65 ? .D : .C }
        if spectrum.bright > 0.3 { return .B }
        return spectrum.low > 0.75 ? .F : .E
    }

    /// Band energies of one block: Hann window, a little pre-emphasis, Goertzel at a spread of pitches.
    mutating func spectrum(_ samples: [Float]) -> Spectrum {
        let count = samples.count
        var block = [Double](repeating: 0, count: count)
        var previous = last
        for index in 0 ..< count {
            let window = 0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(count - 1))
            block[index] = Double(samples[index] - 0.95 * previous) * window
            previous = samples[index]
        }
        last = previous
        func band(_ from: Double, _ to: Double, _ step: Double) -> Double {
            var total = 0.0
            var frequency = from
            while frequency < to, frequency < sampleRate * 0.47 {
                total += Self.power(block, frequency: frequency, sampleRate: sampleRate)
                frequency += step
            }
            return total * step
        }
        let low = band(150, 450, 60)
        let open = band(450, 1000, 70)
        let middle = band(1000, 1800, 90)
        let high = band(1800, 3400, 120)
        let hiss = band(4000, 9000, 300)
        let voiced = low + open + middle + high
        let total = voiced + hiss
        guard total > 1e-18 else { return Spectrum() }
        return Spectrum(low: low / max(voiced, 1e-18), openness: (open + middle) / max(voiced, 1e-18), bright: high / max(voiced, 1e-18),
                        hiss: hiss / total)
    }

    /// Goertzel: the power of one frequency in a block.
    static func power(_ block: [Double], frequency: Double, sampleRate: Double) -> Double {
        let coefficient = 2 * cos(2 * Double.pi * frequency / sampleRate)
        var s1 = 0.0
        var s2 = 0.0
        for sample in block {
            let s0 = sample + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }
        return max(s1 * s1 + s2 * s2 - coefficient * s1 * s2, 0) / Double(block.count * block.count)
    }

    /// The channels a mouth sets on a character.
    public static func channels(_ mouth: Mouth) -> [PropertyKey: PropertyValue] {
        [.mouth: .enumeration(mouth.viseme.rawValue), .jawOpen: .float(mouth.jaw), .mouthWide: .float(mouth.wide)]
    }
}

/// The microphone's buffers, whatever their size, cut into the solver's blocks.
public struct VoiceStream: Sendable {
    public static let block = 1024

    private var solver: VoiceSolver
    private var pending: [Float] = []

    public init(sampleRate: Double) {
        solver = VoiceSolver(sampleRate: sampleRate)
    }

    /// Takes whatever arrived; returns the mouth after the last whole block (nil until one is full).
    public mutating func hear(_ samples: [Float]) -> VoiceSolver.Mouth? {
        pending.append(contentsOf: samples)
        var mouth: VoiceSolver.Mouth?
        var start = 0
        while pending.count - start >= Self.block {
            mouth = solver.process(Array(pending[start ..< start + Self.block]))
            start += Self.block
        }
        if start > 0 { pending.removeFirst(start) }
        return mouth
    }
}
