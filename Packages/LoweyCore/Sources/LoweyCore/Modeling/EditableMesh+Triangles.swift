import Foundation

/// Triangles over an editable mesh's own vertex indices, each tagged with the face it came from.
public struct MeshTriangles: Sendable {
    public var triangles: [(Int, Int, Int)]
    public var faceOfTriangle: [Int]
}

public extension EditableMesh {
    /// Every face cut into counter-clockwise triangles that share the mesh's vertices (what a boolean needs).
    func triangulated() -> MeshTriangles {
        var result = MeshTriangles(triangles: [], faceOfTriangle: [])
        for index in faces.indices {
            for triangle in triangulate(face: index) {
                result.triangles.append(triangle)
                result.faceOfTriangle.append(index)
            }
        }
        return result
    }

    /// One face's triangles, as vertex indices.
    func triangulate(face index: Int) -> [(Int, Int, Int)] {
        let face = faces[index]
        let outline = face.outline
        if face.loops.count == 1, outline.count == 3 { return [(outline[0], outline[1], outline[2])] }
        let frame = PlaneFrame(normal: normal(of: index), origin: vertices[outline[0]])
        let loops = face.loops.map { loop in loop.map { (vertex: $0, point: frame.project(vertices[$0])) } }
        return PolygonTriangulator.triangulate(outline: loops[0], holes: Array(loops.dropFirst()))
    }

    /// Flat-shaded triangles for the renderer: each face gets its own vertices with its normal, so edges stay crisp.
    func renderMesh() -> MeshData {
        var mesh = MeshData()
        for index in faces.indices {
            let faceNormal = normal(of: index)
            let shading = faceNormal.float3
            let frame = PlaneFrame(normal: faceNormal, origin: vertices[faces[index].outline[0]])
            var local: [Int: UInt32] = [:]
            for triangle in triangulate(face: index) {
                let corners = [triangle.0, triangle.1, triangle.2].map { vertex -> UInt32 in
                    if let existing = local[vertex] { return existing }
                    let uv = frame.project(vertices[vertex])
                    let added = mesh.addVertex(vertices[vertex].float3, normal: shading, uv: SIMD2<Float>(Float(uv.x), Float(uv.y)))
                    local[vertex] = added
                    return added
                }
                mesh.addTriangle(corners[0], corners[1], corners[2])
            }
        }
        return mesh
    }
}

/// A plane with two in-plane axes, to flatten a face into 2D and lift points back.
public struct PlaneFrame: Hashable, Sendable, Codable {
    public var origin: Vec3
    public var normal: Vec3
    public var u: Vec3
    public var v: Vec3

    public init(normal: Vec3, origin: Vec3) {
        let n = normal.normalized
        // Any vector not parallel to n; then u ⟂ n and v = n × u (right-handed, so CCW stays CCW).
        let helper = abs(n.y) < 0.9 ? Vec3.unitY : Vec3.unitX
        let u = helper.cross(n).normalized
        self.init(origin: origin, normal: n, u: u, v: n.cross(u))
    }

    public init(origin: Vec3, normal: Vec3, u: Vec3, v: Vec3) {
        self.origin = origin
        self.normal = normal
        self.u = u
        self.v = v
    }

    public func project(_ point: Vec3) -> Vec2 {
        let offset = point - origin
        return Vec2(offset.dot(u), offset.dot(v))
    }

    public func lift(_ point: Vec2, height: Double = 0) -> Vec3 {
        origin + u * point.x + v * point.y + normal * height
    }

    /// Signed distance of a point above the plane.
    public func height(of point: Vec3) -> Double {
        (point - origin).dot(normal)
    }
}

/// Ear clipping for a polygon with holes, over caller-owned vertex ids. Holes are joined to the outline by a bridge
/// to a vertex the hole's rightmost point can see, so the result is one weakly simple polygon; a corner only counts as
/// blocking an ear when it's strictly inside it and isn't a copy of one of the ear's corners.
public enum PolygonTriangulator {
    public typealias Corner = (vertex: Int, point: Vec2)

    public static func triangulate(outline: [Corner], holes: [[Corner]]) -> [(Int, Int, Int)] {
        var polygon = signedArea(outline.map(\.point)) < 0 ? Array(outline.reversed()) : outline
        let ordered = holes.map { signedArea($0.map(\.point)) > 0 ? Array($0.reversed()) : $0 }
            .filter { $0.count >= 3 }
            .sorted { ($0.map(\.point.x).max() ?? 0) > ($1.map(\.point.x).max() ?? 0) }
        for hole in ordered {
            polygon = bridge(hole, into: polygon)
        }
        return clip(polygon)
    }

