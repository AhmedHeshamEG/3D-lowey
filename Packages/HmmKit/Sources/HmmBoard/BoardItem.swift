import Foundation
import HmmBrush

/// A brush stroke on the board: the stored path (board units, the Pencil's dynamics already in its widths and
/// opacities), the brush it names among the board's frozen copies, its colour and the seed of its randomness.
public struct BoardStroke: Hashable, Sendable {
    public var path: BrushPath<Vec2>
    public var color: BoardColor
    /// A key of `Board.brushes` (nil: Ink Pen).
    public var brush: String?
    public var seed: UInt64

    public init(path: BrushPath<Vec2>, color: BoardColor = .ink, brush: String? = nil, seed: UInt64 = 1) {
        self.path = path
        self.color = color
        self.brush = brush
        self.seed = seed
    }
}

extension BoardStroke: Codable {
    private enum Key: String, CodingKey { case points, widths, alphas, color, brush, seed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        // Points are stored flat: x0, y0, x1, y1…
        let flat = try c.decode([Double].self, forKey: .points)
        let points = stride(from: 0, to: flat.count - 1, by: 2).map { Vec2(flat[$0], flat[$0 + 1]) }
        var widths = try c.decode([Double].self, forKey: .widths)
        var alphas = try c.decodeIfPresent([Double].self, forKey: .alphas) ?? []
        // A hand-edited file can't leave a point without its width or opacity.
        widths = Self.fitted(widths, to: points.count, fallback: 1)
        alphas = Self.fitted(alphas, to: points.count, fallback: 1)
        path = BrushPath(points: points, widths: widths, alphas: alphas)
        color = try c.decode(BoardColor.self, forKey: .color)
        brush = try c.decodeIfPresent(String.self, forKey: .brush)
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(path.points.flatMap { [$0.x, $0.y] }, forKey: .points)
        try c.encode(path.widths, forKey: .widths)
        try c.encode(path.alphas, forKey: .alphas)
        try c.encode(color, forKey: .color)
        try c.encodeIfPresent(brush, forKey: .brush)
        try c.encode(seed, forKey: .seed)
    }

    static func fitted(_ values: [Double], to count: Int, fallback: Double) -> [Double] {
        if values.count >= count { return Array(values.prefix(count)) }
        return values + Array(repeating: values.last ?? fallback, count: count - values.count)
    }
}

/// A picture dropped on the board: a file in the board's assets, shown in a rectangle.
public struct BoardPicture: Hashable, Sendable, Codable {
    /// The file's name in the board's `assets` folder.
    public var asset: String
    public var rect: BoardRect

    public init(asset: String, rect: BoardRect) {
        self.asset = asset
        self.rect = rect
    }
}

/// A note: a coloured slip of paper with words on it.
public struct BoardNote: Hashable, Sendable, Codable {
    public var text: String
    public var rect: BoardRect
    public var color: BoardColor

    public init(text: String = "", rect: BoardRect, color: BoardColor = .paper) {
        self.text = text
        self.rect = rect
        self.color = color
    }

    public static let defaultSize = Vec2(200, 140)
}

/// An arrow from one place to another. An end tied to an item follows it when it moves.
public struct BoardArrow: Hashable, Sendable, Codable {
    public var from: Vec2
    public var to: Vec2
    public var color: BoardColor
    /// The line's thickness in board units.
    public var width: Double
    public var fromItem: String?
    public var toItem: String?

    public init(from: Vec2, to: Vec2, color: BoardColor = .ink, width: Double = 3, fromItem: String? = nil, toItem: String? = nil) {
        self.from = from
        self.to = to
        self.color = color
        self.width = width
        self.fromItem = fromItem
        self.toItem = toItem
    }

    /// How long and how wide (to one side) the head is.
    public var headLength: Double { min(max(width * 5, 12), from.distance(to: to) * 0.6) }
    public var headHalfWidth: Double { headLength * 0.45 }

    /// The triangles to fill, three points each: two for the shaft, one for the head.
    public var triangles: [Vec2] {
        let length = from.distance(to: to)
        guard length > 1e-9 else { return [] }
        let along = (to - from) * (1 / length)
        let side = Vec2(-along.y, along.x)
        let neck = to - along * headLength
        let half = width / 2
        let a = from + side * half, b = from - side * half, c = neck - side * half, d = neck + side * half
        return [a, b, c, a, c, d, neck + side * headHalfWidth, neck - side * headHalfWidth, to]
    }
}

/// A frame: a named area that groups what lies inside it. Moving the frame moves its contents; it is what gets
/// pinned, shared or framed on screen as one thing.
public struct BoardFrame: Hashable, Sendable, Codable {
    public var title: String
    public var rect: BoardRect

    public init(title: String, rect: BoardRect) {
        self.title = title
        self.rect = rect
    }

    /// The strip above the frame its title sits on (where a tap picks the frame), in board units.
    public static let titleHeight = 28.0
    public var titleRect: BoardRect { BoardRect(x: rect.x, y: rect.y - Self.titleHeight, width: rect.width, height: Self.titleHeight) }
}

/// One thing on the board.
public struct BoardItem: Hashable, Sendable, Identifiable {
    public enum Content: Hashable, Sendable {
        case stroke(BoardStroke)
        case picture(BoardPicture)
        case note(BoardNote)
        case arrow(BoardArrow)
        case frame(BoardFrame)
    }

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case stroke, picture, note, arrow, frame
    }

    public var id: String
    public var content: Content

    public init(id: String, _ content: Content) {
        self.id = id
        self.content = content
    }

    public var kind: Kind {
        switch content {
        case .stroke: .stroke
        case .picture: .picture
        case .note: .note
        case .arrow: .arrow
        case .frame: .frame
        }
    }

    public var stroke: BoardStroke? {
        if case let .stroke(stroke) = content { return stroke }
        return nil
    }

    public var frame: BoardFrame? {
        if case let .frame(frame) = content { return frame }
        return nil
    }

    public var note: BoardNote? {
        if case let .note(note) = content { return note }
        return nil
    }

    public var arrow: BoardArrow? {
        if case let .arrow(arrow) = content { return arrow }
        return nil
    }

    public var picture: BoardPicture? {
        if case let .picture(picture) = content { return picture }
        return nil
    }
}

extension BoardItem: Codable {
    private enum Key: String, CodingKey { case id, kind }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = try c.decode(String.self, forKey: .id)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .stroke: content = try .stroke(BoardStroke(from: decoder))
        case .picture: content = try .picture(BoardPicture(from: decoder))
        case .note: content = try .note(BoardNote(from: decoder))
        case .arrow: content = try .arrow(BoardArrow(from: decoder))
        case .frame: content = try .frame(BoardFrame(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        switch content {
        case let .stroke(stroke): try stroke.encode(to: encoder)
        case let .picture(picture): try picture.encode(to: encoder)
        case let .note(note): try note.encode(to: encoder)
        case let .arrow(arrow): try arrow.encode(to: encoder)
        case let .frame(frame): try frame.encode(to: encoder)
        }
    }
}
