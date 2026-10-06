import Foundation

/// OBJ, the oldest format every 3D app reads: the meshes as placed in the world (metres, Y up), one object and one
/// material each. The materials go in a companion `.mtl` file named in the OBJ.
public enum OBJFile {
    /// The OBJ text and its MTL text; `materialFile` is the MTL's file name, as the OBJ refers to it. Painted meshes
    /// carry their uvs and name their texture (`textureFile(index)`, written next to the OBJ by the caller).
    public static func text(_ meshes: [ExportMesh], materialFile: String) -> (obj: String, mtl: String) {
        var obj = "# Exported from Maquette\nmtllib \(materialFile)\n"
        var mtl = "# Exported from Maquette\n"
        var offset = 1
        var normalOffset = 1
        var uvOffset = 1
        for (index, item) in meshes.enumerated() where !item.mesh.isEmpty {
            let name = identifier(item.name, index)
            obj += "o \(name)\nusemtl \(name)\n"
            let mirrored = item.transform.scale.x * item.transform.scale.y * item.transform.scale.z < 0
            for position in item.mesh.positions {
                let world = item.transform.apply(to: Vec3(Double(position.x), Double(position.y), Double(position.z)))
                obj += "v \(number(world.x)) \(number(world.y)) \(number(world.z))\n"
            }
            let hasNormals = item.mesh.normals.count == item.mesh.positions.count
            if hasNormals {
                for normal in item.mesh.normals {
                    let turned = item.transform.rotation.act(Vec3(Double(normal.x), Double(normal.y), Double(normal.z))).normalized
                    obj += "vn \(number(turned.x)) \(number(turned.y)) \(number(turned.z))\n"
                }
            }
            let hasUVs = item.texture != nil && item.mesh.uvs.count == item.mesh.positions.count
            if hasUVs {
                // OBJ's texture origin is the bottom left.
                for uv in item.mesh.uvs {
                    obj += "vt \(number(Double(uv.x))) \(number(1 - Double(uv.y)))\n"
                }
            }
            for triangle in stride(from: 0, to: item.mesh.indices.count - 2, by: 3) {
                var corners = (0 ..< 3).map { Int(item.mesh.indices[triangle + $0]) }
                if mirrored { corners.swapAt(1, 2) }
                obj += "f " + corners.map { corner(Self.Corner(position: $0 + offset, uv: hasUVs ? $0 + uvOffset : nil,
                                                               normal: hasNormals ? $0 + normalOffset : nil)) }.joined(separator: " ") + "\n"
            }
            offset += item.mesh.positions.count
            if hasNormals { normalOffset += item.mesh.normals.count }
            if hasUVs { uvOffset += item.mesh.uvs.count }
            let c = item.color
            mtl += "newmtl \(name)\nKd \(number(c.r)) \(number(c.g)) \(number(c.b))\nd \(number(c.a))\nNs \(number((1 - item.roughness) * 1000))\n"
            if item.texture != nil { mtl += "map_Kd \(textureFile(index))\n" }
            if let glow = item.emissive, item.emissiveStrength > 0 {
                let s = min(item.emissiveStrength, 1)
                mtl += "Ke \(number(glow.r * s)) \(number(glow.g * s)) \(number(glow.b * s))\n"
            }
            mtl += "\n"
        }
        return (obj, mtl)
    }

    /// A painted mesh's texture file, next to the OBJ.
    public static func textureFile(_ index: Int) -> String {
        "paint_\(index + 1).png"
    }

    /// The painted textures to write next to the OBJ.
    public static func textures(_ meshes: [ExportMesh]) -> [(name: String, data: Data)] {
        meshes.enumerated().compactMap { index, item in item.texture.map { (textureFile(index), $0) } }
    }

    struct Corner {
        var position: Int
        var uv: Int?
        var normal: Int?
    }

    static func corner(_ corner: Corner) -> String {
        switch (corner.uv, corner.normal) {
        case let (uv?, normal?): "\(corner.position)/\(uv)/\(normal)"
        case let (uv?, nil): "\(corner.position)/\(uv)"
        case let (nil, normal?): "\(corner.position)//\(normal)"
        case (nil, nil): "\(corner.position)"
        }
    }

    static func identifier(_ name: String, _ index: Int) -> String {
        let cleaned = String(name.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        return "\(cleaned.isEmpty ? "Object" : cleaned)_\(index + 1)"
    }

    static func number(_ value: Double) -> String {
        let rounded = (value * 1e6).rounded() / 1e6
        if rounded == 0 { return "0" }
        return rounded == rounded.rounded() && abs(rounded) < 1e15 ? String(Int(rounded)) : String(rounded)
    }
}
