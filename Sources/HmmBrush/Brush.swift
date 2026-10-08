import Foundation

/// One brush of the brush engine (CONTEXT §10.3): a tip shape stamped along the stroke, an optional grain inside it,
/// and how the Pencil shapes both. Ink strokes, flipbooks and (later) painting on models and the Schizzo board all
/// draw with it. Values are normalised (0…1 unless said otherwise); the tool's size slider sets the absolute size.
public struct Brush: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var shape: BrushShape
    public var grain: BrushGrain
    public var stroke: BrushStrokeSettings
    public var dynamics: BrushDynamics
    public var rendering: BrushRendering
    /// Where it came from (built in, made here, imported from a file) and who made it.
    public var about: BrushAbout

    public init(id: String, name: String, shape: BrushShape = BrushShape(), grain: BrushGrain = BrushGrain(),
                stroke: BrushStrokeSettings = BrushStrokeSettings(), dynamics: BrushDynamics = BrushDynamics(),
                rendering: BrushRendering = BrushRendering(), about: BrushAbout = BrushAbout()) {
        self.id = id
        self.name = name
        self.shape = shape
        self.grain = grain
        self.stroke = stroke
        self.dynamics = dynamics
        self.rendering = rendering
        self.about = about
    }

    /// Every number inside its range (imports and hand-edited files can carry anything).
    public var clamped: Brush {
        var brush = self
        brush.shape = shape.clamped
        brush.grain = grain.clamped
        brush.stroke = stroke.clamped
        brush.dynamics = dynamics.clamped
        brush.rendering = rendering.clamped
        return brush
    }

    /// The image keys this brush draws with (`BrushImageSource.image`), for copying them with it.
    public var imageKeys: [String] {
        [shape.source.imageKey, grain.source?.imageKey].compactMap { $0 }
    }
}

/// A tip or grain picture: one of the built-in ones (drawn by `BrushImages`), or an image file (white paints).
public enum BrushImageSource: Hashable, Sendable {
    case builtIn(BuiltInBrushImage)
    /// A grey PNG by key: `brushes/<hash>.png` in a project, the same name in the brush library.
    case image(String)

    public var imageKey: String? {
        if case let .image(key) = self { return key }
        return nil
    }
}

extension BrushImageSource: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let builtIn = BuiltInBrushImage(rawValue: raw) {
            self = .builtIn(builtIn)
        } else {
            self = .image(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .builtIn(image): try container.encode(image.rawValue)
        case let .image(key): try container.encode(key)
        }
    }
}

/// The pictures the app draws itself (no bundled bitmaps: nothing of Procreate's or Adobe's ships).
public enum BuiltInBrushImage: String, Codable, Sendable, CaseIterable {
    // Tips.
    case hardRound, softRound, pencilTip, chalkTip, bristleTip, flatTip, splatterTip
    // Grains.
    case paper, canvas, noise, charcoal

    public var isGrain: Bool {
        switch self {
        case .paper, .canvas, .noise, .charcoal: true
        default: false
        }
    }
}

/// The tip stamped along the stroke.
public struct BrushShape: Codable, Hashable, Sendable {
    public var source: BrushImageSource
    /// 1 = as drawn, smaller squashes it (a calligraphy nib).
    public var roundness: Double
    /// Degrees.
    public var angle: Double
    /// The tip turns with the stroke's direction (else it keeps its angle on the canvas).
    public var followsStroke: Bool
    /// 0…1: each stamp turns by a random amount up to a full turn.
    public var rotationJitter: Double
    public var flipXJitter: Bool
    public var flipYJitter: Bool
    /// Stamps per step (1…16), each scattered.
    public var count: Int
    /// Black paints instead of white.
    public var inverted: Bool

    public init(source: BrushImageSource = .builtIn(.hardRound), roundness: Double = 1, angle: Double = 0, followsStroke: Bool = true,
                rotationJitter: Double = 0, flipXJitter: Bool = false, flipYJitter: Bool = false, count: Int = 1, inverted: Bool = false) {
        self.source = source
        self.roundness = roundness
        self.angle = angle
        self.followsStroke = followsStroke
        self.rotationJitter = rotationJitter
        self.flipXJitter = flipXJitter
        self.flipYJitter = flipYJitter
        self.count = count
        self.inverted = inverted
    }

    var clamped: BrushShape {
        var shape = self
        shape.roundness = roundness.clamped(0.05, 1)
        shape.angle = angle.truncatingRemainder(dividingBy: 360)
        shape.rotationJitter = rotationJitter.clamped(0, 1)
        shape.count = min(max(count, 1), 16)
        return shape
    }
}

