import Foundation

/// What a 3D printer (or a slicer) will think of a shape, in plain words.
public struct PrintReport: Hashable, Sendable {
    /// Closed, every edge shared by exactly two faces, faces pointing out: a slicer reads it as a solid.
    public var isWatertight: Bool
    /// Edges with a face on one side only (holes in the surface).
    public var openEdges: Int
    /// Edges shared by more than two faces (fins, shapes touching along an edge).
    public var tangledEdges: Int
    /// Faces turned inside out.
    public var insideOut: Bool
    /// Faces where the wall behind them is thinner than the printer's minimum.
    public var thinFaces: Set<Int>
    /// The thinnest wall measured (metres), when the shape is closed.
    public var thinnestWall: Double?
    /// Whether it fits the printer's build volume as placed (nil without a printer).
    public var fitsBed: Bool?
    public var volume: Double

    public var isReady: Bool { isWatertight && thinFaces.isEmpty && fitsBed != false }

    /// One sentence per problem, in the order to fix them.
    public var problems: [String] {
        var lines: [String] = []
        if openEdges > 0 { lines.append("It has holes in its surface (\(openEdges) open edges).") }
        if tangledEdges > 0 { lines.append("Some edges are shared by more than two faces (\(tangledEdges)).") }
        if insideOut { lines.append("Some faces point inward.") }
        if !thinFaces.isEmpty { lines.append("Some walls are thinner than this printer can print.") }
        if fitsBed == false { lines.append("It's bigger than the printer's build volume.") }
        return lines
    }
}

/// Checking and repairing shapes for 3D printing.
public enum PrintCheck {
    /// Checks a shape in world space (metres) against a printer (its minimum wall and build volume).
    public static func check(_ mesh: EditableMesh, bed: PrintBed?) -> PrintReport {
        let topology = MeshTopology(mesh)
        var uses: [MeshEdge: Int] = [:]
        for edge in topology.halfEdges {
            uses[MeshEdge(edge.from, edge.to), default: 0] += 1
        }
        let open = topology.borderEdges.count
        let tangled = uses.values.count { $0 > 2 }
        let closed = topology.isClosedManifold
        let volume = closed ? mesh.volume : 0
        let insideOut = closed && (volume < 0 || !consistentlyWound(mesh, topology))
        let watertight = closed && !insideOut && MeshBoolean.isSolid(mesh)
        var thin = Set<Int>()
        var thinnest: Double?
        if watertight {
            (thin, thinnest) = walls(mesh, minimum: bed?.minimumWall ?? 0)
        }
        return PrintReport(isWatertight: watertight, openEdges: open, tangledEdges: tangled, insideOut: insideOut, thinFaces: thin,
                           thinnestWall: thinnest, fitsBed: bed.flatMap { bed in mesh.bounds.map(bed.fits) }, volume: abs(volume))
    }

    /// Every edge is walked once each way (neighbouring faces agree on which way is out).
    static func consistentlyWound(_ mesh: EditableMesh, _ topology: MeshTopology) -> Bool {
        var directed = Set<SIMD2<Int>>()
        for edge in topology.halfEdges where !directed.insert(SIMD2(edge.from, edge.to)).inserted {
            return false
        }
        return true
    }

    // MARK: Repair

    /// The shape made printable where it can be: corners that nearly meet are joined, slivers and doubled faces
    /// removed, faces turned to agree and to point out, and holes closed with new faces.
    public static func repair(_ mesh: EditableMesh) -> EditableMesh {
        let size = max(mesh.bounds?.size.maxComponent ?? 1, 1e-3)
        let tolerance = size * 1e-6
        let triangles = mesh.triangulated().triangles
        var (positions, remap) = MeshBuilder.weld(mesh.vertices, tolerance: tolerance)
        var tris = triangles.map { (remap[$0.0], remap[$0.1], remap[$0.2]) }
        tris = withoutDegenerate(tris, positions: positions, tolerance: tolerance)
        tris = wound(tris, positions: positions)
        tris += caps(for: tris, positions: &positions)
        tris = wound(tris, positions: positions)
        return MeshBuilder.mesh(positions: positions, triangles: tris, weld: false)
    }

