import Foundation

/// One mesh to export, already in its final (world) placement.
public struct ExportMesh: Hashable, Sendable {
    public var name: String
    public var transform: Transform
    public var mesh: MeshData
    public var color: RGBA
    public var emissive: RGBA?
    public var emissiveStrength: Double
    public var roughness: Double
    public var metallic: Double

    public init(name: String, transform: Transform, mesh: MeshData, color: RGBA, emissive: RGBA? = nil, emissiveStrength: Double = 0,
                roughness: Double = 0.85, metallic: Double = 0) {
        self.name = name
        self.transform = transform
        self.mesh = mesh
        self.color = color
        self.emissive = emissive
        self.emissiveStrength = emissiveStrength
        self.roughness = roughness
        self.metallic = metallic
    }
}

/// 3D export (glTF binary and USDZ) of the selection or the whole scene, written in pure Swift.
public enum SceneExport {
    /// Meshes for blockout and drawn objects. Other kinds (library models, prefab instances) come
    /// from `extra`, which the render layer fills from the loaded entities.
    public static func meshes(
        _ ids: [ObjectID]?, in scene: Scene, look: Look, extra: (SceneObject, Transform) -> [ExportMesh] = { _, _ in [] }
    ) -> [ExportMesh] {
        let roots = ids ?? scene.roots
        var visited = Set<ObjectID>()
        var result: [ExportMesh] = []
        for root in roots {
            for id in scene.subtree(of: root) where visited.insert(id).inserted {
                guard let object = scene.objects[id], scene.isEffectivelyVisible(id) else { continue }
                let world = scene.worldTransform(of: id)
                let shading: ShadingStyle = switch object.shading {
                case .inherit: look.shading
                case .smooth: .smooth
                case .flat: .flat
                }
                let color = object.color?.resolved(in: look.palette) ?? .blockout
                let emissive = object.emissive?.resolved(in: look.palette) ?? (object.emissiveIntensity > 0 ? color : nil)
                let data: MeshData? = switch object.kind {
                case let .primitive(shape): PrimitiveMesh.make(shape, shading: shading)
                case let .drawing(recipe): DrawingMesher.mesh(for: recipe).shaded(shading)
                default: nil
                }
                if let data, !data.isEmpty {
                    result.append(ExportMesh(
                        name: object.name, transform: world, mesh: data, color: color, emissive: emissive,
                        emissiveStrength: object.emissiveIntensity, roughness: object[.roughness]?.floatValue ?? 0.85,
                        metallic: object[.metallic]?.floatValue ?? 0
                    ))
                } else {
                    result += extra(object, world)
                }
            }
        }
        return result
    }

    static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    // MARK: glTF binary

