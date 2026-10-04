import Foundation

/// Drawn effects for flipbook tracks, made from strokes so they look hand-drawn and stay editable: the comic
/// vocabulary that sells a moment (Western comic lineage, no anime focus lines).
public enum FlipbookFX: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Parallel streaks trailing behind something fast (direction: from where it came).
    case speedLines
    /// A jagged burst that pops and breaks up (a hit, a landing, a reveal).
    case impactBurst
    /// A drop that flies off a worried head and falls.
    case sweatDrop
    /// Four-point stars that twinkle (something new, clean, magical).
    case sparkle
    /// A thick swoosh along an arc (a fast swing drawn the way animators smear it).
    case smear

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .speedLines: "Speed lines"
        case .impactBurst: "Impact burst"
        case .sweatDrop: "Sweat drop"
        case .sparkle: "Sparkle"
        case .smear: "Smear"
        }
    }

    /// Frames it draws by default (on twos).
    public var defaultFrames: Int {
        switch self {
        case .speedLines: 4
        case .impactBurst: 4
        case .sweatDrop: 5
        case .sparkle: 6
        case .smear: 3
        }
    }

    /// Whether it naturally loops (sparkles and speed lines keep going; a burst happens once).
    public var loops: Bool { self == .sparkle || self == .speedLines }

    /// The drawings, `size` units across (frame heights on the camera, metres on an object), in `color`.
    public func frames(count: Int? = nil, size: Double = 1, color: ColorValue = .rgba(.white), seed: UInt64 = 1, hold: Int = 2,
                       ids: inout IDFactory) -> [FlipbookFrame] {
        let total = max(count ?? defaultFrames, 1)
        var random = SeededRandom(seed: seed)
        return (0 ..< total).map { index in
            let t = total == 1 ? 1 : Double(index) / Double(total - 1)
            let strokes = strokes(at: t, index: index, random: &random).map { stroke in
                FlipStroke(points: stroke.points.map { $0 * size }, widths: stroke.widths.map { $0 * size }, color: color, filled: stroke.filled)
            }
            let id: TrackID = ids.next()
            return FlipbookFrame(id: id.raw, hold: hold, strokes: strokes)
        }
    }

    /// Strokes for progress `t` (0…1) in a unit box (−0.5…0.5).
    private func strokes(at t: Double, index: Int, random: inout SeededRandom) -> [FlipStroke] {
        switch self {
        case .speedLines: Self.speedLines(t: t, random: &random)
        case .impactBurst: Self.impact(t: t, random: &random)
        case .sweatDrop: Self.sweat(t: t)
        case .sparkle: Self.sparkles(index: index, random: &random)
        case .smear: Self.smear(t: t)
        }
    }

    private static func line(_ points: [Vec2], width: Double, taper: Bool = true) -> FlipStroke {
        let widths = points.indices.map { index -> Double in
            guard taper, points.count > 1 else { return width }
            let u = Double(index) / Double(points.count - 1)
            return width * (0.2 + 0.8 * sin(u * .pi))
        }
        return FlipStroke(points: points, widths: widths, color: .rgba(.white))
    }

    private static func speedLines(t _: Double, random: inout SeededRandom) -> [FlipStroke] {
        (0 ..< 7).map { _ in
            let y = random.range(-0.45, 0.45)
            let start = random.range(-0.5, -0.1)
            let length = random.range(0.25, 0.6)
            return line([Vec2(start, y), Vec2(start + length * 0.5, y), Vec2(start + length, y)], width: random.range(0.004, 0.01))
        }
    }

    private static func impact(t: Double, random: inout SeededRandom) -> [FlipStroke] {
        let scale = t < 0.34 ? 0.55 + t * 1.4 : 1.0
        let spikes = 10
        var outline: [Vec2] = []
        for spike in 0 ..< spikes * 2 {
            let angle = Double(spike) / Double(spikes * 2) * 2 * .pi + random.range(-0.08, 0.08)
            let radius = (spike % 2 == 0 ? random.range(0.42, 0.5) : random.range(0.18, 0.26)) * scale
            outline.append(Vec2(cos(angle) * radius, sin(angle) * radius))
        }
        if t > 0.7 {
            // Breaking up: scattered chips flying out.
            return (0 ..< 8).map { piece in
                let angle = Double(piece) / 8 * 2 * .pi + random.range(-0.2, 0.2)
                let radius = 0.35 + 0.25 * t
                let center = Vec2(cos(angle) * radius, sin(angle) * radius)
                let chip = (0 ..< 3).map { corner -> Vec2 in
                    let a = angle + Double(corner) * 2.1
                    return center + Vec2(cos(a), sin(a)) * 0.05
                }
                return FlipStroke(points: chip, widths: [0.005, 0.005, 0.005], color: .rgba(.white), filled: true)
            }
        }
        return [FlipStroke(points: outline, widths: Array(repeating: 0.006, count: outline.count), color: .rgba(.white), filled: true)]
    }

    private static func sweat(t: Double) -> [FlipStroke] {
        // Flies up and out, then falls; the drop is a teardrop pointing where it came from.
        let x = 0.1 + t * 0.25
        let y = 0.25 + sin(t * .pi) * 0.2 - t * 0.35
        let center = Vec2(x, y)
        var drop: [Vec2] = [center + Vec2(-0.05, 0.12)]
        for step in 0 ... 8 {
            let angle = Double.pi + Double(step) / 8 * .pi
            drop.append(center + Vec2(cos(angle) * 0.06, sin(angle) * 0.06))
        }
        return [FlipStroke(points: drop, widths: Array(repeating: 0.006, count: drop.count), color: .rgba(.white), filled: true)]
    }

    private static func sparkles(index: Int, random: inout SeededRandom) -> [FlipStroke] {
        let spots = [Vec2(-0.3, 0.2), Vec2(0.25, 0.3), Vec2(0.05, -0.25), Vec2(-0.1, -0.05)]
        return spots.enumerated().compactMap { offset, spot in
            // Each sparkle twinkles on its own beat.
            let phase = Double((index + offset * 2) % 4) / 3
            let size = (0.05 + 0.1 * sin(phase * .pi)) * random.range(0.8, 1.2)
            guard size > 0.03 else { return nil }
            let star = (0 ..< 8).map { corner -> Vec2 in
                let angle = Double(corner) / 8 * 2 * .pi
                let radius = corner % 2 == 0 ? size : size * 0.22
                return spot + Vec2(cos(angle) * radius, sin(angle) * radius)
            }
            return FlipStroke(points: star, widths: Array(repeating: 0.003, count: star.count), color: .rgba(.white), filled: true)
        }
    }

    private static func smear(t: Double) -> [FlipStroke] {
        // A crescent sweeping along an arc; thick in the middle, thin at the ends.
        let sweep = 0.35 + t * 0.9
        let end = -0.6 + sweep
        let steps = 14
        var outer: [Vec2] = []
        var inner: [Vec2] = []
        for step in 0 ... steps {
            let u = Double(step) / Double(steps)
            let angle = (-0.6 + (end + 0.6) * u) * .pi
            let thickness = 0.12 * sin(u * .pi) * (1 - t * 0.4)
            outer.append(Vec2(cos(angle) * 0.42, sin(angle) * 0.42))
            inner.append(Vec2(cos(angle) * (0.42 - thickness), sin(angle) * (0.42 - thickness)))
        }
        let shape = outer + inner.reversed()
        return [FlipStroke(points: shape, widths: Array(repeating: 0.004, count: shape.count), color: .rgba(.white), filled: true)]
    }
}
