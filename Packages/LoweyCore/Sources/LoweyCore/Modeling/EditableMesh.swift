import Foundation

/// A polygon mesh you can model: shared vertices and faces made of loops of vertex indices, in the object's own
/// space (metres). A face's first loop is its outline, counter-clockwise seen from outside; any further loops are
/// holes, clockwise. Topology for editing (who touches whom) is built on demand by `MeshTopology`; this value is
/// what the document stores and the journal records.
///
/// Equality and hashing go by a fingerprint of the content, computed once when the mesh is made, so the renderer's
/// mesh cache can key on a mesh every frame without walking its vertices.
public struct EditableMesh: Sendable {
    public struct Face: Hashable, Sendable, Codable {
        /// Outline first, then holes.
        public var loops: [[Int]]

        public init(_ outline: [Int], holes: [[Int]] = []) {
            loops = [outline] + holes
        }

        public init(loops: [[Int]]) {
            self.loops = loops
        }

        public var outline: [Int] { loops.first ?? [] }
        public var holes: ArraySlice<[Int]> { loops.dropFirst() }
        /// Every vertex of the face, outline and holes.
        public var vertices: [Int] { loops.flatMap(\.self) }
    }

    public private(set) var vertices: [Vec3]
    public private(set) var faces: [Face]
    public private(set) var fingerprint: UInt64

    public init(vertices: [Vec3], faces: [Face]) {
        self.vertices = vertices
        self.faces = faces
        fingerprint = Self.fingerprint(vertices: vertices, faces: faces)
    }

    public static let empty = EditableMesh(vertices: [], faces: [])

    public var isEmpty: Bool { faces.isEmpty }

    /// A copy with the vertices moved (same topology).
    public func moving(_ moves: [Int: Vec3]) -> EditableMesh {
        var moved = vertices
        for (index, position) in moves where moved.indices.contains(index) {
            moved[index] = position
        }
        return EditableMesh(vertices: moved, faces: faces)
    }

    /// FNV-1a over the bit patterns of every coordinate and index.
    static func fingerprint(vertices: [Vec3], faces: [Face]) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ value: UInt64) {
            hash ^= value
            hash = hash &* 0x0000_0100_0000_01B3
        }
        mix(UInt64(vertices.count))
        for vertex in vertices {
            mix(vertex.x.bitPattern)
            mix(vertex.y.bitPattern)
            mix(vertex.z.bitPattern)
        }
        mix(UInt64(faces.count))
        for face in faces {
            mix(UInt64(face.loops.count) | 0xF000_0000_0000_0000)
            for loop in face.loops {
                mix(UInt64(loop.count) | 0xE000_0000_0000_0000)
                for index in loop {
                    mix(UInt64(index))
                }
            }
        }
        return hash
    }
}

extension EditableMesh: Hashable {
    public static func == (lhs: EditableMesh, rhs: EditableMesh) -> Bool {
        lhs.fingerprint == rhs.fingerprint && lhs.vertices.count == rhs.vertices.count && lhs.faces.count == rhs.faces.count
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fingerprint)
    }
}

/// Stored compactly: `{"v": [x, y, z, x, y, z, …], "f": [[[0, 1, 2, 3]], …]}`, coordinates rounded to the nanometre so
/// files stay small and diff cleanly.
extension EditableMesh: Codable {
    private enum Key: String, CodingKey { case v, f }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let flat = try container.decode([Double].self, forKey: .v)
        guard flat.count % 3 == 0 else {
            throw DecodingError.dataCorruptedError(forKey: .v, in: container, debugDescription: "Vertex list isn't xyz triples")
        }
        let vertices = stride(from: 0, to: flat.count, by: 3).map { Vec3(flat[$0], flat[$0 + 1], flat[$0 + 2]) }
        let faces = try container.decode([[[Int]]].self, forKey: .f).map(Face.init(loops:))
        for face in faces {
            guard face.outline.count >= 3, face.vertices.allSatisfy(vertices.indices.contains) else {
                throw DecodingError.dataCorruptedError(forKey: .f, in: container, debugDescription: "A face points at a missing vertex")
            }
        }
        self.init(vertices: vertices, faces: faces)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        let flat = vertices.flatMap { [Self.rounded($0.x), Self.rounded($0.y), Self.rounded($0.z)] }
        try container.encode(flat, forKey: .v)
        try container.encode(faces.map(\.loops), forKey: .f)
    }

    static func rounded(_ value: Double) -> Double {
        (value * 1e9).rounded() / 1e9
    }
}

// MARK: Measuring

public extension EditableMesh {
    var bounds: Bounds? { Bounds(points: vertices) }

    /// The face's normal (Newell's method over its outline: robust for any planar polygon).
    func normal(of face: Int) -> Vec3 {
        Self.newellNormal(faces[face].outline.map { vertices[$0] })
    }

    func centroid(of face: Int) -> Vec3 {
        let outline = faces[face].outline
        guard !outline.isEmpty else { return .zero }
        return outline.reduce(Vec3.zero) { $0 + vertices[$1] } / Double(outline.count)
    }

    /// Area of the face, holes taken out.
    func area(of face: Int) -> Double {
        let loops = faces[face].loops
        guard let outline = loops.first else { return 0 }
        let normal = normal(of: face)
        let outer = Self.newellVector(outline.map { vertices[$0] }).dot(normal) / 2
        let holes = loops.dropFirst().reduce(0) { $0 + abs(Self.newellVector($1.map { vertices[$0] }).dot(normal) / 2) }
        return abs(outer) - holes
    }

    /// Unique undirected edges (smaller index first), in the order they first appear.
    var edges: [MeshEdge] {
        var seen = Set<MeshEdge>()
        var result: [MeshEdge] = []
        for face in faces {
            for loop in face.loops {
                for index in loop.indices {
                    let edge = MeshEdge(loop[index], loop[(index + 1) % loop.count])
                    if seen.insert(edge).inserted { result.append(edge) }
                }
            }
        }
        return result
    }

    func length(of edge: MeshEdge) -> Double {
        vertices[edge.a].distance(to: vertices[edge.b])
    }

    /// Enclosed volume (positive for a closed, outward-facing solid).
    var volume: Double {
        let triangles = triangulated()
        var total = 0.0
        for tri in triangles.triangles {
            let a = vertices[tri.0], b = vertices[tri.1], c = vertices[tri.2]
            total += a.dot(b.cross(c))
        }
        return total / 6
    }

    static func newellVector(_ points: [Vec3]) -> Vec3 {
        var normal = Vec3.zero
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            normal.x += (current.y - next.y) * (current.z + next.z)
            normal.y += (current.z - next.z) * (current.x + next.x)
            normal.z += (current.x - next.x) * (current.y + next.y)
        }
        return normal
    }

    static func newellNormal(_ points: [Vec3]) -> Vec3 {
        let normal = newellVector(points)
        let length = normal.length
        return length > 1e-15 ? normal / length : .unitY
    }
}

/// An undirected edge between two vertices (stored smaller index first).
public struct MeshEdge: Hashable, Sendable, Codable {
    public let a: Int
    public let b: Int

    public init(_ first: Int, _ second: Int) {
        a = min(first, second)
        b = max(first, second)
    }
}
