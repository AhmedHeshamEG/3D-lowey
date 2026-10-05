import Foundation

/// Loops and regions of a sketch.
enum SketchLoops {
    /// Joins open curves whose ends meet into closed loops (a run of lines drawn corner to corner).
    static func chain(_ pieces: [[Vec2]], tolerance: Double) -> [[Vec2]] {
        var remaining = pieces.filter { $0.count >= 2 }
        var loops: [[Vec2]] = []
        while let first = remaining.first {
            remaining.removeFirst()
            var path = first
            var grew = true
            while grew, !closes(path, tolerance) {
                grew = false
                guard let end = path.last else { break }
                for (index, piece) in remaining.enumerated() {
                    if let start = piece.first, near(start, end, tolerance) {
                        path += piece.dropFirst()
                    } else if let last = piece.last, near(last, end, tolerance) {
                        path += piece.reversed().dropFirst()
                    } else {
                        continue
                    }
                    remaining.remove(at: index)
                    grew = true
                    break
                }
            }
            if closes(path, tolerance) { loops.append(Array(path.dropLast())) }
        }
        return loops
    }

    static func closes(_ path: [Vec2], _ tolerance: Double) -> Bool {
        guard path.count >= 4, let first = path.first, let last = path.last else { return false }
        return near(first, last, tolerance)
    }

    static func near(_ a: Vec2, _ b: Vec2, _ tolerance: Double) -> Bool {
        (a - b).length <= tolerance
    }

    /// Each loop with the loops directly inside it as holes.
    static func regions(_ loops: [[Vec2]]) -> [SketchRegion] {
        let oriented = loops.map { PolygonTriangulator.signedArea($0) < 0 ? Array($0.reversed()) : $0 }
        let areas = oriented.map { abs(PolygonTriangulator.signedArea($0)) }
        // A loop's parent: the smallest other loop that contains it.
        let parents = oriented.indices.map { index -> Int? in
            oriented.indices.filter { other in
                other != index && areas[other] > areas[index] && oriented[index].allSatisfy { Outlines.contains(oriented[other], $0) }
            }.min { areas[$0] < areas[$1] }
        }
        return oriented.indices.map { index in
            let holes = oriented.indices.filter { parents[$0] == index }.map { Array(oriented[$0].reversed()) }
            return SketchRegion(outline: oriented[index], holes: holes)
        }
    }

    /// Whether a point lies on a loop's outline.
    static func onLoop(_ point: Vec2, _ loop: [Vec2], tolerance: Double) -> Bool {
        loop.indices.contains { index in
            let a = loop[index], b = loop[(index + 1) % loop.count]
            let ab = b - a
            let lengthSquared = ab.x * ab.x + ab.y * ab.y
            guard lengthSquared > 0 else { return (point - a).length <= tolerance }
            let t = min(max(((point.x - a.x) * ab.x + (point.y - a.y) * ab.y) / lengthSquared, 0), 1)
            return (point - (a + ab * t)).length <= tolerance
        }
    }
}

/// A circular arc through three points.
struct SketchArc {
    let center: Vec2
    let radius: Double
    let start: Double
    let sweep: Double

    init?(_ a: Vec2, _ b: Vec2, _ c: Vec2) {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > 1e-18 else { return nil }
        let a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y
        let center = Vec2((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
                          (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
        self.center = center
        radius = (a - center).length
        let angleA = atan2(a.y - center.y, a.x - center.x)
        let angleB = atan2(b.y - center.y, b.x - center.x)
        let angleC = atan2(c.y - center.y, c.x - center.x)
        // Counter-clockwise from a to c; if b isn't on that way round, go clockwise.
        let ccwToC = Self.wrap(angleC - angleA), ccwToB = Self.wrap(angleB - angleA)
        start = angleA
        sweep = ccwToB <= ccwToC ? ccwToC : ccwToC - 2 * .pi
    }

    var points: [Vec2] {
        let count = max(Int(abs(sweep) / (2 * .pi) * Double(SketchCurve.circleSegments)), 2)
        return (0 ... count).map { index in
            let angle = start + sweep * Double(index) / Double(count)
            return Vec2(center.x + cos(angle) * radius, center.y + sin(angle) * radius)
        }
    }

    static func wrap(_ angle: Double) -> Double {
        var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if value < 0 { value += 2 * .pi }
        return value
    }
}

/// Catmull-Rom through control points.
enum SketchSpline {
    static let samplesPerSpan = 12

    static func sample(_ points: [Vec2], closed: Bool) -> [Vec2] {
        guard points.count >= 3 else { return points }
        let count = points.count
        func point(_ index: Int) -> Vec2 {
            closed ? points[(index % count + count) % count] : points[min(max(index, 0), count - 1)]
        }
        let spans = closed ? count : count - 1
        var result: [Vec2] = []
        for span in 0 ..< spans {
            let p0 = point(span - 1), p1 = point(span), p2 = point(span + 1), p3 = point(span + 2)
            for step in 0 ..< samplesPerSpan {
                let t = Double(step) / Double(samplesPerSpan)
                let t2 = t * t, t3 = t2 * t
                let x = 0.5 * (2 * p1.x + (p2.x - p0.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                    + (3 * p1.x - p0.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * (2 * p1.y + (p2.y - p0.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                    + (3 * p1.y - p0.y - 3 * p2.y + p3.y) * t3)
                result.append(Vec2(x, y))
            }
        }
        if !closed, let last = points.last { result.append(last) }
        return result
    }
}

/// Offsetting a polyline: each segment moves sideways, corners meet at the mitre (capped so sharp corners don't
/// shoot out).
enum SketchOffset {
    static func offset(_ points: [Vec2], closed: Bool, distance: Double) -> [Vec2] {
        guard points.count >= 2 else { return points }
        // Outward is to the right of a counter-clockwise loop's direction.
        let sign: Double = closed && PolygonTriangulator.signedArea(points) < 0 ? -1 : 1
        let count = points.count
        func normal(_ a: Vec2, _ b: Vec2) -> Vec2 {
            let d = b - a
            let scale: Double = sign * distance / Swift.max(d.length, 1e-300)
            return Vec2(d.y * scale, -d.x * scale)
        }
        return (0 ..< count).map { index in
            let hasPrev = closed || index > 0, hasNext = closed || index < count - 1
            let here = points[index]
            let prevNormal = hasPrev ? normal(points[(index - 1 + count) % count], here) : nil
            let nextNormal = hasNext ? normal(here, points[(index + 1) % count]) : nil
            switch (prevNormal, nextNormal) {
            case let (p?, n?):
                let sum = p + n
                let sumLength = sum.length
                guard sumLength > 1e-300 else { return here + n }
                // Mitre: along the bisector, long enough that both segments move by `distance`.
                let bisector = sum * (1 / sumLength)
                let cosHalf = (bisector.x * n.x + bisector.y * n.y) / abs(distance)
                let mitre = abs(distance) / max(cosHalf, 0.25)
                return here + bisector * mitre
            case let (p?, nil): return here + p
            case let (nil, n?): return here + n
            default: return here
            }
        }
    }
}
