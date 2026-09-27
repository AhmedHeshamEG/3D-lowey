import Foundation

/// Cleans raw Pencil input into a stroke worth meshing.
public enum StrokeFilter {
    /// - Parameters:
    ///   - smoothing: 0 keeps everything, 1 is very smooth and simplified.
    ///   - minSpacing: points closer than this (m) are merged.
    public static func process(
        points: [Vec3], widths: [Double], smoothing: Double, minSpacing: Double = 0.01
    ) -> (points: [Vec3], widths: [Double]) {
        guard points.count > 1 else { return (points, widths) }
        let widths = widths.count == points.count ? widths : Array(repeating: widths.first ?? 0.05, count: points.count)
        // 1. Spacing.
        var p: [Vec3] = [points[0]]
        var w: [Double] = [widths[0]]
        for index in 1 ..< points.count where points[index].distance(to: p[p.count - 1]) >= minSpacing {
            p.append(points[index])
            w.append(widths[index])
        }
        if let last = points.last, p.count > 1, p[p.count - 1] != last {
            p[p.count - 1] = last
        } else if p.count == 1, let last = points.last, last != p[0] {
            p.append(last)
            w.append(widths[widths.count - 1])
        }
        let amount = min(max(smoothing, 0), 1)
        guard amount > 0, p.count > 2 else { return (p, w) }
        // 2. Laplacian smoothing (endpoints pinned).
        let iterations = Int((amount * 6).rounded(.up))
        for _ in 0 ..< iterations {
            var next = p
            var nextW = w
            for index in 1 ..< p.count - 1 {
                next[index] = p[index] * 0.5 + (p[index - 1] + p[index + 1]) * 0.25
                nextW[index] = w[index] * 0.5 + (w[index - 1] + w[index + 1]) * 0.25
            }
            p = next
            w = nextW
        }
        // 3. Simplify (low-poly friendly): Ramer–Douglas–Peucker.
        let length = zip(p, p.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        let tolerance = length * 0.004 * amount
        let keep = rdp(p, tolerance: tolerance)
        return (keep.map { p[$0] }, keep.map { w[$0] })
    }

    /// Indices kept by Ramer–Douglas–Peucker simplification.
    static func rdp(_ points: [Vec3], tolerance: Double) -> [Int] {
        guard points.count > 2, tolerance > 0 else { return Array(points.indices) }
        var keep = Array(repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            let a = points[start]
            let b = points[end]
            let ab = b - a
            let abLengthSquared = ab.lengthSquared
            var maxDistance = 0.0
            var maxIndex = start
            for index in start + 1 ..< end {
                let ap = points[index] - a
                let distance: Double
                if abLengthSquared < 1e-18 {
                    distance = ap.length
                } else {
                    let t = min(max(ap.dot(ab) / abLengthSquared, 0), 1)
                    distance = (ap - ab * t).length
                }
                if distance > maxDistance {
                    maxDistance = distance
                    maxIndex = index
                }
            }
            if maxDistance > tolerance {
                keep[maxIndex] = true
                stack.append((start, maxIndex))
                stack.append((maxIndex, end))
            }
        }
        return keep.indices.filter { keep[$0] }
    }
}

/// Turns a `DrawingRecipe` into triangles.
public enum DrawingMesher {
    public static func mesh(for recipe: DrawingRecipe) -> MeshData {
        var result = MeshData()
        for stroke in recipe.strokes where !stroke.points.isEmpty {
            switch recipe.style {
            case .tube:
                result.append(tube(stroke, sides: max(3, recipe.segments)))
            case .ribbon:
                result.append(ribbon(stroke, normal: recipe.normal))
            case .extrude:
                result.append(extrude(outline: stroke.points, normal: recipe.normal, depth: recipe.depth))
            case .lathe:
                result.append(lathe(profile: stroke.points, segments: max(3, recipe.segments)))
            }
        }
        return result
    }

    // MARK: Tube

