import CoreGraphics
import CoreText
import Foundation
import LoweyCore
import UIKit

/// Draws overlays (titles, labels, arrows, the big X…) and captions with CoreGraphics. The stage (SwiftUI
/// Canvas) and the exporter (the frame's pixels) call the same code, so what you see is what you export.
/// Contexts are y-down (UIKit convention).
public enum OverlayRenderer {
    /// Draws `placements` in a frame of `size`. `image` loads overlay images by file name.
    public static func draw(_ placements: [OverlayPlacement], in context: CGContext, size: CGSize,
                            image: (String) -> CGImage? = { _ in nil }) {
        for placement in placements {
            context.saveGState()
            context.setAlpha(CGFloat(placement.opacity))
            context.translateBy(x: CGFloat(placement.center.x), y: CGFloat(placement.center.y))
            context.rotate(by: -CGFloat(placement.angle))
            context.setShadow(offset: CGSize(width: 0, height: CGFloat(placement.unit) * 0.04), blur: CGFloat(placement.unit) * 0.12,
                              color: UIColor.black.withAlphaComponent(0.45).cgColor)
            drawShape(placement, in: context, frame: size, image: image)
            context.restoreGState()
        }
    }

    /// Size of an overlay's box in pixels before rotation (hit testing and the selection frame).
    public static func boxSize(_ placement: OverlayPlacement, frame: CGSize) -> CGSize {
        let unit = CGFloat(placement.unit)
        let sx = CGFloat(placement.scale.x)
        let sy = CGFloat(placement.scale.y)
        let recipe = placement.recipe
        switch recipe.shape {
        case .title, .label:
            let text = textLayout(placement, frame: frame)
            let padding: CGFloat = recipe.shape == .label ? text.font.pointSize * 0.5 : 0
            return CGSize(width: text.size.width + padding * 2, height: text.size.height + padding)
        case .arrow, .highlight, .rectangle:
            return CGSize(width: unit * CGFloat(recipe.aspect) * sx, height: unit * sy * (recipe.shape == .arrow ? 0.8 : 1))
        default:
            return CGSize(width: unit * 2 * sx, height: unit * 2 * sy)
        }
    }

    // MARK: Shapes

