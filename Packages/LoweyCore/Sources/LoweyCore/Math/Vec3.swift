import Foundation

/// A 3D vector in scene units (meters). Double precision in the model; the
/// render layer converts to `Float` at the boundary.
///
/// Encodes as a compact JSON array `[x, y, z]` so scene files stay readable
/// and Scene Scripts written by people or AI stay short.
public struct Vec3: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(x: Double, y: Double, z: Double) {
        self.init(x, y, z)
    }

    public static let zero = Vec3(0, 0, 0)
    public static let one = Vec3(1, 1, 1)
    public static let unitX = Vec3(1, 0, 0)
    public static let unitY = Vec3(0, 1, 0)
    public static let unitZ = Vec3(0, 0, 1)

    public subscript(axis: Axis) -> Double {
        get {
            switch axis {
            case .x: x
            case .y: y
            case .z: z
            }
        }
        set {
            switch axis {
            case .x: x = newValue
            case .y: y = newValue
            case .z: z = newValue
            }
        }
    }

    public var length: Double { (x * x + y * y + z * z).squareRoot() }
    public var lengthSquared: Double { x * x + y * y + z * z }

    public var normalized: Vec3 {
        let len = length
        return len > 1e-12 ? self / len : .zero
    }

    public func dot(_ other: Vec3) -> Double { x * other.x + y * other.y + z * other.z }

    public func cross(_ other: Vec3) -> Vec3 {
        Vec3(y * other.z - z * other.y, z * other.x - x * other.z, x * other.y - y * other.x)
    }

    public func distance(to other: Vec3) -> Double { (self - other).length }

    public func lerp(to other: Vec3, _ t: Double) -> Vec3 { self + (other - self) * t }

    /// Component-wise multiply.
    public func scaled(by other: Vec3) -> Vec3 { Vec3(x * other.x, y * other.y, z * other.z) }

    public func map(_ transform: (Double) -> Double) -> Vec3 { Vec3(transform(x), transform(y), transform(z)) }

    public var maxComponent: Double { Swift.max(x, Swift.max(y, z)) }
    public var minComponent: Double { Swift.min(x, Swift.min(y, z)) }

    public func isApproximately(_ other: Vec3, tolerance: Double = 1e-6) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance && abs(z - other.z) <= tolerance
    }

    public static func + (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z) }
    public static func - (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z) }
    public static func * (lhs: Vec3, rhs: Double) -> Vec3 { Vec3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs) }
    public static func * (lhs: Double, rhs: Vec3) -> Vec3 { rhs * lhs }
    public static func / (lhs: Vec3, rhs: Double) -> Vec3 { Vec3(lhs.x / rhs, lhs.y / rhs, lhs.z / rhs) }
    public static prefix func - (vector: Vec3) -> Vec3 { Vec3(-vector.x, -vector.y, -vector.z) }
    public static func += (lhs: inout Vec3, rhs: Vec3) { lhs = lhs + rhs }
    public static func -= (lhs: inout Vec3, rhs: Vec3) { lhs = lhs - rhs }
    public static func *= (lhs: inout Vec3, rhs: Double) { lhs = lhs * rhs }

    public static func min(_ lhs: Vec3, _ rhs: Vec3) -> Vec3 {
        Vec3(Swift.min(lhs.x, rhs.x), Swift.min(lhs.y, rhs.y), Swift.min(lhs.z, rhs.z))
    }

    public static func max(_ lhs: Vec3, _ rhs: Vec3) -> Vec3 {
        Vec3(Swift.max(lhs.x, rhs.x), Swift.max(lhs.y, rhs.y), Swift.max(lhs.z, rhs.z))
    }
}

extension Vec3: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
        z = try container.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
    }
}

extension Vec3: CustomStringConvertible {
    public var description: String { "(\(x), \(y), \(z))" }
}

/// A principal axis.
public enum Axis: String, Codable, Sendable, CaseIterable {
    case x, y, z

    public var unit: Vec3 {
        switch self {
        case .x: .unitX
        case .y: .unitY
        case .z: .unitZ
        }
    }
}

/// 2D vector, used for drawing outlines on a guide plane.
public struct Vec2: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static func - (lhs: Vec2, rhs: Vec2) -> Vec2 { Vec2(lhs.x - rhs.x, lhs.y - rhs.y) }
    public static func + (lhs: Vec2, rhs: Vec2) -> Vec2 { Vec2(lhs.x + rhs.x, lhs.y + rhs.y) }
    public static func * (lhs: Vec2, rhs: Double) -> Vec2 { Vec2(lhs.x * rhs, lhs.y * rhs) }

    public func cross(_ other: Vec2) -> Double { x * other.y - y * other.x }
    public var length: Double { (x * x + y * y).squareRoot() }
}