/// The texture inside the tip.
public struct BrushGrain: Codable, Hashable, Sendable {
    public enum Movement: String, Codable, Sendable, CaseIterable {
        /// The grain rolls with each stamp (a sponge, a bristle).
        case rolling
        /// The grain stays on the canvas, so strokes reveal the same paper (a pencil).
        case texturized
    }

    /// nil: a plain tip.
    public var source: BrushImageSource?
    /// Grain tile size: as a multiple of the tip's diameter (rolling) or of 15 % of the view's height (texturized).
    public var scale: Double
    /// How much the grain takes away (0 none, 1 all of it).
    public var depth: Double
    public var movement: Movement
    public var inverted: Bool

    public init(source: BrushImageSource? = nil, scale: Double = 1, depth: Double = 1, movement: Movement = .texturized,
                inverted: Bool = false) {
        self.source = source
        self.scale = scale
        self.depth = depth
        self.movement = movement
        self.inverted = inverted
    }

    var clamped: BrushGrain {
        var grain = self
        grain.scale = scale.clamped(0.05, 10)
        grain.depth = depth.clamped(0, 1)
        return grain
    }
}

/// How the stroke is laid down.
public struct BrushStrokeSettings: Codable, Hashable, Sendable {
    /// Distance between stamps as a fraction of the tip's diameter (0.02 … 2).
    public var spacing: Double
    /// Pulls the line toward a smooth path behind the Pencil (0 raw … 1 very smooth).
    public var streamline: Double
    /// Stamps scatter sideways by up to this many diameters.
    public var jitter: Double
    /// The stroke fades out along its length (0 never … 1 within a short stroke).
    public var falloff: Double
    /// How far the tapers reach at each end, 0…1 (1 = twenty diameters).
    public var taperStart: Double
    public var taperEnd: Double
    /// How thin a taper's tip gets (1 = to a point) and how transparent.
    public var taperSize: Double
    public var taperOpacity: Double

    public init(spacing: Double = 0.1, streamline: Double = 0.3, jitter: Double = 0, falloff: Double = 0, taperStart: Double = 0,
                taperEnd: Double = 0, taperSize: Double = 0.8, taperOpacity: Double = 0) {
        self.spacing = spacing
        self.streamline = streamline
        self.jitter = jitter
        self.falloff = falloff
        self.taperStart = taperStart
        self.taperEnd = taperEnd
        self.taperSize = taperSize
        self.taperOpacity = taperOpacity
    }

    var clamped: BrushStrokeSettings {
        var stroke = self
        stroke.spacing = spacing.clamped(0.02, 2)
        stroke.streamline = streamline.clamped(0, 1)
        stroke.jitter = jitter.clamped(0, 4)
        stroke.falloff = falloff.clamped(0, 1)
        stroke.taperStart = taperStart.clamped(0, 1)
        stroke.taperEnd = taperEnd.clamped(0, 1)
        stroke.taperSize = taperSize.clamped(0, 1)
        stroke.taperOpacity = taperOpacity.clamped(0, 1)
        return stroke
    }
}

/// How pressure, tilt and speed shape each stamp, and the randomness on top.
public struct BrushDynamics: Codable, Hashable, Sendable {
    /// Pressure → size and opacity (0 none … 1 all the way from the minimum).
    public var pressureSize: Double
    public var pressureOpacity: Double
    /// Maps raw Pencil pressure before it's used.
    public var pressureCurve: BrushCurve
    /// Tilting the Pencil over (shading with its side) grows or fades the stamp.
    public var tiltSize: Double
    public var tiltOpacity: Double
    /// Drawing fast thins (positive) or thickens (negative) the line, and fades or darkens it.
    public var speedSize: Double
    public var speedOpacity: Double
    public var sizeJitter: Double
    public var opacityJitter: Double
    /// The smallest a stamp gets at no pressure, as a fraction of the full size.
    public var minimumSize: Double
    public var minimumOpacity: Double

    public init(pressureSize: Double = 0.75, pressureOpacity: Double = 0, pressureCurve: BrushCurve = .linear, tiltSize: Double = 0,
                tiltOpacity: Double = 0, speedSize: Double = 0, speedOpacity: Double = 0, sizeJitter: Double = 0, opacityJitter: Double = 0,
                minimumSize: Double = 0.25, minimumOpacity: Double = 0.2) {
        self.pressureSize = pressureSize
        self.pressureOpacity = pressureOpacity
        self.pressureCurve = pressureCurve
        self.tiltSize = tiltSize
        self.tiltOpacity = tiltOpacity
        self.speedSize = speedSize
        self.speedOpacity = speedOpacity
        self.sizeJitter = sizeJitter
        self.opacityJitter = opacityJitter
        self.minimumSize = minimumSize
        self.minimumOpacity = minimumOpacity
    }

