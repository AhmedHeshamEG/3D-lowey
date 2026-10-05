import Foundation

/// Where planes meet, in Double: the smallest move δ of a point with n·δ = r for each plane (normal n, residual r).
/// Three or more planes pin a corner down (least squares when they disagree a hair); two leave a line and one a plane,
/// and then the shortest move wins. Shell offsets corners with it; booleans put new corners back exactly on their
/// planes with it.
enum PlaneSolve {
    static func correction(normals: [Vec3], residuals: [Double]) -> Vec3 {
        guard !normals.isEmpty, normals.count == residuals.count else { return .zero }
        // (Σ n nᵀ + λI) δ = Σ n r; the small λ picks the shortest δ when the planes don't pin it down.
        let lambda = 1e-9
        var m = [[Double]](repeating: [0, 0, 0], count: 3)
        var b = Vec3.zero
        for (n, r) in zip(normals, residuals) {
            let c = [n.x, n.y, n.z]
            for row in 0 ..< 3 {
                for column in 0 ..< 3 {
                    m[row][column] += c[row] * c[column]
                }
            }
            b += n * r
        }
        // Planes that pin the point down are solved as they are; only a loose system gets the nudge.
        if abs(determinant(m)) < 1e-6 {
            for index in 0 ..< 3 {
                m[index][index] += lambda
            }
        }
        let d = determinant(m)
        guard abs(d) > 1e-30 else { return normals[0] * residuals[0] }
        let rhs = [b.x, b.y, b.z]
        let solved = (0 ..< 3).map { column -> Double in
            var replaced = m
            for row in 0 ..< 3 {
                replaced[row][column] = rhs[row]
            }
            return determinant(replaced) / d
        }
        return Vec3(solved[0], solved[1], solved[2])
    }

    static func determinant(_ a: [[Double]]) -> Double {
        a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
            + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
    }

    /// A face's plane: unit normal and offset (n·p = offset on the plane).
    struct Plane {
        var normal: Vec3
        var offset: Double
    }

    static func planes(of mesh: EditableMesh) -> [Plane] {
        mesh.faces.indices.compactMap { face in
            guard mesh.area(of: face) > 0 else { return nil }
            let normal = mesh.normal(of: face)
            return Plane(normal: normal, offset: normal.dot(mesh.centroid(of: face)))
        }
    }

    /// The point moved exactly onto the corner where the planes it lies on (within `tolerance`) meet, when at least
    /// three distinct planes pin it down; otherwise it stays where it is.
    static func snap(_ point: Vec3, to planes: [Plane], tolerance: Double) -> Vec3 {
        var normals: [Vec3] = []
        var residuals: [Double] = []
        for plane in planes {
            let residual = plane.offset - plane.normal.dot(point)
            guard abs(residual) <= tolerance, !normals.contains(where: { abs($0.dot(plane.normal)) > 1 - 1e-9 }) else { continue }
            normals.append(plane.normal)
            residuals.append(residual)
        }
        guard normals.count >= 3 else { return point }
        let move = correction(normals: normals, residuals: residuals)
        // A move much bigger than the tolerance means the planes meet somewhere else (nearly parallel): keep it.
        return move.length <= tolerance * 4 ? point + move : point
    }
}
