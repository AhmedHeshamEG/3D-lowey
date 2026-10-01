import Foundation
import LoweyCore
import Metal
import simd

extension SceneCompiler {
    /// A library model: one draw per part, its own materials and textures unless the object is tinted, GPU skinning
    /// for rigged parts with this frame's pose.
    func compileAsset(_ id: AssetID, object: SceneObject, state: Inherited, base: ObjectUniforms, input: RenderInput, casts: Bool,
                      scene: inout RenderScene) {
        guard let asset = input.catalog.manifest.asset(id) else {
            placeholder(base: base, world: state.world.matrix, color: RGBA(1, 0.6, 0.2), scene: &scene)
            return
        }
        guard let model = models.model(asset, catalog: input.catalog) else {
            let color = models.failure(id) == nil ? RGBA(0.6, 0.6, 0.65) : RGBA(1, 0.3, 0.3)
            placeholder(base: base, world: state.world.matrix, color: color, scene: &scene)
            return
        }
        let tinted = object.color != nil || state.tint != nil
        var jointOffset: UInt32 = 0
        if let skin = model.skin, model.parts.contains(where: \.isSkinned) {
            jointOffset = UInt32(scene.joints.count)
            scene.joints += SkinPalette.matrices(skin: skin, rig: models.rig(id), pose: input.poses[object.id])
        }
        let world = state.world.matrix
        let device = device
        for (index, part) in model.parts.enumerated() {
            guard let mesh = meshes.mesh(.asset(id, part: index), make: {
                GPUMesh(device: device, mesh: part.mesh, joints: part.joints, weights: part.weights, label: part.name)
            }) else { continue }
            var uniforms = base
            let material = model.materials.indices.contains(part.material) ? model.materials[part.material] : ImportedMaterial()
            var texture: MTLTexture?
            if !tinted {
                uniforms.baseColor = SIMD4<Float>(material.baseColor.linear, Float(material.baseColor.a) * base.baseColor.w)
                if let textureIndex = material.baseColorTexture, model.textures.indices.contains(textureIndex) {
                    texture = textures.texture(model: id, index: textureIndex, texture: model.textures[textureIndex])
                }
            }
            // Its own emission, plus "self glow" (glowing in its own colours) from the object's glow.
            let glow = Float(object.emissiveIntensity)
            uniforms.emissive = SIMD4<Float>(material.emissive.linear * Float(material.emissiveStrength)
                + uniforms.baseColor.xyz4 * glow, glow)
            if material.isGlossy {
                uniforms.params.z = 1
                uniforms.ids.z |= ObjectFlags.glossy.rawValue
            }
            if part.isSkinned, mesh.isSkinned {
                uniforms.ids.z |= ObjectFlags.skinned.rawValue
                uniforms.ids.w = jointOffset
            }
            add(mesh, world: world, uniforms: uniforms, texture: texture, castsShadow: casts, scene: &scene)
        }
    }

    /// A translucent box where a model will appear (loading), or a red one when it couldn't load.
    func placeholder(base: ObjectUniforms, world: simd_float4x4, color: RGBA, scene: inout RenderScene) {
        let device = device
        guard let mesh = meshes.mesh(.primitive(.cube, faceted: false), make: {
            GPUMesh(device: device, mesh: PrimitiveMesh.make(.cube, shading: .smooth), label: "placeholder")
        }) else { return }
        var uniforms = base
        uniforms.baseColor = SIMD4<Float>(color.linear, 0.35)
        add(mesh, world: world, uniforms: uniforms, castsShadow: false, scene: &scene)
    }
}

/// Joint matrices for GPU skinning: the pose's joints in model space (armature above the root included) times the
/// skin's inverse bind matrices, in the skin's joint order.
enum SkinPalette {
    static func matrices(skin: ImportedSkin, rig: RigAsset?, pose: [LoweyCore.Transform]?) -> [simd_float4x4] {
        guard let rig else { return skin.joints.map { _ in matrix_identity_float4x4 } }
        let skeleton = rig.skeleton
        let armature = matrix(skin.armature)
        var globals = [simd_float4x4](repeating: matrix_identity_float4x4, count: skeleton.joints.count)
        for (index, joint) in skeleton.joints.enumerated() {
            let local = (pose.flatMap { index < $0.count ? $0[index] : nil } ?? joint.rest).matrix
            if let parent = joint.parent, parent < index {
                globals[index] = globals[parent] * local
            } else {
                globals[index] = armature * local
            }
        }
        var lookup: [String: Int] = [:]
        for (index, joint) in skeleton.joints.enumerated() {
            lookup[joint.name] = index
        }
        return skin.joints.enumerated().map { skinIndex, name in
            guard let core = lookup[name], skin.inverseBindMatrices.indices.contains(skinIndex) else { return matrix_identity_float4x4 }
            return globals[core] * matrix(skin.inverseBindMatrices[skinIndex])
        }
    }

    /// Column-major 16 floats → matrix.
    static func matrix(_ values: [Float]) -> simd_float4x4 {
        guard values.count == 16 else { return matrix_identity_float4x4 }
        return simd_float4x4(columns: (SIMD4<Float>(values[0], values[1], values[2], values[3]),
                                       SIMD4<Float>(values[4], values[5], values[6], values[7]),
                                       SIMD4<Float>(values[8], values[9], values[10], values[11]),
                                       SIMD4<Float>(values[12], values[13], values[14], values[15])))
    }
}
