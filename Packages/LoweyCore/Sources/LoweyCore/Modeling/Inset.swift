import Foundation

/// Inset: a face shrinks into itself by an exact distance and a ring of new faces fills the gap, so the middle can be
/// pushed or pulled on its own (a panel on a door, a recess for a label). Holes shrink the same way: the ring is
/// always on the face's side of each loop. The inner face keeps the original face's index, so it stays picked.
public enum Inset {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case noSuchFace
        /// The face would close up or turn inside out at that distance.
        case tooFar

        public var description: String {
            switch self {
            case .noSuchFace: "That face isn't there any more."
            case .tooFar: "The face isn't big enough to inset that far."
            }
        }
    }

    /// The mesh with each of `faces` inset by `distance` (metres, inward).
    public static func apply(_ mesh: EditableMesh, faces: Set<Int>, distance: Double) throws(Failure) -> EditableMesh {
        guard !faces.isEmpty, faces.allSatisfy(mesh.faces.indices.contains) else { throw .noSuchFace }
        guard distance > 1e-9 else { return mesh }
        var vertices = mesh.vertices
        var result = mesh.faces
        var ring: [EditableMesh.Face] = []
        for face in faces.sorted() {
            let frame = PlaneFrame(normal: mesh.normal(of: face), origin: mesh.vertices[mesh.faces[face].outline[0]])
            var inner: [[Int]] = []
            var shrunk: [[Vec2]] = []
            for loop in mesh.faces[face].loops {
                let flat = loop.map { frame.project(mesh.vertices[$0]) }
                guard let moved = offsetLeft(flat, by: distance) else { throw .tooFar }
                shrunk.append(moved)
                let start = vertices.count
                vertices += moved.map { frame.lift($0) }
                let newLoop = Array(start ..< start + loop.count)
                inner.append(newLoop)
                // Each old edge keeps its direction, so the neighbour across it still walks it the other way.
                for index in loop.indices {
                    let next = (index + 1) % loop.count
                    ring.append(EditableMesh.Face([loop[index], loop[next], newLoop[next], newLoop[index]]))
                }
            }
            guard loopsStaySeparate(shrunk), holesStayInside(shrunk) else { throw .tooFar }
            result[face] = EditableMesh.Face(loops: inner)
        }
        return EditableMesh(vertices: vertices, faces: result + ring)
    }

    /// The loop moved `distance` to the left of its edges (into a face, whichever way the loop runs), with mitred
    /// corners; nil when an edge would flip or the loop would close up.
    static func offsetLeft(_ loop: [Vec2], by distance: Double) -> [Vec2]? {
        let count = loop.count
        guard count >= 3 else { return nil }
        func leftNormal(_ index: Int) -> Vec2? {
            let edge = loop[(index + 1) % count] - loop[index]
            let length = edge.length
            return length > 1e-15 ? Vec2(-edge.y / length, edge.x / length) : nil
        }
        var moved: [Vec2] = []
        for index in 0 ..< count {
            guard let incoming = leftNormal((index + count - 1) % count), let outgoing = leftNormal(index) else { return nil }
            let bend = 1 + incoming.x * outgoing.x + incoming.y * outgoing.y
            // A corner that folds back on itself (a spike) can't be mitred.
            guard bend > 1e-6 else { return nil }
            moved.append(loop[index] + (incoming + outgoing) * (distance / bend))
        }
        // Every edge must keep its direction: one that turned around means the inset went past it.
        for index in 0 ..< count {
            let next = (index + 1) % count
            let before = loop[next] - loop[index], after = moved[next] - moved[index]
            if before.x * after.x + before.y * after.y <= 1e-15 { return nil }
        }
        // An outline (counter-clockwise) only shrinks; a hole (clockwise) only grows. Either way it keeps its turn.
        let area = PolygonTriangulator.signedArea(loop), after = PolygonTriangulator.signedArea(moved)
        guard area * after > 0, area < 0 || after < area else { return nil }
        return moved
    }

    /// Every hole is still inside the outline and outside the other holes (a hole can grow past the outline without
    /// any edges crossing).
    static func holesStayInside(_ loops: [[Vec2]]) -> Bool {
        guard let outline = loops.first else { return true }
        for (index, hole) in loops.enumerated().dropFirst() {
            guard let point = hole.first, Outlines.contains(outline, point) else { return false }
            for (other, loop) in loops.enumerated().dropFirst() where other != index {
                if let first = loop.first, Outlines.contains(hole, first) { return false }
            }
        }
        return true
    }

    /// No two edges of the shrunk loops cross (a hole grown into the outline, or two holes grown into each other).
    static func loopsStaySeparate(_ loops: [[Vec2]]) -> Bool {
        var segments: [(Vec2, Vec2)] = []
        for loop in loops {
            for index in loop.indices {
                segments.append((loop[index], loop[(index + 1) % loop.count]))
            }
        }
        for i in segments.indices {
            for j in segments.indices where j > i + 1 {
                let (a, b) = segments[i], (c, d) = segments[j]
                if a == d || b == c || a == c || b == d { continue }
                if PolygonTriangulator.segmentsCross(a, b, c, d) { return false }
            }
        }
        return true
    }
}