    public static func tube(_ stroke: DrawingRecipe.Stroke, sides: Int) -> MeshData {
        let points = stroke.points.map(\.float3)
        let widths = stroke.widths.map { Float($0) }
        var mesh = MeshData()
        guard points.count >= 2 else {
            // A dot becomes a little low-poly ball.
            let radius = Float(stroke.widths.first ?? 0.05)
            var ball = PrimitiveMesh.sphere(segments: 6, rings: 4)
            ball.positions = ball.positions.map { ($0 - SIMD3<Float>(0, 0.5, 0)) * (radius * 2) + (points.first ?? .zero) }
            return ball
        }
        // Parallel-transport frames.
        var tangents: [SIMD3<Float>] = []
        for index in points.indices {
            let prev = points[max(index - 1, 0)]
            let next = points[min(index + 1, points.count - 1)]
            tangents.append(normalize3(next - prev, fallback: SIMD3<Float>(0, 0, 1)))
        }
        var normal = perpendicular(to: tangents[0])
        var normals: [SIMD3<Float>] = []
        for index in points.indices {
            if index > 0 {
                let axis = cross3(tangents[index - 1], tangents[index])
                let axisLength = length3(axis)
                if axisLength > 1e-6 {
                    let angle = acos(min(max(dot3(tangents[index - 1], tangents[index]), -1), 1))
                    normal = rotate(normal, around: axis / axisLength, angle: angle)
                }
            }
            normals.append(normal)
        }
        for index in points.indices {
            let t = tangents[index]
            let n = normals[index]
            let b = cross3(t, n)
            let radius = max(widths[index], 0.002)
            for side in 0 ..< sides {
                let angle = Float(side) / Float(sides) * 2 * Float.pi
                let direction = n * cos(angle) + b * sin(angle)
                mesh.addVertex(points[index] + direction * radius, normal: direction,
                               uv: SIMD2<Float>(Float(side) / Float(sides), Float(index) / Float(points.count - 1)))
            }
        }
        let ringSize = UInt32(sides)
        for index in 0 ..< UInt32(points.count - 1) {
            for side in 0 ..< ringSize {
                let a = index * ringSize + side
                let b = index * ringSize + (side + 1) % ringSize
                let c = (index + 1) * ringSize + side
                let d = (index + 1) * ringSize + (side + 1) % ringSize
                mesh.addTriangle(a, b, d)
                mesh.addTriangle(a, d, c)
            }
        }
        // Caps.
        let startCenter = mesh.addVertex(points[0], normal: -tangents[0])
        for side in 0 ..< ringSize {
            mesh.addTriangle(startCenter, (side + 1) % ringSize, side)
        }
        let lastRing = UInt32(points.count - 1) * ringSize
        let endCenter = mesh.addVertex(points[points.count - 1], normal: tangents[tangents.count - 1])
        for side in 0 ..< ringSize {
            mesh.addTriangle(endCenter, lastRing + side, lastRing + (side + 1) % ringSize)
        }
        return mesh
    }

    // MARK: Ribbon

    public static func ribbon(_ stroke: DrawingRecipe.Stroke, normal: Vec3) -> MeshData {
        let points = stroke.points.map(\.float3)
        guard points.count >= 2 else { return tube(stroke, sides: 4) }
        let up = normalize3(normal.float3, fallback: SIMD3<Float>(0, 1, 0))
        var mesh = MeshData()
        var lefts: [SIMD3<Float>] = []
        var rights: [SIMD3<Float>] = []
        for index in points.indices {
            let prev = points[max(index - 1, 0)]
            let next = points[min(index + 1, points.count - 1)]
            let tangent = normalize3(next - prev, fallback: SIMD3<Float>(1, 0, 0))
            let side = normalize3(cross3(up, tangent), fallback: perpendicular(to: tangent))
            let width = Float(max(stroke.widths[index], 0.002))
            lefts.append(points[index] + side * width)
            rights.append(points[index] - side * width)
        }
        // Front (facing `up`) and back faces so the ribbon reads from both sides.
        for (faceNormal, flip) in [(up, false), (-up, true)] {
            let base = UInt32(mesh.positions.count)
            for index in points.indices {
                let v = Float(index) / Float(points.count - 1)
                mesh.addVertex(lefts[index] + faceNormal * 0.0005, normal: faceNormal, uv: SIMD2<Float>(0, v))
                mesh.addVertex(rights[index] + faceNormal * 0.0005, normal: faceNormal, uv: SIMD2<Float>(1, v))
            }
            for index in 0 ..< UInt32(points.count - 1) {
                let l0 = base + index * 2, r0 = l0 + 1, l1 = l0 + 2, r1 = l0 + 3
                if flip {
                    mesh.addTriangle(l0, l1, r0)
                    mesh.addTriangle(r0, l1, r1)
                } else {
                    mesh.addTriangle(l0, r0, l1)
                    mesh.addTriangle(r0, r1, l1)
                }
            }
        }
        return mesh
    }