    var clamped: BrushDynamics {
        var dynamics = self
        dynamics.pressureSize = pressureSize.clamped(0, 1)
        dynamics.pressureOpacity = pressureOpacity.clamped(0, 1)
        dynamics.pressureCurve = pressureCurve.clamped
        dynamics.tiltSize = tiltSize.clamped(0, 1)
        dynamics.tiltOpacity = tiltOpacity.clamped(0, 1)
        dynamics.speedSize = speedSize.clamped(-1, 1)
        dynamics.speedOpacity = speedOpacity.clamped(-1, 1)
        dynamics.sizeJitter = sizeJitter.clamped(0, 1)
        dynamics.opacityJitter = opacityJitter.clamped(0, 1)
        dynamics.minimumSize = minimumSize.clamped(0, 1)
        dynamics.minimumOpacity = minimumOpacity.clamped(0, 1)
        return dynamics
    }
}

/// How the stamps meet the canvas.
public struct BrushRendering: Codable, Hashable, Sendable {
    /// Each stamp's opacity: low flow builds up where stamps overlap (an airbrush).
    public var flow: Double
    /// Darker rims, as if the paint pooled at the edge (0 none … 1 strong).
    public var wetEdges: Double
    /// Stamps soften at the edge by this much (anti-aliasing for hard tips is always on).
    public var softness: Double

    public init(flow: Double = 1, wetEdges: Double = 0, softness: Double = 0) {
        self.flow = flow
        self.wetEdges = wetEdges
        self.softness = softness
    }

    var clamped: BrushRendering {
        var rendering = self
        rendering.flow = flow.clamped(0.01, 1)
        rendering.wetEdges = wetEdges.clamped(0, 1)
        rendering.softness = softness.clamped(0, 1)
        return rendering
    }
}

/// Where a brush came from: shown in Brush Studio's About, kept through duplicates, imports and shares.
public struct BrushAbout: Codable, Hashable, Sendable {
    public enum Origin: String, Codable, Sendable {
        case builtIn, made, procreate, photoshop, shared
    }

    public var origin: Origin
    public var author: String?
    /// The built-in brush it started from, so Reset can bring it back.
    public var resetsTo: String?

    public init(origin: Origin = .made, author: String? = nil, resetsTo: String? = nil) {
        self.origin = origin
        self.author = author
        self.resetsTo = resetsTo
    }
}

/// A response curve through points in 0…1 (x in, y out), linear between them; x rises.
public struct BrushCurve: Codable, Hashable, Sendable {
    public var points: [Vec2]

    public init(_ points: [Vec2]) {
        self.points = points
    }

    public static let linear = BrushCurve([Vec2(0, 0), Vec2(1, 1)])
    /// Light touches count for more (a soft pencil).
    public static let soft = BrushCurve([Vec2(0, 0), Vec2(0.35, 0.6), Vec2(1, 1)])
    /// Only firm presses count (a stiff pen).
    public static let firm = BrushCurve([Vec2(0, 0), Vec2(0.6, 0.35), Vec2(1, 1)])

    public func value(at x: Double) -> Double {
        let x = x.clamped(0, 1)
        guard let first = points.first, let last = points.last else { return x }
        if x <= first.x { return first.y.clamped(0, 1) }
        if x >= last.x { return last.y.clamped(0, 1) }
        for (a, b) in zip(points, points.dropFirst()) where x <= b.x {
            let span = b.x - a.x
            let t = span > 1e-9 ? (x - a.x) / span : 1
            return (a.y + (b.y - a.y) * t).clamped(0, 1)
        }
        return last.y.clamped(0, 1)
    }

    /// Sorted, inside the unit square, at least the two ends.
    public var clamped: BrushCurve {
        let kept = points.map { Vec2($0.x.clamped(0, 1), $0.y.clamped(0, 1)) }.sorted { $0.x < $1.x }
        return kept.count >= 2 ? BrushCurve(kept) : .linear
    }
}

public extension Double {
    /// Inside `lower…upper` (the lower bound for anything that isn't a number).
    func clamped(_ lower: Double, _ upper: Double) -> Double {
        guard isFinite else { return lower }
        return Swift.min(Swift.max(self, lower), upper)
    }
}
