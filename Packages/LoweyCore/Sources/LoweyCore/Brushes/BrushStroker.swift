import Foundation

/// A point a brush can walk along: a flipbook's 2D units or an ink drawing's 3D metres.
public protocol BrushPoint: Hashable, Sendable {
    static func + (lhs: Self, rhs: Self) -> Self
    static func - (lhs: Self, rhs: Self) -> Self
    static func * (lhs: Self, rhs: Double) -> Self
    func distance(to other: Self) -> Double
}

extension BrushPoint {
    static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }
}

extension Vec3: BrushPoint {}

extension Vec2: BrushPoint {
    public func distance(to other: Vec2) -> Double { (self - other).length }
}

/// One Pencil (or finger) sample on its way into a stroke.
public struct BrushInput<P: BrushPoint>: Hashable, Sendable {
    public var point: P
    /// 0…1 (fingers report about 0.6).
    public var pressure: Double
    /// Radians from the screen: π/2 upright, 0 lying flat; nil for fingers.
    public var altitude: Double?
    /// Seconds, any origin (only differences count).
    public var time: Double

    public init(point: P, pressure: Double, altitude: Double? = nil, time: Double = 0) {
        self.point = point
        self.pressure = pressure
        self.altitude = altitude
        self.time = time
    }
}

/// A stroke as it's stored: the smoothed path with each point's radius and opacity, the Pencil's dynamics already
/// applied, so a stroke looks the same however its brush changes later and erasing can split it anywhere.
public struct BrushPath<P: BrushPoint>: Hashable, Sendable {
    public var points: [P]
    /// Radii, same units as the points.
    public var widths: [Double]
    /// 0…1.
    public var alphas: [Double]

    public init(points: [P] = [], widths: [Double] = [], alphas: [Double] = []) {
        self.points = points
        self.widths = widths
        self.alphas = alphas
    }

    public var length: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
}

/// One stamp of the brush tip.
public struct BrushDab<P: BrushPoint>: Hashable, Sendable {
    public var center: P
    /// The stroke's direction here (unit; zero for a dot).
    public var direction: P
    /// Sideways from the stroke, in the same units (the drawer turns it across the direction it sees).
    public var lateral: Double
    public var radius: Double
    /// 0…1, flow included.
    public var opacity: Double
    /// Radians on top of the tip's angle and the stroke's direction.
    public var rotation: Double
    public var flipX: Bool
    public var flipY: Bool
    /// How far along the stroke, in diameters (a rolling grain moves with it).
    public var travel: Double
}

/// The brush engine's arithmetic, pure and deterministic: samples → a stored path (`path`), a stored path → stamps
/// (`dabs`). The live stroke on screen and the committed one run the same functions over the same samples, so what
/// is drawn is what is kept; the seed keeps the randomness the same in every render and export.
public enum BrushStroker {
    /// At most this many stamps per stroke (a huge stroke spaces out instead of stalling the frame).
    public static let maximumDabs = 20000

    /// Smooths the samples with the brush's streamline (or `streamline` when larger) and turns pressure, tilt and
    /// speed into each point's radius and opacity. `size` is the radius at full pressure, `opacity` the tool's.
    /// Points closer than `minimumSpacing` merge.
    public static func path<P>(_ samples: [BrushInput<P>], brush: Brush, size: Double, opacity: Double = 1, streamline: Double = 0,
                               minimumSpacing: Double = 0) -> BrushPath<P> {
        guard let first = samples.first else { return BrushPath() }
        let pull = 1 - max(brush.stroke.streamline, streamline).clamped(0, 1) * 0.9
        var path = BrushPath<P>()
        var smoothed = first.point
        var speed = 0.0
        var previous = first
        for (index, sample) in samples.enumerated() {
            if index > 0 {
                smoothed += (sample.point - smoothed) * pull
                let elapsed = sample.time - previous.time
                if elapsed > 1e-4 {
                    let diameters = sample.point.distance(to: previous.point) / max(size * 2, 1e-9) / elapsed
                    speed += (min(diameters / 60, 1) - speed) * 0.3
                }
                previous = sample
            }
            let isLast = index == samples.count - 1
            // The last sample always lands where the Pencil lifted.
            let point = isLast && index > 0 ? sample.point : smoothed
            let (radius, alpha) = dynamics(sample, speed: speed, brush: brush, size: size, opacity: opacity)
            if let last = path.points.last, point.distance(to: last) < minimumSpacing {
                // Too close: skipped, except the lift, which replaces the point before it.
                guard isLast, path.points.count > 1 else { continue }
                path.points[path.points.count - 1] = point
                path.widths[path.widths.count - 1] = radius
                path.alphas[path.alphas.count - 1] = alpha
                continue
            }
            path.points.append(point)
            path.widths.append(radius)
            path.alphas.append(alpha)
        }
        return path
    }

    /// A sample's radius and opacity from the brush's dynamics.
    static func dynamics<P>(_ sample: BrushInput<P>, speed: Double, brush: Brush, size: Double, opacity: Double) -> (Double, Double) {
        let dynamics = brush.dynamics
        let pressure = dynamics.pressureCurve.value(at: sample.pressure)
        let tilt = sample.altitude.map { 1 - ($0 / (.pi / 2)).clamped(0, 1) } ?? 0
        var sizeFactor = 1 + (pressure - 1) * dynamics.pressureSize
        sizeFactor = dynamics.minimumSize + (1 - dynamics.minimumSize) * sizeFactor
        sizeFactor *= 1 + dynamics.tiltSize * tilt * 2
        sizeFactor *= 1 - dynamics.speedSize * 0.6 * speed
        var alpha = 1 + (pressure - 1) * dynamics.pressureOpacity
        alpha = dynamics.minimumOpacity + (1 - dynamics.minimumOpacity) * alpha
        alpha *= 1 - dynamics.tiltOpacity * tilt
        alpha *= 1 - dynamics.speedOpacity * 0.6 * speed
        return (max(size * sizeFactor, 1e-6), (alpha * opacity).clamped(0, 1))
    }

