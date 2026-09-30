import Foundation

/// A primitive's bevel: rounded edges that catch the rim light and give lines something to follow.
public struct BevelSpec: Hashable, Sendable {
    /// Radius in metres (after the object's own scale).
    public var radius: Double
    public var segments: Int

    public init(radius: Double, segments: Int = 2) {
        self.radius = max(radius, 0)
        self.segments = min(max(segments, 1), 6)
    }

    /// New primitives start with a small bevel.
    public static let standard = BevelSpec(radius: 0.02, segments: 2)

    /// The object's bevel (none unless it has the property: 1.x objects keep their sharp edges).
    public init?(_ object: SceneObject) {
        guard let radius = object[.bevel]?.floatValue, radius > 0.0005 else { return nil }
        self.init(radius: radius, segments: Int(object[.bevelSegments]?.floatValue ?? 2))
    }

    /// Whether `shape` has edges to bevel.
    public static func applies(to shape: PrimitiveShape) -> Bool {
        shape == .cube || shape == .cylinder || shape == .cone
    }
}

/// Bevelled primitives, built at the object's real size (so the bevel stays round under non-uniform scale), pivot
/// at the base centre like every primitive. Normals are exact: flat on faces, curving across the bevel.
public enum BevelMesh {
    /// The mesh for `shape` at `size` (metres), or nil when the shape has nothing to bevel.
    public static func make(_ shape: PrimitiveShape, size: SIMD3<Float>, bevel: BevelSpec) -> MeshData? {
        guard BevelSpec.applies(to: shape), bevel.radius > 0 else { return nil }
        let safe = SIMD3<Float>(max(size.x, 1e-3), max(size.y, 1e-3), max(size.z, 1e-3))
        switch shape {
        case .cube: return roundedBox(size: safe, radius: Float(bevel.radius), segments: bevel.segments)
        case .cylinder: return lathe(size: safe, radius: Float(bevel.radius), segments: bevel.segments, cone: false)
        case .cone: return lathe(size: safe, radius: Float(bevel.radius), segments: bevel.segments, cone: true)
        default: return nil
        }
    }

    /// Grid coordinates across one axis: the flat middle plus `segments` steps through each bevel.
    static func stops(half: Float, radius: Float, segments: Int) -> [Float] {
        var values: [Float] = []
        for index in 0 ... segments {
            values.append(-half + radius * Float(index) / Float(segments))
        }
        for index in 0 ... segments {
            values.append(half - radius + radius * Float(index) / Float(segments))
        }
        return values
    }

    /// A box whose edges and corners are rounded with `radius`: every point of a subdivided box is pulled onto the
    /// rounded surface (the classic rounded-box construction).
    static func roundedBox(size: SIMD3<Float>, radius: Float, segments: Int) -> MeshData {
        let half = size / 2
        let r = min(radius, min(half.x, min(half.y, half.z)) * 0.95)
        let inner = half - SIMD3<Float>(repeating: r)
        var mesh = MeshData()
        // (normal axis, sign, u axis, v axis) with u × v = normal for counter-clockwise front faces.
        let faces: [(Int, Float, Int, Int)] = [(2, 1, 0, 1), (2, -1, 1, 0), (0, 1, 1, 2), (0, -1, 2, 1), (1, 1, 2, 0), (1, -1, 0, 2)]
        for (axis, sign, uAxis, vAxis) in faces {
            let us = stops(half: half[uAxis], radius: r, segments: segments)
            let vs = stops(half: half[vAxis], radius: r, segments: segments)
            let base = UInt32(mesh.positions.count)
            for (vi, v) in vs.enumerated() {
                for (ui, u) in us.enumerated() {
                    var point = SIMD3<Float>(repeating: 0)
                    point[axis] = half[axis] * sign
                    point[uAxis] = u
                    point[vAxis] = v
                    let core = SIMD3<Float>(min(max(point.x, -inner.x), inner.x), min(max(point.y, -inner.y), inner.y),
                                            min(max(point.z, -inner.z), inner.z))
                    var normal = SIMD3<Float>(repeating: 0)
                    normal[axis] = sign
                    normal = normalize3(point - core, fallback: normal)
                    let surface = core + normal * r + SIMD3<Float>(0, half.y, 0)
                    mesh.addVertex(surface, normal: normal, uv: SIMD2<Float>(Float(ui) / Float(us.count - 1), Float(vi) / Float(vs.count - 1)))
                }
            }
            let columns = UInt32(us.count)
            for row in 0 ..< UInt32(vs.count - 1) {
                for column in 0 ..< columns - 1 {
                    let a = base + row * columns + column
                    let b = a + 1
                    let c = a + columns + 1
                    let d = a + columns
                    mesh.addTriangle(a, b, c)
                    mesh.addTriangle(a, c, d)
                }
            }
        }
        return mesh
    }

