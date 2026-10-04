import Foundation

// MARK: - glTF binary

public extension SceneExport {
    static func glb(_ meshes: [ExportMesh], generator: String = "Maquette") -> Data {
        var writer = GLBWriter()
        for (index, item) in meshes.enumerated() where !item.mesh.isEmpty {
            writer.add(item, index: index)
        }
        return writer.finish(generator: generator)
    }
}

/// Builds one .glb: a binary buffer plus the JSON that describes it.
private struct GLBWriter {
    static let arrayBuffer = 34962
    static let elementBuffer = 34963
    static let float = 5126
    static let unsignedInt = 5125

    var binary = Data()
    var bufferViews: [[String: Any]] = []
    var accessors: [[String: Any]] = []
    var meshes: [[String: Any]] = []
    var materials: [[String: Any]] = []
    var nodes: [[String: Any]] = []

    mutating func align() {
        while binary.count % 4 != 0 {
            binary.append(0)
        }
    }

    mutating func addView(_ data: Data, target: Int) -> Int {
        align()
        bufferViews.append(["buffer": 0, "byteOffset": binary.count, "byteLength": data.count, "target": target])
        binary.append(data)
        return bufferViews.count - 1
    }

    /// Adds an accessor over a new buffer view; returns the accessor's index.
    mutating func addAccessor(_ data: Data, target: Int, componentType: Int, count: Int, type: String, extra: [String: Any] = [:]) -> Int {
        let view = addView(data, target: target)
        var accessor: [String: Any] = ["bufferView": view, "componentType": componentType, "count": count, "type": type]
        accessor.merge(extra) { _, new in new }
        accessors.append(accessor)
        return accessors.count - 1
    }

    static func floats(_ values: [Float]) -> Data {
        var data = Data(capacity: values.count * 4)
        for value in values {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    mutating func add(_ item: ExportMesh, index: Int) {
        let mesh = item.mesh
        let bounds = mesh.bounds ?? Bounds(min: .zero, max: .zero)
        var attributes: [String: Int] = [:]
        attributes["POSITION"] = addAccessor(
            Self.floats(mesh.positions.flatMap { [$0.x, $0.y, $0.z] }), target: Self.arrayBuffer, componentType: Self.float,
            count: mesh.positions.count, type: "VEC3",
            extra: ["min": [bounds.min.x, bounds.min.y, bounds.min.z], "max": [bounds.max.x, bounds.max.y, bounds.max.z]]
        )
        if mesh.normals.count == mesh.positions.count {
            let normals = mesh.normals.flatMap { n -> [Float] in
                let length = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
                return length > 0 ? [n.x / length, n.y / length, n.z / length] : [0, 1, 0]
            }
            attributes["NORMAL"] = addAccessor(Self.floats(normals), target: Self.arrayBuffer, componentType: Self.float,
                                               count: mesh.normals.count, type: "VEC3")
        }
        if mesh.uvs.count == mesh.positions.count {
            attributes["TEXCOORD_0"] = addAccessor(Self.floats(mesh.uvs.flatMap { [$0.x, $0.y] }), target: Self.arrayBuffer,
                                                   componentType: Self.float, count: mesh.uvs.count, type: "VEC2")
        }
        var indexData = Data(capacity: mesh.indices.count * 4)
        for value in mesh.indices {
            withUnsafeBytes(of: value.littleEndian) { indexData.append(contentsOf: $0) }
        }
        let indices = addAccessor(indexData, target: Self.elementBuffer, componentType: Self.unsignedInt, count: mesh.indices.count, type: "SCALAR")
        materials.append(Self.material(item))
        meshes.append(["name": item.name, "primitives": [["attributes": attributes, "indices": indices, "material": materials.count - 1]]])
        let t = item.transform
        nodes.append([
            "name": item.name.isEmpty ? "Object \(index + 1)" : item.name, "mesh": meshes.count - 1,
            "translation": [t.position.x, t.position.y, t.position.z],
            "rotation": [t.rotation.x, t.rotation.y, t.rotation.z, t.rotation.w],
            "scale": [t.scale.x, t.scale.y, t.scale.z]
        ])
    }

    static func material(_ item: ExportMesh) -> [String: Any] {
        let linear = SceneExport.linear
        var material: [String: Any] = [
            "name": "\(item.name) material",
            "pbrMetallicRoughness": [
                "baseColorFactor": [linear(item.color.r), linear(item.color.g), linear(item.color.b), item.color.a],
                "metallicFactor": item.metallic, "roughnessFactor": item.roughness
            ]
        ]
        if let emissive = item.emissive, item.emissiveStrength > 0 {
            let strength = min(item.emissiveStrength, 1)
            material["emissiveFactor"] = [linear(emissive.r) * strength, linear(emissive.g) * strength, linear(emissive.b) * strength]
        }
        return material
    }

    mutating func finish(generator: String) -> Data {
        align()
        let json: [String: Any] = [
            "asset": ["version": "2.0", "generator": generator],
            "scene": 0,
            "scenes": [["nodes": Array(nodes.indices)]],
            "nodes": nodes, "meshes": meshes, "materials": materials,
            "accessors": accessors, "bufferViews": bufferViews,
            "buffers": [["byteLength": binary.count]]
        ]
        var jsonData = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data("{}".utf8)
        while jsonData.count % 4 != 0 {
            jsonData.append(0x20)
        }
        var result = Data()
        func u32(_ value: Int) {
            withUnsafeBytes(of: UInt32(value).littleEndian) { result.append(contentsOf: $0) }
        }
        result.append(Data("glTF".utf8))
        u32(2)
        u32(12 + 8 + jsonData.count + 8 + binary.count)
        u32(jsonData.count)
        result.append(Data("JSON".utf8))
        result.append(jsonData)
        u32(binary.count)
        result.append(contentsOf: [0x42, 0x49, 0x4E, 0x00])
        result.append(binary)
        return result
    }
}
