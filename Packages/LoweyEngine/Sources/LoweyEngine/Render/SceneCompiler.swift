import CoreGraphics
import Foundation
import LoweyCore
import Metal
import simd

/// Walks an evaluated document and produces the frame's draw items: world transforms, colours in linear light,
/// the Look of every object (with overrides inherited down the hierarchy), selection flags, lights and helpers.
/// Meshes come from the renderer's cache; only what changed is built.
final class SceneCompiler {
    let device: MTLDevice
    let meshes: MeshCache
    let textures: TextureStore
    let models: ModelLibrary
    /// Ink strokes' stamps.
    let stamper: BrushStamper
    /// The camera of the frame being compiled (ink strokes turn to face it).
    var eye = SIMD3<Float>.zero
    /// The smear of the object being compiled (and its parts), applied on top of its world matrix.
    var activeDeform: simd_float4x4?
    /// The outline width of the character part being compiled.
    var activeHull: Float = 0

    init(device: MTLDevice, meshes: MeshCache, textures: TextureStore, models: ModelLibrary, stamper: BrushStamper) {
        self.device = device
        self.meshes = meshes
        self.textures = textures
        self.models = models
        self.stamper = stamper
    }

    /// What an object passes down to its children.
    struct Inherited {
        var world: LoweyCore.Transform = .identity
        var opacity = 1.0
        var lookOverride: String?
        var accent = false
        var selected = false
        var tint: ColorValue?
        var pickAs: ObjectID?
        var depth = 0
        var ghost = false
        var deform: simd_float4x4?
        /// Inside a character: its outline width (0 outside, and on face decals).
        var hull: Float = 0
        /// A face decal (eyes, brows, mouth…): drawn flat.
        var decal = false
    }

    func compile(_ input: RenderInput, cameraPosition: SIMD3<Float>) -> RenderScene {
        var scene = RenderScene()
        eye = cameraPosition
        _ = scene.lookIndex(input.document.lookPreset)
        var lights: [(LightData, Float)] = []
        func visit(_ id: ObjectID, in objects: [ObjectID: SceneObject], _ inherited: Inherited) {
            guard let object = objects[id], object.isVisible, id != input.hidden else { return }
            var state = inherited
            state.world = inherited.world * object.transform
            state.opacity *= object.opacity
            state.lookOverride = object.lookOverride ?? inherited.lookOverride
            state.accent = inherited.accent || object.isAccent
            state.selected = inherited.selected || input.selection.contains(id)
            if let smear = input.smears[id] { state.deform = Self.matrix(smear) * (inherited.deform ?? matrix_identity_float4x4) }
            outline(object, state: &state, input: input)
            activeDeform = state.deform
            activeHull = state.hull
            compileObject(object, state: state, input: input, scene: &scene, lights: &lights, cameraPosition: cameraPosition)
            for child in object.children {
                visit(child, in: objects, state)
            }
        }
        for root in input.document.scene.roots {
            visit(root, in: input.document.scene.objects, Inherited())
        }
        activeDeform = nil
        activeHull = 0
        for ghost in input.ghosts {
            var state = Inherited()
            state.world = ghost.scene.objects[ghost.root]?.parent.map { ghost.scene.worldTransform(of: $0) } ?? .identity
            state.opacity = ghost.opacity
            state.tint = .rgba(ghost.tint)
            state.ghost = true
            var ignored: [(LightData, Float)] = []
            func visitGhost(_ id: ObjectID, _ inherited: Inherited) {
                guard let object = ghost.scene.objects[id], object.isVisible else { return }
                var next = inherited
                next.world = inherited.world * object.transform
                next.opacity *= object.opacity
                next.lookOverride = object.lookOverride ?? inherited.lookOverride
                compileObject(object, state: next, input: input, scene: &scene, lights: &ignored, cameraPosition: cameraPosition)
                for child in object.children {
                    visitGhost(child, next)
                }
            }
            visitGhost(ghost.root, state)
        }
        scene.lights = Array(lights.sorted { $0.1 < $1.1 }.prefix(max(input.lightBudget, 0)).map(\.0))
        return scene
    }

