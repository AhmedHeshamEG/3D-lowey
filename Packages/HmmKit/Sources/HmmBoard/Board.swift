import Foundation
import HmmBrush

/// The sheet itself: its colour and what's printed on it.
public struct BoardPaper: Hashable, Sendable, Codable {
    public enum Pattern: String, Codable, Sendable, CaseIterable {
        case dots, grid, plain
    }

    public var pattern: Pattern
    public var color: BoardColor

    public init(pattern: Pattern = .dots, color: BoardColor = BoardPaper.dark) {
        self.pattern = pattern
        self.color = color
    }

    /// The studio's dark sheet (the default) and a light one.
    public static let dark = BoardColor(red: 0.086, green: 0.090, blue: 0.102)
    public static let light = BoardColor(red: 0.961, green: 0.961, blue: 0.969)

    public var isDark: Bool { color.luminance < 0.5 }
    /// Ink that shows on this paper: what a new stroke, arrow or title starts with.
    public var ink: BoardColor { isDark ? BoardColor(red: 0.93, green: 0.93, blue: 0.94) : BoardColor(red: 0.11, green: 0.11, blue: 0.12) }
    /// The faint colour of the dots, the grid and a frame's edge.
    public var faint: BoardColor {
        let toward = isDark ? 1.0 : 0.0
        func mix(_ value: Double) -> Double { value + (toward - value) * 0.16 }
        return BoardColor(red: mix(color.red), green: mix(color.green), blue: mix(color.blue))
    }
}

/// A Schizzo board: an endless sheet for planning. Brush strokes, pictures, notes, arrows and frames, back to
/// front; the brushes its strokes were drawn with, frozen (editing a brush later never changes an old stroke).
public struct Board: Hashable, Sendable, Codable {
    /// Back to front.
    public var items: [BoardItem]
    /// The brushes strokes name, by content key (`BrushKey`).
    public var brushes: [String: Brush]
    public var paper: BoardPaper

    public init(items: [BoardItem] = [], brushes: [String: Brush] = [:], paper: BoardPaper = BoardPaper()) {
        self.items = items
        self.brushes = brushes
        self.paper = paper
    }

    private enum Key: String, CodingKey { case items, brushes, paper }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        items = try c.decodeIfPresent([BoardItem].self, forKey: .items) ?? []
        brushes = try c.decodeIfPresent([String: Brush].self, forKey: .brushes) ?? [:]
        paper = try c.decodeIfPresent(BoardPaper.self, forKey: .paper) ?? BoardPaper()
    }

    public var isEmpty: Bool { items.isEmpty }

    public func item(_ id: String) -> BoardItem? {
        items.first { $0.id == id }
    }

    public func index(of id: String) -> Int? {
        items.firstIndex { $0.id == id }
    }

    /// The box around everything (nil on an empty board), or around some of it.
    public func bounds(of ids: Set<String>? = nil) -> BoardRect? {
        var result: BoardRect?
        for item in items where ids?.contains(item.id) ?? true {
            result = result.map { $0.union(item.bounds) } ?? item.bounds
        }
        return result
    }

    /// The topmost item under a point. `tolerance` is the finger's or Pencil's slack, in board units.
    public func item(at point: Vec2, tolerance: Double) -> BoardItem? {
        items.last { $0.hit(point, tolerance: tolerance) }
    }

    /// What a dragged-out rectangle picks: everything it touches, and frames only when it holds them whole (so
    /// picking things inside a frame doesn't pick the frame).
    public func items(in rect: BoardRect) -> [BoardItem] {
        items.filter { item in
            item.frame != nil ? rect.contains(item.bounds) : item.touches(rect)
        }
    }

    /// What a frame carries: everything whose middle lies inside it (other frames only when wholly inside).
    public func contents(ofFrame id: String) -> [BoardItem] {
        guard let frame = item(id)?.frame else { return [] }
        return items.filter { item in
            guard item.id != id else { return false }
            return item.frame != nil ? frame.rect.contains(item.bounds) : frame.rect.contains(item.bounds.center)
        }
    }

    /// The ids a move, copy or delete of `ids` takes along: the frames' contents too.
    public func carried(by ids: Set<String>) -> Set<String> {
        var all = ids
        var frames = ids.filter { item($0)?.frame != nil }
        while let frame = frames.popFirst() {
            for inside in contents(ofFrame: frame) where all.insert(inside.id).inserted {
                if inside.frame != nil { frames.insert(inside.id) }
            }
        }
        return all
    }

    /// The frame a point lies in (the smallest when frames nest).
    public func frame(containing point: Vec2) -> BoardItem? {
        items.filter { $0.frame?.rect.contains(point) ?? false }.min { $0.bounds.area < $1.bounds.area }
    }

    /// A name for the next frame: "Frame 1", "Frame 2"…
    public var nextFrameTitle: String {
        let titles = Set(items.compactMap { $0.frame?.title })
        var number = titles.count + 1
        while titles.contains("Frame \(number)") {
            number += 1
        }
        return "Frame \(number)"
    }
}

