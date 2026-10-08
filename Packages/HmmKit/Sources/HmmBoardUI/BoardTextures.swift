#if canImport(Metal) && canImport(CoreText)
    import CoreGraphics
    import CoreText
    import Foundation
    import HmmBoard
    import ImageIO
    import Metal

    /// The board's pictures and words as textures (premultiplied, with mips so they stay smooth far out), made once
    /// and kept: a picture by its file, words by what they say and how sharp they must be.
    @MainActor
    final class BoardTextures {
        private let device: MTLDevice
        private let queue: MTLCommandQueue
        private var pictures: [String: MTLTexture] = [:]
        private var missing: Set<String> = []
        private var words: [BoardTextSpec: MTLTexture] = [:]
        /// Where a picture's file is (the board's assets).
        var assetURL: (String) -> URL? = { _ in nil }

        /// Pictures are shown at most this many pixels on their long side.
        static let maximumPictureSide = 2048

        init(device: MTLDevice, queue: MTLCommandQueue) {
            self.device = device
            self.queue = queue
        }

        func picture(_ asset: String) -> MTLTexture? {
            if let texture = pictures[asset] { return texture }
            guard !missing.contains(asset) else { return nil }
            guard let url = assetURL(asset), let image = Self.image(at: url), let texture = texture(image) else {
                missing.insert(asset)
                return nil
            }
            pictures[asset] = texture
            return texture
        }

        func text(_ spec: BoardTextSpec) -> MTLTexture? {
            if let texture = words[spec] { return texture }
            let width = Int((spec.width * spec.resolution).rounded(.up)), height = Int((spec.height * spec.resolution).rounded(.up))
            guard width > 0, height > 0, width <= 4096, height <= 4096 else { return nil }
            let texture = texture(width: width, height: height) { context in
                Self.draw(spec, in: context)
            }
            if words.count > 256 { words.removeAll() }
            words[spec] = texture
            return texture
        }

        /// Forgets everything (the board's files changed under it, memory is short).
        func removeAll() {
            pictures.removeAll()
            missing.removeAll()
            words.removeAll()
        }

        // MARK: Making textures

        private func texture(_ image: CGImage) -> MTLTexture? {
            texture(width: image.width, height: image.height) { context in
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
        }

        /// A texture of what `draw` paints into a bitmap of that size (premultiplied sRGB, the first row on top).
        private func texture(width: Int, height: Int, draw: (CGContext) -> Void) -> MTLTexture? {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                draw(context)
                return true
            }
            guard drawn else { return nil }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height,
                                                                      mipmapped: max(width, height) > 1)
            descriptor.usage = [.shaderRead, .renderTarget]
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            texture.label = "board picture"
            bytes.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: base, bytesPerRow: width * 4)
            }
            if texture.mipmapLevelCount > 1, let commandBuffer = queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.generateMipmaps(for: texture)
                blit.endEncoding()
                commandBuffer.commit()
            }
            return texture
        }

        /// A picture file, read no larger than it will be shown and turned the way its camera held it.
        static func image(at url: URL) -> CGImage? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPictureSide
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }

        /// A picture's size in pixels, as it will be shown (turned upright), without decoding it.
        static func pixelSize(of data: Data) -> (width: Double, height: Double)? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Double, let height = properties[kCGImagePropertyPixelHeight] as? Double,
                  width > 0, height > 0 else { return nil }
            // Orientations 5 to 8 lie on their side.
            let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
            return orientation >= 5 ? (height, width) : (width, height)
        }

        /// Words laid out in their box by Core Text (so every script shapes and wraps as the system does).
        static func draw(_ spec: BoardTextSpec, in context: CGContext) {
            context.scaleBy(x: spec.resolution, y: spec.resolution)
            let font = CTFontCreateUIFontForLanguage(spec.isTitle ? .emphasizedSystem : .system, spec.fontSize, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, spec.fontSize, nil)
            let color = CGColor(srgbRed: spec.color.red, green: spec.color.green, blue: spec.color.blue, alpha: 1)
            let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
            guard let string = CFAttributedStringCreate(nil, spec.text as CFString, attributes as CFDictionary) else { return }
            let framesetter = CTFramesetterCreateWithAttributedString(string)
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: spec.width, height: spec.height), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            CTFrameDraw(frame, context)
        }
    }
#endif
