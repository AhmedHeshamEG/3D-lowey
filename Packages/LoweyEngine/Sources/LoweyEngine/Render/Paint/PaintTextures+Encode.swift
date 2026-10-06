import CoreGraphics
import LoweyCore
import Metal
import simd

/// The GPU work of painting: this frame's tile uploads, coverage, compositing, and the stroke under the Pencil.
extension PaintTextures {
    // MARK: Before the frame

    /// Copies the queued tiles into their layers, then rebuilds coverage and the composite of every surface that needs it.
    func encodeUpdates(commandBuffer: MTLCommandBuffer) {
        for surface in surfaces.values {
            for layer in surface.layers.values where layer.needsClear {
                clear(layer.texture, commandBuffer: commandBuffer)
                layer.needsClear = false
                surface.needsCompose = true
            }
        }
        if !uploads.isEmpty, let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.label = "Paint tiles"
            let side = PaintSurface.tileSize
            let clear = [UInt8](repeating: 0, count: side * side * 4)
            for upload in uploads {
                let bytes = upload.bytes ?? clear
                guard let staging = device.device.makeBuffer(bytes: bytes, length: bytes.count, options: .storageModeShared) else { continue }
                blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: side * 4, sourceBytesPerImage: bytes.count,
                          sourceSize: MTLSize(width: side, height: side, depth: 1), to: upload.layer.texture, destinationSlice: 0,
                          destinationLevel: 0, destinationOrigin: MTLOrigin(x: upload.tile.column * side, y: upload.tile.row * side, z: 0))
            }
            blit.endEncoding()
            for surface in surfaces.values where uploads.contains(where: { upload in surface.layers.values.contains { $0 === upload.layer } }) {
                surface.needsCompose = true
            }
            uploads.removeAll()
        }
        for surface in surfaces.values where surface.needsCompose {
            compose(surface, commandBuffer: commandBuffer)
        }
    }

    /// Coverage (when the mesh changed), the layers composited, the finish pass and the mip chain.
    func compose(_ surface: Surface, commandBuffer: MTLCommandBuffer) {
        guard let mesh = surface.mesh, let (first, second) = scratchTextures(size: surface.size) else { return }
        if surface.coverageMesh != ObjectIdentifier(mesh) || surface.coverage == nil {
            encodeCoverage(surface, mesh: mesh, commandBuffer: commandBuffer)
        }
        guard let coverage = surface.coverage else { return }
        var under = first, over = second
        clear(under, commandBuffer: commandBuffer)
        for layer in surface.settings where layer.visible && layer.opacity > 0 {
            guard let texture = surface.layers[layer.id]?.texture,
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: Self.pass(over, load: .dontCare)) else { continue }
            encoder.label = "Paint layer \(layer.name)"
            encoder.setRenderPipelineState(device.pipelines.paint.compose)
            var uniforms = SIMD4<Float>(Float(layer.opacity), Float(Self.blendIndex(layer.blend)), 0, 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.setFragmentTexture(under, index: 0)
            encoder.setFragmentTexture(texture, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            swap(&under, &over)
        }
        let finish = MTLRenderPassDescriptor()
        finish.colorAttachments[0].texture = surface.composite
        finish.colorAttachments[0].level = 0
        finish.colorAttachments[0].loadAction = .dontCare
        finish.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: finish) {
            encoder.label = "Paint finish"
            encoder.setRenderPipelineState(device.pipelines.paint.finish)
            encoder.setFragmentTexture(under, index: 0)
            encoder.setFragmentTexture(coverage, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: surface.composite)
            blit.endEncoding()
        }
        surface.needsCompose = false
    }

    static func blendIndex(_ blend: PaintBlend) -> Int {
        switch blend {
        case .normal: 0
        case .multiply: 1
        case .screen: 2
        case .overlay: 3
        case .add: 4
        }
    }

    private func encodeCoverage(_ surface: Surface, mesh: GPUMesh, commandBuffer: MTLCommandBuffer) {
        if surface.coverage == nil {
            surface.coverage = try? device.makeTexture(.r8Unorm, width: surface.size, height: surface.size, usage: [.renderTarget, .shaderRead],
                                                       label: "paint coverage")
        }
        guard let coverage = surface.coverage,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: Self.pass(coverage, load: .clear)) else { return }
        encoder.label = "Paint coverage"
        encoder.setRenderPipelineState(device.pipelines.paint.coverage)
        encoder.setCullMode(.none)
        var uniforms = PaintUniforms()
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<PaintUniforms>.stride, index: 1)
        encoder.setVertexBuffer(mesh.vertices, offset: 0, index: BufferIndex.vertices)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount, indexType: .uint32, indexBuffer: mesh.indices,
                                      indexBufferOffset: 0)
        encoder.endEncoding()
        surface.coverageMesh = ObjectIdentifier(mesh)
    }

    private func scratchTextures(size: Int) -> (MTLTexture, MTLTexture)? {
        if let scratch, scratch.0.width == size { return scratch }
        guard let first = try? device.makeTexture(RenderDevice.layerFormat, width: size, height: size, usage: [.renderTarget, .shaderRead],
                                                  label: "paint composite A"),
            let second = try? device.makeTexture(RenderDevice.layerFormat, width: size, height: size, usage: [.renderTarget, .shaderRead],
                                                 label: "paint composite B") else { return nil }
        scratch = (first, second)
        return scratch
    }

    static func pass(_ texture: MTLTexture, load: MTLLoadAction) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = load
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        return pass
    }

    func clear(_ texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        commandBuffer.makeRenderCommandEncoder(descriptor: Self.pass(texture, load: .clear))?.endEncoding()
    }

    // MARK: The stroke under the Pencil

    /// What the projection needs from the frame: the object as drawn, the camera, the frame's ID buffer and depth.
    struct StrokeView {
        var item: DrawItem
        var objectIndex: UInt32
        var camera: RenderCamera
        var viewProjection: simd_float4x4
        var ids: MTLTexture
        var depth: MTLTexture
    }

    /// Paints the live stroke into its layer (the layer as it was before the stroke, then the whole stroke so far,
    /// projected), and composites the object again, all before the frame's shading reads it.
    func encodeStroke(_ live: LivePaint, view: StrokeView, stamper: BrushStamper, image: (String) -> CGImage?, commandBuffer: MTLCommandBuffer) {
        guard let surface = surfaces[live.object], let layer = surface.layers[live.layer] else { return }
        guard let before = beforeTexture(for: live, layer: layer, size: surface.size, commandBuffer: commandBuffer),
              let target = strokeTexture(width: view.ids.width, height: view.ids.height) else { return }
        guard drawSource(live, into: target, stamper: stamper, image: image, commandBuffer: commandBuffer) else { return }
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(from: before, to: layer.texture)
            blit.endEncoding()
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: Self.pass(layer.texture, load: .load)) else { return }
        encoder.label = live.erases ? "Paint erase" : "Paint stroke"
        encoder.setRenderPipelineState(live.erases ? device.pipelines.paint.erase : device.pipelines.paint.project)
        encoder.setCullMode(.none)
        var uniforms = PaintUniforms()
        uniforms.model = view.item.uniforms.model
        uniforms.normalMatrix = view.item.uniforms.normalMatrix
        uniforms.viewProjection = view.viewProjection
        // Orthographic views are a far telephoto (RenderCamera), so the eye is always a point.
        uniforms.eye = SIMD4<Float>(view.camera.position, 0)
        uniforms.forward = SIMD4<Float>(view.camera.forward, 0)
        let width = Float(view.ids.width), height = Float(view.ids.height)
        uniforms.screen = SIMD4<Float>(width, height, 1 / width, 1 / height)
        uniforms.params = SIMD4<Float>(Float(view.objectIndex), 0.01, 0, 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<PaintUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PaintUniforms>.stride, index: 1)
        encoder.setVertexBuffer(view.item.mesh.vertices, offset: 0, index: BufferIndex.vertices)
        encoder.setFragmentTexture(target, index: 0)
        encoder.setFragmentTexture(view.ids, index: 1)
        encoder.setFragmentTexture(view.depth, index: 2)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: view.item.mesh.indexCount, indexType: .uint32,
                                      indexBuffer: view.item.mesh.indices, indexBufferOffset: 0)
        encoder.endEncoding()
        compose(surface, commandBuffer: commandBuffer)
    }

    /// The layer as it was when this stroke began (copied once per stroke).
    private func beforeTexture(for live: LivePaint, layer: Layer, size: Int, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let stroke, stroke.id == live.stroke, stroke.object == live.object, stroke.layer == live.layer { return stroke.before }
        let reuse = (stroke?.before ?? spareBefore).flatMap { $0.width == size ? $0 : nil }
        guard let before = reuse ?? (try? device.makeTexture(RenderDevice.layerFormat, width: size, height: size,
                                                             usage: [.renderTarget, .shaderRead], label: "paint before stroke")),
            let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: layer.texture, to: before)
        blit.endEncoding()
        stroke = ActiveStroke(id: live.stroke, object: live.object, layer: live.layer, before: before)
        return before
    }

    private func strokeTexture(width: Int, height: Int) -> MTLTexture? {
        if let strokeTarget, strokeTarget.width == width, strokeTarget.height == height { return strokeTarget }
        strokeTarget = try? device.makeTexture(RenderDevice.layerFormat, width: width, height: height, usage: [.renderTarget, .shaderRead],
                                               label: "paint stroke")
        return strokeTarget
    }

    /// The stroke on the screen, premultiplied in its sRGB colour: the brush engine's stamps, or the picture.
    private func drawSource(_ live: LivePaint, into target: MTLTexture, stamper: BrushStamper, image: (String) -> CGImage?,
                            commandBuffer: MTLCommandBuffer) -> Bool {
        let scale = live.pixelsPerPoint
        switch live.source {
        case let .stamps(dabs, brush):
            clear(target, commandBuffer: commandBuffer)
            let pixels = dabs.map { dab -> BrushDabData in
                var moved = dab
                moved.center = dab.center * scale
                moved.radius = dab.radius * scale
                moved.lateral = dab.lateral * scale
                return BrushDabData(moved)
            }
            guard let buffer = stamper.buffer(pixels),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: Self.pass(target, load: .load)) else { return false }
            encoder.label = "Paint stroke stamps"
            encoder.setRenderPipelineState(device.pipelines.brushLayer)
            let color = SIMD4<Float>(Float(live.color.r), Float(live.color.g), Float(live.color.b), 1)
            stamper.encode([BrushBatch(dabs: buffer, count: pixels.count, brush: brush, color: color, world: nil)], encoder: encoder, view: nil,
                           width: target.width, height: target.height, image: image)
            encoder.endEncoding()
            return true
        case let .picture(picture, rect):
            guard let bytes = PaintPixels.screen(picture, rect: rect, scale: scale, opacity: live.color.a, width: target.width,
                                                 height: target.height),
                let staging = device.device.makeBuffer(bytes: bytes, length: bytes.count, options: .storageModeShared),
                let blit = commandBuffer.makeBlitCommandEncoder() else { return false }
            blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: target.width * 4, sourceBytesPerImage: bytes.count,
                      sourceSize: MTLSize(width: target.width, height: target.height, depth: 1), to: target, destinationSlice: 0,
                      destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
            return true
        }
    }

    // MARK: After the stroke

    /// The copies a finished stroke is read back from: its layer now and as it was before it.
    struct StrokeReadback {
        var commandBuffer: MTLCommandBuffer
        var after: MTLBuffer
        var before: MTLBuffer
        var size: Int
        var object: ObjectID
        var layer: String

        func bytes(_ buffer: MTLBuffer) -> [UInt8] {
            [UInt8](UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt8.self), count: size * size * 4))
        }
    }

    /// Encodes copying the last stroke's layer (now and before) into readable buffers; the caller commits and waits.
    func strokeReadback(queue: MTLCommandQueue) -> StrokeReadback? {
        guard let stroke, let layer = surfaces[stroke.object]?.layers[stroke.layer] else { return nil }
        self.stroke = nil
        spareBefore = stroke.before
        let size = layer.texture.width
        let length = size * size * 4
        guard let after = device.device.makeBuffer(length: length, options: .storageModeShared),
              let before = device.device.makeBuffer(length: length, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        commandBuffer.label = "Paint stroke read back"
        let region = MTLSize(width: size, height: size, depth: 1)
        blit.copy(from: layer.texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: region, to: after,
                  destinationOffset: 0, destinationBytesPerRow: size * 4, destinationBytesPerImage: length)
        blit.copy(from: stroke.before, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: region, to: before,
                  destinationOffset: 0, destinationBytesPerRow: size * 4, destinationBytesPerImage: length)
        blit.endEncoding()
        return StrokeReadback(commandBuffer: commandBuffer, after: after, before: before, size: size, object: stroke.object, layer: stroke.layer)
    }
}

