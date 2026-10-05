import LoweyCore
import Metal
import simd

extension SceneCompiler {
    /// Ink strokes. What shows is the brush engine's stamps, turned to this frame's camera and depth-tested in the
    /// shading pass (`RenderScene.brushes`); the camera-facing ribbon underneath stays for picking, the selection
    /// outline and shadows, and is what an onion-skin ghost shows. Both are written on by the object's `reveal`.
    func compileInk(_ recipe: DrawingRecipe, object: SceneObject, state: Inherited, base: ObjectUniforms, casts: Bool, input: RenderInput,
                    scene: inout RenderScene) {
        let eyeLocal = state.world.inverseApply(to: Vec3(Double(eye.x), Double(eye.y), Double(eye.z)))
        let reveal = min(max(object[.reveal]?.floatValue ?? 1, 0), 1)
        guard reveal > 0 else { return }
        let key = MeshKey.ink(recipe, eye: SIMD3<Int32>(Self.centimetres(eyeLocal.x), Self.centimetres(eyeLocal.y),
                                                        Self.centimetres(eyeLocal.z)),
                              reveal: Int32((reveal * 1000).rounded()))
        let device = device
        guard let mesh = meshes.mesh(key, make: {
            GPUMesh(device: device, mesh: InkMesher.mesh(for: recipe, eye: eyeLocal, reveal: reveal), label: "ink")
        }) else { return }
        var uniforms = base
        uniforms.ids.z |= ObjectFlags.unlit.rawValue | ObjectFlags.ink.rawValue
        let ghost = (base.ids.z & ObjectFlags.ghost.rawValue) != 0
        add(mesh, world: state.world.matrix, uniforms: uniforms, castsShadow: casts, scene: &scene, brushDrawn: !ghost)
        guard !ghost else { return }
        let world = activeDeform.map { $0 * state.world.matrix } ?? state.world.matrix
        let scale = Float(max(abs(state.world.scale.x), abs(state.world.scale.y), abs(state.world.scale.z), 1e-6))
        let opacity = Double(base.baseColor.w)
        for stroke in InkMesher.revealed(recipe, reveal: reveal) {
            let brush = BrushResolver.brush(stroke.brush, in: input.document.project.brushes)
            var path = stroke.path
            if opacity < 0.999 { path.alphas = path.alphas.map { $0 * opacity } }
            guard let (buffer, count) = stamper.stamps(path, brush: brush, key: stroke.brush ?? BuiltInBrushes.inkPenID,
                                                       seed: stroke.seed ?? 0) else { continue }
            scene.brushes.append(BrushBatch(dabs: buffer, count: count, brush: brush, color: SIMD4<Float>(base.baseColor.xyz4, 1),
                                            world: (world, scale)))
        }
    }

    static func centimetres(_ value: Double) -> Int32 {
        Int32(max(min((value * 100).rounded(), Double(Int32.max)), Double(Int32.min)))
    }
}
