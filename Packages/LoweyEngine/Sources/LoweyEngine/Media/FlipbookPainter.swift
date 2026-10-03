import CoreGraphics
import LoweyCore

/// Draws flipbook drawings with Core Graphics: normal ones into the overlay image (under titles and captions), the
/// multiply, screen and add tracks into a layer each, which the composite pass blends with the shot.
public enum FlipbookPainter {
    /// Draws into a context whose user space is the frame, origin at the top left.
    public static func draw(_ draws: [FlipbookDraw], in context: CGContext) {
        for draw in draws {
            context.saveGState()
            context.setAlpha(CGFloat(min(max(draw.opacity, 0), 1)))
            // One layer per drawing: overlapping strokes don't darken each other through the track's opacity.
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            for stroke in draw.strokes {
                paint(stroke, in: context)
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }

    static func paint(_ stroke: FlipbookPixelStroke, in context: CGContext) {
        let color = CGColor(srgbRed: stroke.color.r, green: stroke.color.g, blue: stroke.color.b, alpha: stroke.color.a)
        context.setFillColor(color)
        let shape = stroke.filled ? stroke.points : FlipbookLayout.outline(stroke)
        guard let first = shape.first else { return }
        context.beginPath()
        context.move(to: CGPoint(x: first.x, y: first.y))
        for point in shape.dropFirst() {
            context.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        context.closePath()
        if stroke.filled {
            // A filled shape gets its stroke width as a rim, so small shapes don't vanish.
            context.setStrokeColor(color)
            context.setLineWidth(CGFloat((stroke.widths.first ?? 0) * 2))
            context.setLineJoin(.round)
            context.drawPath(using: .fillStroke)
            return
        }
        context.fillPath()
        // Round ends.
        for index in [0, stroke.points.count - 1] where stroke.points.count > 1 {
            let point = stroke.points[index]
            let radius = max(stroke.widths[index], 0.35)
            context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    /// The blended (not normal) drawings as one image per blend mode, `pixels` big, drawn after `prepare` sets the
    /// context up (the overlay's transform).
    public static func layers(_ draws: [FlipbookDraw], pixels: CGSize, prepare: (CGContext) -> Void) -> [FlipbookBlend: CGImage] {
        var result: [FlipbookBlend: CGImage] = [:]
        for blend in FlipbookBlend.allCases where blend != .normal {
            let group = draws.filter { $0.blend == blend }
            guard !group.isEmpty, pixels.width >= 1, pixels.height >= 1,
                  let context = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            prepare(context)
            draw(group, in: context)
            result[blend] = context.makeImage()
        }
        return result
    }
}
