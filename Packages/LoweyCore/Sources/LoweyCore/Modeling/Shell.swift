import Foundation

/// Shell: hollow a solid out, leaving walls of an exact thickness, optionally with faces left open (a cup, a box
/// without its lid, a vase). The cavity is the solid moved in by the thickness, face by face; it's cut out with the
/// boolean path, together with a short prism through the wall at each open face.
public enum Shell {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notSolid
        /// The walls would meet inside: the solid is thinner than twice the thickness somewhere.
        case tooThick
        case boolean(MeshBoolean.Failure)

        public var description: String {
            switch self {
            case .notSolid: "Only closed solids can be hollowed. Repair it first (Model ▸ Edit ▸ Check for printing)."
            case .tooThick: "The walls would meet inside: try a thinner wall."
            case let .boolean(failure): failure.description
            }
        }
    }

    /// The solid hollowed to walls `thickness` thick (metres), with `open` faces removed.
    public static func apply(_ mesh: EditableMesh, thickness: Double, open: Set<Int> = []) throws(Failure) -> EditableMesh {
        guard MeshTopology(mesh).isClosedManifold, mesh.volume > 0 else { throw .notSolid }
        guard thickness > 1e-9 else { return mesh }
        let inner = offset(mesh, by: -thickness)
        guard keepsItsShape(inner, like: mesh) else { throw .tooThick }
        // Open faces: the cavity's face is pulled out through the wall (a slide for tops and sides, a sweep otherwise).
        var cavity = inner
        let openFaces = open.filter(inner.faces.indices.contains).sorted()
        if !openFaces.isEmpty {
            do throws(PushPull.Failure) {
                cavity = try PushPull.apply(inner, faces: openFaces, distance: thickness * 2)
            } catch {
                if case let .boolean(failure) = error { throw .boolean(failure) }
                throw .tooThick
            }
        }
        do throws(MeshBoolean.Failure) {
            let result = try MeshBoolean.combine(mesh, cavity, .subtract)
            // A cavity that crosses itself still cuts, but takes the wrong amount away.
            guard open.isEmpty ? abs(result.volume - (mesh.volume - inner.volume)) <= mesh.volume * 0.01 : result.volume < mesh.volume else {
                throw MeshBoolean.Failure.failed
            }
            return result
        } catch {
            throw error == .failed ? .tooThick : .boolean(error)
        }
    }

    /// Every face moved `distance` along its normal (outward when positive): each corner goes to where the planes of
    /// its faces meet after the move (least squares where more than three meet, the shortest move where fewer do).
    public static func offset(_ mesh: EditableMesh, by distance: Double) -> EditableMesh {
        let topology = MeshTopology(mesh)
        let normals = mesh.faces.indices.map { mesh.normal(of: $0) }
        let moved = mesh.vertices.indices.map { vertex -> Vec3 in
            var planes: [Vec3] = []
            for face in topology.faces(around: vertex) where !planes.contains(where: { $0.dot(normals[face]) > 1 - 1e-9 }) {
                planes.append(normals[face])
            }
            return mesh.vertices[vertex] + shift(planes, by: distance)
        }
        return EditableMesh(vertices: moved, faces: mesh.faces)
    }

    /// The move δ with n·δ = distance for every normal n (the shortest one when the planes leave it free).
    static func shift(_ normals: [Vec3], by distance: Double) -> Vec3 {
        PlaneSolve.correction(normals: normals, residuals: Array(repeating: distance, count: normals.count))
    }

    /// The offset kept every face facing the same way and every edge running the same way, and it still encloses
    /// space: the walls didn't pass through each other.
    static func keepsItsShape(_ moved: EditableMesh, like original: EditableMesh) -> Bool {
        guard moved.volume > 0, moved.volume < original.volume else { return false }
        for face in original.faces.indices where original.area(of: face) > 0 {
            if moved.normal(of: face).dot(original.normal(of: face)) < 0.5 { return false }
        }
        for edge in original.edges {
            let before = original.vertices[edge.b] - original.vertices[edge.a]
            let after = moved.vertices[edge.b] - moved.vertices[edge.a]
            if before.dot(after) <= 0 { return false }
        }
        return true
    }
}
