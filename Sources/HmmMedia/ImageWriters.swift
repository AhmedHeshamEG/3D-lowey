#if canImport(ImageIO) && canImport(CoreGraphics)
    import CoreGraphics
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    public enum ImageWriteError: Error, Equatable, CustomStringConvertible {
        case cannotCreate
        case cannotFinish

        public var description: String {
            switch self {
            case .cannotCreate: "Couldn't create the image file."
            case .cannotFinish: "Couldn't finish writing the image file."
            }
        }
    }

    /// PNG stills and GIF loops.
    public enum ImageWriters {
        public static func png(_ image: CGImage) throws -> Data {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                throw ImageWriteError.cannotCreate
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw ImageWriteError.cannotFinish }
            return data as Data
        }

        public static func writePNG(_ image: CGImage, to url: URL) throws {
            try png(image).write(to: url, options: .atomic)
        }
    }

    /// Writes an animated GIF frame by frame (loops forever). GIF has 256 colours per frame and 1/100 s timing, so it's
    /// for short loops, not long videos.
    public final class GIFWriter {
        private let destination: CGImageDestination
        private let frameProperties: CFDictionary

        public init(url: URL, frameCount: Int, fps: Int) throws {
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
                throw ImageWriteError.cannotCreate
            }
            self.destination = destination
            let delay = 1 / Double(max(fps, 1))
            frameProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFUnclampedDelayTime as String: delay,
                                                                         kCGImagePropertyGIFDelayTime as String: delay]] as CFDictionary
            let fileProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary
            CGImageDestinationSetProperties(destination, fileProperties)
        }

        public func append(_ image: CGImage) {
            CGImageDestinationAddImage(destination, image, frameProperties)
        }

        public func finish() throws {
            guard CGImageDestinationFinalize(destination) else { throw ImageWriteError.cannotFinish }
        }
    }
#endif
