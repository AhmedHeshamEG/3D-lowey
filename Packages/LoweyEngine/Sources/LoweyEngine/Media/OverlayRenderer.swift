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
        let pen = OverlayPen(placement)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch placement.recipe.shape {
        case .title, .label: drawText(placement, in: context, frame: frame)
        case .arrow: pen.arrow(in: context)
        case .highlight: pen.highlight(in: context)
        case .cross: pen.cross(in: context)
        case .question, .exclamation: pen.glyph(in: context)
        case .check: pen.check(in: context)
        case .circle, .rectangle, .triangle, .star: pen.outline(in: context)
        case .image: pen.picture(in: context, image: image)
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
}
