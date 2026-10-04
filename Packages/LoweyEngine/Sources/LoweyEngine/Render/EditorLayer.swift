import LoweyCore
import Metal
import simd

/// Which gizmo handle.
public struct GizmoHandle: Sendable, Hashable {
    public enum Kind: String, Sendable { case move, rotate, scale, uniformScale }
    public var kind: Kind
    public var axis: CoreAxis

    public init(kind: Kind, axis: CoreAxis) {
        self.kind = kind
        self.axis = axis
    }
}

public enum GizmoMode: String, Sendable, CaseIterable {
    case move, rotate, scale
}

/// What the stage draws over the finished frame (never exported).
public struct EditorScene {
    public var showsGrid = true
    public var showsSelection = true
    public var gizmo: (mode: GizmoMode, pivot: Vec3, size: Double)?
    public var guide: GuideSurface?
    public var strokePreview: (mesh: MeshData, color: RGBA)?
    /// The hovering Pencil (drawn last, on top of everything).
    public var pointer: PencilPointer?
    /// Radians per pixel (2·tan(fov/2) / height in pixels), for the grid's one-pixel lines.
    public var pixelAngle: Float = 0.0012

    public init() {}

    public static let axisColors: [CoreAxis: RGBA] = [.x: RGBA(0.96, 0.33, 0.36), .y: RGBA(0.45, 0.86, 0.4), .z: RGBA(0.35, 0.58, 1)]
    /// Radius of the rotate rings in gizmo units (the gizmo scales to stay the same size on screen).
    public static let ringRadius = 0.95
}

/// The small meshes of the editor layer, built once.
final class EditorMeshes {
    let sphere: GPUMesh
    let box: GPUMesh
    let cylinder: GPUMesh
    let cone: GPUMesh
    let ring: GPUMesh
    let quad: GPUMesh
    let white: MTLTexture

    init(device: MTLDevice) throws {
        func make(_ data: MeshData, _ label: String) throws -> GPUMesh {
            guard let mesh = GPUMesh(device: device, mesh: data, label: label) else { throw RenderError.texture }
            return mesh
        }
        sphere = try make(PrimitiveMesh.make(.sphere, shading: .smooth), "helper sphere")
        box = try make(PrimitiveMesh.make(.cube, shading: .flat), "helper box")
        cylinder = try make(PrimitiveMesh.make(.cylinder, shading: .smooth), "helper cylinder")
        cone = try make(PrimitiveMesh.make(.cone, shading: .smooth), "helper cone")
        ring = try make(PrimitiveMesh.torus(segments: 64, sides: 6, major: Float(EditorScene.ringRadius), minor: 0.022), "gizmo ring")
        quad = try make(PrimitiveMesh.box(size: SIMD3<Float>(800, 0.001, 800)), "grid")
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let white = device.makeTexture(descriptor: descriptor) else { throw RenderError.texture }
        var pixel: [UInt8] = [255, 255, 255, 255]
        white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
        self.white = white
    }

    /// Unit-radius disc (the ground; scaled by its radius in the vertex shader).
    static func disc(segments: Int) -> MeshData {
        var mesh = MeshData()
        let up = SIMD3<Float>(0, 1, 0)
        let center = mesh.addVertex(.zero, normal: up, uv: SIMD2<Float>(0.5, 0.5))
        for segment in 0 ... segments {
            let angle = Float(segment) / Float(segments) * 2 * .pi
            mesh.addVertex(SIMD3<Float>(sin(angle), 0, cos(angle)), normal: up, uv: SIMD2<Float>(0.5 + sin(angle) / 2, 0.5 + cos(angle) / 2))
        }
        for segment in 0 ..< UInt32(segments) {
            mesh.addTriangle(center, segment + 1, segment + 2)
        }
        return mesh
    }
}

extension LoweyRenderer {
    struct EditorDraw {
        var mesh: GPUMesh
        var item: EditorItemUniforms
        var depthTested: Bool
    }