    // MARK: Extrude

    public static func extrude(outline: [Vec3], normal: Vec3, depth: Double) -> MeshData {
        let n = normal.normalized.length > 0 ? normal.normalized : .unitY
        let (u, v) = basis(for: n)
        guard let origin = outline.first else { return MeshData() }
        var polygon = outline.map { Vec2(($0 - origin).dot(u), ($0 - origin).dot(v)) }
        // Drop a closing duplicate.
        if polygon.count > 2, let first = polygon.first, let last = polygon.last, (first - last).length < 1e-4 {
            polygon.removeLast()
        }
        guard polygon.count >= 3 else { return MeshData() }
        if signedArea(polygon) < 0 { polygon.reverse() }
        let triangles = triangulate(polygon)
        guard !triangles.isEmpty else { return MeshData() }

        func point(_ p: Vec2, height: Double) -> SIMD3<Float> {
            (origin + u * p.x + v * p.y + n * height).float3
        }
        var mesh = MeshData()
        let nf = n.float3
        // Bottom cap (faces -n), top cap (faces +n).
        let bottomBase = UInt32(mesh.positions.count)
        for p in polygon {
            mesh.addVertex(point(p, height: 0), normal: -nf)
        }
        for tri in triangles {
            mesh.addTriangle(bottomBase + UInt32(tri.0), bottomBase + UInt32(tri.2), bottomBase + UInt32(tri.1))
        }
        let topBase = UInt32(mesh.positions.count)
        for p in polygon {
            mesh.addVertex(point(p, height: depth), normal: nf)
        }
        for tri in triangles {
            mesh.addTriangle(topBase + UInt32(tri.0), topBase + UInt32(tri.1), topBase + UInt32(tri.2))
        }
        // Walls.
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            PrimitiveMesh.quad(&mesh, point(a, height: 0), point(b, height: 0), point(b, height: depth), point(a, height: depth))
        }
        return mesh
    }

    // MARK: Lathe

    /// Revolves a profile around the local Y axis.
    public static func lathe(profile: [Vec3], segments: Int) -> MeshData {
        let rings = profile.map { (radius: Float((($0.x * $0.x) + ($0.z * $0.z)).squareRoot()), y: Float($0.y)) }
        guard rings.count >= 2 else { return MeshData() }
        var mesh = MeshData()
        for ring in rings.indices {
            for segment in 0 ... segments {
                let angle = Float(segment) / Float(segments) * 2 * Float.pi
                let position = SIMD3<Float>(sin(angle) * rings[ring].radius, rings[ring].y, cos(angle) * rings[ring].radius)
                mesh.addVertex(position, uv: SIMD2<Float>(Float(segment) / Float(segments), Float(ring) / Float(rings.count - 1)))
            }
        }
        let stride = UInt32(segments + 1)
        for ring in 0 ..< UInt32(rings.count - 1) {
            for segment in 0 ..< UInt32(segments) {
                let a = ring * stride + segment
                let b = a + stride
                mesh.addTriangle(a, a + 1, b + 1)
                mesh.addTriangle(a, b + 1, b)
            }
        }
        mesh.computeSmoothNormals()
        // Make sure the surface faces outward whichever way the profile was drawn.
        var outwardScore: Float = 0
        for (index, position) in mesh.positions.enumerated() {
            outwardScore += dot3(mesh.normals[index], SIMD3<Float>(position.x, 0, position.z))
        }
        if outwardScore < 0 {
            var flipped: [UInt32] = []
            for tri in Swift.stride(from: 0, to: mesh.indices.count - 2, by: 3) {
                flipped += [mesh.indices[tri], mesh.indices[tri + 2], mesh.indices[tri + 1]]
            }
            mesh.indices = flipped
            mesh.normals = mesh.normals.map { -$0 }
        }
        // Close ends that don't touch the axis with flat caps (hard edge).
        let top = rings[0].y >= rings[rings.count - 1].y ? 0 : rings.count - 1
        for ring in [0, rings.count - 1] where rings[ring].radius > 0.005 {
            let facingUp = ring == top
            let normal = SIMD3<Float>(0, facingUp ? 1 : -1, 0)
            let center = mesh.addVertex(SIMD3<Float>(0, rings[ring].y, 0), normal: normal)
            let base = UInt32(mesh.positions.count)
            for segment in 0 ... segments {
                mesh.addVertex(mesh.positions[ring * (segments + 1) + segment], normal: normal)
            }
            for segment in 0 ..< UInt32(segments) {
                if facingUp {
                    mesh.addTriangle(center, base + segment, base + segment + 1)
                } else {
                    mesh.addTriangle(center, base + segment + 1, base + segment)
                }
            }
        }
        return mesh
    }

