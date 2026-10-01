import Foundation

/// A surface you draw on (Feather-style). Lock a plane to the view, or wrap strokes
/// around a box, cylinder or sphere. "Draw on an existing object" uses the render
/// layer's mesh raycast instead and produces the same `SurfaceHit`.
public enum GuideSurface: Hashable, Sendable, Codable {
    case plane(origin: Vec3, normal: Vec3)
    case box(center: Vec3, size: Vec3)
    /// Vertical cylinder standing on `base`.
    case cylinder(base: Vec3, radius: Double, height: Double)
    case sphere(center: Vec3, radius: Double)

    public var kindName: String {
        switch self {
        case .plane: "Plane"
        case .box: "Box"
        case .cylinder: "Cylinder"
        case .sphere: "Sphere"
        }
    }

    /// Nearest hit in front of the ray origin.
    public func intersect(_ ray: Ray) -> SurfaceHit? {
        switch self {
        case let .plane(origin, normal):
            return Self.intersectPlane(ray, origin: origin, normal: normal.normalized)
        case let .box(center, size):
            return Self.intersectBox(ray, center: center, extents: size * 0.5)
        case let .cylinder(base, radius, height):
            return Self.intersectCylinder(ray, base: base, radius: radius, height: height)
        case let .sphere(center, radius):
            return Self.intersectSphere(ray, center: center, radius: radius)
        }
    }

    static func intersectPlane(_ ray: Ray, origin: Vec3, normal: Vec3) -> SurfaceHit? {
        let denominator = normal.dot(ray.direction)
        guard abs(denominator) > 1e-9 else { return nil }
        let t = (origin - ray.origin).dot(normal) / denominator
        guard t > 0 else { return nil }
        // The side facing the viewer.
        let facing = denominator < 0 ? normal : -normal
        return SurfaceHit(point: ray.point(at: t), normal: facing, distance: t)
    }

    static func intersectBox(_ ray: Ray, center: Vec3, extents: Vec3) -> SurfaceHit? {
        let origin = ray.origin - center
        var tMin = -Double.infinity
        var tMax = Double.infinity
        var hitAxis: Axis = .x
        var hitSign = 1.0
        for axis in Axis.allCases {
            let o = origin[axis]
            let d = ray.direction[axis]
            let e = extents[axis]
            if abs(d) < 1e-12 {
                if o < -e || o > e { return nil }
                continue
            }
            var t1 = (-e - o) / d
            var t2 = (e - o) / d
            var sign = -1.0
            if t1 > t2 {
                swap(&t1, &t2)
                sign = 1.0
            }
            if t1 > tMin {
                tMin = t1
                hitAxis = axis
                hitSign = sign
            }
            tMax = min(tMax, t2)
            if tMin > tMax { return nil }
        }
        guard tMin > 0 else { return nil }
        return SurfaceHit(point: ray.point(at: tMin), normal: hitAxis.unit * hitSign, distance: tMin)
    }

    static func intersectSphere(_ ray: Ray, center: Vec3, radius: Double) -> SurfaceHit? {
        let oc = ray.origin - center
        let b = oc.dot(ray.direction)
        let c = oc.lengthSquared - radius * radius
        let discriminant = b * b - c
        guard discriminant >= 0 else { return nil }
        let root = discriminant.squareRoot()
        var t = -b - root
        if t <= 0 { t = -b + root }
        guard t > 0 else { return nil }
        let point = ray.point(at: t)
        return SurfaceHit(point: point, normal: (point - center).normalized, distance: t)
    }

    static func intersectCylinder(_ ray: Ray, base: Vec3, radius: Double, height: Double) -> SurfaceHit? {
        var best: SurfaceHit?
        // Side.
        let ox = ray.origin.x - base.x
        let oz = ray.origin.z - base.z
        let dx = ray.direction.x
        let dz = ray.direction.z
        let a = dx * dx + dz * dz
        if a > 1e-12 {
            let b = ox * dx + oz * dz
            let c = ox * ox + oz * oz - radius * radius
            let discriminant = b * b - a * c
            if discriminant >= 0 {
                let root = discriminant.squareRoot()
                for t in [(-b - root) / a, (-b + root) / a] where t > 0 {
                    let point = ray.point(at: t)
                    if point.y >= base.y, point.y <= base.y + height {
                        let normal = Vec3(point.x - base.x, 0, point.z - base.z).normalized
                        if t < best?.distance ?? .infinity { best = SurfaceHit(point: point, normal: normal, distance: t) }
                        break
                    }
                }
            }
        }
        // Caps.
        for (y, normal) in [(base.y + height, Vec3.unitY), (base.y, -Vec3.unitY)] {
            if let hit = intersectPlane(ray, origin: Vec3(base.x, y, base.z), normal: normal) {
                let dxz = Vec3(hit.point.x - base.x, 0, hit.point.z - base.z)
                if dxz.length <= radius, hit.distance < best?.distance ?? .infinity {
                    best = SurfaceHit(point: hit.point, normal: normal, distance: hit.distance)
                }
            }
        }
        return best
    }
}

public struct SurfaceHit: Hashable, Sendable {
    public var point: Vec3
    public var normal: Vec3
    public var distance: Double

    public init(point: Vec3, normal: Vec3, distance: Double) {
        self.point = point
        self.normal = normal
        self.distance = distance
    }
}

/// Quick views and locked drawing planes.
public enum ViewAxis: String, Codable, Sendable, CaseIterable {
    case top, front, side, perspective

    public var displayName: String {
        switch self {
        case .top: "Top"
        case .front: "Front"
        case .side: "Side"
        case .perspective: "Perspective"
        }
    }

    /// Yaw/pitch for the quick view.
    public var angles: (yaw: Double, pitch: Double) {
        switch self {
        case .top: (0, 89.9)
        case .front: (0, 0)
        case .side: (90, 0)
        case .perspective: (35, 28)
        }
    }

    /// Normal of the drawing plane locked to this view (points toward the viewer).
    public var planeNormal: Vec3 {
        switch self {
        case .top: .unitY
        case .front: .unitZ
        case .side: .unitX
        case .perspective: .unitY
        }
    }
}
