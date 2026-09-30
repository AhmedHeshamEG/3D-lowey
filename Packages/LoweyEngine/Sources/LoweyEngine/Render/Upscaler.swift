import Metal
#if canImport(MetalFX)
    import MetalFX
#endif

/// Upscales the shaded image to native resolution when the render scale is below 1: MetalFX spatial scaling where
/// the GPU supports it, bilinear otherwise (docs/DECISIONS.md, MetalFX spike). Lines and overlays are drawn after
/// this, at native resolution.
final class Upscaler {
    private let device: RenderDevice
    #if canImport(MetalFX)
        private var scaler: MTLFXSpatialScaler?
        private var scalerSize: (Int, Int, Int, Int)?
    #endif

    init(device: RenderDevice) {
        self.device = device
    }

    static func isMetalFXSupported(_ device: MTLDevice) -> Bool {
        #if canImport(MetalFX) && !targetEnvironment(simulator)
            return MTLFXSpatialScalerDescriptor.supportsDevice(device)
        #else
            return false
        #endif
    }

    func encode(from source: MTLTexture, to destination: MTLTexture, commandBuffer: MTLCommandBuffer, pipelines: Pipelines) {
        #if canImport(MetalFX)
            if device.capabilities.metalFX, let scaler = scaler(source: source, destination: destination) {
                scaler.colorTexture = source
                scaler.outputTexture = destination
                scaler.encode(commandBuffer: commandBuffer)
                return
            }
        #endif
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Upscale"
        encoder.setComputePipelineState(pipelines.upscale)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        let group = MTLSize(width: 8, height: 8, depth: 1)
        encoder.dispatchThreadgroups(MTLSize(width: (destination.width + 7) / 8, height: (destination.height + 7) / 8, depth: 1),
                                     threadsPerThreadgroup: group)
        encoder.endEncoding()
    }

    #if canImport(MetalFX)
        private func scaler(source: MTLTexture, destination: MTLTexture) -> MTLFXSpatialScaler? {
            let size = (source.width, source.height, destination.width, destination.height)
            if let scaler, let scalerSize, scalerSize == size { return scaler }
            let descriptor = MTLFXSpatialScalerDescriptor()
            descriptor.inputWidth = source.width
            descriptor.inputHeight = source.height
            descriptor.outputWidth = destination.width
            descriptor.outputHeight = destination.height
            descriptor.colorTextureFormat = source.pixelFormat
            descriptor.outputTextureFormat = destination.pixelFormat
            descriptor.colorProcessingMode = .linear
            scaler = descriptor.makeSpatialScaler(device: device.device)
            scalerSize = size
            return scaler
        }
    #endif
}
