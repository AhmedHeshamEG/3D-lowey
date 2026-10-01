import CoreGraphics
import Foundation
import LoweyCore
import Metal
import simd

/// One frame for the renderer: the evaluated scene, the shot camera, and what goes around it.
public struct FrameRequest {
    public var input: RenderInput
    public var camera: RenderCamera
    /// The shot camera's lens (depth of field when its aperture > 0).
    public var lens: CameraLens?
    /// The other shot of a transition in progress.
    public var transition: (camera: RenderCamera, lens: CameraLens?, kind: TransitionSpec.Kind, progress: Double)?
    public var screen: ScreenState
    public var frameIndex: Int
    /// 0.5…1: the shaded image's resolution (lines and overlays stay native). Export always renders at 1.
    public var renderScale: Float
    /// No sky or ground: the frame keeps an alpha channel (transparent exports).
    public var transparent: Bool
    /// Overlays and captions, drawn by Core Graphics at the output size (premultiplied sRGB).
    public var overlay: CGImage?
    /// Stage-only drawing (grid, gizmo, helpers, guide, stroke preview).
    public var editor: EditorScene?
    /// Director view framing guides.
    public var guides: FramingGuides?

    public init(input: RenderInput, camera: RenderCamera, lens: CameraLens? = nil, screen: ScreenState = ScreenState(), frameIndex: Int = 0,
                renderScale: Float = 1, transparent: Bool = false, overlay: CGImage? = nil, editor: EditorScene? = nil,
                guides: FramingGuides? = nil) {
        self.input = input
        self.camera = camera
        self.lens = lens
        self.screen = screen
        self.frameIndex = frameIndex
        self.renderScale = renderScale
        self.transparent = transparent
        self.overlay = overlay
        self.editor = editor
        self.guides = guides
    }
}

/// Framing guides of the Director view: the delivery shape masked, thirds, safe areas.
public struct FramingGuides: Sendable, Equatable {
    public var aspect: Double?
    public var thirds: Bool
    public var safeAreas: Bool

    public init(aspect: Double?, thirds: Bool = true, safeAreas: Bool = false) {
        self.aspect = aspect
        self.thirds = thirds
        self.safeAreas = safeAreas
    }
}

/// What the renderer measured about a frame.
public struct FrameReport: Sendable, Equatable {
    public var drawCalls: Int
    public var triangles: Int
    public var objects: Int
}

/// The renderer contract the stage, snapshots, thumbnails and export use.
public protocol SceneRendering: AnyObject {
    /// Encodes a frame into `output` (bgra8Unorm, the output size).
    func encode(_ request: FrameRequest, to output: MTLTexture, commandBuffer: MTLCommandBuffer) throws -> FrameReport
    /// The scene object at a pixel of the last frame's ID buffer (exact, no ray misses on thin objects).
    func pick(at pixel: SIMD2<Int>, radius: Int) -> PickHit?
}

/// LoweyRender 2: shadow map → prepass (depth, normal, ID) → Look shading (MSAA) → contact shading → lines →
/// bloom, lens, halftone, finish → transitions, screen effects, overlays → the stage's editor layer.
public final class LoweyRenderer: SceneRendering {
    let device: RenderDevice
    let meshes = MeshCache()
    let textures: TextureStore
    let compiler: SceneCompiler
    let upscaler: Upscaler
    private(set) var targets: FrameTargets?
    let shadowMap: MTLTexture
    let groundMesh: GPUMesh
    let editorMeshes: EditorMeshes
    let buffers: BufferRing
    /// The last frame, for picking.
    private(set) var lastScene: RenderScene?
    private(set) var lastCamera: RenderCamera?

