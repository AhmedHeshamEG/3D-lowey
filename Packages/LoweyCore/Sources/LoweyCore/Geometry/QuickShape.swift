import Foundation

/// Draw, then hold: the stroke becomes the clean shape it was meant to be (Procreate's QuickShape).
/// Works on the stroke's screen points, so the result lands on whatever guide the stroke was drawn on.
public enum QuickShape {
    public enum Kind: String, Sendable, CaseIterable {
        case line, arc, polyline, circle, ellipse, triangle, rectangle

        public var title: String {
            switch self {
            case .line: "Line"
            case .arc: "Arc"
            case .polyline: "Polyline"
            case .circle: "Circle"
            case .ellipse: "Ellipse"
            case .triangle: "Triangle"
            case .rectangle: "Rectangle"
            }
        }
    }

    public struct Result: Sendable, Equatable {
        public var kind: Kind
        /// Densely sampled along the ideal shape; closed shapes end where they start.
        public var points: [Vec2]
        /// Where resizing and turning pivot (the centre of a closed shape, the start of an open one).
        public var pivot: Vec2

        public var isClosed: Bool { [.circle, .ellipse, .triangle, .rectangle].contains(kind) }
    }

    /// The shape `stroke` looks like, or nil for a free scribble (it stays as drawn).
    public static func fit(_ stroke: [Vec2]) -> Result? {
        let points = dedupe(stroke)
        guard points.count >= 2 else { return nil }
        let length = pathLength(points)
        guard length >= 16, let first = points.first, let last = points.last else { return nil }
        if points.count < 4 {
            return line(first, last)
        }
        let chord = (last - first).length
        let size = boundsDiagonal(points)
        let closed = length > 60 && chord < max(0.2 * length, 0.15 * size)
        return closed ? fitClosed(points, size: size) : fitOpen(points, length: length, chord: chord)
    }

    /// The shape after the finger moved from `anchor` (where it snapped) to `current`, still holding:
    /// a line's end follows the finger; anything else turns and scales about its pivot.
    public static func adjusted(_ result: Result, anchor: Vec2, current: Vec2) -> Result {
        if result.kind == .line, let start = result.points.first {
            var moved = line(start, current)
            moved.pivot = start
            return moved
        }
        let from = anchor - result.pivot
        let to = current - result.pivot
        guard from.length > 4 else { return result }
        let scale = min(max(to.length / from.length, 0.1), 10)
        let turn = atan2(to.y, to.x) - atan2(from.y, from.x)
        let c = cos(turn)
        let s = sin(turn)
        var copy = result
        copy.points = result.points.map { point in
            let v = point - result.pivot
            return result.pivot + Vec2((v.x * c - v.y * s) * scale, (v.x * s + v.y * c) * scale)
        }
        return copy
    }

    // MARK: Open strokes

    private static func fitOpen(_ points: [Vec2], length: Double, chord: Double) -> Result? {
        guard let first = points.first, let last = points.last else { return nil }
        // Straight: every point close to the chord.
        let deviation = points.map { distance($0, toSegment: first, last) }.max() ?? 0
        if chord > 0, deviation / chord < 0.06 {
            return line(first, last)
        }
        // Corners: a few straight pieces (an L, a V, a zigzag).
        let corners = simplify(points, epsilon: max(0.045 * length, 4))
        if corners.count >= 3, corners.count <= 6, straightPieces(points, corners: corners, tolerance: 0.07) {
            return polyline(corners)
        }
        // A bend of constant curvature.
        if let circle = circleFit(points), circle.radius < 6 * max(chord, 1) {
            let error = rms(points.map { abs(($0 - circle.center).length - circle.radius) })
            if error / circle.radius < 0.07 {
                return arc(points, center: circle.center, radius: circle.radius)
            }
        }
        return nil
    }

    // MARK: Closed strokes