    /// The stamps along a stored path: spaced by the tip's size, tapered at both ends, faded by the falloff,
    /// jittered by the seed.
    public static func dabs<P>(_ path: BrushPath<P>, brush: Brush, seed: UInt64) -> [BrushDab<P>] {
        guard let first = path.points.first else { return [] }
        var random = SeededRandom(seed: seed)
        let settings = brush.stroke
        let total = path.length
        let meanRadius = path.widths.reduce(0, +) / Double(max(path.widths.count, 1))
        guard path.points.count > 1, total > meanRadius * 0.05 else {
            let radius = path.widths.first ?? meanRadius
            let alpha = (path.alphas.first ?? 1) * brush.rendering.flow
            return stamps(at: first, direction: first - first, radius: radius, opacity: alpha, travel: 0, brush: brush, random: &random)
        }
        let taper = Taper(settings: settings, length: total, radius: meanRadius)
        // A step never shorter than the stroke over `maximumDabs`.
        let minimumStep = total / Double(maximumDabs / max(brush.shape.count, 1))
        var dabs: [BrushDab<P>] = []
        var walked = 0.0
        var segment = 0
        var segmentStart = 0.0
        while walked <= total * (1 + 1e-9) + 1e-12 {
            while segment < path.points.count - 2,
                  segmentStart + path.points[segment].distance(to: path.points[segment + 1]) < walked {
                segmentStart += path.points[segment].distance(to: path.points[segment + 1])
                segment += 1
            }
            let a = path.points[segment], b = path.points[segment + 1]
            let span = a.distance(to: b)
            let t = span > 1e-12 ? ((walked - segmentStart) / span).clamped(0, 1) : 0
            let radius = lerp(path.widths[segment], path.widths[segment + 1], t)
            let alpha = lerp(path.alphas[segment], path.alphas[segment + 1], t)
            let (sizeTaper, alphaTaper) = taper.factors(at: walked)
            let fade = settings.falloff > 0 ? exp(-settings.falloff * walked / max(meanRadius * 20, 1e-9)) : 1
            let direction = span > 1e-12 ? (b - a) * (1 / span) : a - a
            let center = a + (b - a) * t
            dabs += stamps(at: center, direction: direction, radius: radius * sizeTaper,
                           opacity: stamped(alpha * alphaTaper * fade, spacing: settings.spacing) * brush.rendering.flow,
                           travel: walked / max(meanRadius * 2, 1e-9), brush: brush, random: &random)
            walked += max(settings.spacing * 2 * max(radius * sizeTaper, meanRadius * 0.15), minimumStep)
        }
        return dabs
    }

    /// A stamp's opacity so that the stamps overlapping at this spacing (about 1 / spacing of them over any point)
    /// add up to the stroke's opacity instead of piling up past it: 1 − (1 − a)^spacing. Flow then builds on top, as
    /// in a painting app (low flow builds up where you go over the same place again).
    static func stamped(_ alpha: Double, spacing: Double) -> Double {
        let a = alpha.clamped(0, 1)
        guard a < 1 else { return 1 }
        return 1 - pow(1 - a, min(max(spacing, 0.02), 1))
    }

    /// One step's stamps (the tip's count), with the brush's jitter.
    static func stamps<P>(at center: P, direction: P, radius: Double, opacity: Double, travel: Double, brush: Brush,
                          random: inout SeededRandom) -> [BrushDab<P>] {
        let count = brush.shape.count
        let dynamics = brush.dynamics
        return (0 ..< count).map { index in
            var lateral = (random.unit() * 2 - 1) * brush.stroke.jitter * radius * 2
            if count > 1, index > 0 { lateral += (random.unit() * 2 - 1) * radius }
            let size = radius * (1 - dynamics.sizeJitter * random.unit() * 0.8)
            let alpha = opacity * (1 - dynamics.opacityJitter * random.unit())
            let rotation = brush.shape.angle * .pi / 180 + brush.shape.rotationJitter * random.unit() * 2 * .pi
            let flipX = brush.shape.flipXJitter && random.unit() < 0.5
            let flipY = brush.shape.flipYJitter && random.unit() < 0.5
            return BrushDab(center: center, direction: direction, lateral: lateral, radius: max(size, 1e-7), opacity: alpha.clamped(0, 1),
                            rotation: rotation, flipX: flipX, flipY: flipY, travel: travel)
        }
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

/// The two ends' tapers: how far they reach and how small and faint the tip gets.
struct Taper {
    var start: Double
    var end: Double
    var length: Double
    var size: Double
    var opacity: Double

    init(settings: BrushStrokeSettings, length: Double, radius: Double) {
        // 1 reaches twenty diameters; the two tapers never cross the middle.
        start = min(settings.taperStart * radius * 40, length * 0.45)
        end = min(settings.taperEnd * radius * 40, length * 0.45)
        self.length = length
        size = settings.taperSize
        opacity = settings.taperOpacity
    }

    func factors(at distance: Double) -> (size: Double, opacity: Double) {
        func ease(_ x: Double) -> Double {
            let t = x.clamped(0, 1)
            return t * t * (3 - 2 * t)
        }
        let fromStart = start > 1e-12 ? ease(distance / start) : 1
        let fromEnd = end > 1e-12 ? ease((length - distance) / end) : 1
        let e = min(fromStart, fromEnd)
        return (1 - size * (1 - e), 1 - opacity * (1 - e))
    }
}