    public init(device: RenderDevice, models: ModelLibrary = .shared) throws {
        self.device = device
        textures = TextureStore(device: device.device)
        compiler = SceneCompiler(device: device.device, meshes: meshes, textures: textures, models: models)
        upscaler = Upscaler(device: device)
        shadowMap = try device.makeTexture(RenderDevice.depthFormat, width: RenderDevice.shadowMapSize, height: RenderDevice.shadowMapSize,
                                           usage: [.renderTarget, .shaderRead], label: "sun shadows", arrayLength: 2)
        guard let ground = GPUMesh(device: device.device, mesh: EditorMeshes.disc(segments: 128), label: "ground") else {
            throw RenderError.texture
        }
        groundMesh = ground
        editorMeshes = try EditorMeshes(device: device.device)
        buffers = BufferRing(device: device.device)
    }

    public var capabilities: RenderCapabilities { device.capabilities }

    /// Frees cached meshes and textures that weren't used lately (memory warning).
    public func trimCaches() {
        meshes.trim()
        textures.removeAll()
    }

    func targets(width: Int, height: Int, scale: Float) throws -> FrameTargets {
        let shadingHeight = max(Int((Float(height) * min(max(scale, 0.5), 1)).rounded()), 1)
        if let targets, targets.width == width, targets.height == height, targets.shadingHeight == shadingHeight { return targets }
        let made = try FrameTargets(device: device, width: width, height: height, scale: scale)
        targets = made
        return made
    }

    public func encode(_ request: FrameRequest, to output: MTLTexture, commandBuffer: MTLCommandBuffer) throws -> FrameReport {
        let targets = try targets(width: output.width, height: output.height, scale: request.renderScale)
        var scene = compiler.compile(request.input, cameraPosition: request.camera.position)
        let slot = buffers.next(for: commandBuffer)
        let ordered = order(&scene, camera: request.camera)
        let gpu = try slot.fill(scene: scene, ordered: ordered)
        var report = FrameReport(drawCalls: 0, triangles: 0, objects: scene.objectIDs.count)
        if let transition = request.transition {
            let other = ShotContext(camera: transition.camera, lens: transition.lens, destination: targets.finishedOther)
            try encodeShot(other, request: request, scene: scene, ordered: ordered, gpu: gpu, targets: targets, commandBuffer: commandBuffer,
                           report: &report)
        }
        let main = ShotContext(camera: request.camera, lens: request.lens, destination: targets.finished)
        try encodeShot(main, request: request, scene: scene, ordered: ordered, gpu: gpu, targets: targets, commandBuffer: commandBuffer,
                       report: &report)
        let overlay = request.overlay.flatMap { textures.texture(for: $0, key: "overlay", maxSide: 8192) }
        encodeComposite(request, targets: targets, overlay: overlay, output: output, commandBuffer: commandBuffer)
        if let editor = request.editor {
            encodeEditor(editor, request: request, scene: scene, targets: targets, output: output, commandBuffer: commandBuffer)
        }
        lastScene = scene
        lastCamera = request.camera
        return report
    }

    /// One camera's view, rendered to `destination`.
    struct ShotContext {
        var camera: RenderCamera
        var lens: CameraLens?
        var destination: MTLTexture
    }

    /// Opaque first (grouped by mesh so repeats instance), then see-through back to front.
    func order(_ scene: inout RenderScene, camera: RenderCamera) -> [DrawItem] {
        let opaque = scene.items.filter { !$0.blended }.sorted { lhs, rhs in
            if lhs.mesh.isSkinned != rhs.mesh.isSkinned { return !lhs.mesh.isSkinned }
            let left = ObjectIdentifier(lhs.mesh)
            let right = ObjectIdentifier(rhs.mesh)
            if left != right { return left < right }
            return (lhs.texture.map { ObjectIdentifier($0) }.map { $0.hashValue } ?? 0)
                < (rhs.texture.map { ObjectIdentifier($0) }.map { $0.hashValue } ?? 0)
        }
        let blended = scene.items.filter(\.blended).sorted { lhs, rhs in
            simd_distance(lhs.worldBounds.center.float3, camera.position) > simd_distance(rhs.worldBounds.center.float3, camera.position)
        }
        return opaque + blended
    }
}
