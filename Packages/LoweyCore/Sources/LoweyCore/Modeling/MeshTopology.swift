import Foundation

/// Who touches whom in an editable mesh, built from its faces: one half-edge per directed loop edge, its twin the
/// same edge walked the other way by the neighbouring face. Cheap to build (a pass over the loops) and thrown away
/// after each operation, so the stored mesh stays a plain list of faces.
public struct MeshTopology: Sendable {
    public struct HalfEdge: Hashable, Sendable {
        public var from: Int
        public var to: Int
        public var face: Int
    }

    public let halfEdges: [HalfEdge]
    private let byEnds: [SIMD2<Int>: [Int]]
    private let facesByVertex: [[Int]]

    public init(_ mesh: EditableMesh) {
        var halfEdges: [HalfEdge] = []
        var byEnds: [SIMD2<Int>: [Int]] = [:]
        var facesByVertex = [[Int]](repeating: [], count: mesh.vertices.count)
        for (faceIndex, face) in mesh.faces.enumerated() {
            for loop in face.loops {
                for index in loop.indices {
                    let from = loop[index], to = loop[(index + 1) % loop.count]
                    byEnds[SIMD2(from, to), default: []].append(halfEdges.count)
                    halfEdges.append(HalfEdge(from: from, to: to, face: faceIndex))
                    if facesByVertex[from].last != faceIndex { facesByVertex[from].append(faceIndex) }
                }
            }
        }
        self.halfEdges = halfEdges
        self.byEnds = byEnds
        self.facesByVertex = facesByVertex.map { Array(Set($0)).sorted() }
    }

    /// The half-edge walking `to → from`, when exactly one face walks it.
    public func twin(of index: Int) -> Int? {
        let edge = halfEdges[index]
        guard let twins = byEnds[SIMD2(edge.to, edge.from)], twins.count == 1 else { return nil }
        return twins[0]
    }

    /// Closed and manifold: every edge is walked once each way, by two faces. A solid you can print or cut.
    public var isClosedManifold: Bool {
        guard !halfEdges.isEmpty else { return false }
        for (ends, list) in byEnds {
            guard list.count == 1, byEnds[SIMD2(ends.y, ends.x)]?.count == 1 else { return false }
        }
        return true
    }

    /// Edges walked by only one face (the border of an open surface).
    public var borderEdges: [MeshEdge] {
        halfEdges.indices.compactMap { index in
            twin(of: index) == nil ? MeshEdge(halfEdges[index].from, halfEdges[index].to) : nil
        }
    }

    public func faces(around vertex: Int) -> [Int] {
        facesByVertex.indices.contains(vertex) ? facesByVertex[vertex] : []
    }

    public func faces(along edge: MeshEdge) -> [Int] {
        let forward = byEnds[SIMD2(edge.a, edge.b)] ?? []
        let backward = byEnds[SIMD2(edge.b, edge.a)] ?? []
        return Array(Set((forward + backward).map { halfEdges[$0].face })).sorted()
    }

    /// Faces sharing an edge with this one.
    public func neighbours(of face: Int, in mesh: EditableMesh) -> [Int] {
        var result = Set<Int>()
        for loop in mesh.faces[face].loops {
            for index in loop.indices {
                let edge = MeshEdge(loop[index], loop[(index + 1) % loop.count])
                for other in faces(along: edge) where other != face {
                    result.insert(other)
                }
            }
        }
        return result.sorted()
    }

    /// Vertices joined to this one by an edge.
    public func neighbours(ofVertex vertex: Int) -> [Int] {
        var result = Set<Int>()
        for edge in halfEdges where edge.from == vertex || edge.to == vertex {
            result.insert(edge.from == vertex ? edge.to : edge.from)
        }
        return result.sorted()
    }

    /// Edges that end at this vertex.
    public func edges(around vertex: Int) -> [MeshEdge] {
        var result = Set<MeshEdge>()
        for edge in halfEdges where edge.from == vertex || edge.to == vertex {
            result.insert(MeshEdge(edge.from, edge.to))
        }
        return result.sorted { ($0.a, $0.b) < ($1.a, $1.b) }
    }
}
