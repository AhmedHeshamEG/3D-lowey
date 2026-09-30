import CoreGraphics
import CoreVideo
import Foundation
import Metal

/// Renders frames away from the screen: snapshots, library thumbnails, tests, and every exported frame (straight
/// into the encoder's IOSurface-backed pixel buffers, no copy). The stage and this share `LoweyRenderer`, so the
/// preview is the export.
@MainActor
public final class FrameRenderer {
    public let device: RenderDevice
    public let renderer: LoweyRenderer
    private var textureCache: CVMetalTextureCache?
    private var output: MTLTexture?

    public init(device: RenderDevice, models: ModelLibrary = .shared) throws {
        self.device = device
        renderer = try LoweyRenderer(device: device, models: models)
        CVMetalTextureCacheCreate(nil, nil, device.device, nil, &textureCache)
    }

    /// A readable output texture of `width` × `height`.
    func outputTexture(width: Int, height: Int) throws -> MTLTexture {
        if let output, output.width == width, output.height == height { return output }
        let texture = try device.makeTexture(RenderDevice.outputFormat, width: width, height: height,
                                             usage: [.shaderWrite, .shaderRead, .renderTarget], storage: .shared, label: "offscreen output")
        output = texture
        return texture
    }

    /// Encodes, commits and waits (without blocking the main thread).
    func run(_ request: FrameRequest, into texture: MTLTexture) async throws -> FrameReport {
        guard let commandBuffer = device.queue.makeCommandBuffer() else { throw RenderError.noMetal }
        commandBuffer.label = "Offscreen frame"
        let report = try renderer.encode(request, to: texture, commandBuffer: commandBuffer)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            commandBuffer.addCompletedHandler { _ in continuation.resume() }
            commandBuffer.commit()
        }
        if let error = commandBuffer.error { throw error }
        return report
    }

    /// BGRA bytes of a frame, top row first.
    public func bytes(_ request: FrameRequest, width: Int, height: Int) async throws -> [UInt8] {
        let texture = try outputTexture(width: width, height: height)
        _ = try await run(request, into: texture)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return bytes
    }

    public func image(_ request: FrameRequest, width: Int, height: Int) async throws -> CGImage {
        let bytes = try await bytes(request, width: width, height: height)
        return try Self.image(bgra: bytes, width: width, height: height, transparent: request.transparent)
    }

    /// Renders straight into a pixel buffer (the encoder's, for export).
    public func render(_ request: FrameRequest, into buffer: CVPixelBuffer) async throws -> FrameReport {
        let texture = try texture(for: buffer)
        return try await run(request, into: texture)
    }

    /// A Metal texture over a pixel buffer's IOSurface.
    public func texture(for buffer: CVPixelBuffer) throws -> MTLTexture {
        guard let textureCache else { throw RenderError.texture }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        var cvTexture: CVMetalTexture?
        let usage: MTLTextureUsage = [.shaderRead, .shaderWrite, .renderTarget]
        let attributes = [kCVMetalTextureUsage as String: usage.rawValue] as CFDictionary
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, buffer, attributes, RenderDevice.outputFormat, width, height, 0, &cvTexture)
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { throw RenderError.texture }
        return texture
    }

    public static func image(bgra bytes: [UInt8], width: Int, height: Int, transparent: Bool) throws -> CGImage {
        let alpha: CGImageAlphaInfo = transparent ? .premultipliedFirst : .noneSkipFirst
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | alpha.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw RenderError.readback }
        return image
    }
}
