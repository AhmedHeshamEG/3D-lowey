import Foundation

/// Moving paint between surfaces on the CPU: baking a model's own colours into a first layer, and carrying layers onto
/// a new unwrap when the shape under them changed (each pixel finds the closest point of the old surface).
public enum PaintTransfer {
    /// A `size` picture of the unwrap where each covered pixel takes `color(triangle, weights)` (nil leaves it clear).
    /// Triangle `t` of the unwrap is triangle `t` of the mesh it was made from.
    public static func bake(_ unwrap: PaintUnwrap, size: Int, color: (_ triangle: Int, _ weights: SIMD3<Float>) -> RGBA?) -> RGBAImage {
        var image = RGBAImage.clear(width: size, height: size)
        let scale = Float(size)
        for face in 0 ..< unwrap.triangleCount {
            let a = unwrap.uvs[Int(unwrap.indices[face * 3])] * scale
            let b = unwrap.uvs[Int(unwrap.indices[face * 3 + 1])] * scale
            let c = unwrap.uvs[Int(unwrap.indices[face * 3 + 2])] * scale
            PaintRaster.triangle(a, b, c, width: size, height: size) { x, y, weights in
                if let value = color(face, weights) { image.setPixel(x, y, value) }
            }
        }
        return image
    }

    /// Where every covered pixel of the new surface lies on the old one: its uv there, or nil when the old surface is
    /// farther than `reach` (paint doesn't jump onto new parts of the shape).
    public static func correspondence(from old: PaintUnwrap, to new: PaintUnwrap, size: Int) -> [SIMD2<Float>?] {
        var map = [SIMD2<Float>?](repeating: nil, count: size * size)
        let oldPaint = old.surfaceMesh, newPaint = new.surfaceMesh
        guard let bounds = oldPaint.bounds, !newPaint.isEmpty else { return map }
        let reach = Float(max(bounds.size.length * 0.03, 1e-4))
        let grid = TriangleGrid(oldPaint, cell: reach)
        var last: Int?
        let scale = Float(size)
        for face in 0 ..< newPaint.triangleCount {
            let i = (Int(newPaint.indices[face * 3]), Int(newPaint.indices[face * 3 + 1]), Int(newPaint.indices[face * 3 + 2]))
            PaintRaster.triangle(newPaint.uvs[i.0] * scale, newPaint.uvs[i.1] * scale, newPaint.uvs[i.2] * scale,
                                 width: size, height: size) { x, y, w in
                let point = newPaint.positions[i.0] * w.x + newPaint.positions[i.1] * w.y + newPaint.positions[i.2] * w.z
                guard let hit = grid.closest(to: point, within: reach, hint: last) else { return }
                last = hit.triangle
                let o = (Int(oldPaint.indices[hit.triangle * 3]), Int(oldPaint.indices[hit.triangle * 3 + 1]),
                         Int(oldPaint.indices[hit.triangle * 3 + 2]))
                map[y * size + x] = oldPaint.uvs[o.0] * hit.weights.x + oldPaint.uvs[o.1] * hit.weights.y + oldPaint.uvs[o.2] * hit.weights.z
            }
        }
        return map
    }

    /// A picture sampled through a correspondence (pixels without one stay clear).
    public static func carry(_ image: RGBAImage, through map: [SIMD2<Float>?], size: Int) -> RGBAImage {
        var result = RGBAImage.clear(width: size, height: size)
        for index in 0 ..< min(map.count, size * size) {
            guard let uv = map[index] else { continue }
            let color = image.sample(u: Double(uv.x), v: Double(uv.y))
            guard color.a > 0 else { continue }
            result.setPixel(index % size, index / size, color)
        }
        return result
    }
}

/// Triangles bucketed in a uniform grid for closest-point queries near the surface.
struct TriangleGrid {
    let mesh: MeshData
    let cell: Float
    let origin: SIMD3<Float>
    private var buckets: [SIMD3<Int32>: [Int]] = [:]

