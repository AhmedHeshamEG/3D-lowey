import LoweyCore
import Metal
import simd

extension LoweyRenderer {
    func dispatch(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState, width: Int, height: Int) {
        encoder.setComputePipelineState(pipeline)
        let group = MTLSize(width: 8, height: 8, depth: 1)
        encoder.dispatchThreadgroups(MTLSize(width: (width + 7) / 8, height: (height + 7) / 8, depth: 1), threadsPerThreadgroup: group)
    }

    // MARK: Contact shading

    func encodeAO(frame: FrameUniforms, targets: FrameTargets, look: LookUniforms, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Contact shading"
        var params = AOParams(projection: SIMD4<Float>(frame.projection.columns.0.x, frame.projection.columns.1.y, 0.45,
                                                       look.rim.w > 0 ? 1.1 : 0),
                              size: SIMD4<Float>(Float(targets.ao.width), Float(targets.ao.height), Float(targets.width), Float(targets.height)))
        encoder.setTexture(targets.normalDepth, index: 0)
        encoder.setTexture(targets.ao, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<AOParams>.stride, index: 0)
        dispatch(encoder, device.pipelines.ssao, width: targets.ao.width, height: targets.ao.height)
        encoder.endEncoding()
    }

    // MARK: Lines → bloom → lens → finish

    func encodePost(_ shot: ShotContext, request: FrameRequest, gpu: FrameBuffers, targets: FrameTargets, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Lines and finish"
        let width = targets.width
        let height = targets.height
        let post = request.input.document.effectiveLook.post
        let sceneLook = request.input.document.lookPreset
        // Lines at native resolution.
        var lines = LineUniforms()
        lines.size = SIMD4<Float>(Float(width), Float(height), 1 / Float(width), 1 / Float(height))
        lines.scale = SIMD4<Float>(Float(height) / 1080, Float(request.frameIndex / 2), post.outline > 0 ? Float(1 + post.outline * 2.4) : 0, 0)
        lines.selection = SIMD4<Float>(RGBA(1, 0.72, 0.28).linear, request.editor?.showsSelection == true ? 1 : 0)
        lines.extraInk = SIMD4<Float>(post.outlineColor.linear, 0)
        var looks = gpu.looks
        encoder.setTexture(targets.nativeColor, index: 0)
        encoder.setTexture(targets.ids, index: 1)
        encoder.setTexture(targets.normalDepth, index: 2)
        encoder.setTexture(targets.lined, index: 3)
        encoder.setBytes(&looks, length: MemoryLayout<LookUniforms>.stride * looks.count, index: 0)
        encoder.setBuffer(gpu.lineWeights, offset: 0, index: 1)
        encoder.setBytes(&lines, length: MemoryLayout<LineUniforms>.stride, index: 2)
        dispatch(encoder, device.pipelines.lines, width: width, height: height)

        var uniforms = LookResolver.post(post, sceneLook: sceneLook, frame: request.frameIndex, size: SIMD2<Float>(Float(width), Float(height)))
        encodeBloom(encoder, source: targets.lined, targets: targets, uniforms: &uniforms)

        // Lens: blur, or misregistration in a Look that asks for it; chromatic aberration.
        var source = targets.lined
        if let lens = shot.lens, lens.aperture > 0, post.depthOfField {
            let cocScale = Float(lens.focalLength / 1000 * lens.focalLength / 1000 / max(lens.aperture, 0.7) * Double(height) / 0.024)
            uniforms.lens = SIMD4<Float>(cocScale, 1 / Float(max(lens.focusDistance, 0.05)), Float(height) * 0.03,
                                         sceneLook.comic.misregistration ? 2 : 1)
        }
        if uniforms.lens.w > 0 || post.chromaticAberration > 0 {
            encoder.setTexture(targets.lined, index: 0)
            encoder.setTexture(targets.normalDepth, index: 1)
            encoder.setTexture(targets.lensed, index: 2)
            encoder.setBytes(&uniforms, length: MemoryLayout<PostUniforms>.stride, index: 0)
            dispatch(encoder, device.pipelines.lens, width: width, height: height)
            source = targets.lensed
        }
        encoder.setTexture(source, index: 0)
        encoder.setTexture(targets.light, index: 1)
        encoder.setTexture(targets.ids, index: 2)
        encoder.setTexture(targets.bloomUp[0], index: 3)
        encoder.setTexture(shot.destination, index: 4)
        encoder.setBytes(&uniforms, length: MemoryLayout<PostUniforms>.stride, index: 0)
        encoder.setBytes(&looks, length: MemoryLayout<LookUniforms>.stride * looks.count, index: 1)
        dispatch(encoder, device.pipelines.finish, width: width, height: height)
        encoder.endEncoding()
    }

