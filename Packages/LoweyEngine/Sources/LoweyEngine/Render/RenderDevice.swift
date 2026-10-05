import Foundation
import Metal
import os

public enum RenderError: Error, Equatable, CustomStringConvertible {
    case noMetal
    case missingShaders
    case pipeline(String)
    case texture
    case readback

    public var description: String {
        switch self {
        case .noMetal: "Metal isn't available on this device."
        case .missingShaders: "The renderer's shaders are missing from the app."
        case let .pipeline(name): "Couldn't build the \(name) pipeline."
        case .texture: "Couldn't create a render target."
        case .readback: "Couldn't read the rendered image."
        }
    }
}

/// What this GPU can do (recorded by the spikes in docs/DECISIONS.md and shown in Diagnostics).
public struct RenderCapabilities: Sendable, Equatable {
    public var msaaSamples: Int
    public var memorylessTargets: Bool
    public var metalFX: Bool
    public var name: String

    public var summary: String {
        "\(name) · MSAA \(msaaSamples)× · \(memorylessTargets ? "memoryless" : "private") targets · \(metalFX ? "MetalFX" : "bilinear") upscaling"
    }
}

/// The Metal device, queue, shader library and every pipeline, built once and shared by the stage, snapshots,
/// thumbnails and export.
public final class RenderDevice: @unchecked Sendable {
    // @unchecked: every stored property is immutable after init, and Metal devices, queues and pipeline states are
    // documented as thread-safe to use from any thread.
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    let library: MTLLibrary
    public let capabilities: RenderCapabilities
    let pipelines: Pipelines
    let logger = Logger(subsystem: "studio.h.maquette", category: "render")

    public static let colorFormat = MTLPixelFormat.rgba16Float
    public static let lightFormat = MTLPixelFormat.r8Unorm
    public static let normalFormat = MTLPixelFormat.rgba16Float
    public static let idFormat = MTLPixelFormat.r32Uint
    public static let depthFormat = MTLPixelFormat.depth32Float
    public static let outputFormat = MTLPixelFormat.bgra8Unorm
    /// Flipbook layers and brush previews: premultiplied sRGB, like the overlay image.
    public static let layerFormat = MTLPixelFormat.rgba8Unorm
    public static let shadowMapSize = 2048

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else { throw RenderError.noMetal }
        self.device = device
        self.queue = queue
        queue.label = "Lowey render"
        let candidates = [try? device.makeDefaultLibrary(bundle: Bundle.module), device.makeDefaultLibrary()]
        guard let library = candidates.compactMap({ $0 }).first(where: { $0.functionNames.contains("lw_shade") }) else {
            throw RenderError.missingShaders
        }
        self.library = library
        let samples = device.supportsTextureSampleCount(4) ? 4 : 1
        capabilities = RenderCapabilities(msaaSamples: samples, memorylessTargets: Self.supportsMemoryless(device),
                                          metalFX: Upscaler.isMetalFXSupported(device), name: device.name)
        pipelines = try Pipelines(device: device, library: library, samples: samples)
    }

    private static func supportsMemoryless(_ device: MTLDevice) -> Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            return device.supportsFamily(.apple4)
        #endif
    }

    /// A shared instance for the whole app (pipelines are expensive to build).
    public static let shared: Result<RenderDevice, RenderError> = {
        do {
            return try .success(RenderDevice())
        } catch let error as RenderError {
            return .failure(error)
        } catch {
            return .failure(.noMetal)
        }
    }()

    public static func sharedDevice() throws -> RenderDevice {
        try shared.get()
    }

    func makeTexture(_ format: MTLPixelFormat, width: Int, height: Int, usage: MTLTextureUsage, samples: Int = 1,
                     storage: MTLStorageMode = .private, label: String, arrayLength: Int = 1) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = format
        descriptor.width = max(width, 1)
        descriptor.height = max(height, 1)
        descriptor.usage = usage
        descriptor.storageMode = storage
        if arrayLength > 1 {
            descriptor.textureType = .type2DArray
            descriptor.arrayLength = arrayLength
        } else if samples > 1 {
            descriptor.textureType = .type2DMultisample
            descriptor.sampleCount = samples
        }
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError.texture }
        texture.label = label
        return texture
    }
}

