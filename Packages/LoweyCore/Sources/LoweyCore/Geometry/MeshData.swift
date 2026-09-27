import Foundation

/// Plain triangle mesh (Float, ready for the GPU). Generated in Core so it's unit
/// tested and identical on every platform; the render layer only uploads it.
public struct MeshData: Hashable, Sendable {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var uvs: [SIMD2<Float>]
    /// Counter-clockwise triangles (front faces), 3 indices each.
    public var indices: [UInt32]

    public init(positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], indices: [UInt32] = []) {
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.indices = indices
    }

    public var triangleCount: Int { indices.count / 3 }
    public var isEmpty: Bool { indices.isEmpty }

    public var bounds: Bounds? {
        Bounds(points: positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) })
    }

    /// Appends another mesh.
    public mutating func append(_ other: MeshData) {
        let offset = UInt32(positions.count)
        positions += other.positions
        normals += other.normals.count == other.positions.count
            ? other.normals : Array(repeating: SIMD3<Float>(0, 1, 0), count: other.positions.count)
        uvs += other.uvs.count == other.positions.count
            ? other.uvs : Array(repeating: SIMD2<Float>(0, 0), count: other.positions.count)
        indices += other.indices.map { $0 + offset }
    }

    /// Adds a vertex and returns its index.
    @discardableResult
    public mutating func addVertex(_ position: SIMD3<Float>, normal: SIMD3<Float> = .init(0, 1, 0), uv: SIMD2<Float> = .zero) -> UInt32 {
        positions.append(position)
        normals.append(normal)
        uvs.append(uv)
        return UInt32(positions.count - 1)
    }

    public mutating func addTriangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        indices += [a, b, c]
    }

    /// Recomputes smooth normals by area-weighted averaging of face normals over shared vertices.
    public mutating func computeSmoothNormals() {
        var accum = Array(repeating: SIMD3<Float>(0, 0, 0), count: positions.count)
        for tri in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = Int(indices[tri]), b = Int(indices[tri + 1]), c = Int(indices[tri + 2])
            let n = cross3(positions[b] - positions[a], positions[c] - positions[a])
            accum[a] += n
            accum[b] += n
            accum[c] += n
        }
        normals = accum.map { normalize3($0, fallback: SIMD3<Float>(0, 1, 0)) }
    }

    /// Welds vertices at identical positions (so smooth normals flow across seams).
    public func welded(tolerance: Float = 1e-5) -> MeshData {
        var map: [SIMD3<Int32>: UInt32] = [:]
        var result = MeshData()
        var remap = [UInt32](repeating: 0, count: positions.count)
        let scale = 1 / tolerance
        for (index, position) in positions.enumerated() {
            let key = SIMD3<Int32>(
                Int32((position.x * scale).rounded()), Int32((position.y * scale).rounded()), Int32((position.z * scale).rounded())
            )
            if let existing = map[key] {
                remap[index] = existing
            } else {
                let uv = uvs.indices.contains(index) ? uvs[index] : .zero
                let newIndex = result.addVertex(position, uv: uv)
                map[key] = newIndex
                remap[index] = newIndex
            }
        }
        result.indices = indices.map { remap[Int($0)] }
        return result
    }

    /// Flat shading: every triangle gets its own three vertices with the face normal.
    public func faceted() -> MeshData {
        var result = MeshData()
        result.positions.reserveCapacity(indices.count)
        for tri in stride(from: 0, to: indices.count - 2, by: 3) {
            let ia = Int(indices[tri]), ib = Int(indices[tri + 1]), ic = Int(indices[tri + 2])
            let a = positions[ia], b = positions[ib], c = positions[ic]
            let n = normalize3(cross3(b - a, c - a), fallback: SIMD3<Float>(0, 1, 0))
            let uvA = uvs.indices.contains(ia) ? uvs[ia] : .zero
            let uvB = uvs.indices.contains(ib) ? uvs[ib] : .zero
            let uvC = uvs.indices.contains(ic) ? uvs[ic] : .zero
            let i0 = result.addVertex(a, normal: n, uv: uvA)
            let i1 = result.addVertex(b, normal: n, uv: uvB)
            let i2 = result.addVertex(c, normal: n, uv: uvC)
            result.addTriangle(i0, i1, i2)
        }
        return result
    }

    /// Smooth shading: weld, then average normals.
    public func smoothed() -> MeshData {
        var result = welded()
        result.computeSmoothNormals()
        return result
    }

    /// Flat → faceted. Smooth → auto-smooth (soft surfaces, crisp hard edges).
    public func shaded(_ style: ShadingStyle) -> MeshData {
        style == .flat ? faceted() : autoSmoothed()
    }

    /// Mirrors across the plane `axis = offset` and appends the mirror (winding flipped).
    public func mirroredCopy(axis: Axis, offset: Float = 0) -> MeshData {
        var mirror = self
        let component = axis == .x ? 0 : (axis == .y ? 1 : 2)
        mirror.positions = positions.map { position in
            var p = position
            p[component] = 2 * offset - p[component]
            return p
        }
        mirror.normals = normals.map { normal in
            var n = normal
            n[component] = -n[component]
            return n
        }
        var flipped: [UInt32] = []
        flipped.reserveCapacity(indices.count)
        for tri in stride(from: 0, to: indices.count - 2, by: 3) {
            flipped += [indices[tri], indices[tri + 2], indices[tri + 1]]
        }
        mirror.indices = flipped
        return mirror
    }

    /// Transforms positions and normals.
    public func transformed(_ transform: Transform) -> MeshData {
        var result = self
        result.positions = positions.map { p in
            let v = transform.apply(to: Vec3(Double(p.x), Double(p.y), Double(p.z)))
            return SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))
        }
        result.normals = normals.map { n in
            let s = transform.scale
            let inv = Vec3(s.x != 0 ? 1 / s.x : 0, s.y != 0 ? 1 / s.y : 0, s.z != 0 ? 1 / s.z : 0)
            let v = transform.rotation.act(Vec3(Double(n.x), Double(n.y), Double(n.z)).scaled(by: inv)).normalized
            return SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))
        }
        return result
    }
}

// MARK: - Float helpers (no simd import: Core must build on Linux)

@inline(__always) func cross3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

@inline(__always) func dot3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    a.x * b.x + a.y * b.y + a.z * b.z
}

@inline(__always) func length3(_ a: SIMD3<Float>) -> Float {
    dot3(a, a).squareRoot()
}

@inline(__always) func normalize3(_ a: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
    let len = length3(a)
    return len > 1e-12 ? a / len : fallback
}

public extension Vec3 {
    var float3: SIMD3<Float> { SIMD3<Float>(Float(x), Float(y), Float(z)) }

    init(_ vector: SIMD3<Float>) {
        self.init(Double(vector.x), Double(vector.y), Double(vector.z))
    }
}
