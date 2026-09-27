import Foundation

/// Unit quaternion rotation. Encodes as `[x, y, z, w]`.
public struct Quat: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double

    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public static let identity = Quat(x: 0, y: 0, z: 0, w: 1)

    /// Rotation of `angle` radians around `axis`.
    public init(angle: Double, axis: Vec3) {
        let axis = axis.normalized
        let half = angle / 2
        let sine = sin(half)
        self.init(x: axis.x * sine, y: axis.y * sine, z: axis.z * sine, w: cos(half))
    }

    /// Rotation from Euler angles in degrees, applied in Y (yaw), X (pitch), Z (roll) order —
    /// the order people expect when they type numbers into an inspector.
    public init(eulerDegrees euler: Vec3) {
        let toRad = Double.pi / 180
        let qx = Quat(angle: euler.x * toRad, axis: .unitX)
        let qy = Quat(angle: euler.y * toRad, axis: .unitY)
        let qz = Quat(angle: euler.z * toRad, axis: .unitZ)
        self = (qy * qx * qz).normalized
    }

    /// Euler angles in degrees (inverse of `init(eulerDegrees:)`).
    public var eulerDegrees: Vec3 {
        let q = normalized
        // Rotation matrix elements for R = Ry * Rx * Rz.
        let m12 = 2 * (q.y * q.z - q.w * q.x)
        let sinPitch = -m12
        let pitch: Double
        let yaw: Double
        let roll: Double
        if abs(sinPitch) >= 0.999_999 {
            pitch = sinPitch > 0 ? Double.pi / 2 : -Double.pi / 2
            let m20 = 2 * (q.x * q.z - q.w * q.y)
            let m00 = 1 - 2 * (q.y * q.y + q.z * q.z)
            yaw = atan2(-m20, m00)
            roll = 0
        } else {
            pitch = asin(sinPitch)
            let m02 = 2 * (q.x * q.z + q.w * q.y)
            let m22 = 1 - 2 * (q.x * q.x + q.y * q.y)
            yaw = atan2(m02, m22)
            let m10 = 2 * (q.x * q.y + q.w * q.z)
            let m11 = 1 - 2 * (q.x * q.x + q.z * q.z)
            roll = atan2(m10, m11)
        }
        let toDeg = 180 / Double.pi
        return Vec3(pitch * toDeg, yaw * toDeg, roll * toDeg)
    }

    public var length: Double { (x * x + y * y + z * z + w * w).squareRoot() }

    public var normalized: Quat {
        let len = length
        guard len > 1e-12 else { return .identity }
        return Quat(x: x / len, y: y / len, z: z / len, w: w / len)
    }

    public var conjugate: Quat { Quat(x: -x, y: -y, z: -z, w: w) }

    public var inverse: Quat {
        let lsq = x * x + y * y + z * z + w * w
        guard lsq > 1e-12 else { return .identity }
        let c = conjugate
        return Quat(x: c.x / lsq, y: c.y / lsq, z: c.z / lsq, w: c.w / lsq)
    }

    public func dot(_ other: Quat) -> Double { x * other.x + y * other.y + z * other.z + w * other.w }

    /// Rotates a vector.
    public func act(_ vector: Vec3) -> Vec3 {
        let u = Vec3(x, y, z)
        let uv = u.cross(vector)
        let uuv = u.cross(uv)
        return vector + (uv * w + uuv) * 2
    }

    public static func * (lhs: Quat, rhs: Quat) -> Quat {
        Quat(
            x: lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
            z: lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
            w: lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z
        )
    }

    /// Spherical interpolation along the shortest arc.
    public func slerp(to target: Quat, _ t: Double) -> Quat {
        var end = target
        var cosTheta = dot(target)
        if cosTheta < 0 {
            end = Quat(x: -target.x, y: -target.y, z: -target.z, w: -target.w)
            cosTheta = -cosTheta
        }
        if cosTheta > 0.9995 {
            let result = Quat(
                x: x + (end.x - x) * t,
                y: y + (end.y - y) * t,
                z: z + (end.z - z) * t,
                w: w + (end.w - w) * t
            )
            return result.normalized
        }
        let theta = acos(cosTheta)
        let sinTheta = sin(theta)
        let a = sin((1 - t) * theta) / sinTheta
        let b = sin(t * theta) / sinTheta
        return Quat(x: x * a + end.x * b, y: y * a + end.y * b, z: z * a + end.z * b, w: w * a + end.w * b)
    }

    /// True when both describe the same rotation (q and -q are equal rotations).
    public func isApproximately(_ other: Quat, tolerance: Double = 1e-6) -> Bool {
        abs(abs(normalized.dot(other.normalized)) - 1) <= tolerance
    }

    /// Rotation that turns `from` into `to` (both non-zero).
    public static func rotation(from: Vec3, to: Vec3) -> Quat {
        let a = from.normalized
        let b = to.normalized
        let d = a.dot(b)
        if d > 0.999_999 { return .identity }
        if d < -0.999_999 {
            var axis = Vec3.unitX.cross(a)
            if axis.length < 1e-6 { axis = Vec3.unitY.cross(a) }
            return Quat(angle: .pi, axis: axis)
        }
        let c = a.cross(b)
        return Quat(x: c.x, y: c.y, z: c.z, w: 1 + d).normalized
    }
}

extension Quat: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
        z = try container.decode(Double.self)
        w = try container.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
        try container.encode(w)
    }
}
