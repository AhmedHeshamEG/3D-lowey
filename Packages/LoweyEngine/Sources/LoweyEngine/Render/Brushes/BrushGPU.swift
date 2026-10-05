import CoreGraphics
import LoweyCore
import Metal
import simd

/// Swift mirrors of Brush.metal's structs (SIMD4 and float4x4 members only, like GPUTypes).
struct BrushUniforms {
    var viewProjection = matrix_identity_float4x4
    var model = matrix_identity_float4x4
    /// xyz eye, w = mode (0 pixels, 1 world).
    var eye = SIMD4<Float>.zero
    /// xyz camera right, w = the model's scale.
    var cameraRight = SIMD4<Float>(1, 0, 0, 1)
    var cameraUp = SIMD4<Float>(0, 1, 0, 0)
    var color = SIMD4<Float>(0, 0, 0, 1)
    var shape = SIMD4<Float>(1, 0, 1, 0)
    var grain = SIMD4<Float>.zero
    var render = SIMD4<Float>.zero
    var viewport = SIMD4<Float>(1, 1, 1, 1)

    /// The brush's settings (the rest is filled by whoever draws).
    init(brush: Brush) {
        // The tip's angle is already in every stamp's rotation (`BrushStroker`).
        shape = SIMD4<Float>(Float(brush.shape.roundness), 0, brush.shape.followsStroke ? 1 : 0, brush.shape.inverted ? 1 : 0)
        let grain = brush.grain
        self.grain = SIMD4<Float>(grain.source == nil ? 0 : 1, Float(grain.scale), Float(grain.depth), grain.movement == .rolling ? 1 : 0)
        render = SIMD4<Float>(Float(brush.rendering.wetEdges), Float(brush.rendering.softness), grain.inverted ? 1 : 0, 0)
    }

    mutating func setViewport(width: Int, height: Int) {
        viewport = SIMD4<Float>(Float(width), Float(height), 1 / Float(max(width, 1)), 1 / Float(max(height, 1)))
        // A texturized grain tile is 15 % of the target's height times its scale.
        render.w = Float(height) * 0.15 * max(grain.y, 0.05)
    }
}

/// One stamp on the GPU (see `BrushDabData` in Brush.metal). The tip's angle is already in `rotation`.
struct BrushDabData: Equatable {
    var center: SIMD4<Float>
    var direction: SIMD4<Float>
    var params: SIMD4<Float>

    init(_ dab: BrushDab<Vec2>) {
        center = SIMD4<Float>(Float(dab.center.x), Float(dab.center.y), 0, Float(dab.radius))
        direction = SIMD4<Float>(Float(dab.direction.x), Float(dab.direction.y), 0, Float(dab.lateral))
        params = Self.params(dab.opacity, dab.rotation, dab.flipX, dab.flipY, dab.travel)
    }

    init(_ dab: BrushDab<Vec3>) {
        center = SIMD4<Float>(dab.center.float3, Float(dab.radius))
        direction = SIMD4<Float>(dab.direction.float3, Float(dab.lateral))
        params = Self.params(dab.opacity, dab.rotation, dab.flipX, dab.flipY, dab.travel)
    }

    static func params(_ opacity: Double, _ rotation: Double, _ flipX: Bool, _ flipY: Bool, _ travel: Double) -> SIMD4<Float> {
        SIMD4<Float>(Float(opacity), Float(rotation), Float((flipX ? 1 : 0) + (flipY ? 2 : 0)), Float(travel))
    }
}

struct BrushFillUniforms {
    var color = SIMD4<Float>.zero
    var viewport = SIMD4<Float>.zero
}

/// A run of stamps drawn with one brush and one colour: an ink stroke group in the scene, a flipbook stroke, the
/// stroke under the Pencil, a preview.
struct BrushBatch {
    var dabs: MTLBuffer
    var count: Int
    var brush: Brush
    /// rgb in the target's space (linear in the scene, sRGB on layers and the stage), a = 1.
    var color: SIMD4<Float>
    /// World mode: the drawing's matrix and scale (dabs are in its space).
    var world: (model: simd_float4x4, scale: Float)?
}