    /// Soft-threshold prefilter, three levels down, back up with a tent filter. The result is `bloomUp[0]`.
    func encodeBloom(_ encoder: MTLComputeCommandEncoder, source: MTLTexture, targets: FrameTargets, uniforms: inout PostUniforms) {
        encoder.setTexture(source, index: 0)
        encoder.setTexture(targets.bloom[0], index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<PostUniforms>.stride, index: 0)
        dispatch(encoder, device.pipelines.bloomPrefilter, width: targets.bloom[0].width, height: targets.bloom[0].height)
        for level in 1 ..< targets.bloom.count {
            encoder.setTexture(targets.bloom[level - 1], index: 0)
            encoder.setTexture(targets.bloom[level], index: 1)
            dispatch(encoder, device.pipelines.bloomDown, width: targets.bloom[level].width, height: targets.bloom[level].height)
        }
        let last = targets.bloom.count - 1
        var smaller = targets.bloom[last]
        for level in stride(from: last - 1, through: 0, by: -1) {
            encoder.setTexture(smaller, index: 0)
            encoder.setTexture(targets.bloom[level], index: 1)
            encoder.setTexture(targets.bloomUp[level], index: 2)
            dispatch(encoder, device.pipelines.bloomUp, width: targets.bloomUp[level].width, height: targets.bloomUp[level].height)
            smaller = targets.bloomUp[level]
        }
    }

    // MARK: Composite

    func encodeComposite(_ request: FrameRequest, targets: FrameTargets, overlay: MTLTexture?, flipbooks: [FlipbookBlend: MTLTexture],
                         output: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Composite"
        var uniforms = CompositeUniforms()
        uniforms.size = SIMD4<Float>(Float(output.width), Float(output.height), 1 / Float(output.width), 1 / Float(output.height))
        if let transition = request.transition {
            let kind: Float = switch transition.kind {
            case .cut: 1
            case .fade: 2
            case .dipToBlack: 3
            case .wipe: 4
            case .zoomThrough: 5
            }
            let progress = min(max(transition.progress, 0), 1)
            uniforms.transition = SIMD4<Float>(kind, Float(progress), Float(Easing.easeInOut.apply(progress)), 0)
        }
        let screen = request.screen
        uniforms.shake = SIMD4<Float>(Float(screen.shake.x), Float(screen.shake.y), Float(screen.shake.z), Float(screen.zoomBlur))
        uniforms.effects = SIMD4<Float>(Float(screen.glitch), Float(screen.speedLines), Float(screen.flash), Float(screen.glitchSeed % 9973))
        uniforms.flashColor = SIMD4<Float>(screen.flashColor.linear, Float(screen.lineSeed % 9973))
        if let guides = request.guides {
            uniforms.guides = SIMD4<Float>(1, Float(guides.aspect ?? 0), guides.thirds ? 1 : 0, guides.safeAreas ? 1 : 0)
        }
        let layerMask = (flipbooks[.multiply] == nil ? 0 : 1) + (flipbooks[.screen] == nil ? 0 : 2) + (flipbooks[.add] == nil ? 0 : 4)
            + (flipbooks[.normal] == nil ? 0 : 8)
        uniforms.options = SIMD4<Float>(overlay == nil ? 0 : 1, request.transparent ? 1 : 0, request.transparent ? 0 : 1, Float(layerMask))
        encoder.setTexture(targets.finished, index: 0)
        encoder.setTexture(request.transition == nil ? targets.finished : targets.finishedOther, index: 1)
        encoder.setTexture(overlay ?? editorMeshes.white, index: 2)
        encoder.setTexture(output, index: 3)
        encoder.setTexture(flipbooks[.multiply] ?? editorMeshes.white, index: 4)
        encoder.setTexture(flipbooks[.screen] ?? editorMeshes.white, index: 5)
        encoder.setTexture(flipbooks[.add] ?? editorMeshes.white, index: 6)
        encoder.setTexture(flipbooks[.normal] ?? editorMeshes.white, index: 7)
        encoder.setBytes(&uniforms, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
        dispatch(encoder, device.pipelines.composite, width: output.width, height: output.height)
        encoder.endEncoding()
    }
}
