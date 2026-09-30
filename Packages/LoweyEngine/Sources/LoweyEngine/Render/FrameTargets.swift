import Metal

/// The intermediate textures of one output size and render scale (rebuilt only when either changes).
final class FrameTargets {
    let width: Int
    let height: Int
    let shadingWidth: Int
    let shadingHeight: Int
    let samples: Int

    // Prepass (native resolution, single sample: lines and picking read it pixel-exact).
    let normalDepth: MTLTexture
    let ids: MTLTexture
    let depth: MTLTexture
    // Shading (scaled, multisampled).
    let msaaColor: MTLTexture?
    let msaaLight: MTLTexture?
    let shadingDepth: MTLTexture
    let color: MTLTexture
    let light: MTLTexture
    let ao: MTLTexture
    // Native resolution after upscaling.
    let upscaled: MTLTexture?
    let lined: MTLTexture
    let lensed: MTLTexture
    let finished: MTLTexture
    let finishedOther: MTLTexture
    let bloom: [MTLTexture]
    let bloomUp: [MTLTexture]

    var scale: Float { Float(shadingHeight) / Float(max(height, 1)) }

    init(device: RenderDevice, width: Int, height: Int, scale: Float) throws {
        self.width = max(width, 1)
        self.height = max(height, 1)
        let clamped = min(max(scale, 0.5), 1)
        shadingWidth = max(Int((Float(width) * clamped).rounded()), 1)
        shadingHeight = max(Int((Float(height) * clamped).rounded()), 1)
        samples = device.capabilities.msaaSamples
        let target: MTLTextureUsage = [.renderTarget, .shaderRead]
        let rw: MTLTextureUsage = [.shaderRead, .shaderWrite]
        let transient: MTLStorageMode = device.capabilities.memorylessTargets ? .memoryless : .private
        normalDepth = try device.makeTexture(RenderDevice.normalFormat, width: self.width, height: self.height, usage: target, label: "normal+depth")
        ids = try device.makeTexture(RenderDevice.idFormat, width: self.width, height: self.height, usage: target, label: "ids")
        depth = try device.makeTexture(RenderDevice.depthFormat, width: self.width, height: self.height, usage: target, label: "prepass depth")
        if samples > 1 {
            msaaColor = try device.makeTexture(RenderDevice.colorFormat, width: shadingWidth, height: shadingHeight, usage: .renderTarget,
                                               samples: samples, storage: transient, label: "msaa colour")
            msaaLight = try device.makeTexture(RenderDevice.lightFormat, width: shadingWidth, height: shadingHeight, usage: .renderTarget,
                                               samples: samples, storage: transient, label: "msaa light")
            shadingDepth = try device.makeTexture(RenderDevice.depthFormat, width: shadingWidth, height: shadingHeight, usage: .renderTarget,
                                                  samples: samples, storage: transient, label: "msaa depth")
        } else {
            msaaColor = nil
            msaaLight = nil
            shadingDepth = try device.makeTexture(RenderDevice.depthFormat, width: shadingWidth, height: shadingHeight, usage: .renderTarget,
                                                  storage: transient, label: "shading depth")
        }
        color = try device.makeTexture(RenderDevice.colorFormat, width: shadingWidth, height: shadingHeight, usage: target.union(rw), label: "colour")
        light = try device.makeTexture(RenderDevice.lightFormat, width: shadingWidth, height: shadingHeight, usage: target, label: "light")
        ao = try device.makeTexture(.r16Float, width: max(shadingWidth / 2, 1), height: max(shadingHeight / 2, 1), usage: rw, label: "ao")
        upscaled = shadingWidth == self.width && shadingHeight == self.height ? nil
            : try device.makeTexture(RenderDevice.colorFormat, width: self.width, height: self.height, usage: rw.union(.renderTarget),
                                     label: "upscaled")
        lined = try device.makeTexture(RenderDevice.colorFormat, width: self.width, height: self.height, usage: rw, label: "lined")
        lensed = try device.makeTexture(RenderDevice.colorFormat, width: self.width, height: self.height, usage: rw, label: "lensed")
        finished = try device.makeTexture(RenderDevice.colorFormat, width: self.width, height: self.height, usage: rw, label: "finished")
        finishedOther = try device.makeTexture(RenderDevice.colorFormat, width: self.width, height: self.height, usage: rw,
                                               label: "finished (other shot)")
        var mips: [MTLTexture] = []
        var ups: [MTLTexture] = []
        var mipWidth = self.width
        var mipHeight = self.height
        for level in 0 ..< 4 {
            mipWidth = max(mipWidth / 2, 1)
            mipHeight = max(mipHeight / 2, 1)
            mips.append(try device.makeTexture(RenderDevice.colorFormat, width: mipWidth, height: mipHeight, usage: rw, label: "bloom \(level)"))
            ups.append(try device.makeTexture(RenderDevice.colorFormat, width: mipWidth, height: mipHeight, usage: rw, label: "bloom up \(level)"))
        }
        bloom = mips
        bloomUp = ups
    }

    /// The shaded image at native resolution (the upscaled one when the render scale is below 1).
    var nativeColor: MTLTexture { upscaled ?? color }
}