    // MARK: Helpers

    /// Orthonormal (u, v) spanning the plane with normal `n`, with u × v = n.
    public static func basis(for n: Vec3) -> (Vec3, Vec3) {
        let helper = abs(n.y) < 0.9 ? Vec3.unitY : Vec3.unitX
        let u = helper.cross(n).normalized
        let v = n.cross(u).normalized
        return (u, v)
    }

    static func perpendicular(to v: SIMD3<Float>) -> SIMD3<Float> {
        let helper = abs(v.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        return normalize3(cross3(v, helper), fallback: SIMD3<Float>(1, 0, 0))
    }

    static func rotate(_ v: SIMD3<Float>, around axis: SIMD3<Float>, angle: Float) -> SIMD3<Float> {
        // Rodrigues' rotation formula.
        let c = cos(angle), s = sin(angle)
        return v * c + cross3(axis, v) * s + axis * dot3(axis, v) * (1 - c)
    }

    public static func signedArea(_ polygon: [Vec2]) -> Double {
        var area = 0.0
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            area += a.x * b.y - b.x * a.y
        }
        return area / 2
    }

    /// Ear-clipping triangulation of a simple counter-clockwise polygon.
    public static func triangulate(_ polygon: [Vec2]) -> [(Int, Int, Int)] {
        var remaining = Array(polygon.indices)
        var triangles: [(Int, Int, Int)] = []
        var guardCounter = 0
        while remaining.count > 3, guardCounter < polygon.count * polygon.count {
            guardCounter += 1
            var clipped = false
            for i in remaining.indices {
                let prev = remaining[(i + remaining.count - 1) % remaining.count]
                let current = remaining[i]
                let next = remaining[(i + 1) % remaining.count]
                let a = polygon[prev], b = polygon[current], c = polygon[next]
                // Convex corner?
                guard (b - a).cross(c - b) > 1e-12 else { continue }
                // No other vertex inside the ear.
                let inside = remaining.contains { index in
                    index != prev && index != current && index != next && pointInTriangle(polygon[index], a, b, c)
                }
                if inside { continue }
                triangles.append((prev, current, next))
                remaining.remove(at: i)
                clipped = true
                break
            }
            if !clipped {
                // Degenerate/self-intersecting outline: fall back to a fan so the user still gets a shape.
                break
            }
        }
        if remaining.count == 3 {
            triangles.append((remaining[0], remaining[1], remaining[2]))
        } else if remaining.count > 3 {
            for index in 1 ..< remaining.count - 1 {
                triangles.append((remaining[0], remaining[index], remaining[index + 1]))
            }
        }
        return triangles
    }

    static func pointInTriangle(_ p: Vec2, _ a: Vec2, _ b: Vec2, _ c: Vec2) -> Bool {
        let d1 = (b - a).cross(p - a)
        let d2 = (c - b).cross(p - b)
        let d3 = (a - c).cross(p - c)
        let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
        let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNegative && hasPositive)
    }
}
