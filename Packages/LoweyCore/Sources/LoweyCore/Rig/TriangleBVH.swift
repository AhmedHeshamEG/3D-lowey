import Foundation

/// A bounding-volume tree over a mesh's triangles, for many ray and segment queries against one surface (drawn bones
/// look through a limb; bone heat asks whether a bone can be seen from each vertex).
public struct TriangleBVH: Sendable {
    struct Node {
        var low: SIMD3<Float>
        var high: SIMD3<Float>
        /// Leaf: first triangle and count; inner: left child index (the right one follows its subtree), count 0.
        var start: Int32
        var size: Int32
        var right: Int32
    }

    let positions: [SIMD3<Float>]
    /// Triangles as index triples, reordered by the build.
    let triangles: [SIMD3<UInt32>]
    let nodes: [Node]

    public init(_ mesh: MeshData) {
        positions = mesh.positions
        var triangles: [SIMD3<UInt32>] = []
        triangles.reserveCapacity(mesh.triangleCount)
        for tri in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            triangles.append(SIMD3<UInt32>(mesh.indices[tri], mesh.indices[tri + 1], mesh.indices[tri + 2]))
        }
        var builder = Builder(positions: mesh.positions, triangles: triangles)
        if !triangles.isEmpty { builder.build(0, triangles.count) }
        self.triangles = builder.triangles
        nodes = builder.nodes
    }

    private struct Builder {
        let positions: [SIMD3<Float>]
        var triangles: [SIMD3<UInt32>]
        var nodes: [Node] = []

        func centre(_ tri: SIMD3<UInt32>) -> SIMD3<Float> {
            (positions[Int(tri.x)] + positions[Int(tri.y)] + positions[Int(tri.z)]) / 3
        }

        @discardableResult
        mutating func build(_ start: Int, _ end: Int) -> Int {
            var low = SIMD3<Float>(repeating: .infinity)
            var high = SIMD3<Float>(repeating: -.infinity)
            for index in start ..< end {
                for corner in [triangles[index].x, triangles[index].y, triangles[index].z] {
                    low = pointwiseMin(low, positions[Int(corner)])
                    high = pointwiseMax(high, positions[Int(corner)])
                }
            }
            let nodeIndex = nodes.count
            nodes.append(Node(low: low, high: high, start: Int32(start), size: Int32(end - start), right: 0))
            guard end - start > 4 else { return nodeIndex }
            let extent = high - low
            let axis = extent.x > extent.y ? (extent.x > extent.z ? 0 : 2) : (extent.y > extent.z ? 1 : 2)
            let slice = triangles[start ..< end].sorted { centre($0)[axis] < centre($1)[axis] }
            triangles.replaceSubrange(start ..< end, with: slice)
            let middle = (start + end) / 2
            nodes[nodeIndex].size = 0
            nodes[nodeIndex].start = Int32(nodes.count)
            build(start, middle)
            nodes[nodeIndex].right = Int32(build(middle, end))
            return nodeIndex
        }
    }

    /// Every distance along the ray (within `limit`) where it crosses a triangle, nearest first.
    public func hits(origin: Vec3, direction: Vec3, limit: Double = .infinity) -> [Double] {
        var result: [Double] = []
        visit(origin: origin.float3, direction: direction.float3, limit: Float(min(limit, 1e30))) { t in
            result.append(Double(t))
            return false
        }
        return result.sorted()
    }

    /// Whether the open segment from `a` to `b` crosses the surface (its ends, within `margin`, don't count).
    public func blocks(_ a: Vec3, _ b: Vec3, margin: Double) -> Bool {
        let length = a.distance(to: b)
        guard length > 2 * margin else { return false }
        let direction = (b - a) / length
        var blocked = false
        visit(origin: a.float3, direction: direction.float3, limit: Float(length - margin)) { t in
            if Double(t) > margin {
                blocked = true
                return true
            }
            return false
        }
        return blocked
    }

    /// Calls `found` with each crossing distance; `found` returns true to stop.
    private func visit(origin: SIMD3<Float>, direction: SIMD3<Float>, limit: Float, found: (Float) -> Bool) {
        guard !nodes.isEmpty else { return }
        func safe(_ value: Float) -> Float { abs(value) < 1e-20 ? (value < 0 ? -1e-20 : 1e-20) : value }
        let inverse = SIMD3<Float>(1 / safe(direction.x), 1 / safe(direction.y), 1 / safe(direction.z))
        var stack: [Int32] = [0]
        while let index = stack.popLast() {
            let node = nodes[Int(index)]
            guard Self.slab(node.low, node.high, origin: origin, inverse: inverse, limit: limit) else { continue }
            if node.size > 0 {
                for tri in Int(node.start) ..< Int(node.start + node.size) {
                    if let t = intersect(triangles[tri], origin: origin, direction: direction), t <= limit, found(t) { return }
                }
            } else {
                stack.append(node.start)
                stack.append(node.right)
            }
        }
    }

    private static func slab(_ low: SIMD3<Float>, _ high: SIMD3<Float>, origin: SIMD3<Float>, inverse: SIMD3<Float>, limit: Float) -> Bool {
        let a = (low - origin) * inverse
        let b = (high - origin) * inverse
        let near = pointwiseMin(a, b)
        let far = pointwiseMax(a, b)
        let enter = max(near.x, near.y, near.z, 0)
        let exit = min(far.x, far.y, far.z, limit)
        return enter <= exit * 1.000_01 + 1e-6
    }

    private func intersect(_ tri: SIMD3<UInt32>, origin: SIMD3<Float>, direction: SIMD3<Float>) -> Float? {
        let a = positions[Int(tri.x)]
        let edge1 = positions[Int(tri.y)] - a
        let edge2 = positions[Int(tri.z)] - a
        let p = cross3(direction, edge2)
        let determinant = dot3(edge1, p)
        guard abs(determinant) > 1e-12 else { return nil }
        let inverse = 1 / determinant
        let s = origin - a
        let u = dot3(s, p) * inverse
        guard u >= 0, u <= 1 else { return nil }
        let q = cross3(s, edge1)
        let v = dot3(direction, q) * inverse
        guard v >= 0, u + v <= 1 else { return nil }
        let t = dot3(edge2, q) * inverse
        return t > 0 ? t : nil
    }
}
