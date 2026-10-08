import Foundation
import HmmBrush

/// The board's flat shapes as triangles (three points each, board units), for whoever fills them: a note's slip, a
/// frame's edge, the selection's outline, the paper's dots.
public enum BoardShapes {
    public static func quad(_ rect: BoardRect) -> [Vec2] {
        let c = rect.corners
        return [c[0], c[1], c[2], c[0], c[2], c[3]]
    }

    /// A straight line as a thin box.
    public static func line(from a: Vec2, to b: Vec2, thickness: Double) -> [Vec2] {
        let length = a.distance(to: b)
        guard length > 1e-9 else { return [] }
        let side = Vec2(-(b.y - a.y) / length, (b.x - a.x) / length) * (thickness / 2)
        return [a + side, a - side, b - side, a + side, b - side, b + side]
    }

    /// A rectangle's edge, `thickness` wide, centred on the edge.
    public static func outline(_ rect: BoardRect, thickness: Double) -> [Vec2] {
        let half = thickness / 2
        let outer = rect.expanded(by: half), inner = rect.expanded(by: -half)
        return quad(BoardRect(x: outer.minX, y: outer.minY, width: outer.width, height: thickness))
            + quad(BoardRect(x: outer.minX, y: inner.maxY, width: outer.width, height: thickness))
            + quad(BoardRect(x: outer.minX, y: inner.minY, width: thickness, height: inner.height))
            + quad(BoardRect(x: inner.maxX, y: inner.minY, width: thickness, height: inner.height))
    }

    /// A rectangle with rounded corners, as a fan around its middle.
    public static func roundedRect(_ rect: BoardRect, radius: Double, segments: Int = 5) -> [Vec2] {
        let r = min(max(radius, 0), rect.width / 2, rect.height / 2)
        guard r > 1e-9 else { return quad(rect) }
        // Corner centres, clockwise on screen from the top left, each with the angle its arc starts at.
        let centers: [(Vec2, Double)] = [
            (Vec2(rect.minX + r, rect.minY + r), .pi), (Vec2(rect.maxX - r, rect.minY + r), 1.5 * .pi),
            (Vec2(rect.maxX - r, rect.maxY - r), 0), (Vec2(rect.minX + r, rect.maxY - r), 0.5 * .pi)
        ]
        var rim: [Vec2] = []
        for (center, start) in centers {
            for step in 0 ... max(segments, 1) {
                let angle = start + 0.5 * .pi * Double(step) / Double(max(segments, 1))
                rim.append(center + Vec2(cos(angle), sin(angle)) * r)
            }
        }
        let middle = rect.center
        return rim.indices.flatMap { [middle, rim[$0], rim[($0 + 1) % rim.count]] }
    }

    public static func disc(center: Vec2, radius: Double, segments: Int = 20) -> [Vec2] {
        let rim = circle(center: center, radius: radius, segments: segments)
        return rim.indices.flatMap { [center, rim[$0], rim[($0 + 1) % rim.count]] }
    }

    /// A circle's line (the eraser's size under the Pencil).
    public static func ring(center: Vec2, radius: Double, thickness: Double, segments: Int = 40) -> [Vec2] {
        let outer = circle(center: center, radius: radius + thickness / 2, segments: segments)
        let inner = circle(center: center, radius: max(radius - thickness / 2, 0), segments: segments)
        return outer.indices.flatMap { index -> [Vec2] in
            let next = (index + 1) % outer.count
            return [outer[index], inner[index], inner[next], outer[index], inner[next], outer[next]]
        }
    }

    static func circle(center: Vec2, radius: Double, segments: Int) -> [Vec2] {
        (0 ..< max(segments, 3)).map { step in
            let angle = 2 * .pi * Double(step) / Double(max(segments, 3))
            return center + Vec2(cos(angle), sin(angle)) * radius
        }
    }

    /// How far apart the paper's dots or lines are at a zoom, in board units: 32 at 100 %, doubling or halving so
    /// they stay between 20 and 40 points apart on screen.
    public static func paperStep(scale: Double) -> Double {
        let exponent = log2(20 / (32 * max(scale, 1e-6))).rounded(.up)
        return 32 * pow(2, exponent)
    }

    /// The paper's pattern over a part of the board: dots (small squares) or grid lines, `mark` board units thick.
    public static func paper(_ pattern: BoardPaper.Pattern, over rect: BoardRect, scale: Double, mark: Double) -> [Vec2] {
        guard pattern != .plain else { return [] }
        let step = paperStep(scale: scale)
        let columns = stride(from: (rect.minX / step).rounded(.down) * step, through: rect.maxX, by: step)
        let rows = stride(from: (rect.minY / step).rounded(.down) * step, through: rect.maxY, by: step)
        switch pattern {
        case .plain:
            return []
        case .grid:
            return columns.flatMap { quad(BoardRect(x: $0 - mark / 2, y: rect.minY, width: mark, height: rect.height)) }
                + rows.flatMap { quad(BoardRect(x: rect.minX, y: $0 - mark / 2, width: rect.width, height: mark)) }
        case .dots:
            let ys = Array(rows)
            return columns.flatMap { x in ys.flatMap { y in quad(BoardRect(center: Vec2(x, y), width: mark * 1.6, height: mark * 1.6)) } }
        }
    }

    /// The selection's eight handles (corners and sides), clockwise from the top left.
    public static func handles(of rect: BoardRect) -> [Vec2] {
        [
            Vec2(rect.minX, rect.minY), Vec2(rect.center.x, rect.minY), Vec2(rect.maxX, rect.minY), Vec2(rect.maxX, rect.center.y),
            Vec2(rect.maxX, rect.maxY), Vec2(rect.center.x, rect.maxY), Vec2(rect.minX, rect.maxY), Vec2(rect.minX, rect.center.y)
        ]
    }

    /// The rectangle a selection becomes when handle `index` (as in `handles`) is dragged to `point`. Corners keep
    /// the shape's proportions; sides stretch one way. It never turns inside out or gets smaller than `minimum`.
    public static func resized(_ rect: BoardRect, handle index: Int, to point: Vec2, minimum: Double) -> BoardRect {
        var left = rect.minX, right = rect.maxX, top = rect.minY, bottom = rect.maxY
        let movesLeft = [0, 6, 7].contains(index), movesRight = [2, 3, 4].contains(index)
        let movesTop = [0, 1, 2].contains(index), movesBottom = [4, 5, 6].contains(index)
        if movesLeft { left = min(point.x, right - minimum) }
        if movesRight { right = max(point.x, left + minimum) }
        if movesTop { top = min(point.y, bottom - minimum) }
        if movesBottom { bottom = max(point.y, top + minimum) }
        let isCorner = index % 2 == 0
        if isCorner, rect.width > 1e-9, rect.height > 1e-9 {
            // The larger pull wins; the other side follows it.
            let factor = max((right - left) / rect.width, (bottom - top) / rect.height)
            let width = rect.width * factor, height = rect.height * factor
            if movesLeft { left = right - width } else { right = left + width }
            if movesTop { top = bottom - height } else { bottom = top + height }
        }
        return BoardRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
