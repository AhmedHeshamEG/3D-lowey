import Foundation

/// Reads the drawable part of glTF / GLB files in pure Swift: every mesh primitive (triangles) with its material,
/// the images, and the skin (joints, weights, inverse bind matrices). Static meshes come out in model space (node
/// transforms baked in); skinned meshes stay in bind space. Tested on Linux; the engine only uploads the result.
public enum GLTFMeshReader {
    public static func model(contentsOf url: URL) throws -> ImportedModel {
        try model(data: Data(contentsOf: url), baseURL: url.deletingLastPathComponent())
    }

    public static func model(data: Data, baseURL: URL? = nil) throws -> ImportedModel {
        let file = try GLTFReader.parse(data, baseURL: baseURL)
        let nodes = file.array("nodes")
        let globals = globalTransforms(file)
        let skinNode = nodes.indices.first { nodes[$0]["skin"] != nil && nodes[$0]["mesh"] != nil }
        var parts: [ImportedPart] = []
        for (index, node) in nodes.enumerated() {
            guard let meshIndex = node["mesh"] as? Int else { continue }
            let skinned = node["skin"] is Int
            parts += try meshParts(file, mesh: meshIndex, transform: skinned ? .identity : globals[index] ?? .identity, skinned: skinned)
        }
        return try ImportedModel(parts: parts, materials: materials(file), textures: textures(file, baseURL: baseURL),
                                 skin: skinNode.flatMap { try? skin(file, globals: globals, node: $0) })
    }

    // MARK: Nodes

    /// Global transform of every node reachable from the default scene (or every root).
    static func globalTransforms(_ file: GLTFReader.File) -> [Int: Transform] {
        let nodes = file.array("nodes")
        var parentOf: [Int: Int] = [:]
        for (index, node) in nodes.enumerated() {
            for child in node["children"] as? [Int] ?? [] {
                parentOf[child] = index
            }
        }
        var globals: [Int: Transform] = [:]
        func visit(_ index: Int, parent: Transform, depth: Int) {
            guard index < nodes.count, depth < 256, globals[index] == nil else { return }
            let global = parent * GLTFReader.localTransform(nodes[index])
            globals[index] = global
            for child in nodes[index]["children"] as? [Int] ?? [] {
                visit(child, parent: global, depth: depth + 1)
            }
        }
        for index in nodes.indices where parentOf[index] == nil {
            visit(index, parent: .identity, depth: 0)
        }
        return globals
    }

    // MARK: Meshes

    static func meshParts(_ file: GLTFReader.File, mesh index: Int, transform: Transform, skinned: Bool) throws -> [ImportedPart] {
        let meshes = file.array("meshes")
        guard index < meshes.count else { throw GLTFReadError.malformed("mesh \(index)") }
        let name = meshes[index]["name"] as? String ?? "Mesh \(index)"
        var parts: [ImportedPart] = []
        for (primitiveIndex, primitive) in (meshes[index]["primitives"] as? [[String: Any]] ?? []).enumerated() {
            // Triangles only (points and lines have no surface to shade).
            guard (primitive["mode"] as? Int ?? 4) == 4, let attributes = primitive["attributes"] as? [String: Any],
                  let positionAccessor = attributes["POSITION"] as? Int else { continue }
            var part = try primitivePart(file, attributes: attributes, positions: positionAccessor, indices: primitive["indices"] as? Int,
                                         name: primitiveIndex == 0 ? name : "\(name) \(primitiveIndex + 1)",
                                         material: primitive["material"] as? Int ?? 0, skinned: skinned)
            if transform != .identity {
                part.mesh = part.mesh.transformed(transform)
            }
            parts.append(part)
        }
        return parts
    }

