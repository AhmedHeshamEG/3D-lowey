import Foundation

/// A drawing guide (Procreate's Drawing Guide): a 2D grid, an isometric grid, 1/2/3-point perspective or symmetry,
/// with Drawing Assist pulling strokes onto it. Coordinates are a plane's: a flipbook's units (frame heights from the
/// centre, y up) on the frame, or metres along a 3D guide plane's two axes on the stage.
public struct DrawingGuide: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case grid, isometric, perspective, symmetry
    }

    public enum Symmetry: String, Codable, Sendable, CaseIterable {
        /// Mirrored left ↔ right across the vertical axis.
        case vertical
        case horizontal
        /// Both axes: four copies.
        case quadrant
        /// Copies turned around the centre (`segments`), mirrored too when `mirrorRadial`.
        case radial
    }

    public var kind: Kind
    /// Strokes snap to the guide (grid, isometric, perspective) or are mirrored (symmetry).
    public var assisted: Bool
    /// Grid size, in the plane's units.
    public var spacing: Double
    /// The grid's origin, the symmetry's centre.
    public var origin: Vec2
    /// Degrees the grid or the symmetry's axes turn.
    public var angle: Double
    /// 1, 2 or 3 vanishing points (perspective).
    public var vanishingPoints: [Vec2]
    public var symmetry: Symmetry
    public var segments: Int
    public var mirrorRadial: Bool

    public init(kind: Kind = .grid, assisted: Bool = true, spacing: Double = 0.05, origin: Vec2 = Vec2(0, 0), angle: Double = 0,
                vanishingPoints: [Vec2] = [Vec2(0, 0.1)], symmetry: Symmetry = .vertical, segments: Int = 6, mirrorRadial: Bool = false) {
        self.kind = kind
        self.assisted = assisted
        self.spacing = spacing
        self.origin = origin
        self.angle = angle
        self.vanishingPoints = vanishingPoints
        self.symmetry = symmetry
        self.segments = segments
        self.mirrorRadial = mirrorRadial
    }

    /// Two-point perspective with its points on a horizon a little above the middle.
    public static func perspective(points count: Int) -> DrawingGuide {
        let points: [Vec2] = switch count {
        case 1: [Vec2(0, 0.1)]
        case 2: [Vec2(-0.9, 0.1), Vec2(0.9, 0.1)]
        default: [Vec2(-0.9, 0.15), Vec2(0.9, 0.15), Vec2(0, -1.6)]
        }
        return DrawingGuide(kind: .perspective, vanishingPoints: points)
    }

    var radians: Double { angle * .pi / 180 }

    /// Unit direction at `degrees` from the guide's angle.
    func axis(_ degrees: Double) -> Vec2 {
        let a = radians + degrees * .pi / 180
        return Vec2(cos(a), sin(a))
    }
}

/// Drawing Assist and symmetry: pure functions over a stroke's points in the guide's plane.
public enum GuideAssist {
    /// The stroke pulled onto the guide: a straight line along the guide direction nearest the way it was drawn
    /// (grid: its two axes; isometric: three; perspective: toward each vanishing point, plus level and upright lines for
    /// one and two points). Symmetry and unassisted guides leave it as drawn.
    public static func constrained(_ points: [Vec2], guide: DrawingGuide) -> [Vec2] {
        guard guide.assisted, guide.kind != .symmetry, let start = points.first, points.count > 1,
              let far = points.max(by: { ($0 - start).length < ($1 - start).length }), (far - start).length > 1e-9 else { return points }
        let drawn = (far - start) * (1 / (far - start).length)
        let directions = candidates(from: start, guide: guide)
        guard let best = directions.max(by: { abs(dot($0, drawn)) < abs(dot($1, drawn)) }) else { return points }
        return points.map { start + best * dot($0 - start, best) }
    }

    /// The directions a stroke starting at `start` may take.
    static func candidates(from start: Vec2, guide: DrawingGuide) -> [Vec2] {
        switch guide.kind {
        case .grid: return [guide.axis(0), guide.axis(90)]
        case .isometric: return [guide.axis(30), guide.axis(90), guide.axis(150)]
        case .symmetry: return []
        case .perspective:
            var directions = guide.vanishingPoints.compactMap { point -> Vec2? in
                let toward = point - start
                return toward.length > 1e-9 ? toward * (1 / toward.length) : nil
            }
            if guide.vanishingPoints.count < 3 { directions += [Vec2(1, 0), Vec2(0, 1)] }
            return directions
        }
    }