    // MARK: Objects

    func compileObject(_ object: SceneObject, state: Inherited, input: RenderInput, scene: inout RenderScene,
                       lights: inout [(LightData, Float)], cameraPosition: SIMD3<Float>) {
        switch object.kind {
        case .group, .overlay:
            return
        case .light where state.ghost, .camera where state.ghost, .particles where state.ghost:
            return
        case let .light(type):
            let light = Self.lightData(type, object: object, world: state.world, palette: input.document.palette)
            lights.append((light, simd_distance(light.position.xyz4, cameraPosition)))
            if input.showsHelpers {
                let color = object[.lightColor]?.colorValue?.resolved(in: input.document.palette) ?? .white
                scene.helpers.append(HelperItem(kind: .light, object: object.id, transform: state.world, color: color, radius: 0.12))
            }
        case .camera:
            if input.showsHelpers {
                scene.helpers.append(HelperItem(kind: .camera, object: object.id, transform: state.world, color: RGBA(0.35, 0.8, 0.85),
                                                radius: 0.2))
            }
        case .particles:
            compileParticles(object, state: state, input: input, scene: &scene)
        default:
            compileSurface(object, state: state, input: input, scene: &scene)
        }
    }

    /// The uniforms every surface of an object shares.
    func uniforms(for object: SceneObject, state: Inherited, input: RenderInput, scene: inout RenderScene, objectIndex: UInt32) -> ObjectUniforms {
        if state.ghost { return ghostUniforms(state: state, input: input, scene: &scene) }
        let palette = input.document.palette
        var uniforms = ObjectUniforms()
        let color = (state.tint ?? object.color)?.resolved(in: palette) ?? .blockout
        uniforms.baseColor = SIMD4<Float>(color.linear, Float(min(max(state.opacity, 0), 1)))
        let intensity = object.emissiveIntensity
        if intensity > 0 {
            let glow = object.emissive?.resolved(in: palette) ?? color
            uniforms.emissive = SIMD4<Float>(glow.linear * Float(intensity), Float(intensity))
        }
        let smoothing: Float = if let value = object[.smoothing]?.floatValue {
            Float(value)
        } else {
            switch object.shading {
            case .inherit: -1
            case .smooth: 1
            case .flat: 0
            }
        }
        uniforms.params = SIMD4<Float>(smoothing, Float(object[.rimStrength]?.floatValue ?? -1), object.isGlossy ? 1 : 0,
                                       Float(object.lineWeight))
        let preset = LookLibrary.resolve(state.lookOverride ?? input.document.effectiveLook.presetID,
                                         custom: input.document.project.customLooks)
        var flags = ObjectFlags()
        if state.accent { flags.insert(.accent) }
        if state.decal { flags.insert(.unlit) }
        if state.selected { flags.insert(.selected) }
        if object.isGlossy { flags.insert(.glossy) }
        uniforms.ids = SIMD4<UInt32>(objectIndex, scene.lookIndex(preset), flags.rawValue, 0)
        return uniforms
    }

    func add(_ mesh: GPUMesh, world: simd_float4x4, uniforms base: ObjectUniforms, texture: MTLTexture? = nil, castsShadow: Bool,
             scene: inout RenderScene, brushDrawn: Bool = false) {
        var uniforms = base
        let world = activeDeform.map { $0 * world } ?? world
        uniforms.model = world
        uniforms.normalMatrix = world.normalMatrix
        let ghost = (base.ids.z & ObjectFlags.ghost.rawValue) != 0
        if texture != nil, !ghost { uniforms.ids.z |= ObjectFlags.textured.rawValue }
        let bounds = mesh.bounds.transformed(by: world)
        let blended = uniforms.baseColor.w < 0.999
        let ink = (base.ids.z & ObjectFlags.ink.rawValue) != 0
        scene.add(DrawItem(mesh: mesh, uniforms: uniforms, texture: ghost ? nil : texture, blended: blended,
                           castsShadow: castsShadow && !ghost, worldBounds: bounds, ghost: ghost,
                           hull: ghost || blended || ink ? 0 : activeHull, brushDrawn: brushDrawn))
    }

