import Metal

/// Builds the pipelines from the shader library (vertex layouts, attachments, blending).
struct PipelineBuilder {
    let device: MTLDevice
    let library: MTLLibrary
    let samples: Int

    /// Interleaved vertices: position, normal, uv, shadow bias (36 bytes); skinned meshes add joints + weights in a
    /// second buffer (24 bytes).
    static func vertexDescriptor(skinned: Bool) -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        let formats: [(MTLVertexFormat, Int)] = [(.float3, 0), (.float3, 12), (.float2, 24), (.float, 32)]
        for (index, (format, offset)) in formats.enumerated() {
            descriptor.attributes[index].format = format
            descriptor.attributes[index].offset = offset
            descriptor.attributes[index].bufferIndex = BufferIndex.vertices
        }
        descriptor.layouts[BufferIndex.vertices].stride = GPUMesh.vertexStride
        if skinned {
            descriptor.attributes[4].format = .ushort4
            descriptor.attributes[4].offset = 0
            descriptor.attributes[4].bufferIndex = BufferIndex.skin
            descriptor.attributes[5].format = .float4
            descriptor.attributes[5].offset = 8
            descriptor.attributes[5].bufferIndex = BufferIndex.skin
            descriptor.layouts[BufferIndex.skin].stride = GPUMesh.skinStride
        }
        return descriptor
    }

    private func function(_ name: String) throws -> MTLFunction {
        guard let function = library.makeFunction(name: name) else { throw RenderError.pipeline(name) }
        return function
    }

    private func render(_ descriptor: MTLRenderPipelineDescriptor, name: String) throws -> MTLRenderPipelineState {
        descriptor.label = name
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RenderError.pipeline("\(name): \(error.localizedDescription)")
        }
    }

    func shadow(vertex: String, skinned: Bool) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try function(vertex)
        descriptor.vertexDescriptor = Self.vertexDescriptor(skinned: skinned)
        descriptor.depthAttachmentPixelFormat = RenderDevice.depthFormat
        descriptor.inputPrimitiveTopology = .triangle
        return try render(descriptor, name: vertex)
    }

    func prepass(vertex: String, fragment: String, skinned: Bool) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try function(vertex)
        descriptor.fragmentFunction = try function(fragment)
        descriptor.vertexDescriptor = Self.vertexDescriptor(skinned: skinned)
        descriptor.colorAttachments[0].pixelFormat = RenderDevice.normalFormat
        descriptor.colorAttachments[1].pixelFormat = RenderDevice.idFormat
        descriptor.depthAttachmentPixelFormat = RenderDevice.depthFormat
        return try render(descriptor, name: "\(vertex)+\(fragment)")
    }

    func shading(vertex: String, fragment: String, skinned: Bool, blended: Bool) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try function(vertex)
        descriptor.fragmentFunction = try function(fragment)
        descriptor.vertexDescriptor = Self.vertexDescriptor(skinned: skinned)
        descriptor.rasterSampleCount = samples
        descriptor.colorAttachments[0].pixelFormat = RenderDevice.colorFormat
        descriptor.colorAttachments[1].pixelFormat = RenderDevice.lightFormat
        if blended {
            let color = descriptor.colorAttachments[0]
            color?.isBlendingEnabled = true
            color?.sourceRGBBlendFactor = .sourceAlpha
            color?.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color?.sourceAlphaBlendFactor = .one
            color?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        descriptor.depthAttachmentPixelFormat = RenderDevice.depthFormat
        return try render(descriptor, name: "\(vertex)+\(fragment)\(blended ? " blended" : "")")
    }

    func sky() throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try function("lw_vertexSky")
        descriptor.fragmentFunction = try function("lw_shadeSky")
        descriptor.rasterSampleCount = samples
        descriptor.colorAttachments[0].pixelFormat = RenderDevice.colorFormat
        descriptor.colorAttachments[1].pixelFormat = RenderDevice.lightFormat
        descriptor.depthAttachmentPixelFormat = RenderDevice.depthFormat
        return try render(descriptor, name: "sky")
    }

    func editor(fragment: String) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try function("lw_editorVertex")
        descriptor.fragmentFunction = try function(fragment)
        descriptor.vertexDescriptor = Self.vertexDescriptor(skinned: false)
        let color = descriptor.colorAttachments[0]
        color?.pixelFormat = RenderDevice.outputFormat
        color?.isBlendingEnabled = true
        color?.sourceRGBBlendFactor = .one
        color?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color?.sourceAlphaBlendFactor = .one
        color?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = RenderDevice.depthFormat
        return try render(descriptor, name: fragment)
    }

    /// Where brush stamps land: the scene's shading pass (MSAA, linear, depth-tested), the stage's editor layer, or a
    /// plain layer texture (flipbooks, previews).
    enum BrushTarget {
        case scene, editor, layer
    }

    /// Premultiplied stamps (`lw_brushVertex` / `lw_brushFragment`), or a layer's other passes by name.
    func brush(_ target: BrushTarget, vertex: String = "lw_brushVertex", fragment: String = "lw_brushFragment") throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try function(vertex)
        descriptor.fragmentFunction = try function(fragment)
        let color = descriptor.colorAttachments[0]
        switch target {
        case .scene:
            descriptor.rasterSampleCount = samples
            color?.pixelFormat = RenderDevice.colorFormat
            descriptor.colorAttachments[1].pixelFormat = RenderDevice.lightFormat
            descriptor.colorAttachments[1].writeMask = []
            descriptor.depthAttachmentPixelFormat = RenderDevice.depthFormat
        case .editor:
            color?.pixelFormat = RenderDevice.outputFormat
            descriptor.depthAttachmentPixelFormat = RenderDevice.depthFormat
        case .layer:
            color?.pixelFormat = RenderDevice.layerFormat
        }
        color?.isBlendingEnabled = true
        color?.sourceRGBBlendFactor = .one
        color?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color?.sourceAlphaBlendFactor = .one
        color?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try render(descriptor, name: "\(fragment) (\(target))")
    }

    func compute(_ name: String) throws -> MTLComputePipelineState {
        do {
            return try device.makeComputePipelineState(function: function(name))
        } catch let error as RenderError {
            throw error
        } catch {
            throw RenderError.pipeline("\(name): \(error.localizedDescription)")
        }
    }

    func depth(compare: MTLCompareFunction, write: Bool) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = compare
        descriptor.isDepthWriteEnabled = write
        guard let state = device.makeDepthStencilState(descriptor: descriptor) else { throw RenderError.pipeline("depth") }
        return state
    }
}