    private static func fitClosed(_ points: [Vec2], size: Double) -> Result? {
        let ring = closedCorners(points, epsilon: max(0.07 * size, 4))
        if ring.count == 3 {
            return polygon(ring, kind: .triangle)
        }
        if ring.count == 4, let rectangle = rectangle(ring) {
            return rectangle
        }
        guard let ellipse = ellipseFit(points) else { return nil }
        let error = rms(points.map { point -> Double in
            let v = point - ellipse.center
            let u = (v.x * ellipse.axis.x + v.y * ellipse.axis.y) / ellipse.a
            let w = (-v.x * ellipse.axis.y + v.y * ellipse.axis.x) / ellipse.b
            return abs((u * u + w * w).squareRoot() - 1)
        })
        guard error < 0.16 else { return nil }
        let round = ellipse.b / ellipse.a > 0.85
        let a = round ? (ellipse.a + ellipse.b) / 2 : ellipse.a
        let b = round ? a : ellipse.b
        let steps = 72
        var outline: [Vec2] = []
        // Start where the stroke started, going the way it went (so pressure and taper follow the hand).
        let start = points[0] - ellipse.center
        let startAngle = atan2((-start.x * ellipse.axis.y + start.y * ellipse.axis.x) / b, (start.x * ellipse.axis.x + start.y * ellipse.axis.y) / a)
        let direction: Double = signedArea(points) >= 0 ? 1 : -1
        for index in 0 ... steps {
            let t = startAngle + direction * 2 * .pi * Double(index) / Double(steps)
            let u = cos(t) * a
            let w = sin(t) * b
            outline.append(ellipse.center + Vec2(u * ellipse.axis.x - w * ellipse.axis.y, u * ellipse.axis.y + w * ellipse.axis.x))
        }
        return Result(kind: round ? .circle : .ellipse, points: outline, pivot: ellipse.center)
    }

    /// Four corners that are nearly right angles become an exact rectangle (sides averaged, square corners).
    private static func rectangle(_ corners: [Vec2]) -> Result? {
        for index in 0 ..< 4 {
            let a = corners[(index + 3) % 4] - corners[index]
            let b = corners[(index + 1) % 4] - corners[index]
            let cosine = dot(a, b) / max(a.length * b.length, 1e-9)
            if abs(cosine) > 0.42 { return nil } // not near 90°: leave it to the ellipse
        }
        let center = corners.reduce(Vec2(0, 0), +) * 0.25
        let edge = corners[1] - corners[0]
        let axis = edge * (1 / max(edge.length, 1e-9))
        let normal = Vec2(-axis.y, axis.x)
        let width = ((corners[1] - corners[0]).length + (corners[2] - corners[3]).length) / 2
        let height = ((corners[3] - corners[0]).length + (corners[2] - corners[1]).length) / 2
        // Keep the drawing direction: which side of the first edge the rectangle lies on.
        let side: Double = dot(corners[3] - corners[0], normal) >= 0 ? 1 : -1
        let origin = center - axis * (width / 2) - normal * (side * height / 2)
        let square = [origin, origin + axis * width, origin + axis * width + normal * (side * height), origin + normal * (side * height)]
        return polygon(square, kind: .rectangle)
    }

    // MARK: Output shapes

    private static func line(_ start: Vec2, _ end: Vec2) -> Result {
        let steps = 24
        let points = (0 ... steps).map { start + (end - start) * (Double($0) / Double(steps)) }
        return Result(kind: .line, points: points, pivot: start)
    }

    private static func polyline(_ corners: [Vec2]) -> Result {
        Result(kind: .polyline, points: densify(corners, closed: false), pivot: corners[0])
    }

    private static func polygon(_ corners: [Vec2], kind: Kind) -> Result {
        let center = corners.reduce(Vec2(0, 0), +) * (1 / Double(corners.count))
        return Result(kind: kind, points: densify(corners, closed: true), pivot: center)
    }