/// Tip and grain textures by picture, built once: built-ins drawn by `BrushImages`, imported pictures through the
/// frame's image loader (`brushes/<hash>.png` in the project's assets). Grey, with a CPU-built mip chain so tiny
/// stamps stay smooth.
final class BrushTextureCache {
    private let device: MTLDevice
    private var textures: [String: MTLTexture] = [:]
    let white: MTLTexture

    init(device: MTLDevice) throws {
        self.device = device
        guard let white = Self.upload(GreyImage(width: 1, height: 1, pixels: [255]), device: device) else { throw RenderError.texture }
        self.white = white
    }

    /// A picture's texture (nil when an imported one can't be found: the caller falls back).
    func texture(_ source: BrushImageSource, image: (String) -> CGImage?) -> MTLTexture? {
        let key: String = switch source {
        case let .builtIn(builtIn): "builtin:" + builtIn.rawValue
        case let .image(name): name
        }
        if let cached = textures[key] { return cached }
        let grey: GreyImage? = switch source {
        case let .builtIn(builtIn): BrushImages.image(builtIn)
        case let .image(name): image(name).flatMap(GreyImage.init(cgImage:))
        }
        guard let grey, let texture = Self.upload(grey, device: device) else { return nil }
        if textures.count > 64 { textures.removeAll() }
        textures[key] = texture
        return texture
    }

    /// The tip to stamp (a missing picture draws as a hard round) and the grain (white = none).
    func textures(for brush: Brush, image: (String) -> CGImage?) -> (shape: MTLTexture, grain: MTLTexture) {
        let shape = texture(brush.shape.source, image: image) ?? texture(.builtIn(.hardRound), image: image) ?? white
        let grain = brush.grain.source.flatMap { texture($0, image: image) } ?? white
        return (shape, grain)
    }

    static func upload(_ image: GreyImage, device: MTLDevice) -> MTLTexture? {
        let levels = Int(log2(Double(max(image.width, image.height)))) + 1
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: image.width, height: image.height,
                                                                  mipmapped: levels > 1)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "brush picture"
        var level = image
        for index in 0 ..< texture.mipmapLevelCount {
            level.pixels.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                texture.replace(region: MTLRegionMake2D(0, 0, level.width, level.height), mipmapLevel: index, withBytes: base,
                                bytesPerRow: level.width)
            }
            level = level.halved
        }
        return texture
    }
}

extension GreyImage {
    /// A picture's coverage: its alpha when it has see-through parts (a shape on transparency), else its brightness
    /// (Procreate's and Photoshop's white-paints convention).
    init?(cgImage: CGImage) {
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0, width <= 8192, height <= 8192 else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(cgImage.alphaInfo)
        if hasAlpha {
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            if let context = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.draw(cgImage, in: rect)
                let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
                if alpha.contains(where: { $0 < 250 }) {
                    self.init(width: width, height: height, pixels: alpha)
                    return
                }
            }
        }
        var grey = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &grey, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.draw(cgImage, in: rect)
        self.init(width: width, height: height, pixels: grey)
    }

    /// Half the size, box-filtered (the next mip level).
    var halved: GreyImage {
        let w = max(width / 2, 1), h = max(height / 2, 1)
        var result = [UInt8](repeating: 0, count: w * h)
        for row in 0 ..< h {
            for column in 0 ..< w {
                let x0 = min(column * 2, width - 1), x1 = min(column * 2 + 1, width - 1)
                let y0 = min(row * 2, height - 1), y1 = min(row * 2 + 1, height - 1)
                let sum = Int(pixels[y0 * width + x0]) + Int(pixels[y0 * width + x1]) + Int(pixels[y1 * width + x0]) + Int(pixels[y1 * width + x1])
                result[row * w + column] = UInt8(sum / 4)
            }
        }
        return GreyImage(width: w, height: h, pixels: result)
    }
}