    static func primitivePart(_ file: GLTFReader.File, attributes: [String: Any], positions positionAccessor: Int, indices: Int?,
                              name: String, material: Int, skinned: Bool) throws -> ImportedPart {
        var mesh = MeshData()
        let positions = try GLTFReader.accessor(file, positionAccessor)
        mesh.positions = stride(from: 0, to: positions.values.count - 2, by: positions.components).map {
            SIMD3<Float>(Float(positions.values[$0]), Float(positions.values[$0 + 1]), Float(positions.values[$0 + 2]))
        }
        if let normalAccessor = attributes["NORMAL"] as? Int {
            let normals = try GLTFReader.accessor(file, normalAccessor)
            mesh.normals = stride(from: 0, to: normals.values.count - 2, by: normals.components).map {
                normalize3(SIMD3<Float>(Float(normals.values[$0]), Float(normals.values[$0 + 1]), Float(normals.values[$0 + 2])),
                           fallback: SIMD3<Float>(0, 1, 0))
            }
        }
        if let uvAccessor = attributes["TEXCOORD_0"] as? Int {
            let uvs = try GLTFReader.accessor(file, uvAccessor)
            mesh.uvs = stride(from: 0, to: uvs.values.count - 1, by: uvs.components).map {
                SIMD2<Float>(Float(uvs.values[$0]), Float(uvs.values[$0 + 1]))
            }
        }
        if let indices {
            mesh.indices = try GLTFReader.accessor(file, indices).values.map { UInt32(max($0, 0)) }
        } else {
            mesh.indices = (0 ..< UInt32(mesh.positions.count)).map { $0 }
        }
        mesh.indices = mesh.indices.filter { Int($0) < mesh.positions.count }
        mesh.indices.removeLast(mesh.indices.count % 3)
        if mesh.normals.count != mesh.positions.count { mesh.computeSmoothNormals() }
        if mesh.uvs.count != mesh.positions.count { mesh.uvs = Array(repeating: .zero, count: mesh.positions.count) }
        var part = ImportedPart(name: name, mesh: mesh, material: material)
        if skinned, let jointAccessor = attributes["JOINTS_0"] as? Int, let weightAccessor = attributes["WEIGHTS_0"] as? Int {
            let joints = try GLTFReader.accessor(file, jointAccessor)
            let weights = try GLTFReader.accessor(file, weightAccessor)
            guard joints.components == 4, weights.components == 4, joints.count == mesh.positions.count, weights.count == joints.count else {
                return part
            }
            part.joints = (0 ..< joints.count).map { vertex in
                SIMD4<UInt16>((0 ..< 4).map { UInt16(clamping: Int(joints.values[vertex * 4 + $0])) })
            }
            part.weights = (0 ..< weights.count).map { vertex in
                let raw = SIMD4<Float>((0 ..< 4).map { Float(weights.values[vertex * 4 + $0]) })
                let sum = raw.x + raw.y + raw.z + raw.w
                return sum > 1e-6 ? raw / sum : SIMD4<Float>(1, 0, 0, 0)
            }
        }
        return part
    }

    // MARK: Materials & images

    static func materials(_ file: GLTFReader.File) -> [ImportedMaterial] {
        file.array("materials").enumerated().map { index, material in
            let pbr = material["pbrMetallicRoughness"] as? [String: Any] ?? [:]
            let base = GLTFReader.numbers(pbr["baseColorFactor"]) ?? [1, 1, 1, 1]
            let emissive = GLTFReader.numbers(material["emissiveFactor"]) ?? [0, 0, 0]
            let extensions = material["extensions"] as? [String: Any] ?? [:]
            let strength = (extensions["KHR_materials_emissive_strength"] as? [String: Any])?["emissiveStrength"] as? Double ?? 1
            let texture = (pbr["baseColorTexture"] as? [String: Any])?["index"] as? Int
            return ImportedMaterial(
                name: material["name"] as? String ?? "Material \(index + 1)",
                baseColor: base.count == 4 ? RGBA(base[0], base[1], base[2], base[3]) : RGBA(1, 1, 1),
                baseColorTexture: texture.flatMap { imageIndex(file, texture: $0) },
                emissive: emissive.count == 3 ? RGBA(emissive[0], emissive[1], emissive[2]) : RGBA(0, 0, 0),
                emissiveStrength: strength,
                metallic: pbr["metallicFactor"] as? Double ?? 0,
                roughness: pbr["roughnessFactor"] as? Double ?? 1,
                blended: (material["alphaMode"] as? String) == "BLEND",
                doubleSided: material["doubleSided"] as? Bool ?? false
            )
        }
    }

