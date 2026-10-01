import Foundation
import ImageIO
import LoweyCore
import ModelIO
import simd
import UniformTypeIdentifiers

/// USDZ (and anything else ModelIO reads) → `ImportedModel`: every mesh in model space, one part per submesh,
/// base colours and base-colour textures.
enum ModelIOImporter {
    static func model(url: URL) throws -> ImportedModel {
        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        descriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0)
        descriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: 24, bufferIndex: 0)
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: 32)
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: nil)
        asset.loadTextures()
        var parts: [ImportedPart] = []
        var materials: [ImportedMaterial] = []
        var textures: [ImportedTexture] = []
        for index in 0 ..< asset.count {
            visit(asset.object(at: index)) { mesh in
                if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
                    mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)
                }
                mesh.vertexDescriptor = descriptor
                let transform = MDLTransform.globalTransform(with: mesh, atTime: 0)
                parts += meshParts(mesh, transform: transform, materials: &materials, textures: &textures)
            }
        }
        return ImportedModel(parts: parts, materials: materials, textures: textures)
    }

    private static func visit(_ object: MDLObject, _ body: (MDLMesh) -> Void) {
        if let mesh = object as? MDLMesh { body(mesh) }
        for child in object.children.objects {
            visit(child, body)
        }
    }

    private static func meshParts(_ mesh: MDLMesh, transform: simd_float4x4, materials: inout [ImportedMaterial],
                                  textures: inout [ImportedTexture]) -> [ImportedPart] {
        guard let buffer = mesh.vertexBuffers.first else { return [] }
        let count = mesh.vertexCount
        let map = buffer.map()
        let raw = map.bytes.assumingMemoryBound(to: Float.self)
        let normalMatrix = simd_float3x3(SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                                         SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                                         SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)).inverse.transpose
        var base = MeshData()
        for vertex in 0 ..< count {
            let v = raw + vertex * 8
            let position = transform * SIMD4<Float>(v[0], v[1], v[2], 1)
            base.addVertex(SIMD3<Float>(position.x, position.y, position.z),
                           normal: normalize(normalMatrix * SIMD3<Float>(v[3], v[4], v[5])), uv: SIMD2<Float>(v[6], v[7]))
        }
        var parts: [ImportedPart] = []
        for case let submesh as MDLSubmesh in mesh.submeshes ?? [] where submesh.geometryType == .triangles {
            var part = base
            part.indices = indices(submesh)
            guard !part.indices.isEmpty else { continue }
            materials.append(material(submesh.material, textures: &textures))
            parts.append(ImportedPart(name: mesh.name, mesh: part, material: materials.count - 1))
        }
        return parts
    }

    private static func indices(_ submesh: MDLSubmesh) -> [UInt32] {
        let map = submesh.indexBuffer.map()
        let count = submesh.indexCount
        switch submesh.indexType {
        case .uInt32:
            return Array(UnsafeBufferPointer(start: map.bytes.assumingMemoryBound(to: UInt32.self), count: count))
        case .uInt16:
            return UnsafeBufferPointer(start: map.bytes.assumingMemoryBound(to: UInt16.self), count: count).map(UInt32.init)
        case .uInt8:
            return UnsafeBufferPointer(start: map.bytes.assumingMemoryBound(to: UInt8.self), count: count).map(UInt32.init)
        default:
            return []
        }
    }

    private static func material(_ source: MDLMaterial?, textures: inout [ImportedTexture]) -> ImportedMaterial {
        var material = ImportedMaterial(name: source?.name ?? "Material")
        guard let property = source?.property(with: .baseColor) else { return material }
        switch property.type {
        case .float3:
            let color = property.float3Value
            material.baseColor = RGBA(Double(color.x), Double(color.y), Double(color.z))
        case .float4:
            let color = property.float4Value
            material.baseColor = RGBA(Double(color.x), Double(color.y), Double(color.z), Double(color.w))
        case .texture:
            if let image = property.textureSamplerValue?.texture?.imageFromTexture()?.takeUnretainedValue(), let data = png(image) {
                textures.append(ImportedTexture(data: data, mimeType: "image/png"))
                material.baseColor = RGBA(1, 1, 1)
                material.baseColorTexture = textures.count - 1
            }
        default:
            break
        }
        if let roughness = source?.property(with: .roughness), roughness.type == .float { material.roughness = Double(roughness.floatValue) }
        if let metallic = source?.property(with: .metallic), metallic.type == .float { material.metallic = Double(metallic.floatValue) }
        return material
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
