import CoreGraphics
import LoweyCore
import Metal
import simd

extension LoweyRenderer {
    /// A run of consecutive draw items sharing a mesh and texture: one instanced draw.
    struct Run {
        var start: Int
        var count: Int
    }

    static func runs(_ ordered: [DrawItem], where include: (DrawItem) -> Bool) -> [Run] {
        var runs: [Run] = []
        for (index, item) in ordered.enumerated() where include(item) {
            if let last = runs.last, last.start + last.count == index {
                let previous = ordered[last.start]
                if previous.mesh === item.mesh, previous.texture === item.texture, !item.mesh.isSkinned, !item.blended {
                    runs[runs.count - 1].count += 1
                    continue
                }
            }
            runs.append(Run(start: index, count: 1))
        }
        return runs
    }

    /// Frame uniforms for one camera.
    func frameUniforms(_ request: FrameRequest, camera: RenderCamera, scene: RenderScene, width: Int, height: Int,
                       shadingWidth: Int, shadingHeight: Int) -> FrameUniforms {
        var frame = FrameUniforms()
        let look = request.input.document.effectiveLook
        LookResolver.world(look, into: &frame, transparentBackdrop: request.transparent)
        let aspect = Float(width) / Float(max(height, 1))
        let view = camera.viewMatrix
        let projection = camera.projection(aspect: aspect)
        frame.view = view
        frame.projection = projection
        frame.viewProjection = projection * view
        frame.inverseViewProjection = frame.viewProjection.inverse
        let (splits, first, second) = ShadowCascades.matrices(camera: camera, aspect: aspect, sunToward: frame.sunDirection.xyz4,
                                                              sceneBounds: scene.bounds, mapSize: shadowMapSize)
        frame.shadowMatrix0 = first
        frame.shadowMatrix1 = second
        frame.cascades = SIMD4<Float>(splits.x, splits.y, 1 / Float(shadowMapSize), Float(request.frameIndex))
        frame.cameraPosition = SIMD4<Float>(camera.position, Float(request.input.time))
        frame.viewport = SIMD4<Float>(Float(shadingWidth), Float(shadingHeight), 1 / Float(max(shadingWidth, 1)),
                                      1 / Float(max(shadingHeight, 1)))
        frame.misc = SIMD4<Float>(Float(scene.lights.count), camera.near, camera.far, 0)
        if let section = request.editor?.section {
            frame.section = SIMD4<Float>(Float(section.normal.x), Float(section.normal.y), Float(section.normal.z), Float(section.offset))
        }
        if request.transparent || !look.ground.visible { frame.groundBounce.w = 0 }
        return frame
    }

    func encodeShot(_ shot: ShotContext, request: FrameRequest, scene: RenderScene, ordered: [DrawItem], gpu: FrameBuffers,
                    targets: FrameTargets, commandBuffer: MTLCommandBuffer, report: inout FrameReport) throws {
        var frame = frameUniforms(request, camera: shot.camera, scene: scene, width: targets.width, height: targets.height,
                                  shadingWidth: targets.shadingWidth, shadingHeight: targets.shadingHeight)
        let showsGround = !request.transparent && request.input.document.effectiveLook.ground.visible
        if frame.sunColor.w > 0.5 { encodeShadows(frame: frame, ordered: ordered, gpu: gpu, commandBuffer: commandBuffer) }
        // The prepass is native resolution: its viewport uses the native size.
        var native = frame
        native.viewport = SIMD4<Float>(Float(targets.width), Float(targets.height), 1 / Float(targets.width), 1 / Float(targets.height))
        encodePrepass(frame: native, ordered: ordered, gpu: gpu, targets: targets, ground: showsGround, commandBuffer: commandBuffer)
        encodeAO(frame: frame, targets: targets, look: gpu.looks[0], commandBuffer: commandBuffer)
        let groundColor = request.input.document.effectiveLook.ground.color.linear * frame.skyHorizon.w
        report.drawCalls += encodeShading(frame: &frame, ordered: ordered, gpu: gpu, targets: targets, ground: showsGround ? groundColor : nil,
                                          brushes: (scene.brushes, request.input.mediaImage), commandBuffer: commandBuffer,
                                          triangles: &report.triangles)
        if let upscaled = targets.upscaled {
            upscaler.encode(from: targets.color, to: upscaled, commandBuffer: commandBuffer, pipelines: device.pipelines)
        }
        encodePost(shot, request: request, gpu: gpu, targets: targets, commandBuffer: commandBuffer)
    }