    private static func drawShape(_ placement: OverlayPlacement, in context: CGContext, frame: CGSize, image: (String) -> CGImage?) {
        let recipe = placement.recipe
        let unit = CGFloat(placement.unit)
        let sx = CGFloat(placement.scale.x)
        let sy = CGFloat(placement.scale.y)
        let color = placement.color.uiColor
        let reveal = CGFloat(placement.reveal)
        let line = max(CGFloat(recipe.stroke) * unit * max(sy, 0.1), 1)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch recipe.shape {
        case .title, .label:
            drawText(placement, in: context, frame: frame)

        case .arrow:
            let length = unit * CGFloat(recipe.aspect) * sx
            let start = CGPoint(x: -length / 2, y: 0)
            let end = CGPoint(x: length / 2, y: 0)
            let control = CGPoint(x: 0, y: -CGFloat(recipe.bend) * length * 0.6)
            let steps = 40
            var points: [CGPoint] = []
            for index in 0 ... Int(CGFloat(steps) * reveal) {
                let t = CGFloat(index) / CGFloat(steps)
                let u = 1 - t
                points.append(CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                                      y: u * u * start.y + 2 * u * t * control.y + t * t * end.y))
            }
            guard points.count > 1 else { return }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(line)
            context.addLines(between: points)
            context.strokePath()
            // Arrowhead along the last segment.
            let tip = points[points.count - 1]
            let before = points[max(points.count - 3, 0)]
            let angle = atan2(tip.y - before.y, tip.x - before.x)
            let head = line * 3.2
            context.setFillColor(color.cgColor)
            context.move(to: CGPoint(x: tip.x + cos(angle) * head * 0.35, y: tip.y + sin(angle) * head * 0.35))
            context.addLine(to: CGPoint(x: tip.x + cos(angle + 2.5) * head, y: tip.y + sin(angle + 2.5) * head))
            context.addLine(to: CGPoint(x: tip.x + cos(angle - 2.5) * head, y: tip.y + sin(angle - 2.5) * head))
            context.closePath()
            context.fillPath()

        case .highlight:
            // A marker circle drawn around something (a little wobbly, drawn in by `reveal`).
            let rx = unit * CGFloat(recipe.aspect) * sx / 2
            let ry = unit * sy / 2
            if recipe.filled {
                context.setFillColor(color.withAlphaComponent(0.35).cgColor)
                context.fill(CGRect(x: -rx, y: -ry, width: rx * 2 * reveal, height: ry * 2))
            } else {
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(line)
                let turns = 1.08 * reveal
                let steps = 80
                var points: [CGPoint] = []
                for index in 0 ... Int(CGFloat(steps) * turns) {
                    let t = CGFloat(index) / CGFloat(steps) * 2 * .pi - .pi * 0.6
                    let wobble = 1 + 0.035 * sin(t * 3)
                    points.append(CGPoint(x: cos(t) * rx * wobble, y: sin(t) * ry * wobble))
                }
                if points.count > 1 {
                    context.addLines(between: points)
                    context.strokePath()
                }
            }

        case .cross:
            let half = unit * 0.9
            let width = max(unit * CGFloat(recipe.stroke) * 3.2, 2) * max(sy, 0.1)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            let first = min(reveal * 2, 1)
            let second = max(reveal * 2 - 1, 0)
            context.move(to: CGPoint(x: -half * sx, y: -half * sy))
            context.addLine(to: CGPoint(x: -half * sx + 2 * half * sx * first, y: -half * sy + 2 * half * sy * first))
            if second > 0 {
                context.move(to: CGPoint(x: half * sx, y: -half * sy))
                context.addLine(to: CGPoint(x: half * sx - 2 * half * sx * second, y: -half * sy + 2 * half * sy * second))
            }
            context.strokePath()

        case .question, .exclamation:
            let glyph = recipe.shape == .question ? "?" : "!"
            let font = UIFont.systemFont(ofSize: unit * 2.4 * sy, weight: .black).withDesign(.rounded)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .strokeColor: UIColor.black.withAlphaComponent(0.85), .strokeWidth: -4
            ]
            let text = NSAttributedString(string: glyph, attributes: attributes)
            let bounds = text.size()
            context.scaleBy(x: max(sx / max(sy, 0.01), 0.01) * max(reveal, 0.001), y: max(reveal, 0.001))
            UIGraphicsPushContext(context)
            text.draw(at: CGPoint(x: -bounds.width / 2, y: -bounds.height / 2))
            UIGraphicsPopContext()

        case .check:
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(max(unit * CGFloat(recipe.stroke) * 3, 2) * max(sy, 0.1))
            let points = [CGPoint(x: -0.8 * unit * sx, y: 0), CGPoint(x: -0.2 * unit * sx, y: 0.6 * unit * sy),
                          CGPoint(x: 0.9 * unit * sx, y: -0.7 * unit * sy)]
            let lengths = [hypot(points[1].x - points[0].x, points[1].y - points[0].y), hypot(points[2].x - points[1].x, points[2].y - points[1].y)]
            var budget = (lengths[0] + lengths[1]) * reveal
            context.move(to: points[0])
            for index in 0 ..< 2 where budget > 0 {
                let t = min(budget / lengths[index], 1)
                context.addLine(to: CGPoint(x: points[index].x + (points[index + 1].x - points[index].x) * t,
                                            y: points[index].y + (points[index + 1].y - points[index].y) * t))
                budget -= lengths[index]
            }
            context.strokePath()

