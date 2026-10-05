import CoreGraphics
import LoweyCore
import Metal
import simd

/// The brush engine's GPU half: turns strokes into stamp buffers (cached while they stay the same) and draws them
/// with the pipeline the caller set (scene, editor or layer). Core's `BrushStroker` decides every stamp; this only
/// uploads and draws.
final class BrushStamper {
    let device: MTLDevice
    let textures: BrushTextureCache
    private var strokeBuffers: [StrokeKey: (buffer: MTLBuffer, count: Int, lastUse: UInt64)] = [:]
    private var clock: UInt64 = 0

    /// A stroke's stamps depend on its path, brush and seed only.
    struct StrokeKey: Hashable {
        var points: [SIMD2<Float>]
        var depthPoints: [Float]
        var widths: [Float]
        var alphas: [Float]
        var brush: String
        var seed: UInt64
    }

    init(device: MTLDevice) throws {
        self.device = device
        textures = try BrushTextureCache(device: device)
    }

    // MARK: Buffers

    func buffer(_ dabs: [BrushDabData]) -> MTLBuffer? {
        guard !dabs.isEmpty else { return nil }
        return dabs.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
        }
    }

    /// A 2D stroke's stamps (pixels), built once per path.
    func stamps(_ path: BrushPath<Vec2>, brush: Brush, key: String, seed: UInt64) -> (MTLBuffer, Int)? {
        let strokeKey = StrokeKey(points: path.points.map { SIMD2<Float>(Float($0.x), Float($0.y)) }, depthPoints: [],
                                  widths: path.widths.map(Float.init), alphas: path.alphas.map(Float.init), brush: key, seed: seed)
        return cached(strokeKey) { BrushStroker.dabs(path, brush: brush, seed: seed).map(BrushDabData.init) }
    }

    /// A 3D stroke's stamps (in its drawing's space), built once per path.
    func stamps(_ path: BrushPath<Vec3>, brush: Brush, key: String, seed: UInt64) -> (MTLBuffer, Int)? {
        let strokeKey = StrokeKey(points: path.points.map { SIMD2<Float>(Float($0.x), Float($0.y)) }, depthPoints: path.points.map { Float($0.z) },
                                  widths: path.widths.map(Float.init), alphas: path.alphas.map(Float.init), brush: key, seed: seed)
        return cached(strokeKey) { BrushStroker.dabs(path, brush: brush, seed: seed).map(BrushDabData.init) }
    }

    private func cached(_ key: StrokeKey, make: () -> [BrushDabData]) -> (MTLBuffer, Int)? {
        clock &+= 1
        if let entry = strokeBuffers[key] {
            strokeBuffers[key] = (entry.buffer, entry.count, clock)
            return (entry.buffer, entry.count)
        }
        let dabs = make()
        guard let buffer = buffer(dabs) else { return nil }
        strokeBuffers[key] = (buffer, dabs.count, clock)
        if strokeBuffers.count > 4096 {
            let recent = clock > 2048 ? clock - 2048 : 0
            strokeBuffers = strokeBuffers.filter { $0.value.lastUse >= recent }
        }
        return (buffer, dabs.count)
    }

    func trim() {
        strokeBuffers.removeAll()
    }

    // MARK: Drawing

    /// The camera, for stamps in the world.
    struct WorldView {
        var viewProjection: simd_float4x4
        var eye: SIMD3<Float>
        var right: SIMD3<Float>
        var up: SIMD3<Float>

        init(viewProjection: simd_float4x4, view: simd_float4x4, eye: SIMD3<Float>) {
            self.viewProjection = viewProjection
            self.eye = eye
            // The view matrix's rows are the camera's axes in the world.
            right = SIMD3<Float>(view.columns.0.x, view.columns.1.x, view.columns.2.x)
            up = SIMD3<Float>(view.columns.0.y, view.columns.1.y, view.columns.2.y)
        }
    }

    /// Draws batches with the pipeline already set on `encoder`. World batches need `view`.
    func encode(_ batches: [BrushBatch], encoder: MTLRenderCommandEncoder, view: WorldView?, width: Int, height: Int,
                image: (String) -> CGImage?) {
        for batch in batches where batch.count >= 1 {
            var uniforms = BrushUniforms(brush: batch.brush)
            uniforms.setViewport(width: width, height: height)
            uniforms.color = batch.color
            if let world = batch.world, let view {
                uniforms.viewProjection = view.viewProjection
                uniforms.model = world.model
                uniforms.eye = SIMD4<Float>(view.eye, 1)
                uniforms.cameraRight = SIMD4<Float>(view.right, world.scale)
                uniforms.cameraUp = SIMD4<Float>(view.up, 0)
            } else if batch.world != nil {
                continue
            }
            let (shape, grain) = textures.textures(for: batch.brush, image: image)
            encoder.setVertexBuffer(batch.dabs, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<BrushUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BrushUniforms>.stride, index: 1)
            encoder.setFragmentTexture(shape, index: 0)
            encoder.setFragmentTexture(grain, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: batch.count)
        }
    }

    /// A filled shape (pixels) in one premultiplied colour, with the fill pipeline set.
    func encodeFill(_ outline: [Vec2], color: SIMD4<Float>, encoder: MTLRenderCommandEncoder, width: Int, height: Int) {
        guard outline.count >= 3 else { return }
        let area = zip(outline, outline.dropFirst() + [outline[0]]).reduce(0) { $0 + $1.0.cross($1.1) }
        let ordered = area < 0 ? Array(outline.reversed()) : outline
        let triangles = PolygonTriangulator.triangulate(outline: ordered.enumerated().map { (vertex: $0.offset, point: $0.element) }, holes: [])
        encodeTriangles(triangles.flatMap { [ordered[$0.0], ordered[$0.1], ordered[$0.2]] }, color: color, encoder: encoder, width: width,
                        height: height)
    }
}
