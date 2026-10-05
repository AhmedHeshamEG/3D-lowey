import Foundation

/// A flat drawing on a surface or a guide plane: lines, rectangles, circles, arcs, splines and offsets. Closed
/// shapes fill into regions, and a region can be pulled into a solid or cut into the face it was drawn on. Sketches
/// are construction lines: the stage draws them, exports and renders never do.
public struct Sketch: Codable, Hashable, Sendable {
    /// The sketch's plane in world space (the sketch object stays at the origin).
    public var plane: PlaneFrame
    public var curves: [SketchCurve]
    /// The object whose face it was drawn on (pulling a region in or out changes that object).
    public var target: ObjectID?

    public init(plane: PlaneFrame, curves: [SketchCurve] = [], target: ObjectID? = nil) {
        self.plane = plane
        self.curves = curves
        self.target = target
    }

    /// Every curve as a polyline in plane coordinates, with whether it closes on itself.
    public var polylines: [(points: [Vec2], closed: Bool)] {
        curves.map { ($0.points, $0.isClosed) }
    }

    /// The closed loops: closed curves, plus open curves joined end to end into a loop.
    public var loops: [[Vec2]] {
        var loops = curves.filter(\.isClosed).map(\.points)
        loops += SketchLoops.chain(curves.filter { !$0.isClosed }.map(\.points), tolerance: tolerance)
        return loops.filter { $0.count >= 3 && abs(PolygonTriangulator.signedArea($0)) > tolerance * tolerance }
    }

    /// Fillable regions: each loop with the loops directly inside it as holes (a circle in a rectangle gives the
    /// rectangle with a hole, and the disc on its own), outlines counter-clockwise and holes clockwise.
    public var regions: [SketchRegion] {
        SketchLoops.regions(loops)
    }

    /// The smallest region containing a point of the plane.
    public func region(at point: Vec2) -> Int? {
        let regions = regions
        return regions.indices.filter { regions[$0].contains(point) }.min { regions[$0].area < regions[$1].area }
    }

    /// Lengths in the sketch below this are the same point (a micrometre, or less for tiny sketches).
    var tolerance: Double {
        let extent = curves.flatMap(\.points).reduce(0.0) { max($0, abs($1.x), abs($1.y)) }
        return max(extent, 1e-3) * 1e-6
    }

    /// A curve in the world, for an array to follow: the longest one when none is given.
    public func path(of curve: Int? = nil) -> (points: [Vec3], closed: Bool)? {
        let lengths = curves.map { curve -> Double in
            let points = curve.points
            return zip(points, points.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0).length }
        }
        guard let index = curve ?? lengths.indices.max(by: { lengths[$0] < lengths[$1] }), curves.indices.contains(index) else { return nil }
        return (curves[index].points.map { plane.lift($0) }, curves[index].isClosed)
    }

    // MARK: Pulling

    /// The solid a region sweeps when pulled `distance` along the plane's normal (negative goes below it).
    public func prism(of region: SketchRegion, distance: Double) -> EditableMesh {
        prism(of: region, from: 0, to: distance)
    }

    /// The solid a region sweeps between two heights above the plane.
    public func prism(of region: SketchRegion, from start: Double, to end: Double) -> EditableMesh {
        Prism.make(outline: region.outline.map { plane.lift($0) }, holes: region.holes.map { $0.map { plane.lift($0) } },
                   normal: plane.normal, from: start, to: end)
    }

    /// The sketch without the curves that made a region (pulled regions are used up, like Shapr3D).
    public func removing(_ region: SketchRegion) -> Sketch {
        var copy = self
        copy.curves = curves.filter { curve in
            let points = curve.points
            return !points.allSatisfy { point in
                ([region.outline] + region.holes).contains { loop in SketchLoops.onLoop(point, loop, tolerance: tolerance * 10) }
            }
        }
        return copy
    }
}

/// A closed area of a sketch, in plane coordinates.
public struct SketchRegion: Hashable, Sendable {
    public var outline: [Vec2]
    public var holes: [[Vec2]]

    public var area: Double {
        abs(PolygonTriangulator.signedArea(outline)) - holes.reduce(0) { $0 + abs(PolygonTriangulator.signedArea($1)) }
    }

    public func contains(_ point: Vec2) -> Bool {
        Outlines.contains(outline, point) && !holes.contains { Outlines.contains($0, point) }
    }

    /// Triangles over `outline + holes` (concatenated), for filling it on screen.
    public var triangles: [(Int, Int, Int)] {
        let corners: [PolygonTriangulator.Corner] = outline.enumerated().map { ($0.offset, $0.element) }
        var holeCorners: [[PolygonTriangulator.Corner]] = []
        var next = outline.count
        for hole in holes {
            holeCorners.append(hole.map { point in
                defer { next += 1 }
                return (next, point)
            })
        }
        return PolygonTriangulator.triangulate(outline: corners, holes: holeCorners)
    }
}

/// One drawn curve, in plane coordinates (metres).
public enum SketchCurve: Codable, Hashable, Sendable {
    case line(Vec2, Vec2)
    case rectangle(Vec2, Vec2)
    case circle(center: Vec2, radius: Double)
    /// Through three points: start, a point on the arc, end.
    case arc(Vec2, Vec2, Vec2)
    /// A smooth curve through the points (Catmull-Rom).
    case spline([Vec2], closed: Bool)
    /// Straight segments through the points (offsets of closed shapes, chained lines).
    case polyline([Vec2], closed: Bool)

    public var isClosed: Bool {
        switch self {
        case .rectangle, .circle: true
        case let .spline(_, closed), let .polyline(_, closed): closed
        case .line, .arc: false
        }
    }

    /// Segments a full circle is drawn and cut with.
    public static let circleSegments = 64

    public var points: [Vec2] {
        switch self {
        case let .line(a, b): [a, b]
        case let .rectangle(a, b): [a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)]
        case let .circle(center, radius):
            (0 ..< Self.circleSegments).map { index in
                let angle = Double(index) / Double(Self.circleSegments) * 2 * .pi
                return Vec2(center.x + cos(angle) * radius, center.y + sin(angle) * radius)
            }
        case let .arc(start, through, end): SketchArc(start, through, end)?.points ?? [start, end]
        case let .spline(points, closed): SketchSpline.sample(points, closed: closed)
        case let .polyline(points, _): points
        }
    }

    /// The curve moved outward (positive) or inward (negative) by `distance`, as a new curve. Closed shapes stay
    /// closed; open ones keep their side (left of their direction is outward).
    public func offset(by distance: Double) -> SketchCurve? {
        switch self {
        case let .circle(center, radius):
            return radius + distance > 1e-9 ? .circle(center: center, radius: radius + distance) : nil
        case let .rectangle(a, b):
            let lo = Vec2(min(a.x, b.x) - distance, min(a.y, b.y) - distance)
            let hi = Vec2(max(a.x, b.x) + distance, max(a.y, b.y) + distance)
            return hi.x - lo.x > 1e-9 && hi.y - lo.y > 1e-9 ? .rectangle(lo, hi) : nil
        default:
            let shifted = SketchOffset.offset(points, closed: isClosed, distance: distance)
            return shifted.count >= 2 ? .polyline(shifted, closed: isClosed) : nil
        }
    }
}
