import Foundation

// MARK: - USDZ

public extension SceneExport {
    /// USD text for the meshes (UsdPreviewSurface materials).
    static func usda(_ meshes: [ExportMesh]) -> String {
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
            text += USDText.material(item, index: index)
        }
        text += "    }\n\n"
        for (index, item) in meshes.enumerated() where !item.mesh.isEmpty {
            text += USDText.mesh(item, index: index)
        }
        text += "}\n"
        return text
    }

    /// A USDZ package: an uncompressed zip whose files start on 64-byte boundaries.
    static func usdz(_ meshes: [ExportMesh]) -> Data {
        ZipWriter.storedArchive([("scene.usda", Data(usda(meshes).utf8))], alignment: 64)
    }
}

/// The pieces of a .usda file.
private enum USDText {
    static func f(_ value: Double) -> String {
        let rounded = (value * 1_000_000).rounded() / 1_000_000
        return rounded == rounded.rounded() ? String(format: "%.1f", rounded) : String(rounded)
    }

    static func ff(_ value: Float) -> String { f(Double(value)) }

    static func identifier(_ name: String, _ index: Int) -> String {
        let cleaned = String(name.map { $0.isLetter || $0.isNumber ? $0 : "_" }).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let base = cleaned.isEmpty || cleaned.first?.isNumber == true ? "Object_\(cleaned)" : cleaned
        return "\(base)_\(index)"
    }

    static func material(_ item: ExportMesh, index: Int) -> String {
        let linear = SceneExport.linear
        let emissive = item.emissive.map { e in
            let s = min(item.emissiveStrength, 1)
            return "(\(f(linear(e.r) * s)), \(f(linear(e.g) * s)), \(f(linear(e.b) * s)))"
        } ?? "(0.0, 0.0, 0.0)"
        return """
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

    static func mesh(_ item: ExportMesh, index: Int) -> String {
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
        let head = """
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
        return head + extras + "        }\n    }\n\n"
    }
}
