import Foundation

/// 3MF, the modern print format: a zip holding XML with real units, shared corners (so slicers know it's closed),
/// one object per part and a colour per object. Written stored (uncompressed), read stored or deflated.
public enum ThreeMFFile {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notA3MF
        case empty

        public var description: String {
            switch self {
            case .notA3MF: "That isn't a 3MF file."
            case .empty: "That 3MF file has no shapes in it."
            }
        }
    }

    static let modelPath = "3D/3dmodel.model"
    static let namespace = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"

    // MARK: Writing

    /// A 3MF of the meshes as placed in the world: one object each, in millimetres with Z up, coloured.
    public static func data(_ meshes: [ExportMesh]) -> Data {
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
        </Types>
        """
        let relationships = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Target="/\(modelPath)" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
        </Relationships>
        """
        return ZipWriter.storedArchive([
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(relationships.utf8)),
            (modelPath, Data(model(meshes).utf8))
        ])
    }

    static func model(_ meshes: [ExportMesh]) -> String {
        let parts = meshes.filter { !$0.mesh.isEmpty }
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xml:lang="en-US" xmlns="\(namespace)">
          <metadata name="Application">Maquette</metadata>
          <resources>
            <basematerials id="1">

        """
        for item in parts {
            xml += "      <base name=\"\(escaped(item.name))\" displaycolor=\"\(hex(item.color))\"/>\n"
        }
        xml += "    </basematerials>\n"
        for (index, item) in parts.enumerated() {
            let (vertices, triangles) = indexed(item)
            xml += "    <object id=\"\(index + 2)\" type=\"model\" name=\"\(escaped(item.name))\" pid=\"1\" pindex=\"\(index)\">\n"
            xml += "      <mesh>\n        <vertices>\n"
            for vertex in vertices {
                xml += "          <vertex x=\"\(number(vertex.x))\" y=\"\(number(vertex.y))\" z=\"\(number(vertex.z))\"/>\n"
            }
            xml += "        </vertices>\n        <triangles>\n"
            for triangle in triangles {
                xml += "          <triangle v1=\"\(triangle.0)\" v2=\"\(triangle.1)\" v3=\"\(triangle.2)\"/>\n"
            }
            xml += "        </triangles>\n      </mesh>\n    </object>\n"
        }
        xml += "  </resources>\n  <build>\n"
        for index in parts.indices {
            xml += "    <item objectid=\"\(index + 2)\"/>\n"
        }
        xml += "  </build>\n</model>\n"
        return xml
    }

    /// The mesh in print space with corners that share a position shared (3MF meshes must be connected).
    static func indexed(_ item: ExportMesh) -> ([Vec3], [(Int, Int, Int)]) {
        var vertices: [Vec3] = []
        var lookup: [SIMD3<Float>: Int] = [:]
        let mirrored = item.transform.scale.x * item.transform.scale.y * item.transform.scale.z < 0
        let remap = item.mesh.positions.map { position -> Int in
            let world = item.transform.apply(to: Vec3(Double(position.x), Double(position.y), Double(position.z)))
            let key = world.float3
            if let known = lookup[key] { return known }
            lookup[key] = vertices.count
            vertices.append(PrintSpace.toFile(world))
            return vertices.count - 1
        }
        var triangles: [(Int, Int, Int)] = []
        for index in stride(from: 0, to: item.mesh.indices.count - 2, by: 3) {
            let a = remap[Int(item.mesh.indices[index])], b = remap[Int(item.mesh.indices[index + 1])]
            let c = remap[Int(item.mesh.indices[index + 2])]
            guard a != b, b != c, a != c else { continue }
            triangles.append(mirrored ? (a, c, b) : (a, b, c))
        }
        return (vertices, triangles)
    }

    static func number(_ value: Double) -> String {
        let rounded = (value * 1e6).rounded() / 1e6
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    static func hex(_ color: RGBA) -> String {
        func byte(_ value: Double) -> String { String(format: "%02X", Int((min(max(value, 0), 1) * 255).rounded())) }
        return "#\(byte(color.r))\(byte(color.g))\(byte(color.b))"
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: Reading

    /// A 3MF's build as a model in scene space (metres, Y up): each placed object a part, with its colour.
    public static func read(_ data: Data) throws -> ImportedModel {
        let entries = try ZipReader.entries(data)
        guard let modelEntry = entries.first(where: { $0.name.lowercased().hasSuffix(".model") && $0.name.lowercased().hasPrefix("3d/") })
            ?? entries.first(where: { $0.name.lowercased().hasSuffix(".model") }),
            let xml = String(data: modelEntry.data, encoding: .utf8) else { throw Failure.notA3MF }
        let document = ThreeMFDocument(xml)
        var parts: [ImportedPart] = []
        var materials: [ImportedMaterial] = []
        for item in document.build {
            for (mesh, color, name) in document.meshes(of: item.object, transform: item.transform) where !mesh.indices.isEmpty {
                materials.append(ImportedMaterial(name: name, baseColor: color ?? RGBA(0.8, 0.8, 0.8)))
                parts.append(ImportedPart(name: name, mesh: mesh, material: materials.count - 1))
            }
        }
        guard !parts.isEmpty else { throw Failure.empty }
        return ImportedModel(parts: parts, materials: materials)
    }
}

/// The parts of a 3MF model file that matter for a mesh: objects (meshes or components), colours and the build.
struct ThreeMFDocument {
    struct Object {
        var name: String
        var vertices: [Vec3] = []
        var triangles: [(Int, Int, Int)] = []
        var components: [(object: Int, transform: [Double])] = []
        var material: (group: Int, index: Int)?
    }

    var objects: [Int: Object] = [:]
    var colors: [Int: [RGBA]] = [:]
    var build: [(object: Int, transform: [Double])] = []
    /// Millimetres per file unit.
    var scale = 1.0

    init(_ xml: String) {
        var current: Int?
        var colorGroup: Int?
        for tag in XMLTags(xml) {
            switch tag.name {
            case "model":
                scale = Self.unitScale(tag["unit"])
            case "basematerials", "m:colorgroup", "colorgroup":
                colorGroup = tag.int("id")
                if let colorGroup, colors[colorGroup] == nil { colors[colorGroup] = [] }
            case "base":
                if let colorGroup, let color = tag["displaycolor"].flatMap(Self.color) { colors[colorGroup, default: []].append(color) }
            case "m:color", "color":
                if let colorGroup, let color = tag["color"].flatMap(Self.color) { colors[colorGroup, default: []].append(color) }
            case "object":
                current = tag.int("id")
                if let current {
                    var object = Object(name: tag["name"] ?? "Part \(current)")
                    if let group = tag.int("pid") { object.material = (group, tag.int("pindex") ?? 0) }
                    objects[current] = object
                }
            case "vertex":
                if let current, let x = tag.double("x"), let y = tag.double("y"), let z = tag.double("z") {
                    objects[current]?.vertices.append(Vec3(x, y, z))
                }
            case "triangle":
                if let current, let a = tag.int("v1"), let b = tag.int("v2"), let c = tag.int("v3") {
                    objects[current]?.triangles.append((a, b, c))
                }
            case "component":
                if let current, let id = tag.int("objectid") { objects[current]?.components.append((id, Self.matrix(tag["transform"]))) }
            case "item":
                if let id = tag.int("objectid") { build.append((id, Self.matrix(tag["transform"]))) }
            default:
                break
            }
        }
    }

    /// The meshes an object makes (its own, and its components' through their transforms), in scene space.
    func meshes(of id: Int, transform: [Double], depth: Int = 0) -> [(MeshData, RGBA?, String)] {
        guard let object = objects[id], depth < 16 else { return [] }
        var result: [(MeshData, RGBA?, String)] = []
        if !object.triangles.isEmpty {
            var mesh = MeshData()
            mesh.positions = object.vertices.map { point in
                PrintSpace.fromFile(Self.apply(transform, to: point) * scale).float3
            }
            mesh.indices = object.triangles.flatMap { [UInt32($0.0), UInt32($0.1), UInt32($0.2)] }
                .filter { Int($0) < mesh.positions.count }
            mesh.indices.removeLast(mesh.indices.count % 3)
            mesh.computeSmoothNormals()
            mesh.uvs = Array(repeating: .zero, count: mesh.positions.count)
            let color = object.material
                .flatMap { material in colors[material.group].flatMap { $0.indices.contains(material.index) ? $0[material.index] : nil } }
            result.append((mesh, color, object.name))
        }
        for component in object.components {
            result += meshes(of: component.object, transform: Self.multiply(transform, component.transform), depth: depth + 1)
        }
        return result
    }

    static func unitScale(_ unit: String?) -> Double {
        switch unit {
        case "micron": 0.001
        case "centimeter": 10
        case "inch": 25.4
        case "foot": 304.8
        case "meter": 1000
        default: 1
        }
    }

    static func color(_ text: String) -> RGBA? {
        RGBA(hex: String(text.prefix(7)))
    }

    /// A 3MF transform: "m00 m01 m02 m10 m11 m12 m20 m21 m22 m30 m31 m32" (row vectors, translation last).
    static func matrix(_ text: String?) -> [Double] {
        let values = (text ?? "").split(separator: " ").compactMap { Double($0) }
        return values.count == 12 ? values : [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
    }

    static func apply(_ m: [Double], to p: Vec3) -> Vec3 {
        Vec3(p.x * m[0] + p.y * m[3] + p.z * m[6] + m[9], p.x * m[1] + p.y * m[4] + p.z * m[7] + m[10], p.x * m[2] + p.y * m[5] + p.z * m[8] + m[11])
    }

    /// The transform of `inner` then `outer` (a component inside a placed item).
    static func multiply(_ outer: [Double], _ inner: [Double]) -> [Double] {
        let x = apply(outer, to: Vec3(inner[0], inner[1], inner[2])) - apply(outer, to: .zero)
        let y = apply(outer, to: Vec3(inner[3], inner[4], inner[5])) - apply(outer, to: .zero)
        let z = apply(outer, to: Vec3(inner[6], inner[7], inner[8])) - apply(outer, to: .zero)
        let t = apply(outer, to: Vec3(inner[9], inner[10], inner[11]))
        return [x.x, x.y, x.z, y.x, y.y, y.z, z.x, z.y, z.z, t.x, t.y, t.z]
    }
}

/// Start tags of an XML text with their attributes: all a 3MF reader needs (it never looks at text content).
struct XMLTags: Sequence {
    struct Tag {
        var name: String
        var attributes: [String: String]

        subscript(_ key: String) -> String? { attributes[key] }
        func int(_ key: String) -> Int? { attributes[key].flatMap { Int($0) } }
        func double(_ key: String) -> Double? { attributes[key].flatMap { Double($0) } }
    }

    let text: String

    init(_ text: String) {
        self.text = text
    }

    func makeIterator() -> AnyIterator<Tag> {
        let scalars = Array(text.utf8)
        var index = 0
        return AnyIterator {
            while index < scalars.count {
                guard scalars[index] == UInt8(ascii: "<") else {
                    index += 1
                    continue
                }
                let start = index + 1
                var end = start
                var quote: UInt8?
                while end < scalars.count {
                    let byte = scalars[end]
                    if let open = quote {
                        if byte == open { quote = nil }
                    } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                        quote = byte
                    } else if byte == UInt8(ascii: ">") {
                        break
                    }
                    end += 1
                }
                index = end + 1
                guard start < scalars.count, ![UInt8(ascii: "/"), UInt8(ascii: "?"), UInt8(ascii: "!")].contains(scalars[start]),
                      let body = String(bytes: scalars[start ..< Swift.min(end, scalars.count)], encoding: .utf8) else { continue }
                return Self.parse(body)
            }
            return nil
        }
    }

    static func parse(_ body: String) -> Tag {
        let trimmed = body.hasSuffix("/") ? String(body.dropLast()) : body
        let name = String(trimmed.prefix { !$0.isWhitespace })
        var attributes: [String: String] = [:]
        var rest = Substring(trimmed.dropFirst(name.count))
        while let equals = rest.firstIndex(of: "=") {
            let key = rest[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            var after = rest[rest.index(after: equals)...].drop { $0.isWhitespace }
            guard let quote = after.first, quote == "\"" || quote == "'" else { break }
            after = after.dropFirst()
            guard let close = after.firstIndex(of: quote) else { break }
            attributes[key] = String(after[..<close]).replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
            rest = after[after.index(after: close)...]
        }
        return Tag(name: name, attributes: attributes)
    }
}
