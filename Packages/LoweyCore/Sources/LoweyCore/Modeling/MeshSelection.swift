import Foundation

/// Which parts of an editable mesh are picked: vertices, edges or faces (one kind at a time, like Shapr3D).
public struct MeshSelection: Hashable, Sendable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case vertex, edge, face

        public var label: String {
            switch self {
            case .vertex: "Corners"
            case .edge: "Edges"
            case .face: "Faces"
            }
        }
    }

    public var mode: Mode
    public var vertices: Set<Int>
    public var edges: Set<MeshEdge>
    public var faces: Set<Int>

    public init(mode: Mode, vertices: Set<Int> = [], edges: Set<MeshEdge> = [], faces: Set<Int> = []) {
        self.mode = mode
        self.vertices = vertices
        self.edges = edges
        self.faces = faces
    }

    public var isEmpty: Bool {
        switch mode {
        case .vertex: vertices.isEmpty
        case .edge: edges.isEmpty
        case .face: faces.isEmpty
        }
    }

    public var count: Int {
        switch mode {
        case .vertex: vertices.count
        case .edge: edges.count
        case .face: faces.count
        }
    }

    /// Keeps only what still exists in `mesh` (after an operation renumbered it).
    public func valid(in mesh: EditableMesh) -> MeshSelection {
        let existing = Set(mesh.edges)
        return MeshSelection(mode: mode, vertices: vertices.filter(mesh.vertices.indices.contains), edges: edges.filter(existing.contains),
                             faces: faces.filter(mesh.faces.indices.contains))
    }

    /// Every vertex the selection touches (what moves when it's moved).
    public func touchedVertices(in mesh: EditableMesh) -> Set<Int> {
        switch mode {
        case .vertex: vertices
        case .edge: Set(edges.flatMap { [$0.a, $0.b] })
        case .face: Set(faces.filter(mesh.faces.indices.contains).flatMap { mesh.faces[$0].vertices })
        }
    }

    // MARK: Grow, shrink, similar

    /// Adds every neighbour (faces across an edge, edges and corners joined at a corner).
    public func grown(in mesh: EditableMesh) -> MeshSelection {
        let topology = MeshTopology(mesh)
        var result = self
        switch mode {
        case .face:
            for face in faces where mesh.faces.indices.contains(face) {
                result.faces.formUnion(topology.neighbours(of: face, in: mesh))
            }
        case .edge:
            for edge in edges {
                result.edges.formUnion(topology.edges(around: edge.a))
                result.edges.formUnion(topology.edges(around: edge.b))
            }
        case .vertex:
            for vertex in vertices {
                result.vertices.formUnion(topology.neighbours(ofVertex: vertex))
            }
        }
        return result
    }

    /// Drops whatever sits on the selection's border (has a neighbour outside it).
    public func shrunk(in mesh: EditableMesh) -> MeshSelection {
        let topology = MeshTopology(mesh)
        var result = self
        switch mode {
        case .face:
            result.faces = faces.filter { face in
                mesh.faces.indices.contains(face) && topology.neighbours(of: face, in: mesh).allSatisfy(faces.contains)
            }
        case .edge:
            result.edges = edges.filter { edge in
                (topology.edges(around: edge.a) + topology.edges(around: edge.b)).allSatisfy(edges.contains)
            }
        case .vertex:
            result.vertices = vertices.filter { topology.neighbours(ofVertex: $0).allSatisfy(vertices.contains) }
        }
        return result
    }

    /// Everything like what's selected: faces facing the same way with the same area, edges of the same length,
    /// corners where the same number of edges meet.
    public func similar(in mesh: EditableMesh) -> MeshSelection {
        var result = self
        let scale = max(mesh.bounds?.size.maxComponent ?? 1, 1e-6)
        switch mode {
        case .face:
            let picked = faces.filter(mesh.faces.indices.contains).map { (normal: mesh.normal(of: $0), area: mesh.area(of: $0)) }
            for face in mesh.faces.indices {
                let normal = mesh.normal(of: face), area = mesh.area(of: face)
                if picked.contains(where: { $0.normal.dot(normal) > 0.999 && abs($0.area - area) <= max($0.area, area) * 0.01 }) {
                    result.faces.insert(face)
                }
            }
        case .edge:
            let lengths = edges.map { mesh.length(of: $0) }
            for edge in mesh.edges where lengths.contains(where: { abs($0 - mesh.length(of: edge)) <= scale * 1e-6 + $0 * 0.001 }) {
                result.edges.insert(edge)
            }
        case .vertex:
            let topology = MeshTopology(mesh)
            let valences = Set(vertices.map { topology.neighbours(ofVertex: $0).count })
            for vertex in mesh.vertices.indices where valences.contains(topology.neighbours(ofVertex: vertex).count) {
                result.vertices.insert(vertex)
            }
        }
        return result
    }

    // MARK: Lasso

    /// What a Pencil loop drawn on screen catches: elements whose centre projects inside the loop and that face the
    /// viewer. `project` maps object-space points to the screen (nil when behind the camera); `facing` says whether a
    /// face's outward normal (object space) points at the camera.
    public static func lasso(_ loop: [Vec2], mode: Mode, in mesh: EditableMesh, project: (Vec3) -> Vec2?,
                             facing: (_ face: Int) -> Bool) -> MeshSelection {
        guard loop.count >= 3 else { return MeshSelection(mode: mode) }
        func caught(_ point: Vec3) -> Bool {
            guard let screen = project(point) else { return false }
            return Outlines.contains(loop, screen)
        }
        let topology = MeshTopology(mesh)
        let visibleFaces = Set(mesh.faces.indices.filter(facing))
        switch mode {
        case .face:
            return MeshSelection(mode: .face, faces: Set(visibleFaces.filter { caught(mesh.centroid(of: $0)) }))
        case .edge:
            let edges = mesh.edges.filter { edge in
                topology.faces(along: edge).contains(where: visibleFaces.contains)
                    && caught((mesh.vertices[edge.a] + mesh.vertices[edge.b]) / 2)
            }
            return MeshSelection(mode: .edge, edges: Set(edges))
        case .vertex:
            let vertices = mesh.vertices.indices.filter { vertex in
                topology.faces(around: vertex).contains(where: visibleFaces.contains) && caught(mesh.vertices[vertex])
            }
            return MeshSelection(mode: .vertex, vertices: Set(vertices))
        }
    }
}
