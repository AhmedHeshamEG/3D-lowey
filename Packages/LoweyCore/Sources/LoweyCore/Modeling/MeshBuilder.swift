import Foundation

/// Turns triangles (a primitive, an import, a boolean's result) into an editable mesh with real faces: vertices
/// welded, neighbouring triangles on one plane merged into one face (holes kept), and corners that only sit on a
/// straight edge removed. That's what makes a boolean's result clean to keep modelling: the top of a block with a hole
/// through it is one face with one hole, not forty slivers.
public enum MeshBuilder {
    /// `weld` merges positions that nearly coincide (meshes made for rendering repeat corners along seams); a
    /// boolean's result is already connected exactly, and welding its near-coincident corners would join pieces it
    /// keeps apart on purpose.
    public static func mesh(positions: [Vec3], triangles: [(Int, Int, Int)], weld shouldWeld: Bool = true) -> EditableMesh {
        let size = Bounds(points: positions).map { $0.size.maxComponent } ?? 1
        // Float inputs (the renderer's meshes, Manifold's results) carry about 1e-7 relative error.
        let tolerance = max(size, 1e-3) * 1e-6
        let (welded, remap) = shouldWeld ? weld(positions, tolerance: tolerance) : (positions, Array(positions.indices))
        let tris = triangles.map { (remap[$0.0], remap[$0.1], remap[$0.2]) }.filter { (tri: (Int, Int, Int)) -> Bool in
            tri.0 != tri.1 && tri.1 != tri.2 && tri.0 != tri.2
        }
        let groups = coplanarGroups(tris, positions: welded, tolerance: tolerance * 10)
        var faces: [EditableMesh.Face] = []
        for group in groups {
            faces += Self.faces(of: group.map { tris[$0] }, positions: welded)
        }
        let cleaned = removeStraightCorners(faces, positions: welded, tolerance: tolerance)
        return compact(EditableMesh(vertices: welded, faces: closeTJunctions(cleaned, positions: welded, tolerance: tolerance)))
    }

    /// From the renderer's triangles (positions only; normals and uvs are recomputed per face).
    public static func mesh(from data: MeshData) -> EditableMesh {
        let positions = data.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
        let triangles = stride(from: 0, to: data.indices.count - 2, by: 3).map {
            (Int(data.indices[$0]), Int(data.indices[$0 + 1]), Int(data.indices[$0 + 2]))
        }
        return mesh(positions: positions, triangles: triangles)
    }

    // MARK: Steps

    /// Merges positions closer than `tolerance`, looking in the neighbouring grid cells too, so two copies of a point
    /// that land on either side of a cell boundary still become one vertex.
    static func weld(_ positions: [Vec3], tolerance: Double) -> ([Vec3], [Int]) {
        var cells: [SIMD3<Int64>: [Int]] = [:]
        var welded: [Vec3] = []
        var remap: [Int] = []
        remap.reserveCapacity(positions.count)
        func cell(_ point: Vec3) -> SIMD3<Int64> {
            SIMD3<Int64>(Int64((point.x / tolerance).rounded(.down)), Int64((point.y / tolerance).rounded(.down)),
                         Int64((point.z / tolerance).rounded(.down)))
        }
        for position in positions {
            let home = cell(position)
            var found: Int?
            search: for dx in -1 ... 1 {
                for dy in -1 ... 1 {
                    for dz in -1 ... 1 {
                        for candidate in cells[home &+ SIMD3(Int64(dx), Int64(dy), Int64(dz))] ?? []
                            where welded[candidate].distance(to: position) <= tolerance {
                            found = candidate
                            break search
                        }
                    }
                }
            }
            if let found {
                remap.append(found)
            } else {
                cells[home, default: []].append(welded.count)
                remap.append(welded.count)
                welded.append(position)
            }
        }
        return (welded, remap)
    }

