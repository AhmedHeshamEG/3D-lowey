import Foundation

/// The stage's modelling marks as plain triangles, in world space: the edges of the mesh being modelled, the picked
/// faces, edges and corners, sketch lines and regions. The editor layer draws them over the frame (never exported);
/// lines are thin bars sized from the camera so they stay about two points wide.
public enum ModelOverlay {
    /// A bar from `a` to `b`, `width` thick, facing every way (four sides).
    public static func line(_ a: Vec3, _ b: Vec3, width: Double, into mesh: inout MeshData) {
        let along = b - a
        let length = along.length
        guard length > 1e-12 else { return }
        let direction = along / length
        let helper = abs(direction.y) < 0.9 ? Vec3.unitY : Vec3.unitX
        let side = direction.cross(helper).normalized * (width / 2)
        let up = direction.cross(side).normalized * (width / 2)
        let corners = [side + up, side - up, -side - up, -side + up]
        let base = UInt32(mesh.positions.count)
        for corner in corners {
            mesh.addVertex((a + corner).float3, normal: corner.normalized.float3)
            mesh.addVertex((b + corner).float3, normal: corner.normalized.float3)
        }
        for index in 0 ..< 4 {
            let i = base + UInt32(index * 2), j = base + UInt32(((index + 1) % 4) * 2)
            mesh.addTriangle(i, j, j + 1)
            mesh.addTriangle(i, j + 1, i + 1)
        }
    }

    /// A small diamond around a point.
    public static func dot(_ center: Vec3, radius: Double, into mesh: inout MeshData) {
        let axes = [Vec3.unitX, -Vec3.unitX, Vec3.unitY, -Vec3.unitY, Vec3.unitZ, -Vec3.unitZ].map { $0 * radius }
        let faces = [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)]
        let base = UInt32(mesh.positions.count)
        for axis in axes {
            mesh.addVertex((center + axis).float3, normal: axis.normalized.float3)
        }
        for face in faces {
            mesh.addTriangle(base + UInt32(face.0), base + UInt32(face.1), base + UInt32(face.2))
        }
    }

    /// Every edge of a mesh (world space).
    public static func wireframe(_ mesh: EditableMesh, world: Transform, width: Double) -> MeshData {
        var result = MeshData()
        for edge in mesh.edges {
            line(world.apply(to: mesh.vertices[edge.a]), world.apply(to: mesh.vertices[edge.b]), width: width, into: &result)
        }
        return result
    }

    /// The picked parts of a mesh: faces filled (lifted a hair off the surface), edges as bars, corners as dots.
    public static func selection(_ selection: MeshSelection, of mesh: EditableMesh, world: Transform, width: Double) -> MeshData {
        var result = MeshData()
        switch selection.mode {
        case .face:
            for face in selection.faces.sorted() where mesh.faces.indices.contains(face) {
                let lift = world.applyDirection(mesh.normal(of: face)).normalized * (width * 0.5)
                for tri in mesh.triangulate(face: face) {
                    let base = UInt32(result.positions.count)
                    for vertex in [tri.0, tri.1, tri.2] {
                        result.addVertex((world.apply(to: mesh.vertices[vertex]) + lift).float3)
                    }
                    result.addTriangle(base, base + 1, base + 2)
                }
            }
        case .edge:
            for edge in selection.edges where mesh.vertices.indices.contains(edge.a) && mesh.vertices.indices.contains(edge.b) {
                line(world.apply(to: mesh.vertices[edge.a]), world.apply(to: mesh.vertices[edge.b]), width: width * 2.5, into: &result)
            }
        case .vertex:
            for vertex in selection.vertices.sorted() where mesh.vertices.indices.contains(vertex) {
                dot(world.apply(to: mesh.vertices[vertex]), radius: width * 3, into: &result)
            }
        }
        return result
    }

    /// A sketch's curves as bars on its plane.
    public static func sketchLines(_ sketch: Sketch, width: Double) -> MeshData {
        var result = MeshData()
        let lift = sketch.plane.normal * (width * 0.5)
        for (points, closed) in sketch.polylines where points.count >= 2 {
            let count = closed ? points.count : points.count - 1
            for index in 0 ..< count {
                let a = sketch.plane.lift(points[index]) + lift
                let b = sketch.plane.lift(points[(index + 1) % points.count]) + lift
                line(a, b, width: width, into: &result)
            }
        }
        return result
    }

    /// A region filled on its sketch's plane (both sides, so it shows from below too).
    public static func region(_ region: SketchRegion, of sketch: Sketch, lift: Double) -> MeshData {
        var result = MeshData()
        let points = region.outline + region.holes.flatMap(\.self)
        let offset = sketch.plane.normal * lift
        for point in points {
            result.addVertex((sketch.plane.lift(point) + offset).float3, normal: sketch.plane.normal.float3)
        }
        for tri in region.triangles {
            result.addTriangle(UInt32(tri.0), UInt32(tri.1), UInt32(tri.2))
            result.addTriangle(UInt32(tri.0), UInt32(tri.2), UInt32(tri.1))
        }
        return result
    }
}
