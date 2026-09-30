import CoreGraphics
import CoreText
import Foundation
import LoweyCore
import UIKit

/// 3D text in any script (Arabic included) from the system fonts: CoreText lays the lines out, every glyph outline
/// is flattened, triangulated with its holes (`Outlines`) and extruded. Base-centred like every Lowey object.
enum TextMesher {
    static func mesh(for recipe: TextRecipe) -> MeshData {
        let size = CGFloat(max(recipe.size, 0.01))
        let font = self.font(recipe.style, size: size)
        let lines = recipe.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var contoursByLine: [[[Vec2]]] = []
        var widths: [Double] = []
        for line in lines {
            let (contours, width) = outline(line, font: font)
            contoursByLine.append(contours)
            widths.append(width)
        }
        let lineHeight = Double(size) * 1.25
        var contours: [[Vec2]] = []
        for (index, lineContours) in contoursByLine.enumerated() {
            let xOffset: Double = switch recipe.alignment {
            case .left: 0
            case .center: -widths[index] / 2
            case .right: -widths[index]
            }
            let yOffset = Double(lines.count - 1 - index) * lineHeight - Double(CTFontGetDescent(font))
            contours += lineContours.map { contour in contour.map { Vec2($0.x + xOffset, $0.y + yOffset) } }
        }
        var mesh = Outlines.extrude(contours, depth: recipe.size * recipe.depth)
        // Stand on the ground.
        if let bounds = mesh.bounds {
            let lift = Float(-bounds.min.y)
            mesh.positions = mesh.positions.map { SIMD3<Float>($0.x, $0.y + lift, $0.z) }
        }
        return mesh
    }

    static func font(_ style: TextRecipe.Style, size: CGFloat) -> CTFont {
        let font: UIFont = switch style {
        case .rounded:
            rounded(UIFont.systemFont(ofSize: size, weight: .heavy))
        case .serif:
            designed(UIFont.systemFont(ofSize: size, weight: .bold), .serif)
        case .mono:
            UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        case .bold, .blocky:
            UIFont.systemFont(ofSize: size, weight: .black)
        }
        return font as CTFont
    }

    private static func rounded(_ font: UIFont) -> UIFont {
        designed(font, .rounded)
    }

    private static func designed(_ font: UIFont, _ design: UIFontDescriptor.SystemDesign) -> UIFont {
        guard let descriptor = font.fontDescriptor.withDesign(design) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    /// Every glyph contour of one line (flattened), and the line's advance width.
    static func outline(_ text: String, font: CTFont) -> (contours: [[Vec2]], width: Double) {
        guard !text.isEmpty else { return ([], 0) }
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        var contours: [[Vec2]] = []
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            // Substituted glyphs (Arabic in a Latin font) come in their own font.
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = (attributes[kCTFontAttributeName as String] as CFTypeRef?).flatMap { value -> CTFont? in
                CFGetTypeID(value) == CTFontGetTypeID() ? unsafeDowncast(value, to: CTFont.self) : nil
            } ?? font
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for index in 0 ..< count {
                var transform = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                guard let path = CTFontCreatePathForGlyph(runFont, glyphs[index], &transform) else { continue }
                contours += flatten(path)
            }
        }
        return (contours, Double(width))
    }

    /// A CGPath's subpaths as polylines (curves in 6 steps each).
    static func flatten(_ path: CGPath) -> [[Vec2]] {
        var contours: [[Vec2]] = []
        var current: [Vec2] = []
        var last = CGPoint.zero
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                if current.count > 2 { contours.append(current) }
                current = [Vec2(Double(points[0].x), Double(points[0].y))]
                last = points[0]
            case .addLineToPoint:
                current.append(Vec2(Double(points[0].x), Double(points[0].y)))
                last = points[0]
            case .addQuadCurveToPoint:
                for step in 1 ... 6 {
                    let t = CGFloat(step) / 6
                    let p = (1 - t) * (1 - t) * last.vector + 2 * (1 - t) * t * points[0].vector + t * t * points[1].vector
                    current.append(Vec2(Double(p.dx), Double(p.dy)))
                }
                last = points[1]
            case .addCurveToPoint:
                for step in 1 ... 6 {
                    let t = CGFloat(step) / 6
                    let u = 1 - t
                    let p = u * u * u * last.vector + 3 * u * u * t * points[0].vector + 3 * u * t * t * points[1].vector
                        + t * t * t * points[2].vector
                    current.append(Vec2(Double(p.dx), Double(p.dy)))
                }
                last = points[2]
            case .closeSubpath:
                if current.count > 2 { contours.append(current) }
                current = []
            @unknown default:
                break
            }
        }
        if current.count > 2 { contours.append(current) }
        return contours
    }
}

private extension CGPoint {
    var vector: CGVector { CGVector(dx: x, dy: y) }
}

private func * (lhs: CGFloat, rhs: CGVector) -> CGVector {
    CGVector(dx: lhs * rhs.dx, dy: lhs * rhs.dy)
}

private func + (lhs: CGVector, rhs: CGVector) -> CGVector {
    CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
}
