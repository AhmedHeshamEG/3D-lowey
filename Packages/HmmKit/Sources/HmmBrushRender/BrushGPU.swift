#if canImport(Metal)
    import CoreGraphics
    import Foundation
    import HmmBrush
    import Metal
    import simd

    public enum BrushRenderError: Error, Equatable {
        /// The device couldn't make a texture or a buffer.
        case texture
        /// The brush shaders aren't in the build.
        case shaders
        case pipeline(String)
    }

    /// Swift mirrors of Brush.metal's structs (SIMD4 and float4x4 members only, so the layouts match without padding
    /// rules).
    public struct BrushUniforms {
        public var viewProjection = matrix_identity_float4x4
        public var model = matrix_identity_float4x4
        /// 3D: xyz eye. 2D: xy where a fixed grain starts (pixels). w = mode (0 pixels, 1 world).
        public var eye = SIMD4<Float>.zero
        /// xyz camera right, w = the model's scale.
        public var cameraRight = SIMD4<Float>(1, 0, 0, 1)
        public var cameraUp = SIMD4<Float>(0, 1, 0, 0)
        public var color = SIMD4<Float>(0, 0, 0, 1)
        public var shape = SIMD4<Float>(1, 0, 1, 0)
        public var grain = SIMD4<Float>.zero
        public var render = SIMD4<Float>.zero
        public var viewport = SIMD4<Float>(1, 1, 1, 1)

        /// The brush's settings (the rest is filled by whoever draws).
        public init(brush: Brush) {
            // The tip's angle is already in every stamp's rotation (`BrushStroker`).
            shape = SIMD4<Float>(Float(brush.shape.roundness), 0, brush.shape.followsStroke ? 1 : 0, brush.shape.inverted ? 1 : 0)
            let grain = brush.grain
            self.grain = SIMD4<Float>(grain.source == nil ? 0 : 1, Float(grain.scale), Float(grain.depth), grain.movement == .rolling ? 1 : 0)
            render = SIMD4<Float>(Float(brush.rendering.wetEdges), Float(brush.rendering.softness), grain.inverted ? 1 : 0, 0)
        }

        public mutating func setViewport(width: Int, height: Int) {
            viewport = SIMD4<Float>(Float(width), Float(height), 1 / Float(max(width, 1)), 1 / Float(max(height, 1)))
            // A texturized grain tile is 15 % of the target's height times its scale.
            render.w = Float(height) * 0.15 * max(grain.y, 0.05)
        }

        /// 2D strokes kept in their own units (a board): where a unit lands in pixels, and the grain fixed to those
        /// units, one tile every `tile` of them, so it neither slides nor grows when the view moves and zooms.
        public mutating func place(_ placement: BrushBatch.Placement) {
            let s = placement.scale
            model = simd_float4x4(columns: (SIMD4(s, 0, 0, 0), SIMD4(0, s, 0, 0), SIMD4(0, 0, 1, 0),
                                            SIMD4(placement.offset.x, placement.offset.y, 0, 1)))
            cameraRight.w = placement.radiusScale ?? s
            eye = SIMD4<Float>(placement.offset.x, placement.offset.y, 0, 0)
            render.w = placement.tile * max(grain.y, 0.05)
        }
    }

    /// One stamp on the GPU (see `BrushDabData` in Brush.metal). The tip's angle is already in `rotation`.
    public struct BrushDabData: Equatable {
        public var center: SIMD4<Float>
        public var direction: SIMD4<Float>
        public var params: SIMD4<Float>

        public init(_ dab: BrushDab<some BrushPoint>) {
            let center = dab.center.brushCoordinates, direction = dab.direction.brushCoordinates
            self.center = SIMD4<Float>(Float(center.x), Float(center.y), Float(center.z), Float(dab.radius))
            self.direction = SIMD4<Float>(Float(direction.x), Float(direction.y), Float(direction.z), Float(dab.lateral))
            params = Self.params(dab.opacity, dab.rotation, dab.flipX, dab.flipY, dab.travel)
        }

        public static func params(_ opacity: Double, _ rotation: Double, _ flipX: Bool, _ flipY: Bool, _ travel: Double) -> SIMD4<Float> {
            SIMD4<Float>(Float(opacity), Float(rotation), Float((flipX ? 1 : 0) + (flipY ? 2 : 0)), Float(travel))
        }
    }

    public struct BrushFillUniforms {
        public var color: SIMD4<Float>
        public var viewport: SIMD4<Float>

        public init(color: SIMD4<Float> = .zero, viewport: SIMD4<Float> = .zero) {
            self.color = color
            self.viewport = viewport
        }

        public init(color: SIMD4<Float>, width: Int, height: Int) {
            self.color = color
            viewport = SIMD4<Float>(Float(width), Float(height), 1 / Float(max(width, 1)), 1 / Float(max(height, 1)))
        }
    }

    /// A run of stamps drawn with one brush and one colour: an ink stroke group in a scene, a flat stroke, the stroke
    /// under the Pencil, a preview.
    public struct BrushBatch {
        /// Where a flat stroke's own units land in the target: pixel = unit × scale + offset.
        public struct Placement {
            public var offset: SIMD2<Float>
            public var scale: Float
            /// A texturized grain's tile, in the stroke's units (times the grain's own scale).
            public var tile: Float
            /// What the tips' radii grow by when that isn't `scale`: far out, a hairline is kept wide enough to see.
            public var radiusScale: Float?

            public init(offset: SIMD2<Float>, scale: Float, tile: Float = 160, radiusScale: Float? = nil) {
                self.offset = offset
                self.scale = scale
                self.tile = tile
                self.radiusScale = radiusScale
            }
        }

        public var dabs: MTLBuffer
        public var count: Int
        public var brush: Brush
        /// rgb in the target's space (linear in a scene, sRGB on layers), a = 1.
        public var color: SIMD4<Float>
        /// World mode: the drawing's matrix and scale (dabs are in its space).
        public var world: (model: simd_float4x4, scale: Float)?
        /// Flat mode, the dabs in their own units instead of pixels.
        public var placement: Placement?

        public init(dabs: MTLBuffer, count: Int, brush: Brush, color: SIMD4<Float>, world: (model: simd_float4x4, scale: Float)? = nil,
                    placement: Placement? = nil) {
            self.dabs = dabs
            self.count = count
            self.brush = brush
            self.color = color
            self.world = world
            self.placement = placement
        }
    }

    /// Tip and grain textures by picture, built once: built-ins drawn by `BrushImages`, imported pictures through the
    /// caller's image loader (`brushes/<hash>.png`). Grey, with a CPU-built mip chain so tiny stamps stay smooth.
    public final class BrushTextureCache {
        private let device: MTLDevice
        private var textures: [String: MTLTexture] = [:]
        public let white: MTLTexture

        public init(device: MTLDevice) throws {
            self.device = device
            guard let white = Self.upload(GreyImage(width: 1, height: 1, pixels: [255]), device: device) else { throw BrushRenderError.texture }
            self.white = white
        }

        /// A picture's texture (nil when an imported one can't be found: the caller falls back).
        public func texture(_ source: BrushImageSource, image: (String) -> CGImage?) -> MTLTexture? {
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
        public func textures(for brush: Brush, image: (String) -> CGImage?) -> (shape: MTLTexture, grain: MTLTexture) {
            let shape = texture(brush.shape.source, image: image) ?? texture(.builtIn(.hardRound), image: image) ?? white
            let grain = brush.grain.source.flatMap { texture($0, image: image) } ?? white
            return (shape, grain)
        }

        public static func upload(_ image: GreyImage, device: MTLDevice) -> MTLTexture? {
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

    public extension GreyImage {
        /// A picture's coverage: its alpha when it has see-through parts (a shape on transparency), else its
        /// brightness (Procreate's and Photoshop's white-paints convention).
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
                    let top = Int(pixels[y0 * width + x0]) + Int(pixels[y0 * width + x1])
                    let bottom = Int(pixels[y1 * width + x0]) + Int(pixels[y1 * width + x1])
                    result[row * w + column] = UInt8((top + bottom) / 4)
                }
            }
            return GreyImage(width: w, height: h, pixels: result)
        }
    }
#endif
