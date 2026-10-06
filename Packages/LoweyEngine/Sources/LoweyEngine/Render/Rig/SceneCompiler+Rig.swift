import Foundation
import LoweyCore
import Metal
import simd

/// Objects with a drawn skeleton (drawn bones, "Rig as a person"): the mesh the renderer draws for them, skinned on the
/// GPU with this frame's pose. Weights come from the rig's `.skin` file; the joint palette is each joint's pose times
/// the inverse of where it was drawn. Drawings bend on the CPU instead (the animator moves their strokes).
extension SceneCompiler {
    /// The rigged object's weights, when they fit a mesh of `vertexCount` vertices.
    func rigWeights(_ object: SceneObject, input: RenderInput, vertexCount: Int) -> (rig: ObjectRig, weights: SkinWeights)? {
        guard let rig = object.rig, let file = rig.skin, let weights = skins.weights(file, read: input.paintFile),
              weights.count == vertexCount else { return nil }
        return (rig, weights)
    }

    /// Appends the rig's joint palette for this frame and returns where it starts.
    func appendPalette(_ rig: ObjectRig, object: SceneObject, input: RenderInput, scene: inout RenderScene) -> UInt32 {
        let offset = UInt32(scene.joints.count)
        scene.joints += RigPalette.matrices(rig, pose: input.poses[object.id])
        return offset
    }

    /// `source` skinned with the object's rig (`slice`: the part's vertices in the rig's merged surface), or nil when the
    /// object has no rig whose weights fit. In the weight view, its uvs carry the shown joint's weight instead.
    func riggedMesh(_ object: SceneObject, source: GPUMesh, key: String, slice: Range<Int>? = nil, input: RenderInput) -> GPUMesh? {
        guard let rig = object.rig, let file = rig.skin else { return nil }
        let range = slice ?? 0 ..< source.data.positions.count
        guard let loaded = skins.weights(file, read: input.paintFile), range.upperBound <= loaded.count,
              slice != nil || loaded.count == source.data.positions.count else { return nil }
        let device = device
        let dabs = object.shadowDabs
        let joints = Array(loaded.joints[range])
        let weights = Array(loaded.weights[range])
        if let view = input.weightView, view.object == object.id {
            return meshes.mesh(.rigged("weights \(view.joint) \(key)", skin: file, dabs: [])) {
                var data = source.data
                let shown = SkinWeights(joints: joints, weights: weights)
                data.uvs = data.positions.indices.map { SIMD2<Float>(min(max(shown.weight(of: view.joint, at: $0), 0.004), 0.996), 0.5) }
                return GPUMesh(device: device, mesh: data, joints: joints, weights: weights, label: "\(object.name) weights")
            }
        }
        return meshes.mesh(.rigged(key, skin: file, dabs: dabs)) {
            GPUMesh(device: device, mesh: source.data, shadowBias: dabs.isEmpty ? [] : ShadowPaint.biases(for: source.data, dabs: dabs),
                    joints: joints, weights: weights, label: "\(object.name) rigged")
        }
    }

    /// The weight view's colours over a rigged mesh's uniforms (flat, so the colour reads as the number it is).
    func weightUniforms(_ base: ObjectUniforms, object: SceneObject, input: RenderInput) -> (uniforms: ObjectUniforms, texture: MTLTexture?)? {
        guard let view = input.weightView, view.object == object.id, let ramp = skins.ramp(device: device) else { return nil }
        var uniforms = base
        uniforms.baseColor = SIMD4<Float>(1, 1, 1, 1)
        uniforms.emissive = .zero
        uniforms.ids.z |= ObjectFlags.unlit.rawValue
        return (uniforms, ramp)
    }

    /// Draws a surface skinned with its rig (flags, palette), its bounds grown to where the pose can take it.
    func addRigged(_ mesh: GPUMesh, rig: ObjectRig, palette: UInt32, world: simd_float4x4, base: ObjectUniforms, texture: MTLTexture? = nil,
                   casts: Bool, scene: inout RenderScene) {
        var uniforms = base
        uniforms.ids.z |= ObjectFlags.skinned.rawValue
        uniforms.ids.w = palette
        add(mesh, world: world, uniforms: uniforms, texture: texture, castsShadow: casts, scene: &scene)
        let count = rig.skeleton.joints.count
        let start = Int(palette)
        guard start + count <= scene.joints.count, let item = scene.items.indices.last else { return }
        var bounds: Bounds?
        for matrix in scene.joints[start ..< start + count] {
            let moved = mesh.bounds.corners.map { corner -> Vec3 in
                let point = world * matrix * SIMD4<Float>(Float(corner.x), Float(corner.y), Float(corner.z), 1)
                return Vec3(Double(point.x), Double(point.y), Double(point.z))
            }
            if let box = Bounds(points: moved) { bounds = bounds.map { $0.union(box) } ?? box }
        }
        if let bounds { scene.items[item].worldBounds = bounds }
    }