    /// One ring of a lathe profile: radius, height and the profile normal (radial, vertical).
    struct ProfilePoint {
        var radius: Float
        var height: Float
        var normalRadial: Float
        var normalUp: Float
    }

    /// A cylinder (or cone) with rounded rims: flat caps, the rim arcs and the side are revolved around Y.
    static func lathe(size: SIMD3<Float>, radius: Float, segments: Int, cone: Bool) -> MeshData {
        let height: Float = 1
        let outer: Float = 0.5
        // Built in unit space (radius 0.5, height 1), bevel expressed in unit space along the smallest scale.
        let scale = min(size.x, min(size.y, size.z))
        let r = min(radius / max(scale, 1e-3), cone ? 0.2 : 0.45)
        var profile: [ProfilePoint] = []
        let sideAngle: Float = cone ? atan2(outer, height) : 0 // tilt of the side normal from horizontal
        // Bottom rim arc: from straight down to the side normal.
        let bottomCenter = SIMD2<Float>(outer - r, r)
        for index in 0 ... segments {
            let t = Float(index) / Float(segments)
            let angle = -Float.pi / 2 + (Float.pi / 2 + sideAngle) * t
            profile.append(ProfilePoint(radius: bottomCenter.x + cos(angle) * r, height: bottomCenter.y + sin(angle) * r,
                                        normalRadial: cos(angle), normalUp: sin(angle)))
        }
        if cone {
            profile.append(ProfilePoint(radius: 0, height: height, normalRadial: cos(sideAngle), normalUp: sin(sideAngle)))
        } else {
            let topCenter = SIMD2<Float>(outer - r, height - r)
            for index in 0 ... segments {
                let angle = Float.pi / 2 * Float(index) / Float(segments)
                profile.append(ProfilePoint(radius: topCenter.x + cos(angle) * r, height: topCenter.y + sin(angle) * r,
                                            normalRadial: cos(angle), normalUp: sin(angle)))
            }
        }
        var mesh = revolve(profile, sides: 32)
        mesh.append(cap(radius: outer - r, height: 0, up: false, sides: 32))
        if !cone { mesh.append(cap(radius: outer - r, height: height, up: true, sides: 32)) }
        // Unit space → real size; normals follow the inverse scale.
        mesh.positions = mesh.positions.map { SIMD3<Float>($0.x * size.x, $0.y * size.y, $0.z * size.z) }
        mesh.normals = mesh.normals.map { normalize3(SIMD3<Float>($0.x / size.x, $0.y / size.y, $0.z / size.z), fallback: $0) }
        return mesh
    }

    static func revolve(_ profile: [ProfilePoint], sides: Int) -> MeshData {
        var mesh = MeshData()
        for (ring, point) in profile.enumerated() {
            for side in 0 ... sides {
                let angle = Float(side) / Float(sides) * 2 * Float.pi
                let radial = SIMD2<Float>(sin(angle), cos(angle))
                mesh.addVertex(SIMD3<Float>(radial.x * point.radius, point.height, radial.y * point.radius),
                               normal: SIMD3<Float>(radial.x * point.normalRadial, point.normalUp, radial.y * point.normalRadial),
                               uv: SIMD2<Float>(Float(side) / Float(sides), Float(ring) / Float(max(profile.count - 1, 1))))
            }
        }
        let stride = UInt32(sides + 1)
        for ring in 0 ..< UInt32(profile.count - 1) {
            for side in 0 ..< UInt32(sides) {
                let a = ring * stride + side
                let b = a + 1
                let c = a + stride + 1
                let d = a + stride
                mesh.addTriangle(a, b, c)
                mesh.addTriangle(a, c, d)
            }
        }
        return mesh
    }

    static func cap(radius: Float, height: Float, up: Bool, sides: Int) -> MeshData {
        var mesh = MeshData()
        let normal = SIMD3<Float>(0, up ? 1 : -1, 0)
        let center = mesh.addVertex(SIMD3<Float>(0, height, 0), normal: normal, uv: SIMD2<Float>(0.5, 0.5))
        for side in 0 ... sides {
            let angle = Float(side) / Float(sides) * 2 * Float.pi
            mesh.addVertex(SIMD3<Float>(sin(angle) * radius, height, cos(angle) * radius), normal: normal,
                           uv: SIMD2<Float>(0.5 + sin(angle) / 2, 0.5 + cos(angle) / 2))
        }
        for side in 0 ..< UInt32(sides) {
            if up {
                mesh.addTriangle(center, center + side + 1, center + side + 2)
            } else {
                mesh.addTriangle(center, center + side + 2, center + side + 1)
            }
        }
        return mesh
    }
}
