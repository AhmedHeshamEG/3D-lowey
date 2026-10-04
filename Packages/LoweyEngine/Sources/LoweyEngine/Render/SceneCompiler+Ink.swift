import LoweyCore
import Metal
import simd

extension SceneCompiler {
    /// Ink strokes: ribbons turned toward this frame's camera, drawn flat in the object's colour (no Look shading,
    /// no outlines), written on by the object's `reveal`.
    func compileInk(_ recipe: DrawingRecipe, object: SceneObject, state: Inherited, base: ObjectUniforms, casts: Bool,
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
        add(mesh, world: state.world.matrix, uniforms: uniforms, castsShadow: casts, scene: &scene)
    }

    static func centimetres(_ value: Double) -> Int32 {
        Int32(max(min((value * 100).rounded(), Double(Int32.max)), Double(Int32.min)))
    }
}
