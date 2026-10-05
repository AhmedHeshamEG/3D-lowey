import CoreGraphics
import LoweyCore
import Metal

/// Flipbook drawings, stamped by the brush engine into one layer per blend mode at the output size; the composite
/// blends multiply, screen and add over the shot, then lays the normal layer under the overlays. A drawing whose track
/// is see-through is painted on a scratch layer first and laid down at its opacity, so its own strokes don't darken
/// each other where they cross.
extension LoweyRenderer {
    func encodeFlipbookLayers(_ request: FrameRequest, width: Int, height: Int, commandBuffer: MTLCommandBuffer) -> [FlipbookBlend: MTLTexture] {
        guard !request.flipbooks.isEmpty else { return [:] }
        var layers: [FlipbookBlend: MTLTexture] = [:]
        for blend in FlipbookBlend.allCases {
            let draws = request.flipbooks.filter { $0.blend == blend }
            guard !draws.isEmpty, let layer = flipbookTarget(blend.rawValue, width: width, height: height) else { continue }
            clear(layer, commandBuffer: commandBuffer)
            for draw in draws {
                if draw.opacity >= 0.999 {
                    paint(draw, into: layer, request: request, commandBuffer: commandBuffer)
                } else if let scratch = flipbookTarget("scratch", width: width, height: height) {
                    clear(scratch, commandBuffer: commandBuffer)
                    paint(draw, into: scratch, request: request, commandBuffer: commandBuffer)
                    lay(scratch, onto: layer, opacity: draw.opacity, commandBuffer: commandBuffer)
                }
            }
            layers[blend] = layer
        }
        return layers
    }

    private func flipbookTarget(_ name: String, width: Int, height: Int) -> MTLTexture? {
        if let existing = flipbookTargets[name], existing.width == width, existing.height == height { return existing }
        let texture = try? device.makeTexture(RenderDevice.layerFormat, width: width, height: height, usage: [.renderTarget, .shaderRead],
                                              label: "flipbook \(name)")
        flipbookTargets[name] = texture
        return texture
    }

    private func layerPass(_ texture: MTLTexture, load: MTLLoadAction) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = load
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        return pass
    }

    private func clear(_ texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        commandBuffer.makeRenderCommandEncoder(descriptor: layerPass(texture, load: .clear))?.endEncoding()
    }

    /// Every stroke of a drawing: stamps along lines, flat fills (with a rim of the line's width) for closed shapes.
    private func paint(_ draw: FlipbookDraw, into texture: MTLTexture, request: FrameRequest, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: layerPass(texture, load: .load)) else { return }
        encoder.label = "Flipbook \(draw.track)"
        let brushes = request.input.document.project.brushes
        for stroke in draw.strokes {
            let color = SIMD4<Float>(Float(stroke.color.r), Float(stroke.color.g), Float(stroke.color.b), 1)
            var path = stroke.path
            path.alphas = path.alphas.map { $0 * stroke.color.a }
            var brush = BrushResolver.brush(stroke.brush, in: brushes)
            var key = stroke.brush ?? BuiltInBrushes.inkPenID
            if stroke.filled {
                let alpha = Float(stroke.color.a)
                encoder.setRenderPipelineState(device.pipelines.brushFill)
                stamper.encodeFill(stroke.points, color: SIMD4<Float>(color.x * alpha, color.y * alpha, color.z * alpha, alpha), encoder: encoder,
                                   width: texture.width, height: texture.height)
                // The rim: the outline closed, at the stroke's width, so small shapes don't vanish.
                let rim = stroke.points + stroke.points.prefix(1)
                path = BrushPath(points: rim, widths: Array(repeating: stroke.widths.first ?? 1, count: rim.count),
                                 alphas: Array(repeating: stroke.color.a, count: rim.count))
                brush = BuiltInBrushes.technicalPen
                key = "fill-rim"
            }
            guard let (buffer, count) = stamper.stamps(path, brush: brush, key: key, seed: stroke.seed) else { continue }
            encoder.setRenderPipelineState(device.pipelines.brushLayer)
            stamper.encode([BrushBatch(dabs: buffer, count: count, brush: brush, color: color, world: nil)], encoder: encoder, view: nil,
                           width: texture.width, height: texture.height, image: request.input.mediaImage)
        }
        encoder.endEncoding()
    }

    private func lay(_ scratch: MTLTexture, onto layer: MTLTexture, opacity: Double, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: layerPass(layer, load: .load)) else { return }
        encoder.label = "Flipbook opacity"
        var amount = SIMD4<Float>(Float(min(max(opacity, 0), 1)), 0, 0, 0)
        encoder.setRenderPipelineState(device.pipelines.brushCompose)
        encoder.setFragmentBytes(&amount, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        encoder.setFragmentTexture(scratch, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
