#if canImport(CoreGraphics) && canImport(CoreText)
    import CoreGraphics
    import CoreText
    import Foundation

    /// One frame of a contact sheet.
    public struct ContactSheetFrame: @unchecked Sendable {
        // @unchecked: CGImage is immutable and thread-safe; it just isn't annotated Sendable.
        public var image: CGImage
        /// "00:03.20".
        public var timecode: String
        /// A short line under the timecode ("#2 enters · peak speed 0.8").
        public var note: String?

        public init(image: CGImage, timecode: String, note: String? = nil) {
            self.image = image
            self.timecode = timecode
            self.note = note
        }
    }

    /// Draws contact sheets, set-of-marks labels and value images with Core Graphics.
    public enum PerceptionDrawing {
        private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        private static func context(width: Int, height: Int) -> CGContext? {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }

        /// A grid of frames with timecodes (and notes), on a dark sheet.
        public static func contactSheet(_ frames: [ContactSheetFrame], maxWidth: Double = 2048) -> CGImage? {
            guard let first = frames.first else { return nil }
            let aspect = Double(first.image.width) / Double(max(first.image.height, 1))
            let layout = ContactSheetLayout(count: frames.count, aspect: aspect, maxWidth: maxWidth)
            let width = Int(layout.width)
            let height = Int(layout.height)
            guard let context = context(width: width, height: height) else { return nil }
            context.setFillColor(CGColor(srgbRed: 0.055, green: 0.059, blue: 0.067, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for (index, frame) in frames.enumerated() {
                let cell = layout.frame(index)
                context.draw(frame.image, in: flipped(cell, height: Double(height)))
                let caption = layout.caption(index)
                let line = frame.note.map { "\(frame.timecode)  \($0)" } ?? frame.timecode
                drawText(line, in: context, at: CGPoint(x: caption.x + 4, y: Double(height) - caption.y - 22), size: 18,
                         color: CGColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1))
            }
            return context.makeImage()
        }

        /// The image with numbered markers (white number on a black disc with a white ring: legible on anything).
        public static func marked(_ image: CGImage, marks: [Mark]) -> CGImage? {
            let width = image.width
            let height = image.height
            guard let context = context(width: width, height: height) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let radius = Double(height) * 0.022
            for mark in marks {
                let center = CGPoint(x: mark.x * Double(width), y: Double(height) - mark.y * Double(height))
                let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.85))
                context.fillEllipse(in: disc)
                context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                context.setLineWidth(max(radius * 0.12, 1))
                context.strokeEllipse(in: disc)
                let text = "\(mark.number)"
                let size = radius * (text.count > 1 ? 0.95 : 1.15)
                let textWidth = Double(text.count) * size * 0.58
                drawText(text, in: context, at: CGPoint(x: center.x - textWidth / 2, y: center.y - size * 0.36), size: size,
                         color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            }
            return context.makeImage()
        }

        /// The value (squint) view as a grey image.
        public static func valueImage(_ value: ValueImage) -> CGImage? {
            guard value.width > 0, value.height > 0,
                  let context = CGContext(data: nil, width: value.width, height: value.height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
                  let data = context.data else { return nil }
            let rowBytes = context.bytesPerRow
            let bytes = data.bindMemory(to: UInt8.self, capacity: rowBytes * value.height)
            for row in 0 ..< value.height {
                for column in 0 ..< value.width {
                    let lightness = value.lightness[row * value.width + column]
                    bytes[row * rowBytes + column] = UInt8(min(max(lightness / 100 * 255, 0), 255))
                }
            }
            return context.makeImage()
        }

        /// Reads an image as 8-bit RGBA (for `ValueImage`).
        public static func rgbaPixels(_ image: CGImage, maxSide: Int = 512) -> (pixels: [UInt8], width: Int, height: Int)? {
            let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
            let width = max(Int(Double(image.width) * scale), 1)
            let height = max(Int(Double(image.height) * scale), 1)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.interpolationQuality = .medium
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            return drawn ? (pixels, width, height) : nil
        }

        private static func flipped(_ rect: PerceptionRect, height: Double) -> CGRect {
            CGRect(x: rect.x, y: height - rect.y - rect.height, width: rect.width, height: rect.height)
        }

        private static func drawText(_ text: String, in context: CGContext, at point: CGPoint, size: Double, color: CGColor) {
            let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = point
            CTLineDraw(line, context)
        }
    }
#endif