    /// A ghost: flat in its tint, see-through, not pickable (object index 0).
    func ghostUniforms(state: Inherited, input: RenderInput, scene: inout RenderScene) -> ObjectUniforms {
        var uniforms = ObjectUniforms()
        let tint = state.tint?.resolved(in: input.document.palette) ?? .white
        uniforms.baseColor = SIMD4<Float>(tint.linear, Float(min(max(state.opacity, 0.02), 0.95)))
        uniforms.params = SIMD4<Float>(-1, 0, 0, 0)
        uniforms.ids = SIMD4<UInt32>(0, scene.lookIndex(input.document.lookPreset), ObjectFlags.unlit.rawValue | ObjectFlags.ghost.rawValue, 0)
        return uniforms
    }

    // MARK: Lights

    static func lightData(_ type: LightType, object: SceneObject, world: LoweyCore.Transform, palette: Palette) -> LightData {
        let color = (object[.lightColor]?.colorValue?.resolved(in: palette) ?? .white).linear
        let intensity = Float(object[.lightIntensity]?.floatValue ?? 1)
        let range = Float(object[.lightRange]?.floatValue ?? 6)
        let forward = world.rotation.act(Vec3(0, 0, -1)).float3
        var light = LightData()
        light.position = SIMD4<Float>(world.position.float3, max(range, 0.1))
        switch type {
        case .point:
            light.color = SIMD4<Float>(color * intensity * 1.6, 0)
        case .spot:
            let angle = Float(object[.spotAngle]?.floatValue ?? 40) * .pi / 180
            light.color = SIMD4<Float>(color * intensity * 2.2, 1)
            light.direction = SIMD4<Float>(forward, cos(angle / 2))
            light.params = SIMD4<Float>(cos(angle * 0.3), 0, 0, 0)
        case .directional:
            light.color = SIMD4<Float>(color * intensity, 2)
            light.direction = SIMD4<Float>(forward, 0)
            light.position.w = 1e6
        }
        return light
    }
}

extension SceneCompiler {
    /// Characters get an outline (inverted hull) sized to them and their Look; face decals are flat and outline-free.
    func outline(_ object: SceneObject, state: inout Inherited, input: RenderInput) {
        if let role = object[.faceRole]?.stringValue, CharacterOutline.isDecal(role: role) {
            state.hull = 0
            state.decal = true
            return
        }
        guard state.hull == 0, !state.decal, CharacterOutline.isCharacter(object.id, in: input.document.scene) else { return }
        let preset = LookLibrary.resolve(state.lookOverride ?? input.document.effectiveLook.presetID, custom: input.document.project.customLooks)
        let scale = abs(state.world.scale.y)
        state.hull = Float(CharacterOutline.width(look: preset, scale: scale, lineWeight: object.lineWeight) ?? 0)
    }

    /// A smear as a world-space matrix: stretch along the direction about the pivot, slid back by the shift.
    static func matrix(_ smear: Smear) -> simd_float4x4 {
        let n = smear.direction.float3
        let k = Float(smear.stretch) - 1
        let stretch = simd_float3x3(diagonal: SIMD3<Float>(repeating: 1)) + simd_float3x3(columns: (n * n.x * k, n * n.y * k, n * n.z * k))
        let pivot = smear.pivot.float3
        let offset = pivot - stretch * pivot - n * Float(smear.shift)
        return simd_float4x4(columns: (SIMD4<Float>(stretch.columns.0, 0), SIMD4<Float>(stretch.columns.1, 0), SIMD4<Float>(stretch.columns.2, 0),
                                       SIMD4<Float>(offset, 1)))
    }
}

extension SIMD4 where Scalar == Float {
    var xyz4: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}

extension Bounds {
    /// Axis-aligned bounds after a matrix.
    func transformed(by matrix: simd_float4x4) -> Bounds {
        let points = corners.map { corner -> Vec3 in
            let p = matrix * SIMD4<Float>(corner.float3, 1)
            return Vec3(Double(p.x), Double(p.y), Double(p.z))
        }
        return Bounds(points: points) ?? self
    }
}