    public static func glb(_ meshes: [ExportMesh], generator: String = "3D-lowey") -> Data {
        var binary = Data()
        var bufferViews: [[String: Any]] = []
        var accessors: [[String: Any]] = []
        var gltfMeshes: [[String: Any]] = []
        var materials: [[String: Any]] = []
        var nodes: [[String: Any]] = []

        func align() {
            while binary.count % 4 != 0 {
                binary.append(0)
            }
        }
        func addView(_ data: Data, target: Int) -> Int {
            align()
            bufferViews.append(["buffer": 0, "byteOffset": binary.count, "byteLength": data.count, "target": target])
            binary.append(data)
            return bufferViews.count - 1
        }
        func floats(_ values: [Float]) -> Data {
            var data = Data(capacity: values.count * 4)
            for value in values {
                withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
            return data
        }

        for (index, item) in meshes.enumerated() where !item.mesh.isEmpty {
            let mesh = item.mesh
            let positions = mesh.positions.flatMap { [$0.x, $0.y, $0.z] }
            let bounds = mesh.bounds ?? Bounds(min: .zero, max: .zero)
            let positionView = addView(floats(positions), target: 34962)
            accessors.append([
                "bufferView": positionView, "componentType": 5126, "count": mesh.positions.count, "type": "VEC3",
                "min": [bounds.min.x, bounds.min.y, bounds.min.z], "max": [bounds.max.x, bounds.max.y, bounds.max.z]
            ])
            var attributes: [String: Int] = ["POSITION": accessors.count - 1]
            if mesh.normals.count == mesh.positions.count {
                let view = addView(floats(mesh.normals.flatMap { n -> [Float] in
                    let length = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
                    return length > 0 ? [n.x / length, n.y / length, n.z / length] : [0, 1, 0]
                }), target: 34962)
                accessors.append(["bufferView": view, "componentType": 5126, "count": mesh.normals.count, "type": "VEC3"])
                attributes["NORMAL"] = accessors.count - 1
            }
            if mesh.uvs.count == mesh.positions.count {
                let view = addView(floats(mesh.uvs.flatMap { [$0.x, $0.y] }), target: 34962)
                accessors.append(["bufferView": view, "componentType": 5126, "count": mesh.uvs.count, "type": "VEC2"])
                attributes["TEXCOORD_0"] = accessors.count - 1
            }
            var indexData = Data(capacity: mesh.indices.count * 4)
            for value in mesh.indices {
                withUnsafeBytes(of: value.littleEndian) { indexData.append(contentsOf: $0) }
            }
            let indexView = addView(indexData, target: 34963)
            accessors.append(["bufferView": indexView, "componentType": 5125, "count": mesh.indices.count, "type": "SCALAR"])
            let indicesAccessor = accessors.count - 1

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
            materials.append(material)
            gltfMeshes.append(["name": item.name, "primitives": [["attributes": attributes, "indices": indicesAccessor, "material": materials.count - 1]]])
            let t = item.transform
            nodes.append([
                "name": item.name.isEmpty ? "Object \(index + 1)" : item.name, "mesh": gltfMeshes.count - 1,
                "translation": [t.position.x, t.position.y, t.position.z],
                "rotation": [t.rotation.x, t.rotation.y, t.rotation.z, t.rotation.w],
                "scale": [t.scale.x, t.scale.y, t.scale.z]
            ])
        }
        align()
        let json: [String: Any] = [
            "asset": ["version": "2.0", "generator": generator],
            "scene": 0,
            "scenes": [["nodes": Array(nodes.indices)]],
            "nodes": nodes, "meshes": gltfMeshes, "materials": materials,
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

    // MARK: USDZ

    /// USD text for the meshes (UsdPreviewSurface materials).
    public static func usda(_ meshes: [ExportMesh]) -> String {
        func f(_ value: Double) -> String {
            let rounded = (value * 1_000_000).rounded() / 1_000_000
            return rounded == rounded.rounded() ? String(format: "%.1f", rounded) : String(rounded)
        }
        func ff(_ value: Float) -> String { f(Double(value)) }
        func identifier(_ name: String, _ index: Int) -> String {
            let cleaned = String(name.map { $0.isLetter || $0.isNumber ? $0 : "_" }).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            let base = cleaned.isEmpty || cleaned.first?.isNumber == true ? "Object_\(cleaned)" : cleaned
            return "\(base)_\(index)"
        }
        var text = """
        #usda 1.0
        (
            defaultPrim = "Root"
            metersPerUnit = 1
            upAxis = "Y"
            doc = "Exported from 3D-lowey"
        )

        def Xform "Root"
        {
            def Scope "Materials"
            {

        """
        for (index, item) in meshes.enumerated() {
            let emissive = item.emissive.map { e in
                let s = min(item.emissiveStrength, 1)
                return "(\(f(linear(e.r) * s)), \(f(linear(e.g) * s)), \(f(linear(e.b) * s)))"
            } ?? "(0.0, 0.0, 0.0)"
            text += """
                    def Material "M\(index)"
                    {
                        token outputs:surface.connect = </Root/Materials/M\(index)/Surface.outputs:surface>

                        def Shader "Surface"
                        {
                            uniform token info:id = "UsdPreviewSurface"
                            color3f inputs:diffuseColor = (\(f(linear(item.color.r))), \(f(linear(item.color.g))), \(f(linear(item.color.b))))
                            color3f inputs:emissiveColor = \(emissive)
                            float inputs:roughness = \(f(item.roughness))
                            float inputs:metallic = \(f(item.metallic))
                            float inputs:opacity = \(f(item.color.a))
                            token outputs:surface
                        }
                    }

            """
        }
        text += "    }\n\n"
        for (index, item) in meshes.enumerated() where !item.mesh.isEmpty {
            let t = item.transform
            let mesh = item.mesh
            let counts = Array(repeating: "3", count: mesh.indices.count / 3).joined(separator: ", ")
            let indices = mesh.indices.map { String($0) }.joined(separator: ", ")
            let points = mesh.positions.map { "(\(ff($0.x)), \(ff($0.y)), \(ff($0.z)))" }.joined(separator: ", ")
            var extras = ""
            if mesh.normals.count == mesh.positions.count {
                let normals = mesh.normals.map { "(\(ff($0.x)), \(ff($0.y)), \(ff($0.z)))" }.joined(separator: ", ")
                extras += "            normal3f[] normals = [\(normals)] (\n                interpolation = \"vertex\"\n            )\n"
            }
            if mesh.uvs.count == mesh.positions.count {
                let uvs = mesh.uvs.map { "(\(ff($0.x)), \(ff($0.y)))" }.joined(separator: ", ")
                extras += "            texCoord2f[] primvars:st = [\(uvs)] (\n                interpolation = \"vertex\"\n            )\n"
            }
            text += """
                def Xform "\(identifier(item.name, index))"
                {
                    double3 xformOp:translate = (\(f(t.position.x)), \(f(t.position.y)), \(f(t.position.z)))
                    quatf xformOp:orient = (\(f(t.rotation.w)), \(f(t.rotation.x)), \(f(t.rotation.y)), \(f(t.rotation.z)))
                    float3 xformOp:scale = (\(f(t.scale.x)), \(f(t.scale.y)), \(f(t.scale.z)))
                    uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:orient", "xformOp:scale"]

                    def Mesh "Mesh"
                    {
                        int[] faceVertexCounts = [\(counts)]
                        int[] faceVertexIndices = [\(indices)]
                        point3f[] points = [\(points)]
                        uniform token orientation = "rightHanded"
                        uniform token subdivisionScheme = "none"
                        rel material:binding = </Root/Materials/M\(index)>

            """
            text += extras
            text += "        }\n    }\n\n"
        }
        text += "}\n"
        return text
    }

    /// A USDZ package: an uncompressed zip whose files start on 64-byte boundaries.
    public static func usdz(_ meshes: [ExportMesh]) -> Data {
        ZipWriter.storedArchive([("scene.usda", Data(usda(meshes).utf8))], alignment: 64)
    }
}

/// Minimal "stored" (uncompressed) zip writer — all USDZ needs.
public enum ZipWriter {
    public static func storedArchive(_ files: [(name: String, data: Data)], alignment: Int = 1) -> Data {
        var archive = Data()
        var central = Data()
        func u16(_ value: Int, into data: inout Data) {
            withUnsafeBytes(of: UInt16(truncatingIfNeeded: value).littleEndian) { data.append(contentsOf: $0) }
        }
        func u32(_ value: UInt32, into data: inout Data) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        for file in files {
            let name = Data(file.name.utf8)
            let crc = CRC32.checksum(file.data)
            let offset = archive.count
            // Padding in the extra field so the data begins on an aligned offset.
            let headerSize = 30 + name.count
            var padding = 0
            if alignment > 1 {
                let extraHeader = 4
                padding = (alignment - (offset + headerSize + extraHeader) % alignment) % alignment
            }
            let extraLength = alignment > 1 ? 4 + padding : 0
            u32(0x0403_4B50, into: &archive)
            u16(20, into: &archive)
            u16(0, into: &archive)
            u16(0, into: &archive)
            u16(0, into: &archive)
            u16(0x21, into: &archive)
            u32(crc, into: &archive)
            u32(UInt32(file.data.count), into: &archive)
            u32(UInt32(file.data.count), into: &archive)
            u16(name.count, into: &archive)
            u16(extraLength, into: &archive)
            archive.append(name)
            if alignment > 1 {
                u16(0x1986, into: &archive)
                u16(padding, into: &archive)
                archive.append(Data(repeating: 0, count: padding))
            }
            archive.append(file.data)

            u32(0x0201_4B50, into: &central)
            u16(20, into: &central)
            u16(20, into: &central)
            u16(0, into: &central)
            u16(0, into: &central)
            u16(0, into: &central)
            u16(0x21, into: &central)
            u32(crc, into: &central)
            u32(UInt32(file.data.count), into: &central)
            u32(UInt32(file.data.count), into: &central)
            u16(name.count, into: &central)
            u16(0, into: &central)
            u16(0, into: &central)
            u16(0, into: &central)
            u16(0, into: &central)
            u32(0, into: &central)
            u32(UInt32(offset), into: &central)
            central.append(name)
        }
        let centralOffset = archive.count
        archive.append(central)
        u32(0x0605_4B50, into: &archive)
        u16(0, into: &archive)
        u16(0, into: &archive)
        u16(files.count, into: &archive)
        u16(files.count, into: &archive)
        u32(UInt32(central.count), into: &archive)
        u32(UInt32(centralOffset), into: &archive)
        u16(0, into: &archive)
        return archive
    }
}

public enum CRC32 {
    private static let table: [UInt32] = (0 ..< 256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0 ..< 8 {
            c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