    private static func arc(_ points: [Vec2], center: Vec2, radius: Double) -> Result? {
        guard let first = points.first, let last = points.last else { return nil }
        // Unwrap the angle along the stroke to know how far, and which way, it turned.
        var sweep = 0.0
        var previous = atan2(first.y - center.y, first.x - center.x)
        for point in points.dropFirst() {
            let angle = atan2(point.y - center.y, point.x - center.x)
            var delta = angle - previous
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            sweep += delta
            previous = angle
        }
        guard abs(sweep) > 0.35, abs(sweep) < 1.9 * .pi else { return nil }
        let start = atan2(first.y - center.y, first.x - center.x)
        let steps = max(Int(abs(sweep) / (2 * .pi) * 72), 12)
        var outline = (0 ... steps).map { index -> Vec2 in
            let t = start + sweep * Double(index) / Double(steps)
            return center + Vec2(cos(t) * radius, sin(t) * radius)
        }
        // End exactly where the circle passes nearest the stroke's end.
        outline[outline.count - 1] = center + (last - center) * (radius / max((last - center).length, 1e-9))
        return Result(kind: .arc, points: outline, pivot: first)
    }

    private static func densify(_ corners: [Vec2], closed: Bool) -> [Vec2] {
        let ring = closed ? corners + [corners[0]] : corners
        var out: [Vec2] = []
        for index in 0 ..< ring.count - 1 {
            let a = ring[index]
            let b = ring[index + 1]
            let steps = 12
            for step in 0 ..< steps {
                out.append(a + (b - a) * (Double(step) / Double(steps)))
            }
        }
        out.append(ring[ring.count - 1])
        return out
    }

    // MARK: Fitting

    private struct Ellipse {
        var center: Vec2
        /// Unit vector of the major axis.
        var axis: Vec2
        var a: Double
        var b: Double
    }

    /// Principal axes of the outline (points resampled evenly first, so slow parts don't weigh more).
    private static func ellipseFit(_ stroke: [Vec2]) -> Ellipse? {
        let points = resample(stroke, count: 96)
        let n = Double(points.count)
        let center = points.reduce(Vec2(0, 0), +) * (1 / n)
        var sxx = 0.0
        var syy = 0.0
        var sxy = 0.0
        for point in points {
            let v = point - center
            sxx += v.x * v.x
            syy += v.y * v.y
            sxy += v.x * v.y
        }
        sxx /= n
        syy /= n
        sxy /= n
        let trace = sxx + syy
        let det = sxx * syy - sxy * sxy
        let root = max(trace * trace / 4 - det, 0).squareRoot()
        let major = trace / 2 + root
        let minor = max(trace / 2 - root, 0)
        guard major > 1e-6 else { return nil }
        let direction = abs(sxy) > 1e-9 ? Vec2(major - syy, sxy) : (sxx >= syy ? Vec2(1, 0) : Vec2(0, 1))
        let axis = direction * (1 / max(direction.length, 1e-12))
        // Points spread evenly around an ellipse have variance a²/2 along its major axis.
        return Ellipse(center: center, axis: axis, a: (2 * major).squareRoot(), b: max((2 * minor).squareRoot(), 1e-6))
    }

    /// Least-squares circle (Kåsa).
    private static func circleFit(_ points: [Vec2]) -> (center: Vec2, radius: Double)? {
        let n = Double(points.count)
        let mean = points.reduce(Vec2(0, 0), +) * (1 / n)
        var suu = 0.0, svv = 0.0, suv = 0.0, suuu = 0.0, svvv = 0.0, suvv = 0.0, svuu = 0.0
        for point in points {
            let u = point.x - mean.x
            let v = point.y - mean.y
            suu += u * u
            svv += v * v
            suv += u * v
            suuu += u * u * u
            svvv += v * v * v
            suvv += u * v * v
            svuu += v * u * u
        }
        let det = suu * svv - suv * suv
        guard abs(det) > 1e-9 else { return nil }
        let bu = 0.5 * (suuu + suvv)
        let bv = 0.5 * (svvv + svuu)
        let uc = (bu * svv - bv * suv) / det
        let vc = (suu * bv - suv * bu) / det
        let radius = (uc * uc + vc * vc + (suu + svv) / n).squareRoot()
        guard radius.isFinite, radius > 0 else { return nil }
        return (Vec2(mean.x + uc, mean.y + vc), radius)
    }

