import Foundation

/// A plane to mirror across: a point on it and its normal.
public struct MirrorPlane: Hashable, Sendable {
    public var origin: Vec3
    public var normal: Vec3

    public init(origin: Vec3, normal: Vec3) {
        self.origin = origin
        self.normal = normal.normalized
    }

    public func reflect(_ point: Vec3) -> Vec3 {
        point - normal * (2 * (point - origin).dot(normal))
    }

    public func reflectDirection(_ direction: Vec3) -> Vec3 {
        direction - normal * (2 * direction.dot(normal))
    }

    /// Signed distance on the normal's side.
    public func height(of point: Vec3) -> Double {
        (point - origin).dot(normal)
    }
}

/// The axis an object is symmetric about, in its own space: the plane through its pivot square to that axis.
public enum SymmetryAxis: String, Codable, Sendable, CaseIterable {
    case x, y, z

    public var label: String {
        switch self {
        case .x: "Left and right"
        case .y: "Top and bottom"
        case .z: "Front and back"
        }
    }

    public var normal: Vec3 {
        switch self {
        case .x: .unitX
        case .y: .unitY
        case .z: .unitZ
        }
    }

    /// The plane in the object's own space.
    public var plane: MirrorPlane { MirrorPlane(origin: .zero, normal: normal) }
}

/// Mirroring meshes: a mirrored copy, and symmetry (one side kept, the other made its mirror image).
public enum MeshMirror {
    /// The mesh mirrored across a plane, its faces turned back out.
    public static func reflected(_ mesh: EditableMesh, across plane: MirrorPlane) -> EditableMesh {
        EditableMesh(vertices: mesh.vertices.map(plane.reflect),
                     faces: mesh.faces.map { EditableMesh.Face(loops: $0.loops.map { Array($0.reversed()) }) })
    }

    /// The mesh made symmetric: the side on the normal's side of the plane (or the other, with `keepPositive` false)
    /// is kept, and the other side becomes its mirror image, joined into one solid.
    public static func symmetrize(_ mesh: EditableMesh, across plane: MirrorPlane, keepPositive: Bool) throws(MeshBoolean.Failure) -> EditableMesh {
        let side = MirrorPlane(origin: plane.origin, normal: keepPositive ? plane.normal : -plane.normal)
        let heights = mesh.vertices.map(side.height)
        guard let highest = heights.max(), highest > 1e-9 else { throw .nothingLeft }
        let half: EditableMesh = if (heights.min() ?? 0) >= -1e-12 {
            // Already all on the kept side (a half drawn against the plane).
            mesh
        } else {
            try MeshBoolean.combine(mesh, halfSpace(side, around: mesh), .intersect)
        }
        // Corners on the plane go exactly onto it, so they and their mirror images are the same points.
        let tolerance = max(mesh.bounds?.size.maxComponent ?? 1, 1e-3) * 1e-6
        let flush = EditableMesh(vertices: half.vertices.map { point in
            let height = plane.height(of: point)
            return abs(height) <= tolerance ? point - plane.normal * height : point
        }, faces: half.faces)
        let mirrored = reflected(flush, across: plane)
        // A half that doesn't reach the plane stays apart from its twin: one object, two pieces.
        return try MeshBoolean.combine(flush, mirrored, .union)
    }

    /// A box covering everything of `mesh` on the normal's side of the plane, one face on the plane.
    static func halfSpace(_ plane: MirrorPlane, around mesh: EditableMesh) -> EditableMesh {
        let bounds = mesh.bounds ?? Bounds(min: .zero, max: .zero)
        let reach = max((bounds.size.length + (bounds.center - plane.origin).length) * 2, 1e-3)
        let frame = PlaneFrame(normal: plane.normal, origin: plane.origin)
        let middle = frame.project(bounds.center)
        let square = [Vec2(-1, -1), Vec2(1, -1), Vec2(1, 1), Vec2(-1, 1)].map { frame.lift(middle + $0 * reach) }
        return Prism.make(outline: square, holes: [], normal: plane.normal, from: 0, to: reach)
    }

    /// The face that mirrors `face` across the plane (itself when it straddles the plane symmetrically).
    public static func counterpart(of face: Int, in mesh: EditableMesh, across plane: MirrorPlane) -> Int? {
        guard mesh.faces.indices.contains(face) else { return nil }
        let size = max(mesh.bounds?.size.maxComponent ?? 1, 1e-3)
        let centroid = plane.reflect(mesh.centroid(of: face))
        let normal = plane.reflectDirection(mesh.normal(of: face))
        let area = mesh.area(of: face)
        return mesh.faces.indices.first { other in
            mesh.centroid(of: other).distance(to: centroid) < size * 1e-6 && mesh.normal(of: other).dot(normal) > 1 - 1e-6
                && abs(mesh.area(of: other) - area) <= max(area, 1e-18) * 1e-6
        }
    }
}
