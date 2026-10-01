import CoreGraphics
import LoweyCore
import UIKit

/// One overlay's measurements and colour, and how to draw each shape (centred on the origin, y-down).
struct OverlayPen {
    let recipe: OverlayRecipe
    let unit: CGFloat
    let sx: CGFloat
    let sy: CGFloat
    let color: UIColor
    let reveal: CGFloat
    let line: CGFloat

    init(_ placement: OverlayPlacement) {
        recipe = placement.recipe
        unit = CGFloat(placement.unit)
        sx = CGFloat(placement.scale.x)
        sy = CGFloat(placement.scale.y)
        color = placement.color.uiColor
        reveal = CGFloat(placement.reveal)
        line = max(CGFloat(placement.recipe.stroke) * unit * max(sy, 0.1), 1)
    }

    func arrow(in context: CGContext) {
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
    }

    func highlight(in context: CGContext) {
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
    }

    func cross(in context: CGContext) {
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
    }

    func glyph(in context: CGContext) {
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
    }

    func check(in context: CGContext) {
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
    }

    func outline(in context: CGContext) {
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
    }

    func picture(in context: CGContext, image: (String) -> CGImage?) {
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
