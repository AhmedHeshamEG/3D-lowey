import Foundation
import HmmBrush

/// A rectangle on the board, in board units (one unit is one point at 100 %); y runs down, like the screen.
public struct BoardRect: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The rectangle two corners span, whichever way they were dragged.
    public init(_ a: Vec2, _ b: Vec2) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    public init(center: Vec2, width: Double, height: Double) {
        self.init(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var origin: Vec2 { Vec2(x, y) }
    public var center: Vec2 { Vec2(x + width / 2, y + height / 2) }
    public var area: Double { width * height }
    public var corners: [Vec2] { [Vec2(minX, minY), Vec2(maxX, minY), Vec2(maxX, maxY), Vec2(minX, maxY)] }

    public func contains(_ point: Vec2) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    public func contains(_ other: BoardRect) -> Bool {
        other.minX >= minX && other.maxX <= maxX && other.minY >= minY && other.maxY <= maxY
    }

    public func intersects(_ other: BoardRect) -> Bool {
        other.minX <= maxX && other.maxX >= minX && other.minY <= maxY && other.maxY >= minY
    }

    public func union(_ other: BoardRect) -> BoardRect {
        let left = min(minX, other.minX), top = min(minY, other.minY)
        return BoardRect(x: left, y: top, width: max(maxX, other.maxX) - left, height: max(maxY, other.maxY) - top)
    }

    /// Grown by `amount` on every side (shrunk when negative, never past its middle).
    public func expanded(by amount: Double) -> BoardRect {
        let dx = max(amount, -width / 2), dy = max(amount, -height / 2)
        return BoardRect(x: x - dx, y: y - dy, width: width + dx * 2, height: height + dy * 2)
    }

    public func moved(by delta: Vec2) -> BoardRect {
        BoardRect(x: x + delta.x, y: y + delta.y, width: width, height: height)
    }

    /// How far a point is from the rectangle's edge line (0 on it), inside or out.
    public func distanceToEdge(_ point: Vec2) -> Double {
        let outside = Vec2(max(minX - point.x, 0, point.x - maxX), max(minY - point.y, 0, point.y - maxY)).length
        guard outside == 0 else { return outside }
        return min(point.x - minX, maxX - point.x, point.y - minY, maxY - point.y)
    }

    /// The box around some points (nil for none).
    public static func around(_ points: [Vec2]) -> BoardRect? {
        guard let first = points.first else { return nil }
        var left = first.x, right = first.x, top = first.y, bottom = first.y
        for point in points.dropFirst() {
            left = min(left, point.x)
            right = max(right, point.x)
            top = min(top, point.y)
            bottom = max(bottom, point.y)
        }
        return BoardRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

/// A map from one rectangle onto another: what a move or a resize does to everything it carries.
public struct BoardTransform: Hashable, Sendable {
    public var from: BoardRect
    public var to: BoardRect

    public init(from: BoardRect, to: BoardRect) {
        self.from = from
        self.to = to
    }

    public init(movingBy delta: Vec2) {
        from = BoardRect(x: 0, y: 0, width: 1, height: 1)
        to = from.moved(by: delta)
    }

    public var scaleX: Double { from.width > 1e-9 ? to.width / from.width : 1 }
    public var scaleY: Double { from.height > 1e-9 ? to.height / from.height : 1 }
    /// What a stroke's width grows by (the smaller side's scale, so a squashed stroke doesn't fatten).
    public var widthScale: Double { min(abs(scaleX), abs(scaleY)) }
    public var isMove: Bool { abs(scaleX - 1) < 1e-12 && abs(scaleY - 1) < 1e-12 }

    public func apply(_ point: Vec2) -> Vec2 {
        Vec2(to.x + (point.x - from.x) * scaleX, to.y + (point.y - from.y) * scaleY)
    }

    public func apply(_ rect: BoardRect) -> BoardRect {
        BoardRect(apply(Vec2(rect.minX, rect.minY)), apply(Vec2(rect.maxX, rect.maxY)))
    }
}

/// A colour on the board: sRGB, stored as `#RRGGBB`.
public struct BoardColor: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        // Kept in 8-bit steps, so a colour is the same before and after it is written down.
        self.red = (red.clamped(0, 1) * 255).rounded() / 255
        self.green = (green.clamped(0, 1) * 255).rounded() / 255
        self.blue = (blue.clamped(0, 1) * 255).rounded() / 255
    }

    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    public var hex: String {
        let value = UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
        let digits = String(value, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: 6 - digits.count) + digits
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let color = BoardColor(hex: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a colour: \(text)"))
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    /// 0 black … 1 white, as the eye weighs it (what picks dark or light text over it).
    public var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    /// Light ink, for the dark sheet.
    public static let ink = BoardColor(red: 0.93, green: 0.93, blue: 0.94)
    /// A note's amber slip.
    public static let paper = BoardColor(red: 1, green: 0.84, blue: 0.42)
}

enum BoardMath {
    /// The distance from a point to the stretch between two others.
    static func distance(_ point: Vec2, toSegment a: Vec2, _ b: Vec2) -> Double {
        let span = b - a
        let lengthSquared = span.dot(span)
        guard lengthSquared > 1e-18 else { return point.distance(to: a) }
        let t = ((point - a).dot(span) / lengthSquared).clamped(0, 1)
        return point.distance(to: a + span * t)
    }

    /// The shortest distance between two stretches (0 when they cross).
    static func distance(segment a: Vec2, _ b: Vec2, toSegment c: Vec2, _ d: Vec2) -> Double {
        if crosses(a, b, c, d) { return 0 }
        return min(distance(a, toSegment: c, d), distance(b, toSegment: c, d), distance(c, toSegment: a, b), distance(d, toSegment: a, b))
    }

    static func crosses(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> Bool {
        let d1 = (b - a).cross(c - a), d2 = (b - a).cross(d - a)
        let d3 = (d - c).cross(a - c), d4 = (d - c).cross(b - c)
        return d1 * d2 < 0 && d3 * d4 < 0
    }
}