public extension BoardItem {
    /// The box around the item, strokes and arrows with their thickness.
    var bounds: BoardRect {
        switch content {
        case let .stroke(stroke):
            let reach = stroke.path.widths.max() ?? 0
            return (BoardRect.around(stroke.path.points) ?? BoardRect(x: 0, y: 0, width: 0, height: 0)).expanded(by: reach)
        case let .picture(picture): return picture.rect
        case let .note(note): return note.rect
        case let .arrow(arrow): return BoardRect(arrow.from, arrow.to).expanded(by: max(arrow.headHalfWidth, arrow.width / 2))
        case let .frame(frame): return frame.rect.union(frame.titleRect)
        }
    }

    /// Whether a tap at `point` lands on the item. A frame is picked by its edge or its title, so what's inside it
    /// stays reachable.
    func hit(_ point: Vec2, tolerance: Double) -> Bool {
        switch content {
        case let .stroke(stroke):
            guard bounds.expanded(by: tolerance).contains(point) else { return false }
            return stroke.distance(to: point) <= tolerance
        case let .picture(picture): return picture.rect.expanded(by: tolerance / 2).contains(point)
        case let .note(note): return note.rect.expanded(by: tolerance / 2).contains(point)
        case let .arrow(arrow):
            return BoardMath.distance(point, toSegment: arrow.from, arrow.to) <= max(arrow.width / 2, arrow.headHalfWidth / 2) + tolerance
        case let .frame(frame):
            return frame.titleRect.contains(point) || frame.rect.distanceToEdge(point) <= tolerance
        }
    }

    /// Whether any part of the item lies in a rectangle.
    func touches(_ rect: BoardRect) -> Bool {
        guard bounds.intersects(rect) else { return false }
        switch content {
        case let .stroke(stroke):
            let reach = stroke.path.widths.max() ?? 0
            return stroke.path.points.contains { rect.expanded(by: reach).contains($0) }
        case let .arrow(arrow):
            if rect.contains(arrow.from) || rect.contains(arrow.to) { return true }
            let corners = rect.corners
            return (0 ..< 4).contains { BoardMath.crosses(arrow.from, arrow.to, corners[$0], corners[($0 + 1) % 4]) }
        case .picture, .note, .frame:
            return true
        }
    }

    /// The same item carried by a move or a resize. Strokes and arrows scale their thickness with the smaller side.
    func transformed(by transform: BoardTransform) -> BoardItem {
        var copy = self
        switch content {
        case var .stroke(stroke):
            stroke.path.points = stroke.path.points.map(transform.apply)
            if !transform.isMove { stroke.path.widths = stroke.path.widths.map { $0 * transform.widthScale } }
            copy.content = .stroke(stroke)
        case var .picture(picture):
            picture.rect = transform.apply(picture.rect)
            copy.content = .picture(picture)
        case var .note(note):
            note.rect = transform.apply(note.rect)
            copy.content = .note(note)
        case var .arrow(arrow):
            arrow.from = transform.apply(arrow.from)
            arrow.to = transform.apply(arrow.to)
            if !transform.isMove { arrow.width = max(arrow.width * transform.widthScale, 0.5) }
            copy.content = .arrow(arrow)
        case var .frame(frame):
            frame.rect = transform.apply(frame.rect)
            copy.content = .frame(frame)
        }
        return copy
    }
}

public extension BoardStroke {
    /// How far a point is from the stroke's ink (0 inside it).
    func distance(to point: Vec2) -> Double {
        let points = path.points
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return max(point.distance(to: first) - (path.widths.first ?? 0), 0) }
        var best = Double.infinity
        for index in 0 ..< points.count - 1 {
            let reach = max(path.widths[index], path.widths[index + 1])
            best = min(best, BoardMath.distance(point, toSegment: points[index], points[index + 1]) - reach)
        }
        return max(best, 0)
    }

    /// What is left after an eraser of `radius` passes from `a` to `b`: nil when it missed, else the pieces (none
    /// when it took everything). Pieces keep the stroke's brush, colour and seed.
    func erased(from a: Vec2, to b: Vec2, radius: Double) -> [BoardStroke]? {
        let points = path.points
        let gone = points.indices.map { BoardMath.distance(points[$0], toSegment: a, b) <= radius + path.widths[$0] }
        guard gone.contains(true) else { return nil }
        var pieces: [BoardStroke] = []
        var run: [Int] = []
        func close() {
            // A lone point left between two bites is a crumb, not a stroke (unless the stroke was a dot).
            if run.count > 1 || (run.count == 1 && points.count == 1) {
                var piece = self
                piece.path = BrushPath(points: run.map { points[$0] }, widths: run.map { path.widths[$0] }, alphas: run.map { path.alphas[$0] })
                pieces.append(piece)
            }
            run = []
        }
        for index in points.indices {
            if gone[index] { close() } else { run.append(index) }
        }
        close()
        return pieces
    }
}
