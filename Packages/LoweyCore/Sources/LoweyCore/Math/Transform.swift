import Foundation

/// Position / rotation / scale (translate · rotate · scale, the usual order):
/// a point p maps to `position + rotation.act(scale * p)`.
public struct Transform: Hashable, Sendable, Codable {
    public var position: Vec3
    public var rotation: Quat
    public var scale: Vec3

    public init(position: Vec3 = .zero, rotation: Quat = .identity, scale: Vec3 = .one) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }

    public static let identity = Transform()

    public func apply(to point: Vec3) -> Vec3 {
        position + rotation.act(point.scaled(by: scale))
    }

    public func applyDirection(_ direction: Vec3) -> Vec3 {
        rotation.act(direction.scaled(by: scale))
    }

    /// Inverse mapping of `applyDirection(_:)` (not normalised).
    public func inverseApplyDirection(_ direction: Vec3) -> Vec3 {
        let local = rotation.inverse.act(direction)
        return Vec3(scale.x != 0 ? local.x / scale.x : 0, scale.y != 0 ? local.y / scale.y : 0, scale.z != 0 ? local.z / scale.z : 0)
    }

    /// Inverse mapping of `apply(to:)`.
    public func inverseApply(to point: Vec3) -> Vec3 {
        let local = rotation.inverse.act(point - position)
        return Vec3(
            scale.x != 0 ? local.x / scale.x : 0,
            scale.y != 0 ? local.y / scale.y : 0,
            scale.z != 0 ? local.z / scale.z : 0
        )
    }

    /// `parent ∘ child`. Exact for uniform scale (the common case); for non-uniform
    /// parent scale with rotated children it keeps position exact and approximates shear.
    public static func * (parent: Transform, child: Transform) -> Transform {
        Transform(
            position: parent.apply(to: child.position),
            rotation: (parent.rotation * child.rotation).normalized,
            scale: parent.scale.scaled(by: child.scale)
        )
    }

    /// The child transform that, composed under `parent`, yields `world`.
    public static func relative(world: Transform, toParent parent: Transform) -> Transform {
        let inverseRotation = parent.rotation.inverse
        let local = parent.inverseApply(to: world.position)
        let scale = Vec3(
            parent.scale.x != 0 ? world.scale.x / parent.scale.x : world.scale.x,
            parent.scale.y != 0 ? world.scale.y / parent.scale.y : world.scale.y,
            parent.scale.z != 0 ? world.scale.z / parent.scale.z : world.scale.z
        )
        return Transform(position: local, rotation: (inverseRotation * world.rotation).normalized, scale: scale)
    }

    public func isApproximately(_ other: Transform, tolerance: Double = 1e-6) -> Bool {
        position.isApproximately(other.position, tolerance: tolerance)
            && rotation.isApproximately(other.rotation, tolerance: tolerance)
            && scale.isApproximately(other.scale, tolerance: tolerance)
    }
}

/// Axis-aligned bounding box.
public struct Bounds: Hashable, Sendable, Codable {
    public var min: Vec3
    public var max: Vec3

    public init(min: Vec3, max: Vec3) {
        self.min = min
        self.max = max
    }

    public init?(points: some Sequence<Vec3>) {
        var iterator = points.makeIterator()
        guard let first = iterator.next() else { return nil }
        var lo = first
        var hi = first
        while let point = iterator.next() {
            lo = Vec3.min(lo, point)
            hi = Vec3.max(hi, point)
        }
        self.init(min: lo, max: hi)
    }

    /// Unit cube with its base on the ground: the blockout primitive's native bounds.
    public static let unitBase = Bounds(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 1, 0.5))

    public var center: Vec3 { (min + max) * 0.5 }
    public var size: Vec3 { max - min }
    public var extents: Vec3 { size * 0.5 }

    public var corners: [Vec3] {
        [
            Vec3(min.x, min.y, min.z), Vec3(max.x, min.y, min.z),
            Vec3(min.x, max.y, min.z), Vec3(max.x, max.y, min.z),
            Vec3(min.x, min.y, max.z), Vec3(max.x, min.y, max.z),
            Vec3(min.x, max.y, max.z), Vec3(max.x, max.y, max.z)
        ]
    }

    public func union(_ other: Bounds) -> Bounds {
        Bounds(min: Vec3.min(min, other.min), max: Vec3.max(max, other.max))
    }

    public func transformed(by transform: Transform) -> Bounds {
        Bounds(points: corners.map { transform.apply(to: $0) }) ?? self
    }

    public func contains(_ point: Vec3, tolerance: Double = 0) -> Bool {
        point.x >= min.x - tolerance && point.x <= max.x + tolerance
            && point.y >= min.y - tolerance && point.y <= max.y + tolerance
            && point.z >= min.z - tolerance && point.z <= max.z + tolerance
    }

    public func intersects(_ other: Bounds) -> Bool {
        min.x <= other.max.x && max.x >= other.min.x
            && min.y <= other.max.y && max.y >= other.min.y
            && min.z <= other.max.z && max.z >= other.min.z
    }
}

/// A ray for picking and guide-surface drawing.
public struct Ray: Hashable, Sendable {
    public var origin: Vec3
    public var direction: Vec3

    public init(origin: Vec3, direction: Vec3) {
        self.origin = origin
        self.direction = direction.normalized
    }

    public func point(at distance: Double) -> Vec3 { origin + direction * distance }
}
