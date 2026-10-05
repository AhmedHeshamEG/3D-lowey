import Foundation

/// How print files sit: millimetres with Z up (the bed is XY), where the scene is metres with Y up. The turn is a
/// quarter turn about X, so faces keep their winding.
public enum PrintSpace {
    public static let millimetresPerMetre = 1000.0

    /// Scene (metres, Y up) → print file (millimetres, Z up).
    public static func toFile(_ point: Vec3) -> Vec3 {
        Vec3(point.x, -point.z, point.y) * millimetresPerMetre
    }

    /// Print file (millimetres, Z up) → scene (metres, Y up).
    public static func fromFile(_ point: Vec3) -> Vec3 {
        Vec3(point.x, point.z, -point.y) / millimetresPerMetre
    }
}

/// STL, the 3D-printing lingua franca: triangles only, no units (slicers read millimetres), no colour.
public enum STLFile {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case empty
        case damaged

        public var description: String {
            switch self {
            case .empty: "That STL file has no triangles."
            case .damaged: "That STL file is damaged."
            }
        }
    }

    // MARK: Writing

    /// A binary STL of the meshes as placed in the world, in millimetres with Z up.
    public static func binary(_ meshes: [ExportMesh], name: String = "Maquette") -> Data {
        let triangles = worldTriangles(meshes)
        var data = Data()
        var header = Data("\(name) - exported from Maquette".utf8.prefix(80))
        header.append(Data(repeating: 0x20, count: 80 - header.count))
        data.append(header)
        append(UInt32(triangles.count), to: &data)
        for (a, b, c) in triangles {
            let normal = (b - a).cross(c - a).normalized
            for vector in [normal, a, b, c] {
                append(Float(vector.x), to: &data)
                append(Float(vector.y), to: &data)
                append(Float(vector.z), to: &data)
            }
            append(UInt16(0), to: &data)
        }
        return data
    }

    /// Every triangle of the meshes in print space (world placement, millimetres, Z up).
    static func worldTriangles(_ meshes: [ExportMesh]) -> [(Vec3, Vec3, Vec3)] {
        var result: [(Vec3, Vec3, Vec3)] = []
        for item in meshes {
            let points = item.mesh.positions.map { PrintSpace.toFile(item.transform.apply(to: Vec3(Double($0.x), Double($0.y), Double($0.z)))) }
            let mirrored = item.transform.scale.x * item.transform.scale.y * item.transform.scale.z < 0
            for index in stride(from: 0, to: item.mesh.indices.count - 2, by: 3) {
                let a = points[Int(item.mesh.indices[index])], b = points[Int(item.mesh.indices[index + 1])]
                let c = points[Int(item.mesh.indices[index + 2])]
                result.append(mirrored ? (a, c, b) : (a, b, c))
            }
        }
        return result
    }

    // MARK: Reading

    /// Reads binary or ASCII STL into a mesh in scene space (metres, Y up), corners that share a position welded.
    public static func read(_ data: Data) throws(Failure) -> MeshData {
        let triangles = try isBinary(data) ? readBinary(data) : readASCII(data)
        guard !triangles.isEmpty else { throw .empty }
        var mesh = MeshData()
        var index: [SIMD3<Float>: UInt32] = [:]
        for corner in triangles.flatMap(\.self) {
            let point = PrintSpace.fromFile(corner).float3
            if let existing = index[point] {
                mesh.indices.append(existing)
            } else {
                let next = UInt32(mesh.positions.count)
                index[point] = next
                mesh.positions.append(point)
                mesh.indices.append(next)
            }
        }
        mesh.computeSmoothNormals()
        mesh.uvs = Array(repeating: .zero, count: mesh.positions.count)
        return mesh
    }

    /// Binary STL is exactly 84 + 50 bytes per triangle; an ASCII file that starts with "solid" isn't.
    static func isBinary(_ data: Data) -> Bool {
        guard data.count >= 84 else { return false }
        let count = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self).littleEndian })
        return data.count == 84 + count * 50 || !(String(data: data.prefix(5), encoding: .ascii) == "solid")
    }

    static func readBinary(_ data: Data) throws(Failure) -> [[Vec3]] {
        let count = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self).littleEndian })
        guard data.count >= 84 + count * 50 else { throw .damaged }
        return data.withUnsafeBytes { raw in
            (0 ..< count).map { triangle in
                let base = 84 + triangle * 50 + 12
                return (0 ..< 3).map { corner in
                    let offset = base + corner * 12
                    func float(_ at: Int) -> Double {
                        Double(Float(bitPattern: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian))
                    }
                    return Vec3(float(offset), float(offset + 4), float(offset + 8))
                }
            }
        }
    }

    static func readASCII(_ data: Data) throws(Failure) -> [[Vec3]] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw .damaged }
        var corners: [Vec3] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace)
            guard words.first == "vertex", words.count >= 4 else { continue }
            guard let x = Double(words[1]), let y = Double(words[2]), let z = Double(words[3]) else { throw .damaged }
            corners.append(Vec3(x, y, z))
        }
        guard corners.count % 3 == 0 else { throw .damaged }
        return stride(from: 0, to: corners.count, by: 3).map { Array(corners[$0 ..< $0 + 3]) }
    }

    // MARK: Bytes

    static func append(_ value: UInt32, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    static func append(_ value: UInt16, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    static func append(_ value: Float, to data: inout Data) {
        append(value.bitPattern, to: &data)
    }
}