    /// Every copy a symmetry guide draws (the stroke itself first). Other guides return the stroke alone.
    public static func copies(_ points: [Vec2], guide: DrawingGuide) -> [[Vec2]] {
        guard guide.kind == .symmetry, guide.assisted else { return [points] }
        let origin = guide.origin
        let vertical = guide.axis(90), horizontal = guide.axis(0)
        func reflect(_ p: Vec2, across axis: Vec2) -> Vec2 {
            let d = p - origin
            return origin + axis * (2 * dot(d, axis)) - d
        }
        switch guide.symmetry {
        case .vertical:
            return [points, points.map { reflect($0, across: vertical) }]
        case .horizontal:
            return [points, points.map { reflect($0, across: horizontal) }]
        case .quadrant:
            let mirrored = points.map { reflect($0, across: vertical) }
            return [points, mirrored, points.map { reflect($0, across: horizontal) }, mirrored.map { reflect($0, across: horizontal) }]
        case .radial:
            let count = min(max(guide.segments, 2), 24)
            var result: [[Vec2]] = []
            for index in 0 ..< count {
                let turn = 2 * .pi * Double(index) / Double(count)
                let turned = points.map { rotate($0, around: origin, by: turn) }
                result.append(turned)
                if guide.mirrorRadial { result.append(turned.map { reflect($0, across: rotate(vertical, around: Vec2(0, 0), by: turn)) }) }
            }
            return result
        }
    }

    static func rotate(_ p: Vec2, around origin: Vec2, by angle: Double) -> Vec2 {
        let d = p - origin
        return origin + Vec2(d.x * cos(angle) - d.y * sin(angle), d.x * sin(angle) + d.y * cos(angle))
    }

    static func dot(_ a: Vec2, _ b: Vec2) -> Double { a.x * b.x + a.y * b.y }
}

/// The lines a guide shows inside a rectangle of its plane (the frame, or a 3D guide plane's extent).
public enum GuideLines {
    public struct Line: Hashable, Sendable {
        public var from: Vec2
        public var to: Vec2
        /// Axes, horizons and symmetry lines are drawn stronger.
        public var major: Bool

        public init(from: Vec2, to: Vec2, major: Bool) {
            self.from = from
            self.to = to
            self.major = major
        }
    }

    /// At most this many lines, so a tiny grid on a big plane stays cheap.
    static let maximum = 400

    public static func lines(_ guide: DrawingGuide, in rect: (min: Vec2, max: Vec2)) -> [Line] {
        let size = rect.max - rect.min
        let reach = size.length
        let center = rect.min + size * 0.5
        switch guide.kind {
        case .grid: return parallel(guide, angles: [0, 90], center: center, reach: reach)
        case .isometric: return parallel(guide, angles: [30, 90, 150], center: center, reach: reach)
        case .perspective: return perspective(guide, reach: reach, center: center)
        case .symmetry: return symmetry(guide, reach: reach)
        }
    }

    static func parallel(_ guide: DrawingGuide, angles: [Double], center: Vec2, reach: Double) -> [Line] {
        let spacing = max(guide.spacing, reach / Double(maximum / max(angles.count, 1)) * 2)
        var lines: [Line] = []
        for angle in angles {
            let along = guide.axis(angle), across = Vec2(-along.y, along.x)
            // Lines through the origin's grid, enough to cover the rect around its centre.
            let offset = GuideAssist.dot(center - guide.origin, across)
            let first = Int(((offset - reach) / spacing).rounded(.down)), last = Int(((offset + reach) / spacing).rounded(.up))
            for index in first ... last {
                let base = guide.origin + across * (Double(index) * spacing) + along * GuideAssist.dot(center - guide.origin, along)
                lines.append(Line(from: base - along * reach, to: base + along * reach, major: index == 0))
            }
        }
        return lines
    }

    static func perspective(_ guide: DrawingGuide, reach: Double, center: Vec2) -> [Line] {
        var lines: [Line] = []
        let far = reach * 3 + guide.vanishingPoints.map { ($0 - center).length }.reduce(0, max)
        for point in guide.vanishingPoints {
            for index in 0 ..< 36 {
                let angle = Double(index) / 36 * 2 * .pi
                lines.append(Line(from: point, to: point + Vec2(cos(angle), sin(angle)) * far, major: false))
            }
        }
        if guide.vanishingPoints.count >= 2 {
            let a = guide.vanishingPoints[0], b = guide.vanishingPoints[1]
            let direction = (b - a).length > 1e-9 ? (b - a) * (1 / (b - a).length) : Vec2(1, 0)
            lines.append(Line(from: a - direction * far, to: a + direction * far, major: true))
        } else if let point = guide.vanishingPoints.first {
            lines.append(Line(from: point - Vec2(far, 0), to: point + Vec2(far, 0), major: true))
        }
        return lines
    }

    static func symmetry(_ guide: DrawingGuide, reach: Double) -> [Line] {
        let o = guide.origin
        func axis(_ degrees: Double) -> Line {
            let d = guide.axis(degrees)
            return Line(from: o - d * reach, to: o + d * reach, major: true)
        }
        switch guide.symmetry {
        case .vertical: return [axis(90)]
        case .horizontal: return [axis(0)]
        case .quadrant: return [axis(0), axis(90)]
        case .radial:
            let count = min(max(guide.segments, 2), 24)
            return (0 ..< count).map { index in
                let d = guide.axis(90 + 360 * Double(index) / Double(count))
                return Line(from: o, to: o + d * reach, major: true)
            }
        }
    }
}