    static func bridge(_ hole: [Corner], into polygon: [Corner]) -> [Corner] {
        guard let start = hole.indices.max(by: { hole[$0].point.x < hole[$1].point.x }) else { return polygon }
        let point = hole[start].point
        // The nearest outline corner whose segment to the hole's rightmost point crosses no edge.
        let order = polygon.indices.sorted { distance(polygon[$0].point, point) < distance(polygon[$1].point, point) }
        let target = order.first { candidate in
            let to = polygon[candidate].point
            return !crossesAny(point, to, polygon) && !crossesAny(point, to, hole)
        } ?? order.first ?? 0
        let rotated = Array(hole[start...] + hole[..<start])
        var result = polygon
        result.insert(contentsOf: rotated + [hole[start], polygon[target]], at: target + 1)
        return result
    }

    static func clip(_ polygon: [Corner]) -> [(Int, Int, Int)] {
        var remaining = polygon
        var triangles: [(Int, Int, Int)] = []
        var stall = 0
        var index = 0
        while remaining.count > 3, stall < remaining.count {
            let count = remaining.count
            let prev = remaining[(index + count - 1) % count], current = remaining[index % count], next = remaining[(index + 1) % count]
            if isEar(prev.point, current.point, next.point, among: remaining) {
                triangles.append((prev.vertex, current.vertex, next.vertex))
                remaining.remove(at: index % count)
                stall = 0
                index = max(index - 1, 0)
            } else {
                index = (index + 1) % count
                stall += 1
            }
        }
        if remaining.count == 3 {
            triangles.append((remaining[0].vertex, remaining[1].vertex, remaining[2].vertex))
        } else if remaining.count > 3 {
            // Degenerate leftovers (collinear runs): a fan keeps the face closed.
            for corner in 1 ..< remaining.count - 1 {
                triangles.append((remaining[0].vertex, remaining[corner].vertex, remaining[corner + 1].vertex))
            }
        }
        return triangles.filter { $0.0 != $0.1 && $0.1 != $0.2 && $0.0 != $0.2 }
    }

    static func isEar(_ a: Vec2, _ b: Vec2, _ c: Vec2, among corners: [Corner]) -> Bool {
        let turn = (b - a).cross(c - b)
        guard turn > 1e-14 * max(1, (b - a).length * (c - b).length) else { return false }
        for corner in corners {
            let p = corner.point
            if same(p, a) || same(p, b) || same(p, c) { continue }
            if strictlyInside(p, a, b, c) { return false }
        }
        return true
    }

    static func strictlyInside(_ p: Vec2, _ a: Vec2, _ b: Vec2, _ c: Vec2) -> Bool {
        let d1 = (b - a).cross(p - a), d2 = (c - b).cross(p - b), d3 = (a - c).cross(p - c)
        let epsilon = 1e-14
        return d1 > epsilon && d2 > epsilon && d3 > epsilon
    }

    static func crossesAny(_ p: Vec2, _ q: Vec2, _ loop: [Corner]) -> Bool {
        for index in loop.indices {
            let a = loop[index].point, b = loop[(index + 1) % loop.count].point
            if same(a, p) || same(a, q) || same(b, p) || same(b, q) { continue }
            if segmentsCross(p, q, a, b) { return true }
        }
        return false
    }

    static func segmentsCross(_ p: Vec2, _ q: Vec2, _ a: Vec2, _ b: Vec2) -> Bool {
        let d1 = (q - p).cross(a - p), d2 = (q - p).cross(b - p)
        let d3 = (b - a).cross(p - a), d4 = (b - a).cross(q - a)
        return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0))
    }

    static func same(_ lhs: Vec2, _ rhs: Vec2) -> Bool {
        abs(lhs.x - rhs.x) < 1e-12 && abs(lhs.y - rhs.y) < 1e-12
    }

    static func distance(_ lhs: Vec2, _ rhs: Vec2) -> Double {
        (lhs - rhs).length
    }

    public static func signedArea(_ points: [Vec2]) -> Double {
        var area = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        return area / 2
    }
}
