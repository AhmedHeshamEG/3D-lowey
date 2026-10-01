import CoreGraphics
import LoweyCore
import UIKit

// MARK: - Captions

public extension OverlayRenderer {
    /// Draws the caption on screen at `time` (karaoke highlight on the spoken word).
    static func drawCaption(_ page: CaptionPage, activeWord: Int?, settings: CaptionSettings, in context: CGContext, size: CGSize) {
        let pen = CaptionPen(settings: settings, size: size, activeWord: activeWord)
        let y0: CGFloat = switch settings.position {
        case .bottom: size.height * 0.84 - CGFloat(page.lines.count - 1) * pen.lineHeight
        case .middle: size.height * 0.5 - CGFloat(page.lines.count) * pen.lineHeight / 2
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
            pen.drawLine(texts, y: y0 + CGFloat(lineNumber) * pen.lineHeight, width: size.width, wordIndex: &wordIndex, in: context)
        }
    }
}

/// The caption style at one frame size: font, spacing and how each word is drawn.
private struct CaptionPen {
    let settings: CaptionSettings
    let activeWord: Int?
    let fontSize: CGFloat
    let font: UIFont
    let lineHeight: CGFloat
    /// Punchy words pop and wear a thick outline: give them more room so they never touch.
    let space: CGFloat
    let pillPadding: CGFloat

    init(settings: CaptionSettings, size: CGSize, activeWord: Int?) {
        self.settings = settings
        self.activeWord = activeWord
        fontSize = max(CGFloat(settings.size) * min(size.width, size.height), 8)
        let weight: UIFont.Weight = settings.style == .subtitle ? .semibold : .heavy
        font = UIFont.systemFont(ofSize: fontSize, weight: weight).withDesign(.rounded)
        lineHeight = font.lineHeight * 1.12
        space = NSAttributedString(string: " ", attributes: [.font: font]).size().width * (settings.style == .punchy ? 1.6 : 1)
        pillPadding = settings.style == .pill ? fontSize * 0.28 : 0
    }

    func drawLine(_ texts: [String], y: CGFloat, width: CGFloat, wordIndex: inout Int, in context: CGContext) {
        let widths = texts.map { NSAttributedString(string: $0, attributes: [.font: font]).size().width }
        let total = widths.reduce(0, +) + space * CGFloat(max(texts.count - 1, 0)) + pillPadding * 2 * CGFloat(texts.count)
        var x = (width - total) / 2
        if settings.style == .subtitle {
            let box = CGRect(x: x - fontSize * 0.4, y: y - fontSize * 0.08, width: total + fontSize * 0.8, height: lineHeight)
            context.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
            context.addPath(CGPath(roundedRect: box, cornerWidth: fontSize * 0.2, cornerHeight: fontSize * 0.2, transform: nil))
            context.fillPath()
        }
        for (index, text) in texts.enumerated() {
            let active = settings.karaoke && wordIndex == activeWord
            x = drawWord(text, width: widths[index], at: CGPoint(x: x, y: y), active: active, in: context)
            wordIndex += 1
        }
    }

    /// Draws one word at `origin`; returns where the next word starts.
    func drawWord(_ text: String, width: CGFloat, at origin: CGPoint, active: Bool, in context: CGContext) -> CGFloat {
        var x = origin.x
        let y = origin.y
        let color = (active ? settings.highlight : settings.color).uiColor
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if settings.style == .punchy || settings.style == .outline {
            attributes[.strokeColor] = UIColor.black
            attributes[.strokeWidth] = settings.style == .punchy ? -7 : -4
        }
        if settings.style == .pill {
            let pill = CGRect(x: x, y: y - fontSize * 0.05, width: width + pillPadding * 2, height: font.lineHeight * 1.02)
            context.setFillColor((active ? settings.highlight : RGBA(0, 0, 0, 0.6)).uiColor.cgColor)
            context.addPath(CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil))
            context.fillPath()
            if active { attributes[.foregroundColor] = UIColor.black }
            x += pillPadding
        }
        let attributed = NSAttributedString(string: text, attributes: attributes)
        if active, settings.style == .punchy {
            // The spoken word pops a little.
            let grow: CGFloat = 1.07
            context.saveGState()
            context.translateBy(x: x + width / 2, y: y + font.lineHeight / 2)
            context.scaleBy(x: grow, y: grow)
            attributed.draw(at: CGPoint(x: -width / 2, y: -font.lineHeight / 2))
            context.restoreGState()
        } else {
            attributed.draw(at: CGPoint(x: x, y: y))
        }
        return x + width + space + pillPadding
    }
}