    /// Corners of a closed outline: split at the point farthest from the start, simplify both halves.
    private static func closedCorners(_ points: [Vec2], epsilon: Double) -> [Vec2] {
        guard let start = points.first else { return [] }
        let far = points.indices.max { (points[$0] - start).length < (points[$1] - start).length } ?? 0
        guard far > 0, far < points.count - 1 else { return [] }
        let first = simplify(Array(points[0 ... far]), epsilon: epsilon)
        let second = simplify(Array(points[far...]) + [start], epsilon: epsilon)
        var ring = first + second.dropFirst().dropLast()
        // The stroke's start is rarely a real corner: drop it when the outline runs straight through it.
        if ring.count > 3 {
            let previous = ring[ring.count - 1]
            let next = ring[1]
            if distance(ring[0], toSegment: previous, next) < epsilon {
                ring.removeFirst()
            }
        }
        return ring
    }

    /// Ramer–Douglas–Peucker.
    static func simplify(_ points: [Vec2], epsilon: Double) -> [Vec2] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var farthest = 0
        var worst = 0.0
        for index in 1 ..< points.count - 1 {
            let d = distance(points[index], toSegment: first, last)
            if d > worst {
                worst = d
                farthest = index
            }
        }
        guard worst > epsilon else { return [first, last] }
        let left = simplify(Array(points[0 ... farthest]), epsilon: epsilon)
        let right = simplify(Array(points[farthest...]), epsilon: epsilon)
        return left + right.dropFirst()
    }

    /// Every stretch between two corners is close to straight.
    private static func straightPieces(_ points: [Vec2], corners: [Vec2], tolerance: Double) -> Bool {
        var cornerIndex = 1
        var worst = 0.0
        var segmentStart = corners[0]
        for point in points {
            guard cornerIndex < corners.count else { break }
            let segmentEnd = corners[cornerIndex]
            let d = distance(point, toSegment: segmentStart, segmentEnd)
            worst = max(worst, d / max((segmentEnd - segmentStart).length, 1))
            if point == segmentEnd {
                segmentStart = segmentEnd
                cornerIndex += 1
            }
        }
        return worst < tolerance
    }

    // MARK: Small helpers

    private static func dedupe(_ points: [Vec2]) -> [Vec2] {
        var out: [Vec2] = []
        for point in points where out.last.map({ ($0 - point).length >= 0.5 }) ?? true {
            out.append(point)
        }
        return out
    }

    private static func resample(_ points: [Vec2], count: Int) -> [Vec2] {
        let total = pathLength(points)
        guard total > 0, points.count > 1 else { return points }
        var out: [Vec2] = [points[0]]
        let step = total / Double(count - 1)
        var carried = 0.0
        for index in 1 ..< points.count {
            var a = points[index - 1]
            let b = points[index]
            var segment = (b - a).length
            while carried + segment >= step, segment > 0 {
                let t = (step - carried) / segment
                let next = a + (b - a) * t
                a = next
                out.append(a)
                segment = (b - a).length
                carried = 0
            }
            carried += segment
        }
        while out.count < count, let last = points.last {
            out.append(last)
        }
        return Array(out.prefix(count))
    }

    static func pathLength(_ points: [Vec2]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0).length }
    }

    private static func boundsDiagonal(_ points: [Vec2]) -> Double {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return Vec2((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0)).length
    }

    private static func signedArea(_ points: [Vec2]) -> Double {
        zip(points, points.dropFirst() + [points[0]]).reduce(0) { $0 + $1.0.cross($1.1) } / 2
    }

    private static func dot(_ a: Vec2, _ b: Vec2) -> Double { a.x * b.x + a.y * b.y }

    private static func rms(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return (values.reduce(0) { $0 + $1 * $1 } / Double(values.count)).squareRoot()
    }

    static func distance(_ point: Vec2, toSegment a: Vec2, _ b: Vec2) -> Double {
        let ab = b - a
        let lengthSquared = dot(ab, ab)
        guard lengthSquared > 1e-12 else { return (point - a).length }
        let t = min(max(dot(point - a, ab) / lengthSquared, 0), 1)
        return (point - (a + ab * t)).length
    }
}