    /// A placed model with a drawn rig: each part skinned with its share of the rig's weights (the parts in order, as
    /// one surface), in its own materials.
    func riggedAsset(_ id: AssetID, model: ImportedModel, object: SceneObject, state: Inherited, base: ObjectUniforms, input: RenderInput,
                     casts: Bool, scene: inout RenderScene) -> Bool {
        guard object.rig?.skin != nil, !state.ghost, !model.parts.contains(where: \.isSkinned) else { return false }
        let total = model.parts.reduce(0) { $0 + $1.mesh.positions.count }
        guard let rig = rigWeights(object, input: input, vertexCount: total)?.rig else { return false }
        if object.paint != nil, input.weightView?.object != object.id {
            // Painted too: the paint mesh over the parts as one surface, skinned (see `painted`).
            return paintedAsset(id, model: model, object: object, state: state, base: base, input: input, casts: casts, scene: &scene)
        }
        let palette = appendPalette(rig, object: object, input: input, scene: &scene)
        let tinted = object.color != nil || state.tint != nil
        let weightView = weightUniforms(base, object: object, input: input)
        var start = 0
        let device = device
        for (index, part) in model.parts.enumerated() {
            let range = start ..< start + part.mesh.positions.count
            start = range.upperBound
            guard let source = meshes.mesh(.asset(id, part: index), make: { GPUMesh(device: device, mesh: part.mesh, label: part.name) }),
                  let mesh = riggedMesh(object, source: source, key: "\(id.raw) \(index)", slice: range, input: input) else { continue }
            var uniforms = base
            var texture: MTLTexture?
            let material = model.materials.indices.contains(part.material) ? model.materials[part.material] : ImportedMaterial()
            if !tinted {
                uniforms.baseColor = SIMD4<Float>(material.baseColor.linear, Float(material.baseColor.a) * base.baseColor.w)
                if let textureIndex = material.baseColorTexture, model.textures.indices.contains(textureIndex) {
                    texture = textures.texture(model: id, index: textureIndex, texture: model.textures[textureIndex])
                }
            }
            if let weightView {
                uniforms = weightView.uniforms
                texture = weightView.texture
            }
            addRigged(mesh, rig: rig, palette: palette, world: state.world.matrix, base: uniforms, texture: texture, casts: casts, scene: &scene)
        }
        return true
    }
}

/// Joint matrices for a drawn rig: each joint's pose in the rig's space times the inverse of its rest (where it was
/// drawn), in skeleton order.
enum RigPalette {
    static func matrices(_ rig: ObjectRig, pose: [LoweyCore.Transform]?) -> [simd_float4x4] {
        let skeleton = rig.skeleton
        let local = pose.flatMap { $0.count == skeleton.joints.count ? $0 : nil } ?? skeleton.restPose
        let posed = skeleton.modelSpace(local)
        let rest = skeleton.modelRest
        return zip(posed, rest).map { $0.matrix * $1.matrix.inverse }
    }
}

/// Decoded `.skin` files, by name (they never change: a new weighting is a new file), and the weight view's ramp.
final class RigSkinCache {
    private var loaded: [String: SkinWeights] = [:]
    private var order: [String] = []
    private var rampTexture: MTLTexture?

    /// Blue (no weight) through cyan, green and yellow to red (all of it), 256 texels wide.
    func ramp(device: MTLDevice) -> MTLTexture? {
        if let rampTexture { return rampTexture }
        let stops: [SIMD3<Float>] = [SIMD3(0.1, 0.2, 0.9), SIMD3(0.1, 0.8, 0.9), SIMD3(0.2, 0.85, 0.3), SIMD3(1, 0.85, 0.15), SIMD3(0.95, 0.15, 0.1)]
        var bytes: [UInt8] = []
        for texel in 0 ..< 256 {
            let along = Float(texel) / 255 * Float(stops.count - 1)
            let index = min(Int(along), stops.count - 2)
            let colour = stops[index] + (stops[index + 1] - stops[index]) * (along - Float(index))
            bytes += [UInt8(colour.x * 255), UInt8(colour.y * 255), UInt8(colour.z * 255), 255]
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: 256, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, 256, 1), mipmapLevel: 0, withBytes: bytes, bytesPerRow: 256 * 4)
        texture.label = "weight ramp"
        rampTexture = texture
        return texture
    }

    func weights(_ name: String, read: (String) -> Data?) -> SkinWeights? {
        if let weights = loaded[name] { return weights }
        guard let data = read(name), let weights = try? SkinWeights(data: data) else { return nil }
        loaded[name] = weights
        order.append(name)
        if order.count > 48 { loaded[order.removeFirst()] = nil }
        return weights
    }
}
