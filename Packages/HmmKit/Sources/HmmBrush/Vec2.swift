import Foundation

/// A 2D vector: a point on a board or a flipbook's page, an outline on a guide plane.
public struct Vec2: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public static func - (lhs: Vec2, rhs: Vec2) -> Vec2 { Vec2(lhs.x - rhs.x, lhs.y - rhs.y) }
    public static func + (lhs: Vec2, rhs: Vec2) -> Vec2 { Vec2(lhs.x + rhs.x, lhs.y + rhs.y) }
    public static func * (lhs: Vec2, rhs: Double) -> Vec2 { Vec2(lhs.x * rhs, lhs.y * rhs) }

    public func cross(_ other: Vec2) -> Double { x * other.y - y * other.x }
    public func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }
    public var length: Double { (x * x + y * y).squareRoot() }
}

extension Vec2: BrushPoint {
    public func distance(to other: Vec2) -> Double { (self - other).length }
    public var brushCoordinates: SIMD3<Double> { SIMD3(x, y, 0) }
}