    /// Without collapsed triangles, slivers with no area, and triangles that repeat another's corners.
    static func withoutDegenerate(_ tris: [(Int, Int, Int)], positions: [Vec3], tolerance: Double) -> [(Int, Int, Int)] {
        var seen = Set<[Int]>()
        return tris.filter { tri in
            guard tri.0 != tri.1, tri.1 != tri.2, tri.0 != tri.2 else { return false }
            let area = (positions[tri.1] - positions[tri.0]).cross(positions[tri.2] - positions[tri.0]).length
            guard area > tolerance * tolerance else { return false }
            return seen.insert([tri.0, tri.1, tri.2].sorted()).inserted
        }
    }

    /// Triangles turned so neighbours agree (walking each connected piece from one triangle), then each piece turned
    /// to point out (positive volume).
    static func wound(_ tris: [(Int, Int, Int)], positions: [Vec3]) -> [(Int, Int, Int)] {
        var result = tris
        var byEdge: [MeshEdge: [Int]] = [:]
        for (index, tri) in tris.enumerated() {
            for edge in [MeshEdge(tri.0, tri.1), MeshEdge(tri.1, tri.2), MeshEdge(tri.2, tri.0)] {
                byEdge[edge, default: []].append(index)
            }
        }
        func walks(_ tri: (Int, Int, Int), _ a: Int, _ b: Int) -> Bool {
            (tri.0 == a && tri.1 == b) || (tri.1 == a && tri.2 == b) || (tri.2 == a && tri.0 == b)
        }
        var visited = [Bool](repeating: false, count: tris.count)
        for seed in tris.indices where !visited[seed] {
            var piece: [Int] = []
            var queue = [seed]
            visited[seed] = true
            while let current = queue.popLast() {
                piece.append(current)
                let tri = result[current]
                for (a, b) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
                    // Only clean edges (two triangles) carry the orientation across.
                    guard let pair = byEdge[MeshEdge(a, b)], pair.count == 2 else { continue }
                    for other in pair where other != current && !visited[other] {
                        visited[other] = true
                        if walks(result[other], a, b) { result[other] = (result[other].0, result[other].2, result[other].1) }
                        queue.append(other)
                    }
                }
            }
            let volume = piece.reduce(0.0) { sum, index in
                let tri = result[index]
                return sum + positions[tri.0].dot(positions[tri.1].cross(positions[tri.2]))
            }
            if volume < 0 {
                for index in piece {
                    result[index] = (result[index].0, result[index].2, result[index].1)
                }
            }
        }
        return result
    }

    /// New triangles closing each hole: the loop of open edges around it, fanned from its middle (a flat hole gets a
    /// flat cap, a bent one a shallow tent).
    static func caps(for tris: [(Int, Int, Int)], positions: inout [Vec3]) -> [(Int, Int, Int)] {
        var directed = Set<SIMD2<Int>>()
        for tri in tris {
            for (a, b) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
                directed.insert(SIMD2(a, b))
            }
        }
        // The hole's rim runs the other way round from the triangles beside it.
        var next: [Int: Int] = [:]
        for edge in directed where !directed.contains(SIMD2(edge.y, edge.x)) {
            next[edge.y] = edge.x
        }
        var caps: [(Int, Int, Int)] = []
        var used = Set<Int>()
        for start in next.keys.sorted() where !used.contains(start) {
            var loop = [start]
            used.insert(start)
            var current = start
            while let following = next[current], following != start, !used.contains(following), loop.count < 100_000 {
                loop.append(following)
                used.insert(following)
                current = following
            }
            guard loop.count >= 3, next[current] == start else { continue }
            if loop.count == 3 {
                caps.append((loop[0], loop[1], loop[2]))
                continue
            }
            let middle = loop.reduce(Vec3.zero) { $0 + positions[$1] } / Double(loop.count)
            positions.append(middle)
            let centre = positions.count - 1
            for index in loop.indices {
                caps.append((loop[index], loop[(index + 1) % loop.count], centre))
            }
        }
        return caps
    }

    // MARK: Walls

    /// Faces whose wall (the distance straight through the solid behind them) is under `minimum`, and the thinnest
    /// wall found. Each face is sampled at its middle and at its triangles' middles.
    public static func walls(_ mesh: EditableMesh, minimum: Double) -> (thin: Set<Int>, thinnest: Double?) {
        let triangulated = mesh.triangulated()
        let triangles = triangulated.triangles.map { (mesh.vertices[$0.0], mesh.vertices[$0.1], mesh.vertices[$0.2]) }
        let size = max(mesh.bounds?.size.maxComponent ?? 1, 1e-3)
        var thin = Set<Int>()
        var thinnest: Double?
        var samplesByFace: [Int: [Vec3]] = [:]
        for (index, triangle) in triangles.enumerated() {
            samplesByFace[triangulated.faceOfTriangle[index], default: []].append((triangle.0 + triangle.1 + triangle.2) / 3)
        }
        for face in mesh.faces.indices {
            let inward = -mesh.normal(of: face)
            let samples = [mesh.centroid(of: face)] + (samplesByFace[face] ?? []).prefix(8)
            for sample in samples {
                let lead = size * 1e-7
                guard let hit = nearestHit(Ray(origin: sample + inward * lead, direction: inward), triangles, skipping: face,
                                           faceOf: triangulated.faceOfTriangle) else { continue }
                let distance = hit + lead
                thinnest = min(thinnest ?? distance, distance)
                if distance < minimum { thin.insert(face) }
            }
        }
        return (thin, thinnest)
    }

    static func nearestHit(_ ray: Ray, _ triangles: [(Vec3, Vec3, Vec3)], skipping face: Int, faceOf: [Int]) -> Double? {
        var best: Double?
        for (index, triangle) in triangles.enumerated() where faceOf[index] != face {
            if let distance = intersect(ray, triangle), distance < best ?? .infinity { best = distance }
        }
        return best
    }

    /// Möller–Trumbore, both sides.
    static func intersect(_ ray: Ray, _ triangle: (Vec3, Vec3, Vec3)) -> Double? {
        let edge1 = triangle.1 - triangle.0, edge2 = triangle.2 - triangle.0
        let p = ray.direction.cross(edge2)
        let determinant = edge1.dot(p)
        guard abs(determinant) > 1e-24 else { return nil }
        let inverse = 1 / determinant
        let s = ray.origin - triangle.0
        let u = s.dot(p) * inverse
        guard u >= -1e-12, u <= 1 + 1e-12 else { return nil }
        let q = s.cross(edge1)
        let v = ray.direction.dot(q) * inverse
        guard v >= -1e-12, u + v <= 1 + 1e-12 else { return nil }
        let t = edge2.dot(q) * inverse
        return t > 0 ? t : nil
    }
}

public extension ModelingOperations {
    /// Repairs an object's shape for printing (one undo step); it becomes an editable mesh if it wasn't.
    static func repairForPrinting(_ id: ObjectID, in scene: Scene) throws(Failure) -> EditCommand {
        guard let object = scene.objects[id], let (mesh, bakes) = bakedMesh(of: object) else { throw .notEditable }
        return .batch("Repair for printing", setMesh(id, PrintCheck.repair(mesh), bakesScale: bakes))
    }

    /// The object's shape in the world, for checking.
    static func worldMesh(of id: ObjectID, in scene: Scene) -> EditableMesh? {
        guard let object = scene.objects[id], let mesh = editableMesh(of: object) else { return nil }
        return mesh.transformed(by: scene.worldTransform(of: id))
    }
}
