import Foundation
import LoweyCore
import RealityKit
import UIKit

// MARK: - Core → RealityKit value conversions

public extension Vec3 {
    var simd: SIMD3<Float> { SIMD3<Float>(Float(x), Float(y), Float(z)) }
}

public extension Quat {
    var simd: simd_quatf { simd_quatf(ix: Float(x), iy: Float(y), iz: Float(z), r: Float(w)) }

    init(_ quaternion: simd_quatf) {
        self.init(x: Double(quaternion.imag.x), y: Double(quaternion.imag.y), z: Double(quaternion.imag.z), w: Double(quaternion.real))
    }
}

public extension LoweyCore.Transform {
    var realityKit: RealityKit.Transform {
        RealityKit.Transform(scale: scale.simd, rotation: rotation.simd, translation: position.simd)
    }

    init(_ transform: RealityKit.Transform) {
        self.init(position: Vec3(transform.translation), rotation: Quat(transform.rotation), scale: Vec3(transform.scale))
    }
}

public extension RGBA {
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    var cgColor: CGColor { uiColor.cgColor }

    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b), Double(a))
    }
}

public extension BoundingBox {
    var loweyBounds: Bounds { Bounds(min: Vec3(min), max: Vec3(max)) }
}

// MARK: - Mesh upload

public enum MeshUpload {
    /// Uploads Core mesh data to a RealityKit mesh resource.
    @MainActor
    public static func resource(from mesh: MeshData, name: String = "lowey") throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(mesh.positions)
        if mesh.normals.count == mesh.positions.count {
            descriptor.normals = MeshBuffers.Normals(mesh.normals)
        }
        if mesh.uvs.count == mesh.positions.count {
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(mesh.uvs)
        }
        descriptor.primitives = .triangles(mesh.indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// Reads a RealityKit mesh back into Core form (for flat shading and surface raycasts).
    /// Skinned parts are skipped (they deform at runtime).
    @MainActor
    public static func meshData(from resource: MeshResource) -> MeshData {
        var result = MeshData()
        let contents = resource.contents
        var modelsByID: [String: MeshResource.Model] = [:]
        for model in contents.models {
            modelsByID[model.id] = model
        }
        for instance in contents.instances {
            guard let model = modelsByID[instance.model] else { continue }
            for part in model.parts {
                let positions = part.positions.elements
                let indices = part.triangleIndices?.elements ?? []
                guard !positions.isEmpty, !indices.isEmpty else { continue }
                var partData = MeshData()
                partData.positions = positions.map { position in
                    let p = instance.transform * SIMD4<Float>(position, 1)
                    return SIMD3<Float>(p.x, p.y, p.z)
                }
                partData.normals = Array(repeating: SIMD3<Float>(0, 1, 0), count: positions.count)
                partData.uvs = part.textureCoordinates?.elements ?? Array(repeating: .zero, count: positions.count)
                partData.indices = indices
                result.append(partData)
            }
        }
        return result
    }

    /// The same mesh with faceted normals, keeping parts, material slots and UVs.
    /// Returns `nil` for skinned meshes (flat shading would break the skin binding).
    @MainActor
    public static func faceted(_ resource: MeshResource) -> MeshResource? {
        let contents = resource.contents
        var newModels: [MeshResource.Model] = []
        for model in contents.models {
            var newParts: [MeshResource.Part] = []
            for part in model.parts {
                if part.skeletonID != nil { return nil }
                let positions = part.positions.elements
                guard let indices = part.triangleIndices?.elements, !indices.isEmpty else { continue }
                let source = MeshData(
                    positions: positions,
                    normals: [],
                    uvs: part.textureCoordinates?.elements ?? [],
                    indices: indices
                )
                let flat = source.faceted()
                var newPart = MeshResource.Part(id: part.id, materialIndex: part.materialIndex)
                newPart.positions = MeshBuffers.Positions(flat.positions)
                newPart.normals = MeshBuffers.Normals(flat.normals)
                if part.textureCoordinates != nil {
                    newPart.textureCoordinates = MeshBuffers.TextureCoordinates(flat.uvs)
                }
                newPart.triangleIndices = MeshBuffers.TriangleIndices(flat.indices)
                newParts.append(newPart)
            }
            newModels.append(MeshResource.Model(id: model.id, parts: newParts))
        }
        var newContents = MeshResource.Contents()
        newContents.instances = contents.instances
        newContents.models = MeshModelCollection(newModels)
        return try? MeshResource.generate(from: newContents)
    }
}