    init(_ mesh: MeshData, cell: Float) {
        self.mesh = mesh
        self.cell = max(cell, 1e-5)
        origin = mesh.positions.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude)) { pointwiseMin($0, $1) }
        for face in 0 ..< mesh.triangleCount {
            let a = mesh.positions[Int(mesh.indices[face * 3])], b = mesh.positions[Int(mesh.indices[face * 3 + 1])]
            let c = mesh.positions[Int(mesh.indices[face * 3 + 2])]
            let low = cellOf(pointwiseMin(a, pointwiseMin(b, c))), high = cellOf(pointwiseMax(a, pointwiseMax(b, c)))
            for x in low.x ... high.x {
                for y in low.y ... high.y {
                    for z in low.z ... high.z {
                        buckets[SIMD3<Int32>(x, y, z), default: []].append(face)
                    }
                }
            }
        }
    }

    func cellOf(_ point: SIMD3<Float>) -> SIMD3<Int32> {
        let p = (point - origin) / cell
        return SIMD3<Int32>(Int32(p.x.rounded(.down)), Int32(p.y.rounded(.down)), Int32(p.z.rounded(.down)))
    }

    /// The closest point of any triangle within `within`; `hint` (the last answer) is tried first and kept when the
    /// point lies on it.
    func closest(to point: SIMD3<Float>, within: Float, hint: Int?) -> (triangle: Int, weights: SIMD3<Float>)? {
        if let hint {
            let (weights, distance) = closestOnTriangle(hint, point)
            if distance < cell * 1e-3 { return (hint, weights) }
        }
        var best: (triangle: Int, weights: SIMD3<Float>, distance: Float)?
        let center = cellOf(point)
        for x in center.x - 1 ... center.x + 1 {
            for y in center.y - 1 ... center.y + 1 {
                for z in center.z - 1 ... center.z + 1 {
                    for face in buckets[SIMD3<Int32>(x, y, z)] ?? [] {
                        let (weights, distance) = closestOnTriangle(face, point)
                        if distance <= within, distance < (best?.distance ?? .greatestFiniteMagnitude) { best = (face, weights, distance) }
                    }
                }
            }
        }
        return best.map { ($0.triangle, $0.weights) }
    }

    /// Ericson's closest point on a triangle, as barycentric weights, and its distance.
    func closestOnTriangle(_ face: Int, _ p: SIMD3<Float>) -> (SIMD3<Float>, Float) {
        let a = mesh.positions[Int(mesh.indices[face * 3])], b = mesh.positions[Int(mesh.indices[face * 3 + 1])]
        let c = mesh.positions[Int(mesh.indices[face * 3 + 2])]
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = dot3(ab, ap), d2 = dot3(ac, ap)
        func result(_ w: SIMD3<Float>) -> (SIMD3<Float>, Float) {
            (w, length3(a * w.x + b * w.y + c * w.z - p))
        }
        if d1 <= 0, d2 <= 0 { return result(SIMD3<Float>(1, 0, 0)) }
        let bp = p - b
        let d3 = dot3(ab, bp), d4 = dot3(ac, bp)
        if d3 >= 0, d4 <= d3 { return result(SIMD3<Float>(0, 1, 0)) }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0, d1 >= 0, d3 <= 0 {
            let v = d1 / (d1 - d3)
            return result(SIMD3<Float>(1 - v, v, 0))
        }
        let cp = p - c
        let d5 = dot3(ab, cp), d6 = dot3(ac, cp)
        if d6 >= 0, d5 <= d6 { return result(SIMD3<Float>(0, 0, 1)) }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0, d2 >= 0, d6 <= 0 {
            let w = d2 / (d2 - d6)
            return result(SIMD3<Float>(1 - w, 0, w))
        }
        let va = d3 * d6 - d5 * d4
        if va <= 0, d4 - d3 >= 0, d5 - d6 >= 0 {
            let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            return result(SIMD3<Float>(0, 1 - w, w))
        }
        let denominator = 1 / (va + vb + vc)
        let v = vb * denominator, w = vc * denominator
        return result(SIMD3<Float>(1 - v - w, v, w))
    }
}
