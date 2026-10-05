import Foundation

/// Finds the face, edge or corner under a tap, in the object's own space. The face is the nearest one the ray hits;
/// an edge or corner is the one of that face nearest the tap on screen.
public enum MeshPicking {
    public struct FaceHit: Hashable, Sendable {
        public var face: Int
        public var point: Vec3
        public var distance: Double
    }

    /// The nearest face hit by `ray` (object space).
    public static func face(_ ray: Ray, in mesh: EditableMesh) -> FaceHit? {
        var best: FaceHit?
        for face in mesh.faces.indices {
            for tri in mesh.triangulate(face: face) {
                guard let t = intersect(ray, mesh.vertices[tri.0], mesh.vertices[tri.1], mesh.vertices[tri.2]) else { continue }
                if t < best?.distance ?? .infinity { best = FaceHit(face: face, point: ray.point(at: t), distance: t) }
            }
        }
        return best
    }

    /// Picks in a mode: the hit face, or the edge / corner of it nearest `screenPoint` (`project` maps object space to
    /// the screen).
    public static func pick(_ ray: Ray, screenPoint: Vec2, mode: MeshSelection.Mode, in mesh: EditableMesh,
                            project: (Vec3) -> Vec2?) -> MeshSelection? {
        guard let hit = face(ray, in: mesh) else { return nil }
        let face = mesh.faces[hit.face]
        switch mode {
        case .face:
            return MeshSelection(mode: .face, faces: [hit.face])
        case .vertex:
            let nearest = face.vertices.min { lhs, rhs in
                screenDistance(mesh.vertices[lhs], screenPoint, project) < screenDistance(mesh.vertices[rhs], screenPoint, project)
            }
            return nearest.map { MeshSelection(mode: .vertex, vertices: [$0]) }
        case .edge:
            var edges: [MeshEdge] = []
            for loop in face.loops {
                for index in loop.indices {
                    edges.append(MeshEdge(loop[index], loop[(index + 1) % loop.count]))
                }
            }
            let nearest = edges.min { lhs, rhs in
                edgeDistance(lhs, mesh, screenPoint, project) < edgeDistance(rhs, mesh, screenPoint, project)
            }
            return nearest.map { MeshSelection(mode: .edge, edges: [$0]) }
        }
    }

    static func screenDistance(_ point: Vec3, _ screen: Vec2, _ project: (Vec3) -> Vec2?) -> Double {
        guard let projected = project(point) else { return .infinity }
        return (projected - screen).length
    }

    static func edgeDistance(_ edge: MeshEdge, _ mesh: EditableMesh, _ screen: Vec2, _ project: (Vec3) -> Vec2?) -> Double {
        guard let a = project(mesh.vertices[edge.a]), let b = project(mesh.vertices[edge.b]) else { return .infinity }
        let ab = b - a
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 1e-12 else { return (screen - a).length }
        let t = min(max(((screen.x - a.x) * ab.x + (screen.y - a.y) * ab.y) / lengthSquared, 0), 1)
        return (screen - (a + ab * t)).length
    }

    /// Möller–Trumbore, both sides.
    static func intersect(_ ray: Ray, _ a: Vec3, _ b: Vec3, _ c: Vec3) -> Double? {
        let edge1 = b - a, edge2 = c - a
        let p = ray.direction.cross(edge2)
        let determinant = edge1.dot(p)
        guard abs(determinant) > 1e-15 else { return nil }
        let inverse = 1 / determinant
        let s = ray.origin - a
        let u = s.dot(p) * inverse
        guard u >= -1e-9, u <= 1 + 1e-9 else { return nil }
        let q = s.cross(edge1)
        let v = ray.direction.dot(q) * inverse
        guard v >= -1e-9, u + v <= 1 + 1e-9 else { return nil }
        let t = edge2.dot(q) * inverse
        return t > 1e-9 ? t : nil
    }
}
