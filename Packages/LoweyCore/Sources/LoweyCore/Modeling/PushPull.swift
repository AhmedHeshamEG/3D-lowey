import Foundation

/// Push/pull (Shapr3D's core move): drag a face along its normal by an exact distance.
///
/// When every face around it stands square to it (the top of a block, the floor of a pocket), the face just slides
/// and its neighbours stretch: the mesh keeps its faces and the number you type is exactly the new size. Otherwise
/// the face's outline is swept into a prism that's added (pulling out) or cut away (pushing in) with a boolean, which
/// works on any face of any solid.
public enum PushPull {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case noSuchFace
        /// Pushed through the opposite side (the solid would turn inside out).
        case tooFar
        case boolean(MeshBoolean.Failure)

        public var description: String {
            switch self {
            case .noSuchFace: "That face isn't there any more."
            case .tooFar: "That would push the face through the other side."
            case let .boolean(failure): failure.description
            }
        }
    }

    /// The mesh with `face` moved `distance` along its outward normal (negative pushes in).
    public static func apply(_ mesh: EditableMesh, face: Int, distance: Double) throws(Failure) -> EditableMesh {
        guard mesh.faces.indices.contains(face) else { throw .noSuchFace }
        guard abs(distance) > 1e-9 else { return mesh }
        if slides(mesh, face: face) { return try slide(mesh, face: face, distance: distance) }
        // Pushing in, the prism starts a hair outside the face so the two never lie exactly on top of each other.
        let epsilon = max(mesh.bounds?.size.maxComponent ?? 1, 1e-3) * 1e-6
        let prism = distance > 0 ? Prism.make(mesh, face: face, distance: distance) : Prism.make(mesh, face: face, from: epsilon, to: distance)
        do {
            return try MeshBoolean.combine(mesh, prism, distance > 0 ? .union : .subtract)
        } catch {
            throw .boolean(error)
        }
    }

    /// True when every other face touching the face's corners stands square to it, so sliding keeps them flat.
    public static func slides(_ mesh: EditableMesh, face: Int) -> Bool {
        let topology = MeshTopology(mesh)
        let normal = mesh.normal(of: face)
        var around = Set<Int>()
        for vertex in mesh.faces[face].vertices {
            around.formUnion(topology.faces(around: vertex))
        }
        around.remove(face)
        return !around.isEmpty && around.allSatisfy { abs(mesh.normal(of: $0).dot(normal)) < 1e-6 }
    }

    /// How far the face can be pushed in before a neighbour collapses (infinite when it can't slide).
    public static func slideLimit(_ mesh: EditableMesh, face: Int) -> Double {
        let normal = mesh.normal(of: face)
        let plane = normal.dot(mesh.vertices[mesh.faces[face].outline[0]])
        let topology = MeshTopology(mesh)
        let moving = Set(mesh.faces[face].vertices)
        var limit = Double.infinity
        for vertex in moving {
            for other in topology.faces(around: vertex) where other != face {
                for corner in mesh.faces[other].vertices where !moving.contains(corner) {
                    limit = min(limit, plane - normal.dot(mesh.vertices[corner]))
                }
            }
        }
        return limit
    }

    static func slide(_ mesh: EditableMesh, face: Int, distance: Double) throws(Failure) -> EditableMesh {
        if distance < 0, -distance >= slideLimit(mesh, face: face) - 1e-9 { throw .tooFar }
        let offset = mesh.normal(of: face) * distance
        var moves: [Int: Vec3] = [:]
        for vertex in mesh.faces[face].vertices {
            moves[vertex] = mesh.vertices[vertex] + offset
        }
        return mesh.moving(moves)
    }
}

/// Closed prisms: a planar outline (with holes) swept along its normal. Push/pull, sketch pulls and cuts use them.
public enum Prism {
    /// The prism of a face of `mesh`, from the face to `distance` along its normal (either way).
    public static func make(_ mesh: EditableMesh, face: Int, distance: Double) -> EditableMesh {
        make(mesh, face: face, from: 0, to: distance)
    }

    public static func make(_ mesh: EditableMesh, face: Int, from start: Double, to end: Double) -> EditableMesh {
        let loops = mesh.faces[face].loops.map { $0.map { mesh.vertices[$0] } }
        return make(outline: loops[0], holes: Array(loops.dropFirst()), normal: mesh.normal(of: face), from: start, to: end)
    }

    /// A prism between heights `from` and `to` along `normal` (the outline counter-clockwise around the normal,
    /// holes clockwise). Faces point outward whichever way it's swept.
    public static func make(outline: [Vec3], holes: [[Vec3]], normal: Vec3, from start: Double, to end: Double) -> EditableMesh {
        let n = normal.normalized
        let low = min(start, end), high = max(start, end)
        var vertices: [Vec3] = []
        var faces: [EditableMesh.Face] = []
        var bottoms: [[Int]] = []
        var tops: [[Int]] = []
        for loop in [outline] + holes {
            let bottom = loop.map { point -> Int in
                vertices.append(point + n * low)
                return vertices.count - 1
            }
            let top = loop.map { point -> Int in
                vertices.append(point + n * high)
                return vertices.count - 1
            }
            bottoms.append(bottom)
            tops.append(top)
            // Walls: for a counter-clockwise outline (seen from +n) a wall's outward normal is edge × n.
            for index in loop.indices {
                let next = (index + 1) % loop.count
                faces.append(EditableMesh.Face([bottom[index], bottom[next], top[next], top[index]]))
            }
        }
        faces.append(EditableMesh.Face(tops[0], holes: Array(tops.dropFirst())))
        faces.append(EditableMesh.Face(bottoms[0].reversed(), holes: bottoms.dropFirst().map { $0.reversed() }))
        return EditableMesh(vertices: vertices, faces: faces)
    }
}
