import Foundation

/// An image inside a model file, still encoded (PNG / JPEG); the engine decodes it into a texture.
public struct ImportedTexture: Hashable, Sendable {
    public var data: Data
    public var mimeType: String?

    public init(data: Data, mimeType: String? = nil) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// A model material, reduced to what the Looks use.
public struct ImportedMaterial: Hashable, Sendable {
    public var name: String
    public var baseColor: RGBA
    /// Index into `ImportedModel.textures`.
    public var baseColorTexture: Int?
    public var emissive: RGBA
    public var emissiveStrength: Double
    public var metallic: Double
    public var roughness: Double
    public var blended: Bool
    public var doubleSided: Bool

    public init(name: String = "", baseColor: RGBA = RGBA(0.8, 0.8, 0.8), baseColorTexture: Int? = nil, emissive: RGBA = RGBA(0, 0, 0),
                emissiveStrength: Double = 1, metallic: Double = 0, roughness: Double = 0.8, blended: Bool = false, doubleSided: Bool = false) {
        self.name = name
        self.baseColor = baseColor
        self.baseColorTexture = baseColorTexture
        self.emissive = emissive
        self.emissiveStrength = emissiveStrength
        self.metallic = metallic
        self.roughness = roughness
        self.blended = blended
        self.doubleSided = doubleSided
    }

    /// Glass, metal and very smooth surfaces get the Looks' specular shape.
    public var isGlossy: Bool { metallic > 0.5 || roughness < 0.3 || blended }
}

/// One drawable piece of a model: a mesh with one material; skinned pieces carry joints and weights.
public struct ImportedPart: Hashable, Sendable {
    public var name: String
    /// Model space for static parts; bind space for skinned parts.
    public var mesh: MeshData
    public var material: Int
    /// Four skin joint indices (into `ImportedSkin.joints`) and weights per vertex; empty for static parts.
    public var joints: [SIMD4<UInt16>]
    public var weights: [SIMD4<Float>]

    public init(name: String, mesh: MeshData, material: Int, joints: [SIMD4<UInt16>] = [], weights: [SIMD4<Float>] = []) {
        self.name = name
        self.mesh = mesh
        self.material = material
        self.joints = joints
        self.weights = weights
    }

    public var isSkinned: Bool { !joints.isEmpty && joints.count == mesh.positions.count }
}

/// How a model's skin binds to its skeleton.
public struct ImportedSkin: Hashable, Sendable {
    /// Joint names in skin order (matching `Skeleton` joint names).
    public var joints: [String]
    /// Column-major inverse bind matrices, one per joint.
    public var inverseBindMatrices: [[Float]]
    /// Global transform of the nodes above the root joint (the armature), column-major.
    public var armature: [Float]

    public init(joints: [String], inverseBindMatrices: [[Float]], armature: [Float]) {
        self.joints = joints
        self.inverseBindMatrices = inverseBindMatrices
        self.armature = armature
    }
}

/// A model read from a file: parts, materials, still-encoded textures, and its skin.
public struct ImportedModel: Hashable, Sendable {
    public var parts: [ImportedPart]
    public var materials: [ImportedMaterial]
    public var textures: [ImportedTexture]
    public var skin: ImportedSkin?

    public init(parts: [ImportedPart], materials: [ImportedMaterial], textures: [ImportedTexture] = [], skin: ImportedSkin? = nil) {
        self.parts = parts
        self.materials = materials.isEmpty ? [ImportedMaterial()] : materials
        self.textures = textures
        self.skin = skin
    }

    /// Bounds of every part (skinned parts in their bind pose).
    public var bounds: Bounds? {
        parts.compactMap(\.mesh.bounds).reduce(nil as Bounds?) { partial, bounds in partial.map { $0.union(bounds) } ?? bounds }
    }

    public var triangleCount: Int { parts.reduce(0) { $0 + $1.mesh.triangleCount } }

    /// A model from a plain mesh (OBJ, generated geometry).
    public init(mesh: MeshData, name: String = "Model") {
        self.init(parts: [ImportedPart(name: name, mesh: mesh, material: 0)], materials: [ImportedMaterial(name: name)])
    }
}
