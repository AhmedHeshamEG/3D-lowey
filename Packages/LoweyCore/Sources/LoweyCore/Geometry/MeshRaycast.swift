import Foundation

/// Ray/mesh intersection (Möller–Trumbore), for "draw on an existing object".
public enum MeshRaycast {
    /// Nearest hit of `ray` with `mesh` (positions in the same space as the ray).
    public static func intersect(_ ray: Ray, mesh: MeshData) -> SurfaceHit? {
        let origin = ray.origin.float3
        let direction = ray.direction.float3
        var best: (t: Float, normal: SIMD3<Float>)?
        for tri in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let a = mesh.positions[Int(mesh.indices[tri])]
            let b = mesh.positions[Int(mesh.indices[tri + 1])]
            let c = mesh.positions[Int(mesh.indices[tri + 2])]
            let edge1 = b - a
            let edge2 = c - a
            let p = cross3(direction, edge2)
            let determinant = dot3(edge1, p)
            if abs(determinant) < 1e-9 { continue }
            let inverse = 1 / determinant
            let s = origin - a
            let u = dot3(s, p) * inverse
            if u < 0 || u > 1 { continue }
            let q = cross3(s, edge1)
            let v = dot3(direction, q) * inverse
            if v < 0 || u + v > 1 { continue }
            let t = dot3(edge2, q) * inverse
            if t <= 1e-5 { continue }
            if t < best?.t ?? .infinity {
                var normal = normalize3(cross3(edge1, edge2), fallback: SIMD3<Float>(0, 1, 0))
                if dot3(normal, direction) > 0 { normal = -normal } // face the viewer
                best = (t, normal)
            }
        }
        guard let best else { return nil }
        let distance = Double(best.t)
        return SurfaceHit(point: ray.point(at: distance), normal: Vec3(best.normal), distance: distance)
    }
}