    /// The image a texture shows.
    static func imageIndex(_ file: GLTFReader.File, texture: Int) -> Int? {
        let textures = file.array("textures")
        guard texture < textures.count else { return nil }
        return textures[texture]["source"] as? Int
    }

    static func textures(_ file: GLTFReader.File, baseURL: URL?) throws -> [ImportedTexture] {
        let views = file.array("bufferViews")
        return file.array("images").map { image in
            let mime = image["mimeType"] as? String
            if let viewIndex = image["bufferView"] as? Int, viewIndex < views.count {
                let view = views[viewIndex]
                let buffer = view["buffer"] as? Int ?? 0
                let offset = view["byteOffset"] as? Int ?? 0
                let length = view["byteLength"] as? Int ?? 0
                if buffer < file.buffers.count, offset + length <= file.buffers[buffer].count {
                    return ImportedTexture(data: file.buffers[buffer].subdata(in: offset ..< offset + length), mimeType: mime)
                }
            }
            if let uri = image["uri"] as? String {
                if uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ","),
                   let decoded = Data(base64Encoded: String(uri[uri.index(after: comma)...])) {
                    return ImportedTexture(data: decoded, mimeType: mime)
                }
                if let baseURL, let data = try? Data(contentsOf: baseURL.appendingPathComponent(uri.removingPercentEncoding ?? uri)) {
                    return ImportedTexture(data: data, mimeType: mime)
                }
            }
            return ImportedTexture(data: Data(), mimeType: mime)
        }
    }

    // MARK: Skin

    static func skin(_ file: GLTFReader.File, globals: [Int: Transform], node meshNode: Int) throws -> ImportedSkin? {
        let nodes = file.array("nodes")
        guard let skinIndex = nodes[meshNode]["skin"] as? Int, skinIndex < file.array("skins").count else { return nil }
        let skin = file.array("skins")[skinIndex]
        guard let jointNodes = skin["joints"] as? [Int], !jointNodes.isEmpty else { return nil }
        var matrices: [[Float]] = Array(repeating: identityMatrix, count: jointNodes.count)
        if let accessor = skin["inverseBindMatrices"] as? Int {
            let values = try GLTFReader.accessor(file, accessor).values
            for joint in jointNodes.indices where joint * 16 + 15 < values.count {
                matrices[joint] = (0 ..< 16).map { Float(values[joint * 16 + $0]) }
            }
        }
        // The armature: everything above the first joint that isn't itself a joint.
        var parentOf: [Int: Int] = [:]
        for (index, node) in nodes.enumerated() {
            for child in node["children"] as? [Int] ?? [] {
                parentOf[child] = index
            }
        }
        let jointSet = Set(jointNodes)
        var root = jointNodes[0]
        while let parent = parentOf[root], jointSet.contains(parent) {
            root = parent
        }
        let armature = parentOf[root].flatMap { globals[$0] } ?? .identity
        return ImportedSkin(joints: jointNodes.map { GLTFReader.nodeName(nodes[$0], index: $0) }, inverseBindMatrices: matrices,
                            armature: columnMajor(armature))
    }

    static let identityMatrix: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

    /// TRS → column-major 4×4.
    public static func columnMajor(_ transform: Transform) -> [Float] {
        let x = transform.rotation.act(.unitX) * transform.scale.x
        let y = transform.rotation.act(.unitY) * transform.scale.y
        let z = transform.rotation.act(.unitZ) * transform.scale.z
        let p = transform.position
        return [x.x, x.y, x.z, 0, y.x, y.y, y.z, 0, z.x, z.y, z.z, 0, p.x, p.y, p.z, 1].map(Float.init)
    }
}