    /// Triangles grouped by "reachable across an edge while staying on one plane" (union-find).
    static func coplanarGroups(_ tris: [(Int, Int, Int)], positions: [Vec3], tolerance: Double) -> [[Int]] {
        let planes = tris.map { tri -> (normal: Vec3, offset: Double) in
            let normal = (positions[tri.1] - positions[tri.0]).cross(positions[tri.2] - positions[tri.0]).normalized
            return (normal, normal.dot(positions[tri.0]))
        }
        var byEdge: [SIMD2<Int>: Int] = [:]
        for (index, tri) in tris.enumerated() {
            for (a, b) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
                byEdge[SIMD2(a, b)] = index
            }
        }
        // A sliver with no area has no plane of its own: it joins the neighbour across its longest edge, so the
        // corner on that edge ends up in the neighbour's outline instead of leaving a gap.
        let slivers = Set(tris.indices.filter { index in
            let tri = tris[index]
            let ab: Vec3 = positions[tri.1] - positions[tri.0]
            let ac: Vec3 = positions[tri.2] - positions[tri.0]
            return ab.cross(ac).length <= tolerance * tolerance
        })
        var parent = Array(tris.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        for index in slivers {
            let tri = tris[index]
            let sides = [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)]
            let longest = sides.max { positions[$0.0].distance(to: positions[$0.1]) < positions[$1.0].distance(to: positions[$1.1]) }
            if let longest, let other = byEdge[SIMD2(longest.1, longest.0)] { parent[root(index)] = root(other) }
        }
        for (index, tri) in tris.enumerated() where !slivers.contains(index) {
            for (a, b) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
                guard let other = byEdge[SIMD2(b, a)], !slivers.contains(other) else { continue }
                let p = planes[index], q = planes[other]
                guard p.normal.dot(q.normal) > 1 - 1e-9, abs(p.offset - q.offset) < tolerance else { continue }
                parent[root(index)] = root(other)
            }
        }
        var groups: [Int: [Int]] = [:]
        for index in tris.indices {
            groups[root(index), default: []].append(index)
        }
        return groups.keys.sorted().compactMap { groups[$0] }
    }

    /// The boundary of a group of coplanar triangles, as faces: each outer loop with the holes inside it.
    static func faces(of tris: [(Int, Int, Int)], positions: [Vec3]) -> [EditableMesh.Face] {
        var inside = Set<SIMD2<Int>>()
        for tri in tris {
            for (a, b) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
                inside.insert(SIMD2(a, b))
            }
        }
        // Boundary: directed edges whose reverse isn't in the group.
        var outgoing: [Int: [Int]] = [:]
        for edge in inside where !inside.contains(SIMD2(edge.y, edge.x)) {
            outgoing[edge.x, default: []].append(edge.y)
        }
        let areas = tris.map { tri -> Double in
            let ab: Vec3 = positions[tri.1] - positions[tri.0]
            return ab.cross(positions[tri.2] - positions[tri.0]).length
        }
        guard let largest = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[largest] > 0 else { return [] }
        let first = tris[largest]
        let normal = (positions[first.1] - positions[first.0]).cross(positions[first.2] - positions[first.0]).normalized
        let frame = PlaneFrame(normal: normal, origin: positions[first.0])
        let loops = chainLoops(&outgoing, frame: frame, positions: positions).flatMap(splitAtRepeats)
        var outlines: [[Int]] = []
        var holes: [[Int]] = []
        for loop in loops {
            let area = area(loop, frame, positions)
            if area > 0 { outlines.append(loop) } else if area < 0 { holes.append(loop) }
        }
        guard !outlines.isEmpty else { return [] }
        var faces = outlines.map { EditableMesh.Face($0) }
        for hole in holes {
            // A point just inside the face beside the hole's first edge (the face is on the left of a hole's edges);
            // a hole corner itself can sit on an outline and say nothing.
            let a = frame.project(positions[hole[0]]), b = frame.project(positions[hole[1]])
            let along = b - a
            let length = max(along.length, 1e-300)
            let probe = Vec2((a.x + b.x) / 2 - along.y / length * length * 1e-4, (a.y + b.y) / 2 + along.x / length * length * 1e-4)
            let owner = outlines.indices
                .filter { Outlines.contains(outlines[$0].map { frame.project(positions[$0]) }, probe) }
                .min { abs(area(outlines[$0], frame, positions)) < abs(area(outlines[$1], frame, positions)) }
            // Never drop a hole: that would open the solid.
            let slot = owner ?? outlines.indices.max { area(outlines[$0], frame, positions) < area(outlines[$1], frame, positions) } ?? 0
            faces[slot].loops.append(hole)
        }
        return faces
    }

    /// A loop that passes a corner twice (a hole touching the outline there) becomes two simple loops.
    static func splitAtRepeats(_ loop: [Int]) -> [[Int]] {
        var seen: [Int: Int] = [:]
        for (index, vertex) in loop.enumerated() {
            if let first = seen[vertex] {
                let inner = Array(loop[first ..< index])
                let outer = Array(loop[..<first] + loop[index...])
                return splitAtRepeats(inner) + splitAtRepeats(outer)
            }
            seen[vertex] = index
        }
        return loop.count >= 3 ? [loop] : []
    }

    private static func area(_ loop: [Int], _ frame: PlaneFrame, _ positions: [Vec3]) -> Double {
        PolygonTriangulator.signedArea(loop.map { frame.project(positions[$0]) })
    }

    /// Walks boundary edges into closed loops. Where two loops touch at a corner, it takes the sharpest turn to the
    /// right, which keeps each loop simple.
    static func chainLoops(_ outgoing: inout [Int: [Int]], frame: PlaneFrame, positions: [Vec3]) -> [[Int]] {
        var loops: [[Int]] = []
        while let start = outgoing.keys.min() {
            var loop = [start]
            var previous: Int?
            var current = start
            var steps = 0
            while steps < 1_000_000 {
                steps += 1
                guard var options = outgoing[current], !options.isEmpty else { break }
                var pick = 0
                if options.count > 1, let previous {
                    let incoming = frame.project(positions[current]) - frame.project(positions[previous])
                    let turns = options.map { next -> Double in
                        let out = frame.project(positions[next]) - frame.project(positions[current])
                        return atan2(incoming.cross(out), incoming.x * out.x + incoming.y * out.y)
                    }
                    pick = turns.indices.min { turns[$0] < turns[$1] } ?? 0
                }
                let next = options.remove(at: pick)
                outgoing[current] = options.isEmpty ? nil : options
                if next == start { break }
                loop.append(next)
                previous = current
                current = next
            }
            if loop.count >= 3 { loops.append(loop) }
        }
        return loops
    }

    /// Drops corners that sit on a straight run where two faces meet (left over where coplanar triangles met). A
    /// corner goes from both loops or from neither, and never when a loop would be left with fewer than three, so
    /// the faces stay stitched together.
    static func removeStraightCorners(_ faces: [EditableMesh.Face], positions: [Vec3], tolerance: Double) -> [EditableMesh.Face] {
        var straight = [Bool](repeating: true, count: positions.count)
        var uses = [Int](repeating: 0, count: positions.count)
        for face in faces {
            for loop in face.loops {
                for index in loop.indices {
                    let vertex = loop[index]
                    uses[vertex] += 1
                    let prev = positions[loop[(index + loop.count - 1) % loop.count]], next = positions[loop[(index + 1) % loop.count]]
                    let a = positions[vertex] - prev, b = next - positions[vertex]
                    if !(a.cross(b).length <= tolerance * max(a.length, b.length) && a.dot(b) > 0) { straight[vertex] = false }
                }
            }
        }
        var removable = Set(positions.indices.filter { straight[$0] && uses[$0] == 2 })
        // Keep corners a loop can't spare, until nothing changes.
        var changed = true
        while changed {
            changed = false
            for face in faces {
                for loop in face.loops where loop.count(where: { !removable.contains($0) }) < 3 {
                    for vertex in loop where removable.remove(vertex) != nil {
                        changed = true
                    }
                }
            }
        }
        return faces.map { face in
            EditableMesh.Face(loops: face.loops.map { loop in loop.filter { !removable.contains($0) } })
        }
    }

    /// Where one face's edge runs past a corner that only its neighbour kept (two corners a hair apart on one straight
    /// edge, each kept by a different face), the corner is put into that edge too, so every edge is walked both ways.
    static func closeTJunctions(_ faces: [EditableMesh.Face], positions: [Vec3], tolerance: Double) -> [EditableMesh.Face] {
        var faces = faces
        for _ in 0 ..< 4 {
            var walked = Set<SIMD2<Int>>()
            for face in faces {
                for loop in face.loops {
                    for index in loop.indices {
                        walked.insert(SIMD2(loop[index], loop[(index + 1) % loop.count]))
                    }
                }
            }
            let open = walked.filter { !walked.contains(SIMD2($0.y, $0.x)) }
            guard !open.isEmpty else { return faces }
            let loose = Set(open.flatMap { [$0.x, $0.y] })
            var changed = false
            for faceIndex in faces.indices {
                faces[faceIndex].loops = faces[faceIndex].loops.map { loop in
                    var result: [Int] = []
                    for index in loop.indices {
                        let from = loop[index], to = loop[(index + 1) % loop.count]
                        result.append(from)
                        guard open.contains(SIMD2(from, to)) else { continue }
                        let start = positions[from], along = positions[to] - start
                        let length = along.length
                        guard length > 0 else { continue }
                        let direction = along / length
                        let between = loose.filter { vertex in
                            guard vertex != from, vertex != to else { return false }
                            let offset = positions[vertex] - start
                            let t = offset.dot(direction)
                            return t > tolerance && t < length - tolerance && (offset - direction * t).length <= tolerance
                        }
                        let ordered = between.sorted { (positions[$0] - start).dot(direction) < (positions[$1] - start).dot(direction) }
                        if !ordered.isEmpty { changed = true }
                        result += ordered
                    }
                    return result
                }
            }
            if !changed { return faces }
        }
        return faces
    }

    /// Removes vertices no face uses and renumbers.
    public static func compact(_ mesh: EditableMesh) -> EditableMesh {
        var remap = [Int](repeating: -1, count: mesh.vertices.count)
        var vertices: [Vec3] = []
        let faces = mesh.faces.map { face in
            EditableMesh.Face(loops: face.loops.map { loop in
                loop.map { old -> Int in
                    if remap[old] < 0 {
                        remap[old] = vertices.count
                        vertices.append(mesh.vertices[old])
                    }
                    return remap[old]
                }
            })
        }
        return EditableMesh(vertices: vertices, faces: faces)
    }
}