        case .circle, .rectangle, .triangle, .star:
            let path = CGMutablePath()
            let w = (recipe.shape == .rectangle ? unit * CGFloat(recipe.aspect) : unit * 2) * sx * max(reveal, 0.001)
            let h = (recipe.shape == .rectangle ? unit : unit * 2) * sy * max(reveal, 0.001)
            switch recipe.shape {
            case .circle:
                path.addEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            case .rectangle:
                path.addRoundedRect(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: min(w, h) * 0.12,
                                    cornerHeight: min(w, h) * 0.12)
            case .triangle:
                path.addLines(between: [CGPoint(x: 0, y: -h / 2), CGPoint(x: w / 2, y: h / 2), CGPoint(x: -w / 2, y: h / 2)])
                path.closeSubpath()
            default:
                var points: [CGPoint] = []
                for index in 0 ..< 10 {
                    let radius = index.isMultiple(of: 2) ? 1.0 : 0.45
                    let angle = CGFloat(index) / 10 * 2 * .pi - .pi / 2
                    points.append(CGPoint(x: cos(angle) * w / 2 * radius, y: sin(angle) * h / 2 * radius))
                }
                path.addLines(between: points)
                path.closeSubpath()
            }
            context.addPath(path)
            if recipe.filled {
                context.setFillColor(color.cgColor)
                context.fillPath()
            } else {
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(line)
                context.strokePath()
            }

