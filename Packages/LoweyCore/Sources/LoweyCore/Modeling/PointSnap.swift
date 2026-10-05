import Foundation

/// What a point on the stage snapped to: the stage marks it under the finger, so you see why it landed there.
public enum SnapKind: String, Sendable, Hashable {
    case corner, midpoint, edge, face, grid, free
}

public struct SnapResult: Hashable, Sendable {
    public var kind: SnapKind
    public var point: Vec3

    public init(kind: SnapKind, point: Vec3) {
        self.kind = kind
        self.point = point
    }
}

/// Snapping a point under the finger or the Pencil to what's near it on screen, in order: corners, then the middles of
/// edges, then edges, then the face it's over, then the grid on the working plane. Distances are measured on the
/// screen (`radius` in points), so snapping feels the same at any zoom.
public enum PointSnap {
    public struct Nearby {
        /// Solids near the point, in world space.
        public var meshes: [EditableMesh]
        /// Polylines near the point (sketch curves), in world space.
        public var lines: [[Vec3]]

        public init(meshes: [EditableMesh] = [], lines: [[Vec3]] = []) {
            self.meshes = meshes
            self.lines = lines
        }
    }

    /// - Parameters:
    ///   - surface: where the ray first hits a solid, if it does (corners behind it don't count).
    ///   - plane: the working plane (a sketch's, or the ground) for grid and free points.
    public static func snap(screen: Vec2, ray: Ray, surface: Vec3?, in scene: Nearby, plane: PlaneFrame?, settings: SnapSettings,
                            radius: Double, project: (Vec3) -> Vec2?) -> SnapResult? {
        let segments = segments(of: scene)
        let reach = surface.map { $0.distance(to: ray.origin) * (1 + 1e-3) + 1e-6 } ?? .infinity
        func visible(_ point: Vec3) -> Bool { point.distance(to: ray.origin) <= reach }
        // The closest on screen; of points that sit on top of each other there, the one nearest the eye.
        func nearest(_ points: [Vec3]) -> Vec3? {
            var best: (point: Vec3, distance: Double, depth: Double)?
            for point in points where visible(point) {
                guard let onScreen = project(point) else { continue }
                let distance = (onScreen - screen).length
                let depth = point.distance(to: ray.origin)
                guard distance <= radius else { continue }
                if let current = best, distance > current.distance + 0.5 || (distance > current.distance - 0.5 && depth >= current.depth) {
                    continue
                }
                best = (point, distance, depth)
            }
            return best?.point
        }
        if settings.corners {
            let corners = scene.meshes.flatMap(\.vertices) + scene.lines.flatMap(\.self)
            if let corner = nearest(corners) { return SnapResult(kind: .corner, point: corner) }
            if let middle = nearest(segments.map { ($0.0 + $0.1) * 0.5 }) { return SnapResult(kind: .midpoint, point: middle) }
        }
        if settings.edges {
            let onEdges = segments.map { closestPoint(on: $0, to: ray) }
            if let point = nearest(onEdges) { return SnapResult(kind: .edge, point: point) }
        }
        if settings.faces, let surface { return SnapResult(kind: .face, point: surface) }
        guard let plane, let point = intersect(ray, plane) else { return surface.map { SnapResult(kind: .face, point: $0) } }
        if settings.grid, settings.gridSize > 0 {
            let flat = plane.project(point)
            let size = settings.gridSize
            let snapped = Vec2((flat.x / size).rounded() * size, (flat.y / size).rounded() * size)
            return SnapResult(kind: .grid, point: plane.lift(snapped))
        }
        return SnapResult(kind: .free, point: point)
    }

    /// Every edge of the solids and every segment of the polylines.
    static func segments(of scene: Nearby) -> [(Vec3, Vec3)] {
        var result: [(Vec3, Vec3)] = []
        for mesh in scene.meshes {
            result += mesh.edges.map { (mesh.vertices[$0.a], mesh.vertices[$0.b]) }
        }
        for line in scene.lines {
            result += zip(line, line.dropFirst()).map { ($0, $1) }
        }
        return result
    }

    /// The point of a segment closest to a ray (the edge point under the finger).
    public static func closestPoint(on segment: (Vec3, Vec3), to ray: Ray) -> Vec3 {
        let (a, b) = segment
        let u = b - a, v = ray.direction.normalized, w = a - ray.origin
        let uu = u.dot(u), uv = u.dot(v), vv = v.dot(v), uw = u.dot(w), vw = v.dot(w)
        let denominator = uu * vv - uv * uv
        guard uu > 1e-24 else { return a }
        // Parallel: any point works; take the one nearest the ray's origin.
        let t = abs(denominator) < 1e-18 ? -uw / uu : (uv * vw - vv * uw) / denominator
        return a + u * min(max(t, 0), 1)
    }

    public static func intersect(_ ray: Ray, _ plane: PlaneFrame) -> Vec3? {
        let facing = ray.direction.dot(plane.normal)
        guard abs(facing) > 1e-12 else { return nil }
        let t = (plane.origin - ray.origin).dot(plane.normal) / facing
        return t >= 0 ? ray.point(at: t) : nil
    }

    /// Distance between two points, and how far apart they are along each world axis (the measure tool's readout).
    public static func measure(_ start: Vec3, _ end: Vec3) -> (length: Double, along: Vec3) {
        let delta = end - start
        return (delta.length, Vec3(abs(delta.x), abs(delta.y), abs(delta.z)))
    }
}
