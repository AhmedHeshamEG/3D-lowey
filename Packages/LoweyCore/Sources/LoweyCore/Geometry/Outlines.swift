import Foundation

/// Closed outlines with holes (letters from a font, cut-outs) → solid extruded meshes.
public enum Outlines {
    /// Groups contours into shapes: each outer contour with the holes directly inside it (even-odd nesting).
    public static func shapes(_ contours: [[Vec2]]) -> [(outer: [Vec2], holes: [[Vec2]])] {
        let cleaned = contours.map(dropClosingPoint).filter { $0.count >= 3 && abs(DrawingMesher.signedArea($0)) > 1e-10 }
        let depths = cleaned.indices.map { index in
            cleaned.indices.filter { $0 != index && contains(cleaned[$0], cleaned[index][0]) }.count
        }
        var result: [(outer: [Vec2], holes: [[Vec2]])] = []
        var outerIndex: [Int: Int] = [:]
        for index in cleaned.indices where depths[index] % 2 == 0 {
            var outer = cleaned[index]
            if DrawingMesher.signedArea(outer) < 0 { outer.reverse() }
            outerIndex[index] = result.count
            result.append((outer, []))
        }
        for index in cleaned.indices where depths[index] % 2 == 1 {
            // The smallest outer contour that contains this hole.
            let owner = outerIndex.keys
                .filter { contains(cleaned[$0], cleaned[index][0]) }
                .min { abs(DrawingMesher.signedArea(cleaned[$0])) < abs(DrawingMesher.signedArea(cleaned[$1])) }
            guard let owner, let slot = outerIndex[owner] else { continue }
            var hole = cleaned[index]
            if DrawingMesher.signedArea(hole) > 0 { hole.reverse() }
            result[slot].holes.append(hole)
        }
        return result
    }

    /// One simple polygon from an outer contour (counter-clockwise) and its holes (clockwise), joined by bridges
    /// from each hole's rightmost point to a visible outer vertex, so ear clipping can triangulate it.
    public static func merge(outer: [Vec2], holes: [[Vec2]]) -> [Vec2] {
        var polygon = outer
        let ordered = holes.filter { !$0.isEmpty }.sorted { ($0.map(\.x).max() ?? 0) > ($1.map(\.x).max() ?? 0) }
        for hole in ordered {
            guard let rightmost = hole.indices.max(by: { hole[$0].x < hole[$1].x }) else { continue }
            let point = hole[rightmost]
            let candidates = polygon.indices.filter { polygon[$0].x >= point.x - 1e-9 }
            let visible = (candidates.isEmpty ? Array(polygon.indices) : candidates).min { lhs, rhs in
                distance(polygon[lhs], point) < distance(polygon[rhs], point)
            } ?? 0
            // visible → hole (all the way round, back to its start) → visible again → on along the outline.
            let rotatedHole = Array(hole[rightmost...] + hole[..<rightmost])
            polygon.insert(contentsOf: rotatedHole + [point, polygon[visible]], at: visible + 1)
        }
        return polygon
    }

    /// A solid: front face at z = +depth/2 facing +Z, back face at −depth/2, walls along every contour.
    public static func extrude(_ contours: [[Vec2]], depth: Double) -> MeshData {
        var mesh = MeshData()
        let front = Float(depth / 2)
        for shape in shapes(contours) {
            let polygon = merge(outer: shape.outer, holes: shape.holes)
            let triangles = DrawingMesher.triangulate(polygon)
            let frontBase = UInt32(mesh.positions.count)
            for point in polygon {
                mesh.addVertex(SIMD3<Float>(Float(point.x), Float(point.y), front), normal: SIMD3<Float>(0, 0, 1),
                               uv: SIMD2<Float>(Float(point.x), Float(point.y)))
            }
            for triangle in triangles {
                mesh.addTriangle(frontBase + UInt32(triangle.0), frontBase + UInt32(triangle.1), frontBase + UInt32(triangle.2))
            }
            let backBase = UInt32(mesh.positions.count)
            for point in polygon {
                mesh.addVertex(SIMD3<Float>(Float(point.x), Float(point.y), -front), normal: SIMD3<Float>(0, 0, -1),
                               uv: SIMD2<Float>(Float(point.x), Float(point.y)))
            }
            for triangle in triangles {
                mesh.addTriangle(backBase + UInt32(triangle.0), backBase + UInt32(triangle.2), backBase + UInt32(triangle.1))
            }
            for contour in [shape.outer] + shape.holes {
                addWalls(contour, front: front, to: &mesh)
            }
        }
        return mesh
    }

    /// Side walls of a contour (outer counter-clockwise, holes clockwise: normals point out of the solid).
    static func addWalls(_ contour: [Vec2], front: Float, to mesh: inout MeshData) {
        for index in contour.indices {
            let a = contour[index]
            let b = contour[(index + 1) % contour.count]
            let edge = SIMD2<Float>(Float(b.x - a.x), Float(b.y - a.y))
            let length = (edge.x * edge.x + edge.y * edge.y).squareRoot()
            guard length > 1e-7 else { continue }
            let normal = SIMD3<Float>(edge.y / length, -edge.x / length, 0)
            let base = UInt32(mesh.positions.count)
            mesh.addVertex(SIMD3<Float>(Float(a.x), Float(a.y), front), normal: normal)
            mesh.addVertex(SIMD3<Float>(Float(b.x), Float(b.y), front), normal: normal)
            mesh.addVertex(SIMD3<Float>(Float(b.x), Float(b.y), -front), normal: normal)
            mesh.addVertex(SIMD3<Float>(Float(a.x), Float(a.y), -front), normal: normal)
            mesh.addTriangle(base, base + 3, base + 2)
            mesh.addTriangle(base, base + 2, base + 1)
        }
    }

    static func dropClosingPoint(_ contour: [Vec2]) -> [Vec2] {
        guard contour.count > 2, let first = contour.first, let last = contour.last, distance(first, last) < 1e-9 else { return contour }
        return Array(contour.dropLast())
    }

    static func distance(_ a: Vec2, _ b: Vec2) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    /// Even-odd point in polygon.
    static func contains(_ polygon: [Vec2], _ point: Vec2) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
