import CoreGraphics
import LoweyCore
import Metal

/// A stroke for a brush preview: a path in the picture's pixels, the brush, the colour (sRGB).
public struct BrushPreviewStroke: Sendable {
    public var path: BrushPath<Vec2>
    public var brush: Brush
    public var color: RGBA
    public var seed: UInt64

    public init(path: BrushPath<Vec2>, brush: Brush, color: RGBA, seed: UInt64 = 1) {
        self.path = path
        self.brush = brush
        self.color = color
        self.seed = seed
    }
}

/// Brush pictures drawn by the brush engine itself, so a thumbnail, Brush Studio's pad and a stroke on the stage are
/// the same stamps: the library's preview strokes, the pad's strokes, the golden images.
public final class BrushPreviewRenderer {
    private let device: RenderDevice
    private let stamper: BrushStamper

    public init(device: RenderDevice) throws {
        self.device = device
        stamper = try BrushStamper(device: device.device)
    }

    /// Strokes on a transparent (or `background`) picture of `width` × `height` pixels, premultiplied sRGB.
    public func image(_ strokes: [BrushPreviewStroke], width: Int, height: Int, background: RGBA? = nil,
                      image: (String) -> CGImage?) -> CGImage? {
        guard width > 0, height > 0, width <= 4096, height <= 4096 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: RenderDevice.layerFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.device.makeTexture(descriptor: descriptor), let commandBuffer = device.queue.makeCommandBuffer() else {
            return nil
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        let clear = background ?? RGBA(0, 0, 0, 0)
        pass.colorAttachments[0].clearColor = MTLClearColor(red: clear.r * clear.a, green: clear.g * clear.a, blue: clear.b * clear.a, alpha: clear.a)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "Brush preview"
        encoder.setRenderPipelineState(device.pipelines.brushLayer)
        for stroke in strokes {
            var path = stroke.path
            path.alphas = path.alphas.map { $0 * stroke.color.a }
            let dabs = BrushStroker.dabs(path, brush: stroke.brush, seed: stroke.seed).map(BrushDabData.init)
            guard let buffer = stamper.buffer(dabs) else { continue }
            let color = SIMD4<Float>(Float(stroke.color.r), Float(stroke.color.g), Float(stroke.color.b), 1)
            stamper.encode([BrushBatch(dabs: buffer, count: dabs.count, brush: stroke.brush, color: color, world: nil)], encoder: encoder,
                           view: nil, width: width, height: height, image: image)
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            target.getBytes(base, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// The stroke a brush shows itself with: a gentle S across the picture, pressure rising then falling, as if drawn
/// with a Pencil in about half a second.
public enum BrushPreviewPath {
    public static func sample(width: Double, height: Double, brush: Brush, size: Double) -> BrushPath<Vec2> {
        let count = 120
        let margin = size * 1.6 + width * 0.04
        let samples = (0 ..< count).map { index -> BrushInput<Vec2> in
            let t = Double(index) / Double(count - 1)
            let x = margin + (width - margin * 2) * t
            let y = height / 2 + sin(t * 2 * .pi) * (height / 2 - size * 1.4) * 0.6
            let pressure = 0.25 + 0.75 * sin(t * .pi)
            return BrushInput(point: Vec2(x, y), pressure: pressure, altitude: .pi / 2.6, time: t * 0.5)
        }
        return BrushStroker.path(samples, brush: brush, size: size)
    }
}
