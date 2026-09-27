import Foundation

/// Minimal Wavefront OBJ reader: positions, normals, UVs, polygon faces (triangulated),
/// negative indices. Materials are ignored; the object takes a palette color instead.
public enum OBJParser {
    public enum ParseError: Error, Equatable {
        case noGeometry
    }

    public static func parse(_ text: String) throws -> MeshData {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var mesh = MeshData()
        var cache: [String: UInt32] = [:]
        var hasNormals = true

        func resolve(_ index: Int, count: Int) -> Int? {
            let resolved = index > 0 ? index - 1 : count + index
            return (0 ..< count).contains(resolved) ? resolved : nil
        }

        func vertex(for token: Substring) -> UInt32? {
            let key = String(token)
            if let existing = cache[key] { return existing }
            let parts = token.split(separator: "/", omittingEmptySubsequences: false)
            guard let first = parts.first, let rawPosition = Int(first),
                  let positionIndex = resolve(rawPosition, count: positions.count) else { return nil }
            var uv = SIMD2<Float>(0, 0)
            if parts.count > 1, let rawUV = Int(parts[1]), let uvIndex = resolve(rawUV, count: uvs.count) {
                uv = uvs[uvIndex]
            }
            var normal = SIMD3<Float>(0, 1, 0)
            if parts.count > 2, let rawNormal = Int(parts[2]), let normalIndex = resolve(rawNormal, count: normals.count) {
                normal = normals[normalIndex]
            } else {
                hasNormals = false
            }
            let index = mesh.addVertex(positions[positionIndex], normal: normal, uv: uv)
            cache[key] = index
            return index
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let head = tokens.first else { continue }
            let values = tokens.dropFirst()
            switch head {
            case "v":
                let numbers = values.prefix(3).compactMap { Float($0) }
                if numbers.count == 3 { positions.append(SIMD3<Float>(numbers[0], numbers[1], numbers[2])) }
            case "vn":
                let numbers = values.prefix(3).compactMap { Float($0) }
                if numbers.count == 3 { normals.append(SIMD3<Float>(numbers[0], numbers[1], numbers[2])) }
            case "vt":
                let numbers = values.prefix(2).compactMap { Float($0) }
                if numbers.count == 2 { uvs.append(SIMD2<Float>(numbers[0], numbers[1])) }
            case "f":
                let face = values.compactMap { vertex(for: $0) }
                guard face.count >= 3 else { continue }
                for index in 1 ..< face.count - 1 {
                    mesh.addTriangle(face[0], face[index], face[index + 1])
                }
            default:
                continue
            }
        }
        guard !mesh.indices.isEmpty else { throw ParseError.noGeometry }
        if !hasNormals || normals.isEmpty {
            mesh = mesh.autoSmoothed()
        }
        return mesh
    }
}

/// Files a glTF (.gltf JSON) references, so importing copies its .bin and textures along.
public enum GLTFDependencies {
    public static func referencedURIs(in json: Data) -> [String] {
        guard let root = try? LoweyJSON.decode(JSONValue.self, from: json) else { return [] }
        var uris: [String] = []
        for key in ["buffers", "images"] {
            for entry in root[key]?.arrayValue ?? [] {
                if let uri = entry["uri"]?.stringValue, !uri.hasPrefix("data:") {
                    uris.append(uri.removingPercentEncoding ?? uri)
                }
            }
        }
        return uris
    }
}