    /// Character outlines: each part pushed out along its normals, back faces only, in the line colour.
    func encodeHulls(ordered: [DrawItem], gpu: FrameBuffers, encoder: MTLRenderCommandEncoder) -> Int {
        let runs = Self.runs(ordered) { $0.hull > 0 }
        guard !runs.isEmpty else { return 0 }
        encoder.setCullMode(.front)
        encoder.setDepthStencilState(device.pipelines.depthWrite)
        for run in runs {
            let item = ordered[run.start]
            encoder.setRenderPipelineState(item.mesh.isSkinned ? device.pipelines.hullSkinned : device.pipelines.hullStatic)
            var width = item.hull
            encoder.setVertexBytes(&width, length: MemoryLayout<Float>.stride, index: BufferIndex.cascade)
            draw(item.mesh, run: run, encoder: encoder, objects: gpu.objects)
        }
        encoder.setCullMode(.none)
        return runs.count
    }

    // MARK: Shadows

    func encodeShadows(frame: FrameUniforms, ordered: [DrawItem], gpu: FrameBuffers, commandBuffer: MTLCommandBuffer) {
        var uniforms = frame
        for cascade in 0 ..< 2 {
            let pass = MTLRenderPassDescriptor()
            pass.depthAttachment.texture = shadowMap
            pass.depthAttachment.slice = cascade
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1
            pass.depthAttachment.storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { continue }
            encoder.setFrontFacing(.counterClockwise)
            encoder.label = "Sun shadows \(cascade)"
            encoder.setDepthStencilState(device.pipelines.shadowDepth)
            encoder.setDepthBias(0.0005, slopeScale: 2.0, clamp: 0.01)
            encoder.setCullMode(.none)
            var index = UInt32(cascade)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: BufferIndex.frame)
            encoder.setVertexBytes(&index, length: 4, index: BufferIndex.cascade)
            encoder.setVertexBuffer(gpu.joints, offset: 0, index: BufferIndex.joints)
            for run in Self.runs(ordered, where: { $0.castsShadow && !$0.blended && !$0.ghost }) {
                let item = ordered[run.start]
                encoder.setRenderPipelineState(item.mesh.isSkinned ? device.pipelines.shadowSkinned : device.pipelines.shadowStatic)
                draw(item.mesh, run: run, encoder: encoder, objects: gpu.objects)
            }
            encoder.endEncoding()
        }
    }

    func draw(_ mesh: GPUMesh, run: Run, encoder: MTLRenderCommandEncoder, objects: MTLBuffer) {
        let offset = run.start * MemoryLayout<ObjectUniforms>.stride
        encoder.setVertexBuffer(mesh.vertices, offset: 0, index: BufferIndex.vertices)
        if let skin = mesh.skin { encoder.setVertexBuffer(skin, offset: 0, index: BufferIndex.skin) }
        encoder.setVertexBuffer(objects, offset: offset, index: BufferIndex.objects)
        encoder.setFragmentBuffer(objects, offset: offset, index: BufferIndex.objects)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount, indexType: .uint32, indexBuffer: mesh.indices,
                                      indexBufferOffset: 0, instanceCount: run.count)
    }

    // MARK: Prepass

    func encodePrepass(frame: FrameUniforms, ordered: [DrawItem], gpu: FrameBuffers, targets: FrameTargets, ground: Bool,
                       commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targets.normalDepth
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1e6)
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[1].texture = targets.ids
        pass.colorAttachments[1].loadAction = .clear
        pass.colorAttachments[1].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[1].storeAction = .store
        pass.depthAttachment.texture = targets.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 0
        pass.depthAttachment.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setFrontFacing(.counterClockwise)
        encoder.label = "Prepass"
        var uniforms = frame
        encoder.setDepthStencilState(device.pipelines.depthWrite)
        encoder.setCullMode(.none)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: BufferIndex.frame)
        encoder.setVertexBuffer(gpu.joints, offset: 0, index: BufferIndex.joints)
        if ground {
            encoder.setRenderPipelineState(device.pipelines.prepassGround)
            encoder.setVertexBuffer(groundMesh.vertices, offset: 0, index: BufferIndex.vertices)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: groundMesh.indexCount, indexType: .uint32,
                                          indexBuffer: groundMesh.indices, indexBufferOffset: 0)
        }
        for run in Self.runs(ordered, where: { $0.uniforms.baseColor.w > 0.02 && !$0.ghost }) {
            let item = ordered[run.start]
            encoder.setRenderPipelineState(item.mesh.isSkinned ? device.pipelines.prepassSkinned : device.pipelines.prepassStatic)
            draw(item.mesh, run: run, encoder: encoder, objects: gpu.objects)
        }
        encoder.endEncoding()
    }

    // MARK: Shading

    func encodeShading(frame: inout FrameUniforms, ordered: [DrawItem], gpu: FrameBuffers, targets: FrameTargets, ground: SIMD3<Float>?,
                       brushes: (batches: [BrushBatch], image: (String) -> CGImage?), commandBuffer: MTLCommandBuffer,
                       triangles: inout Int) -> Int {
        let pass = MTLRenderPassDescriptor()
        let multisampled = targets.msaaColor != nil
        pass.colorAttachments[0].texture = targets.msaaColor ?? targets.color
        pass.colorAttachments[0].resolveTexture = multisampled ? targets.color : nil
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = multisampled ? .multisampleResolve : .store
        pass.colorAttachments[1].texture = targets.msaaLight ?? targets.light
        pass.colorAttachments[1].resolveTexture = multisampled ? targets.light : nil
        pass.colorAttachments[1].loadAction = .clear
        pass.colorAttachments[1].clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[1].storeAction = multisampled ? .multisampleResolve : .store
        pass.depthAttachment.texture = targets.shadingDepth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 0
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return 0 }
        encoder.setFrontFacing(.counterClockwise)
        encoder.label = "Look shading"
        encoder.setCullMode(.none)
        var looks = gpu.looks
        var lights = gpu.lights
        encoder.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: BufferIndex.frame)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: BufferIndex.frame)
        encoder.setFragmentBytes(&looks, length: MemoryLayout<LookUniforms>.stride * looks.count, index: BufferIndex.looks)
        encoder.setFragmentBytes(&lights, length: MemoryLayout<LightData>.stride * lights.count, index: BufferIndex.lights)
        encoder.setVertexBuffer(gpu.joints, offset: 0, index: BufferIndex.joints)
        encoder.setFragmentTexture(targets.ao, index: 1)
        encoder.setFragmentTexture(shadowMap, index: 2)
        // Sky first (never writes depth), then the ground, then objects.
        encoder.setDepthStencilState(device.pipelines.depthAlways)
        encoder.setRenderPipelineState(device.pipelines.sky)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.setDepthStencilState(device.pipelines.depthWrite)
        var draws = 1
        if let ground {
            var groundColor = SIMD4<Float>(ground, 1)
            encoder.setRenderPipelineState(device.pipelines.shadeGround)
            encoder.setFragmentBytes(&groundColor, length: MemoryLayout<SIMD4<Float>>.stride, index: BufferIndex.objects)
            encoder.setVertexBuffer(groundMesh.vertices, offset: 0, index: BufferIndex.vertices)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: groundMesh.indexCount, indexType: .uint32,
                                          indexBuffer: groundMesh.indices, indexBufferOffset: 0)
            draws += 1
        }
        for run in Self.runs(ordered, where: { !$0.brushDrawn }) {
            let item = ordered[run.start]
            let skinned = item.mesh.isSkinned
            if item.blended {
                encoder.setDepthStencilState(device.pipelines.depthRead)
                encoder.setRenderPipelineState(skinned ? device.pipelines.shadeSkinnedBlended : device.pipelines.shadeStaticBlended)
            } else {
                encoder.setRenderPipelineState(skinned ? device.pipelines.shadeSkinned : device.pipelines.shadeStatic)
            }
            encoder.setFragmentTexture(item.texture ?? editorMeshes.white, index: 0)
            draw(item.mesh, run: run, encoder: encoder, objects: gpu.objects)
            draws += 1
            triangles += item.mesh.indexCount / 3 * run.count
        }
        if !brushes.batches.isEmpty {
            // Ink: stamps over everything shaded, hidden where something stands in front.
            encoder.setRenderPipelineState(device.pipelines.brushScene)
            encoder.setDepthStencilState(device.pipelines.depthRead)
            let view = BrushStamper.WorldView(viewProjection: frame.viewProjection, view: frame.view, eye: frame.cameraPosition.xyz4)
            stamper.encode(brushes.batches, encoder: encoder, view: view, width: targets.shadingWidth, height: targets.shadingHeight,
                           image: brushes.image)
            draws += brushes.batches.count
        }
        draws += encodeHulls(ordered: ordered, gpu: gpu, encoder: encoder)
        encoder.endEncoding()
        return draws
    }
}