        case .image:
            guard let name = recipe.image, let picture = image(name) else { return }
            let aspect = CGFloat(picture.width) / CGFloat(max(picture.height, 1))
            let h = unit * 3 * sy * max(reveal, 0.001)
            let w = h * aspect * sx / max(sy, 0.01)
            context.saveGState()
            // CGContext.draw expects y-up; flip locally.
            context.scaleBy(x: 1, y: -1)
            context.draw(picture, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            context.restoreGState()
        }
    }

    // MARK: Text

    struct TextLayout {
        var attributed: NSAttributedString
        var size: CGSize
        var font: UIFont
    }

    static func font(_ style: OverlayRecipe.Font, size: CGFloat) -> UIFont {
        switch style {
        case .rounded: UIFont.systemFont(ofSize: size, weight: .heavy).withDesign(.rounded)
        case .bold: UIFont.systemFont(ofSize: size, weight: .black)
        case .serif: UIFont.systemFont(ofSize: size, weight: .bold).withDesign(.serif)
        case .mono: UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        case .marker: UIFont(name: "MarkerFelt-Wide", size: size) ?? UIFont.systemFont(ofSize: size, weight: .heavy).withDesign(.rounded)
        }
    }

    static func textLayout(_ placement: OverlayPlacement, frame: CGSize) -> TextLayout {
        let recipe = placement.recipe
        let unit = CGFloat(placement.unit)
        var size = unit * (recipe.shape == .title ? 1.1 : 0.55) * CGFloat(placement.scale.y)
        let shown = String(recipe.text.prefix(Int((Double(recipe.text.count) * placement.reveal).rounded(.down))))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        func make(_ fontSize: CGFloat) -> TextLayout {
            let font = font(recipe.font, size: max(fontSize, 1))
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: placement.color.uiColor, .paragraphStyle: paragraph]
            if recipe.shape == .title {
                attributes[.strokeColor] = (placement.accent?.uiColor ?? UIColor.black).withAlphaComponent(0.8)
                attributes[.strokeWidth] = -3
            }
            let attributed = NSAttributedString(string: shown.isEmpty ? " " : shown, attributes: attributes)
            // Measure the whole text (not just what's revealed) so typing doesn't shift it.
            let full = NSAttributedString(string: recipe.text.isEmpty ? " " : recipe.text, attributes: attributes)
            let bounds = full.boundingRect(with: CGSize(width: frame.width * 0.9, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            return TextLayout(attributed: attributed, size: CGSize(width: ceil(bounds.width), height: ceil(bounds.height)), font: font)
        }
        var layout = make(size)
        // Titles never run off a portrait frame: shrink to fit 90 % of its width.
        let longest = recipe.text.split(separator: "\n").map(\.count).max() ?? 0
        if longest > 0 {
            let single = NSAttributedString(string: String(recipe.text.split(separator: "\n").max { $0.count < $1.count } ?? ""),
                                            attributes: [.font: layout.font]).size().width
            if single > frame.width * 0.9 {
                size *= frame.width * 0.9 / single
                layout = make(size)
            }
        }
        return layout
    }

    private static func drawText(_ placement: OverlayPlacement, in context: CGContext, frame: CGSize) {
        let layout = textLayout(placement, frame: frame)
        let stretch = CGFloat(placement.scale.x / max(placement.scale.y, 0.01))
        context.scaleBy(x: stretch, y: 1)
        let rect = CGRect(x: -layout.size.width / 2, y: -layout.size.height / 2, width: layout.size.width, height: layout.size.height)
        if placement.recipe.shape == .label {
            let padding = layout.font.pointSize * 0.5
            let pill = rect.insetBy(dx: -padding, dy: -padding * 0.45)
            context.setFillColor((placement.accent?.uiColor ?? UIColor.black.withAlphaComponent(0.72)).cgColor)
            context.addPath(CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil))
            context.fillPath()
        }
        UIGraphicsPushContext(context)
        layout.attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        UIGraphicsPopContext()
    }

    // MARK: Captions

    /// Draws the caption on screen at `time` (karaoke highlight on the spoken word).
    public static func drawCaption(_ page: CaptionPage, activeWord: Int?, settings: CaptionSettings, in context: CGContext, size: CGSize) {
        let short = min(size.width, size.height)
        let fontSize = max(CGFloat(settings.size) * short, 8)
        let weight: UIFont.Weight = settings.style == .subtitle ? .semibold : .heavy
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight).withDesign(.rounded)
        let lineHeight = font.lineHeight * 1.12
        let y0: CGFloat = switch settings.position {
        case .bottom: size.height * 0.84 - CGFloat(page.lines.count - 1) * lineHeight
        case .middle: size.height * 0.5 - CGFloat(page.lines.count) * lineHeight / 2
        case .top: size.height * 0.12
        }
        var wordIndex = 0
        context.saveGState()
        UIGraphicsPushContext(context)
        defer {
            UIGraphicsPopContext()
            context.restoreGState()
        }
        for (lineNumber, line) in page.lines.enumerated() {
            let texts = line.map { settings.uppercase ? $0.text.uppercased() : $0.text }
            let space = NSAttributedString(string: " ", attributes: [.font: font]).size().width
            let widths = texts.map { NSAttributedString(string: $0, attributes: [.font: font]).size().width }
            let pillPadding: CGFloat = settings.style == .pill ? fontSize * 0.28 : 0
            let total = widths.reduce(0, +) + space * CGFloat(max(texts.count - 1, 0)) + pillPadding * 2 * CGFloat(texts.count)
            var x = (size.width - total) / 2
            let y = y0 + CGFloat(lineNumber) * lineHeight
            if settings.style == .subtitle {
                let box = CGRect(x: x - fontSize * 0.4, y: y - fontSize * 0.08, width: total + fontSize * 0.8, height: lineHeight)
                context.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
                context.addPath(CGPath(roundedRect: box, cornerWidth: fontSize * 0.2, cornerHeight: fontSize * 0.2, transform: nil))
                context.fillPath()
            }
            for (index, text) in texts.enumerated() {
                let active = settings.karaoke && wordIndex == activeWord
                let color = (active ? settings.highlight : settings.color).uiColor
                var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                if settings.style == .punchy || settings.style == .outline {
                    attributes[.strokeColor] = UIColor.black
                    attributes[.strokeWidth] = settings.style == .punchy ? -7 : -4
                }
                if settings.style == .pill {
                    let pill = CGRect(x: x, y: y - fontSize * 0.05, width: widths[index] + pillPadding * 2, height: font.lineHeight * 1.02)
                    context.setFillColor((active ? settings.highlight : RGBA(0, 0, 0, 0.6)).uiColor.cgColor)
                    context.addPath(CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil))
                    context.fillPath()
                    if active { attributes[.foregroundColor] = UIColor.black }
                    x += pillPadding
                }
                let attributed = NSAttributedString(string: text, attributes: attributes)
                if active, settings.style == .punchy {
                    // The spoken word pops a little.
                    let grow: CGFloat = 1.12
                    context.saveGState()
                    context.translateBy(x: x + widths[index] / 2, y: y + font.lineHeight / 2)
                    context.scaleBy(x: grow, y: grow)
                    attributed.draw(at: CGPoint(x: -widths[index] / 2, y: -font.lineHeight / 2))
                    context.restoreGState()
                } else {
                    attributed.draw(at: CGPoint(x: x, y: y))
                }
                x += widths[index] + space + pillPadding
                wordIndex += 1
            }
        }
    }
}