    func encodeEditor(_ editor: EditorScene, request: FrameRequest, scene: RenderScene, targets: FrameTargets, output: MTLTexture,
                      commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = targets.depth
        pass.depthAttachment.loadAction = .load
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setFrontFacing(.counterClockwise)
        encoder.label = "Editor layer"
        encoder.setCullMode(.none)
        let camera = request.camera
        var uniforms = EditorUniforms(viewProjection: camera.projection(aspect: Float(output.width) / Float(output.height)) * camera.viewMatrix,
                                      cameraPosition: SIMD4<Float>(camera.position, editor.pixelAngle))
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<EditorUniforms>.stride, index: 3)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EditorUniforms>.stride, index: 3)
        if editor.showsGrid {
            encoder.setDepthStencilState(device.pipelines.depthRead)
            encoder.setRenderPipelineState(device.pipelines.grid)
            var grid = EditorItemUniforms(model: matrix_identity_float4x4, color: SIMD4<Float>(1, 1, 1, 1), params: .zero)
            grid.model.columns.3.y = 0.001
            encode(EditorDraw(mesh: editorMeshes.quad, item: grid, depthTested: true), encoder: encoder)
        }
        encoder.setRenderPipelineState(device.pipelines.editor)
        for draw in editorDraws(editor, scene: scene) {
            encode(draw, encoder: encoder)
        }
        if let pointer = editor.pointer {
            for draw in pointerDraws(pointer, camera: camera, aspect: Double(output.width) / Double(max(output.height, 1))) {
                encode(draw, encoder: encoder)
            }
        }
        encoder.endEncoding()
    }

    private func encode(_ draw: EditorDraw, encoder: MTLRenderCommandEncoder) {
        var item = draw.item
        encoder.setDepthStencilState(draw.depthTested ? device.pipelines.depthRead : device.pipelines.depthAlways)
        encoder.setVertexBuffer(draw.mesh.vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&item, length: MemoryLayout<EditorItemUniforms>.stride, index: 2)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: draw.mesh.indexCount, indexType: .uint32, indexBuffer: draw.mesh.indices,
                                      indexBufferOffset: 0)
    }

    func editorDraws(_ editor: EditorScene, scene: RenderScene) -> [EditorDraw] {
        var draws: [EditorDraw] = []
        for helper in scene.helpers {
            let color = SIMD4<Float>(helper.color.srgbVector, 1)
            let mesh = helper.kind == .camera ? editorMeshes.box : editorMeshes.sphere
            let size = helper.kind == .camera ? SIMD3<Float>(0.3, 0.2, 0.2) : SIMD3<Float>(repeating: Float(helper.radius))
            var model = LoweyCore.Transform(position: helper.transform.position, rotation: helper.transform.rotation).matrix
            model *= simd_float4x4(diagonal: SIMD4<Float>(size, 1))
            // Primitives stand on their base: centre them on the object.
            model.columns.3 -= model.columns.1 * 0.5
            draws.append(EditorDraw(mesh: mesh, item: EditorItemUniforms(model: model, color: color, params: SIMD4<Float>(1, 0, 0, 0)),
                                    depthTested: true))
        }
        if let guide = editor.guide { draws += guideDraws(guide) }
        if let (mesh, color) = editor.strokePreview, let gpu = strokePreviewMesh(mesh) {
            draws.append(EditorDraw(mesh: gpu, item: EditorItemUniforms(model: matrix_identity_float4x4, color: SIMD4<Float>(color.srgbVector, 1),
                                                                        params: SIMD4<Float>(1, 0, 0, 0)), depthTested: true))
        }
        if let gizmo = editor.gizmo { draws += gizmoDraws(gizmo.mode, pivot: gizmo.pivot, size: Float(gizmo.size)) }
        return draws
    }

    /// The stroke being drawn, uploaded once per change of its shape (it was uploaded on every frame).
    private func strokePreviewMesh(_ mesh: MeshData) -> GPUMesh? {
        if let cached = strokePreviewCache, cached.mesh == mesh { return cached.gpu }
        let gpu = GPUMesh(device: device.device, mesh: mesh, label: "stroke")
        strokePreviewCache = gpu.map { (mesh, $0) }
        return gpu
    }

    private func guideDraws(_ guide: GuideSurface) -> [EditorDraw] {
        let fill = SIMD4<Float>(0.45, 0.75, 1, 0.16)
        switch guide {
        case let .plane(origin, normal):
            let rotation = Quat.rotation(from: .unitY, to: normal)
            let model = LoweyCore.Transform(position: origin, rotation: rotation, scale: Vec3(0.01, 1, 0.01)).matrix
            return [EditorDraw(mesh: editorMeshes.quad, item: EditorItemUniforms(model: model, color: fill, params: .zero), depthTested: true)]
        case let .box(center, size):
            let model = LoweyCore.Transform(position: center - Vec3(0, size.y / 2, 0), scale: size).matrix
            return [EditorDraw(mesh: editorMeshes.box, item: EditorItemUniforms(model: model, color: fill, params: .zero), depthTested: true)]
        case let .cylinder(base, radius, height):
            let model = LoweyCore.Transform(position: base, scale: Vec3(radius * 2, height, radius * 2)).matrix
            return [EditorDraw(mesh: editorMeshes.cylinder, item: EditorItemUniforms(model: model, color: fill, params: .zero), depthTested: true)]
        case let .sphere(center, radius):
            let model = LoweyCore.Transform(position: center - Vec3(0, radius, 0), scale: Vec3(radius * 2, radius * 2, radius * 2)).matrix
            return [EditorDraw(mesh: editorMeshes.sphere, item: EditorItemUniforms(model: model, color: fill, params: .zero), depthTested: true)]
        }
    }

    /// Move arrows / rotate rings / scale cubes, always on top, a constant size on screen.
    private func gizmoDraws(_ mode: GizmoMode, pivot: Vec3, size: Float) -> [EditorDraw] {
        var draws: [EditorDraw] = []
        let base = simd_float4x4(diagonal: SIMD4<Float>(size, size, size, 1))
        var origin = base
        origin.columns.3 = SIMD4<Float>(pivot.float3, 1)
        for axis in CoreAxis.allCases {
            let color = SIMD4<Float>((EditorScene.axisColors[axis] ?? .white).srgbVector, 1)
            let orient = simd_float4x4(Self.axisRotation(axis))
            let frame = origin * orient
            switch mode {
            case .move, .scale:
                let shaft = frame * LoweyCore.Transform(scale: Vec3(0.05, 0.8, 0.05)).matrix
                draws.append(EditorDraw(mesh: editorMeshes.cylinder, item: EditorItemUniforms(model: shaft, color: color, params: .zero),
                                        depthTested: false))
                let tip = mode == .move
                    ? frame * LoweyCore.Transform(position: Vec3(0, 0.8, 0), scale: Vec3(0.16, 0.25, 0.16)).matrix
                    : frame * LoweyCore.Transform(position: Vec3(0, 0.8, 0), scale: Vec3(0.16, 0.16, 0.16)).matrix
                draws.append(EditorDraw(mesh: mode == .move ? editorMeshes.cone : editorMeshes.box,
                                        item: EditorItemUniforms(model: tip, color: color, params: SIMD4<Float>(1, 0, 0, 0)), depthTested: false))
            case .rotate:
                draws.append(EditorDraw(mesh: editorMeshes.ring, item: EditorItemUniforms(model: frame, color: color, params: .zero),
                                        depthTested: false))
            }
        }
        if mode == .scale {
            let center = origin * LoweyCore.Transform(position: Vec3(0, -0.1, 0), scale: Vec3(0.2, 0.2, 0.2)).matrix
            draws.append(EditorDraw(mesh: editorMeshes.box, item: EditorItemUniforms(model: center, color: SIMD4<Float>(1, 1, 1, 1),
                                                                                     params: SIMD4<Float>(1, 0, 0, 0)), depthTested: false))
        }
        return draws
    }

    /// Points a handle's local +Y along its axis.
    static func axisRotation(_ axis: CoreAxis) -> simd_quatf {
        switch axis {
        case .x: simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 0, 1))
        case .y: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        case .z: simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        }
    }
}

extension RGBA {
    /// sRGB components as a vector (the editor layer draws in sRGB).
    var srgbVector: SIMD3<Float> { SIMD3<Float>(Float(r), Float(g), Float(b)) }
}