/// Every render and compute pipeline of LoweyRender 2.
struct Pipelines {
    let shadowStatic: MTLRenderPipelineState
    let shadowSkinned: MTLRenderPipelineState
    let prepassStatic: MTLRenderPipelineState
    let prepassSkinned: MTLRenderPipelineState
    let prepassGround: MTLRenderPipelineState
    let shadeStatic: MTLRenderPipelineState
    let shadeSkinned: MTLRenderPipelineState
    let shadeStaticBlended: MTLRenderPipelineState
    let shadeSkinnedBlended: MTLRenderPipelineState
    let shadeGround: MTLRenderPipelineState
    let hullStatic: MTLRenderPipelineState
    let hullSkinned: MTLRenderPipelineState
    let sky: MTLRenderPipelineState
    let editor: MTLRenderPipelineState
    let grid: MTLRenderPipelineState
    let brushScene: MTLRenderPipelineState
    let brushEditor: MTLRenderPipelineState
    let brushLayer: MTLRenderPipelineState
    let brushFill: MTLRenderPipelineState
    let brushFillEditor: MTLRenderPipelineState
    let brushCompose: MTLRenderPipelineState
    let ssao: MTLComputePipelineState
    let lines: MTLComputePipelineState
    let bloomPrefilter: MTLComputePipelineState
    let bloomDown: MTLComputePipelineState
    let bloomUp: MTLComputePipelineState
    let lens: MTLComputePipelineState
    let finish: MTLComputePipelineState
    let composite: MTLComputePipelineState
    let upscale: MTLComputePipelineState
    let depthWrite: MTLDepthStencilState
    let depthRead: MTLDepthStencilState
    let depthAlways: MTLDepthStencilState
    let shadowDepth: MTLDepthStencilState

    init(device: MTLDevice, library: MTLLibrary, samples: Int) throws {
        let builder = PipelineBuilder(device: device, library: library, samples: samples)
        shadowStatic = try builder.shadow(vertex: "lw_shadowStatic", skinned: false)
        shadowSkinned = try builder.shadow(vertex: "lw_shadowSkinned", skinned: true)
        prepassStatic = try builder.prepass(vertex: "lw_vertexStatic", fragment: "lw_prepass", skinned: false)
        prepassSkinned = try builder.prepass(vertex: "lw_vertexSkinned", fragment: "lw_prepass", skinned: true)
        prepassGround = try builder.prepass(vertex: "lw_vertexGround", fragment: "lw_prepassGround", skinned: false)
        shadeStatic = try builder.shading(vertex: "lw_vertexStatic", fragment: "lw_shade", skinned: false, blended: false)
        shadeSkinned = try builder.shading(vertex: "lw_vertexSkinned", fragment: "lw_shade", skinned: true, blended: false)
        shadeStaticBlended = try builder.shading(vertex: "lw_vertexStatic", fragment: "lw_shade", skinned: false, blended: true)
        shadeSkinnedBlended = try builder.shading(vertex: "lw_vertexSkinned", fragment: "lw_shade", skinned: true, blended: true)
        shadeGround = try builder.shading(vertex: "lw_vertexGround", fragment: "lw_shadeGround", skinned: false, blended: false)
        hullStatic = try builder.shading(vertex: "lw_vertexHull", fragment: "lw_shadeHull", skinned: false, blended: false)
        hullSkinned = try builder.shading(vertex: "lw_vertexHullSkinned", fragment: "lw_shadeHull", skinned: true, blended: false)
        sky = try builder.sky()
        editor = try builder.editor(fragment: "lw_editorFragment")
        grid = try builder.editor(fragment: "lw_gridFragment")
        brushScene = try builder.brush(.scene)
        brushEditor = try builder.brush(.editor)
        brushLayer = try builder.brush(.layer)
        brushFill = try builder.brush(.layer, vertex: "lw_brushFillVertex", fragment: "lw_brushFillFragment")
        brushFillEditor = try builder.brush(.editor, vertex: "lw_brushFillVertex", fragment: "lw_brushFillFragment")
        brushCompose = try builder.brush(.layer, vertex: "lw_brushLayerVertex", fragment: "lw_brushLayerFragment")
        ssao = try builder.compute("lw_ssao")
        lines = try builder.compute("lw_lines")
        bloomPrefilter = try builder.compute("lw_bloomPrefilter")
        bloomDown = try builder.compute("lw_bloomDown")
        bloomUp = try builder.compute("lw_bloomUp")
        lens = try builder.compute("lw_lens")
        finish = try builder.compute("lw_finish")
        composite = try builder.compute("lw_composite")
        upscale = try builder.compute("lw_upscale")
        depthWrite = try builder.depth(compare: .greater, write: true)
        depthRead = try builder.depth(compare: .greaterEqual, write: false)
        depthAlways = try builder.depth(compare: .always, write: false)
        shadowDepth = try builder.depth(compare: .lessEqual, write: true)
    }
}
