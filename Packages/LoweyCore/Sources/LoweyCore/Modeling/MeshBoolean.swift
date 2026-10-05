import Foundation
import ManifoldCpp

/// Union, subtract and intersect of closed solids, by Manifold (vendored, Apache-2.0). Both meshes are in one space;
/// the result comes back through `MeshBuilder`, so coplanar pieces are merged into whole faces and it's welded.
public enum MeshBoolean {
    public enum Operation: String, Codable, Sendable, CaseIterable {
        case union, subtract, intersect

        public var label: String {
            switch self {
            case .union: "Union"
            case .subtract: "Subtract"
            case .intersect: "Intersect"
            }
        }

        var bridged: MBOperation {
            switch self {
            case .union: MBUnion
            case .subtract: MBSubtract
            case .intersect: MBIntersect
            }
        }
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// One of the inputs has a hole in its surface or faces turned inside out.
        case notSolid
        case invalidInput
        case failed
        /// The operation removed everything (e.g. subtracting a bigger shape, or intersecting shapes that don't touch).
        case nothingLeft

        public var description: String {
            switch self {
            case .notSolid: "One of the shapes isn't a closed solid. Repair it first (Model ▸ Check)."
            case .invalidInput: "One of the shapes has broken geometry."
            case .failed: "The shapes couldn't be combined."
            case .nothingLeft: "Nothing would be left."
            }
        }
    }

    public static func combine(_ a: EditableMesh, _ b: EditableMesh, _ operation: Operation) throws(Failure) -> EditableMesh {
        let left = Flattened(a), right = Flattened(b)
        var result = MBMesh()
        let status = left.withMesh { meshA in
            right.withMesh { meshB in
                MBBoolean(meshA, meshB, operation.bridged, 0, &result)
            }
        }
        defer { MBMeshFree(&result) }
        try check(status)
        guard result.triangleCount > 0, let positionsPointer = result.positions, let trianglesPointer = result.triangles else {
            throw .nothingLeft
        }
        // Corners Manifold kept are the inputs' own (bit for bit in Float): give them back their Double positions,
        // so modelling with exact numbers stays exact through any number of booleans.
        var exact: [SIMD3<Float>: Vec3] = [:]
        for vertex in a.vertices + b.vertices {
            exact[vertex.float3] = vertex
        }
        let positions = (0 ..< result.vertexCount).map { index -> Vec3 in
            let point = SIMD3<Float>(positionsPointer[index * 3], positionsPointer[index * 3 + 1], positionsPointer[index * 3 + 2])
            return exact[point] ?? Vec3(Double(point.x), Double(point.y), Double(point.z))
        }
        let triangles = (0 ..< result.triangleCount).map {
            (Int(trianglesPointer[$0 * 3]), Int(trianglesPointer[$0 * 3 + 1]), Int(trianglesPointer[$0 * 3 + 2]))
        }
        return MeshBuilder.mesh(positions: positions, triangles: triangles, weld: false)
    }

    /// Whether Manifold accepts the mesh as a closed solid (what booleans and 3D printing need).
    public static func isSolid(_ mesh: EditableMesh) -> Bool {
        guard !mesh.isEmpty else { return false }
        let flat = Flattened(mesh)
        return flat.withMesh { MBValidate($0) } == MBOk
    }

    private static func check(_ status: MBStatus) throws(Failure) {
        switch status {
        case MBOk: return
        case MBNotManifold: throw .notSolid
        case MBInvalidInput: throw .invalidInput
        default: throw .failed
        }
    }

    /// A mesh as the flat arrays the C face reads.
    private struct Flattened {
        var positions: [Float]
        var triangles: [UInt32]
        var tags: [UInt32]

        init(_ mesh: EditableMesh) {
            positions = mesh.vertices.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
            let tris = mesh.triangulated()
            triangles = tris.triangles.flatMap { [UInt32($0.0), UInt32($0.1), UInt32($0.2)] }
            tags = tris.faceOfTriangle.map { UInt32($0) }
        }

        func withMesh<T>(_ body: (UnsafePointer<MBMesh>) -> T) -> T {
            var positions = positions, triangles = triangles, tags = tags
            return positions.withUnsafeMutableBufferPointer { p in
                triangles.withUnsafeMutableBufferPointer { t in
                    tags.withUnsafeMutableBufferPointer { g in
                        var mesh = MBMesh(positions: p.baseAddress, vertexCount: p.count / 3, triangles: t.baseAddress,
                                          faceTags: g.baseAddress, triangleCount: t.count / 3)
                        return withUnsafePointer(to: &mesh) { body($0) }
                    }
                }
            }
        }
    }
}