extension PaintPixels {
    /// The tiles whose bytes differ, as straight-alpha pictures.
    static func changedTiles(after: [UInt8], before: [UInt8], size: Int) -> [PaintTileIndex: RGBAImage] {
        var result: [PaintTileIndex: RGBAImage] = [:]
        let tiles = size / side
        for row in 0 ..< tiles {
            for column in 0 ..< tiles {
                var changed = false
                var bytes = [UInt8](repeating: 0, count: side * side * 4)
                for line in 0 ..< side {
                    let from = ((row * side + line) * size + column * side) * 4
                    let range = from ..< from + side * 4
                    if !changed, after[range] != before[range] { changed = true }
                    bytes.replaceSubrange(line * side * 4 ..< (line + 1) * side * 4, with: after[range])
                }
                if changed { result[PaintTileIndex(column: column, row: row)] = straight(bytes, width: side, height: side) }
            }
        }
        return result
    }

    /// A picture placed on the screen (points × scale), premultiplied at `opacity`, as the stroke texture's bytes.
    static func screen(_ picture: CGImage, rect: CGRect, scale: Double, opacity: Double, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // Core Graphics draws y up; the stroke texture runs from the top.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.setAlpha(CGFloat(min(max(opacity, 0), 1)))
            let placed = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            context.translateBy(x: placed.minX, y: placed.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(picture, in: CGRect(origin: .zero, size: placed.size))
            return true
        }
        return drawn ? bytes : nil
    }
}
