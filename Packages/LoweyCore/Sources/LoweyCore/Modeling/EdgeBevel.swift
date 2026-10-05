import Foundation

/// Bevel (a flat cut) and round (a fillet) on the edges of a solid, by an exact size.
///
/// Each edge gets a profile swept along it, in the plane square to the edge: on an outside edge the corner beyond the
/// bevel or the arc is cut away, on an inside edge the gap under it is filled. Both go through the boolean path, so the
/// result is welded, its flat pieces are whole faces, and it stays a solid. Where several bevelled edges meet, the
/// cuts meet in a point.
public enum EdgeBevel {
    public enum Style: String, Codable, Sendable, CaseIterable {
        case chamfer, round

        public var label: String {
            switch self {
            case .chamfer: "Bevel"
            case .round: "Round"
            }
        }
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case noSuchEdge
        /// The edge doesn't have exactly two faces (an open surface or a fin).
        case notSolid
        /// The faces on either side of the edge lie in one plane: there's no corner to bevel.
        case flat
        /// The bevel would be wider than a face beside it.
        case tooBig
        case boolean(MeshBoolean.Failure)

        public var description: String {
            switch self {
            case .noSuchEdge: "That edge isn't there any more."
            case .notSolid: "Only edges between two faces of a solid can be bevelled."
            case .flat: "That edge is flat, so there's no corner to bevel."
            case .tooBig: "That's wider than the faces beside the edge."
            case let .boolean(failure): failure.description
            }
        }
    }

    /// The mesh with `edges` bevelled or rounded. `size` is how far the bevel reaches into each face (chamfer) or
    /// the radius of the round, in metres.
    public static func apply(_ mesh: EditableMesh, edges: Set<MeshEdge>, size: Double, style: Style) throws(Failure) -> EditableMesh {
        guard !edges.isEmpty else { throw .noSuchEdge }
        guard size > 1e-9 else { return mesh }
        let topology = MeshTopology(mesh)
        var cuts: [EditableMesh] = []
        var fills: [EditableMesh] = []
        for edge in edges.sorted(by: { ($0.a, $0.b) < ($1.a, $1.b) }) {
            guard mesh.vertices.indices.contains(edge.a), mesh.vertices.indices.contains(edge.b) else { throw .noSuchEdge }
            let corner = try Corner(edge, in: mesh, topology: topology)
            let profile = try corner.profile(size: size, style: style)
            let tool = corner.sweep(profile, overhang: corner.isConvex)
            if corner.isConvex { cuts.append(tool) } else { fills.append(tool) }
        }
        var result = mesh
        do {
            for cut in cuts {
                result = try MeshBoolean.combine(result, cut, .subtract)
            }
            for fill in fills {
                result = try MeshBoolean.combine(result, fill, .union)
            }
        } catch {
            throw .boolean(error)
        }
        return result
    }

    /// An edge and the two faces meeting at it, seen in the plane square to the edge.
    struct Corner {
        let start: Vec3
        let direction: Vec3
        let length: Double
        /// Outward normals of the two faces.
        let n1: Vec3
        let n2: Vec3
        /// From the edge into each face, in the face's plane.
        let w1: Vec3
        let w2: Vec3
        /// How far each face reaches from the edge (the bevel must stay inside it).
        let reach: Double

        init(_ edge: MeshEdge, in mesh: EditableMesh, topology: MeshTopology) throws(Failure) {
            // The two half-edges along the edge, one per face; each face lies to the left of its own.
            let walks = topology.halfEdges.filter { MeshEdge($0.from, $0.to) == edge }
            guard walks.count == 2, walks[0].face != walks[1].face else { throw .notSolid }
            let a = mesh.vertices[edge.a], b = mesh.vertices[edge.b]
            length = a.distance(to: b)
            guard length > 1e-12 else { throw .noSuchEdge }
            start = a
            direction = (b - a) / length
            let faceA = walks[0].face, faceB = walks[1].face
            n1 = mesh.normal(of: faceA)
            n2 = mesh.normal(of: faceB)
            guard n1.dot(n2) < 1 - 1e-9 else { throw .flat }
            func inward(_ walk: MeshTopology.HalfEdge, _ normal: Vec3) -> Vec3 {
                normal.cross(mesh.vertices[walk.to] - mesh.vertices[walk.from]).normalized
            }
            w1 = inward(walks[0], n1)
            w2 = inward(walks[1], n2)
            func extent(_ face: Int, along w: Vec3) -> Double {
                mesh.faces[face].vertices.map { (mesh.vertices[$0] - a).dot(w) }.max() ?? 0
            }
            reach = min(extent(faceA, along: w1), extent(faceB, along: w2))
        }

        /// Outside edges (the faces turn away from each other) are cut; inside edges are filled.
        var isConvex: Bool { w2.dot(n1) < 0 }

        /// The profile to sweep, as points in space at the edge's start: the corner region beyond the bevel or the arc
        /// (outside edges), or the gap under it (inside edges), reaching a little past the faces so no face of the tool
        /// lies exactly on a face of the solid.
        func profile(size: Double, style: Style) throws(Failure) -> [Vec3] {
            let angle = acos(min(max(w1.dot(w2), -1), 1))
            let setback = style == .round ? size / tan(angle / 2) : size
            guard setback < reach * 0.999 else { throw .tooBig }
            let t1 = w1 * setback, t2 = w2 * setback
            // Outside edges reach out of the solid (far, it's empty); inside edges reach into it (a little).
            let outward = isConvex ? 1.0 : -1.0
            let margin = isConvex ? size * 2 : size * 0.25
            let away1 = n1 * (outward * margin), away2 = n2 * (outward * margin)
            var arc: [Vec3] = []
            if style == .round {
                let center = (w1 + w2).normalized * (size / sin(angle / 2))
                // From the centre the arc runs between the two tangent points, the short way, bulging toward the edge.
                let from = t1 - center, to = t2 - center
                let sweep = acos(min(max(from.normalized.dot(to.normalized), -1), 1))
                // Eight strips a quarter turn (a hair of slack so a quarter turn in floating point is still eight).
                let segments = max(2, Int((sweep / (.pi / 2) * 8 - 1e-6).rounded(.up)))
                arc = (1 ..< segments).map { step in
                    let s = Double(step) / Double(segments)
                    let blend = (from * sin((1 - s) * sweep) + to * sin(s * sweep)) / sin(sweep)
                    return center + blend
                }
            }
            let ring = [t1, t1 + away1, away1 + away2, t2 + away2, t2] + arc.reversed()
            return ring.map { start + $0 }
        }

        /// The profile swept along the edge. A cut runs a little past both ends (beyond them is empty space); a fill
        /// stops exactly at them, or it would stick out of the solid.
        func sweep(_ profile: [Vec3], overhang overhangs: Bool) -> EditableMesh {
            let overhang = overhangs ? max(length * 0.002, 1e-7) : 0
            let shifted = profile.map { $0 - direction * overhang }
            let frame = PlaneFrame(normal: direction, origin: start)
            let counterClockwise = PolygonTriangulator.signedArea(shifted.map { frame.project($0) }) > 0
            return Prism.make(outline: counterClockwise ? shifted : shifted.reversed(), holes: [], normal: direction,
                              from: 0, to: length + overhang * 2)
        }
    }
}
