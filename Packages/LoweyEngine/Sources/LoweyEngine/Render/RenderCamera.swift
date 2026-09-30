import CoreGraphics
import LoweyCore
import simd

/// Output aspect ratios of snapshots and videos.
public enum Framing: String, CaseIterable, Sendable, Identifiable, Codable {
    case landscape = "16:9"
    case portrait = "9:16"
    case square = "1:1"

    public var id: String { rawValue }

    /// Pixel size with the long side = `longSide` (always even, as encoders need).
    public func pixelSize(longSide: Int) -> (width: Int, height: Int) {
        let even = { (value: Int) in value - value % 2 }
        let short = even(Int((Double(longSide) * 9 / 16).rounded()))
        switch self {
        case .landscape: return (even(longSide), short)
        case .portrait: return (short, even(longSide))
        case .square: return (even(longSide), even(longSide))
        }
    }

    public var aspect: Double {
        switch self {
        case .landscape: 16.0 / 9.0
        case .portrait: 9.0 / 16.0
        case .square: 1
        }
    }

    /// The frame drawn over the stage for this framing (what you see is what you export).
    public func guideRect(in size: CGSize) -> CGRect {
        let target = CGFloat(aspect)
        var width = size.width * 0.86
        var height = width / target
        if height > size.height * 0.8 {
            height = size.height * 0.8
            width = height * target
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}

/// A camera as the renderer sees it: where, which way, how wide. Reverse-Z projection (depth 1 at the near plane,
/// 0 at the far plane) for precision across big sets.
public struct RenderCamera: Sendable, Hashable {
    public var position: SIMD3<Float>
    public var orientation: simd_quatf
    /// Vertical field of view in degrees.
    public var fieldOfView: Float
    public var near: Float
    public var far: Float

    public init(position: SIMD3<Float>, orientation: simd_quatf, fieldOfView: Float, near: Float = 0.02, far: Float = 3000) {
        self.position = position
        self.orientation = orientation
        self.fieldOfView = fieldOfView
        self.near = near
        self.far = far
    }

    /// Orthographic views are an extreme telephoto (2° from far away): it looks orthographic and keeps one code
    /// path for picking, projection and export (D19).
    public static let orthographicFieldOfView = 2.0

    public static func pose(for viewpoint: Viewpoint) -> (eye: Vec3, rotation: Quat, fieldOfView: Double) {
        guard viewpoint.projection == .orthographic else { return (viewpoint.eye, viewpoint.rotation, viewpoint.fieldOfView) }
        let visibleHeight = 2 * viewpoint.distance * tan(viewpoint.fieldOfView * .pi / 360)
        var far = viewpoint
        far.distance = visibleHeight / (2 * tan(orthographicFieldOfView * .pi / 360))
        return (far.eye, viewpoint.rotation, orthographicFieldOfView)
    }

    /// The editor's orbit camera.
    public init(viewpoint: Viewpoint) {
        let pose = Self.pose(for: viewpoint)
        self.init(position: pose.eye.float3, orientation: pose.rotation.simd, fieldOfView: Float(pose.fieldOfView),
                  near: viewpoint.projection == .orthographic ? 1 : 0.02, far: viewpoint.projection == .orthographic ? 60000 : 3000)
    }

    /// The shot at a moment: the cut's camera (framed for `aspect`), else the scene's saved view.
    public static func shot(_ id: ObjectID?, in scene: LoweyCore.Scene, fallback: Viewpoint, aspect: Double) -> RenderCamera {
        guard let id, let object = scene.objects[id] else { return RenderCamera(viewpoint: fallback) }
        let world = scene.worldTransform(of: id)
        let framing = CameraLens(object).framing(aspect: aspect)
        let rotation = (world.rotation * Quat(angle: framing.yaw, axis: .unitY)).normalized
        return RenderCamera(position: world.position.float3, orientation: rotation.simd, fieldOfView: Float(framing.fieldOfView))
    }

    public var forward: SIMD3<Float> { orientation.act(SIMD3<Float>(0, 0, -1)) }

    public var viewMatrix: simd_float4x4 {
        let rotation = simd_float4x4(orientation.inverse)
        var translation = matrix_identity_float4x4
        translation.columns.3 = SIMD4<Float>(-position, 1)
        return rotation * translation
    }

    /// Reverse-Z perspective, right-handed, looking down −Z.
    public func projection(aspect: Float) -> simd_float4x4 {
        let f = 1 / tan(fieldOfView * .pi / 360)
        let range = far - near
        return simd_float4x4(columns: (
            SIMD4<Float>(f / max(aspect, 1e-4), 0, 0, 0),
            SIMD4<Float>(0, f, 0, 0),
            SIMD4<Float>(0, 0, near / range, -1),
            SIMD4<Float>(0, 0, far * near / range, 0)
        ))
    }

    /// World-space ray through a point of a view of `size` (points, y down).
    public func ray(through point: CGPoint, in size: CGSize) -> Ray {
        let aspect = Double(size.width / max(size.height, 1))
        let tanHalf = tan(Double(fieldOfView) * .pi / 360)
        let x = (Double(point.x / max(size.width, 1)) * 2 - 1) * tanHalf * aspect
        let y = (1 - Double(point.y / max(size.height, 1)) * 2) * tanHalf
        let direction = orientation.act(normalize(SIMD3<Float>(Float(x), Float(y), -1)))
        return Ray(origin: Vec3(position), direction: Vec3(direction).normalized)
    }

    /// Where a world point lands in a view of `size` (nil when it's behind the camera).
    public func project(_ world: Vec3, in size: CGSize) -> CGPoint? {
        let local = orientation.inverse.act(world.float3 - position)
        guard local.z < -1e-5 else { return nil }
        let tanHalf = tan(fieldOfView * .pi / 360)
        let aspect = Float(size.width / max(size.height, 1))
        let ndcX = local.x / -local.z / (tanHalf * aspect)
        let ndcY = local.y / -local.z / tanHalf
        return CGPoint(x: CGFloat((ndcX + 1) / 2) * size.width, y: CGFloat((1 - ndcY) / 2) * size.height)
    }
}

public extension Quat {
    var simd: simd_quatf { simd_quatf(ix: Float(x), iy: Float(y), iz: Float(z), r: Float(w)) }

    init(_ quaternion: simd_quatf) {
        self.init(x: Double(quaternion.imag.x), y: Double(quaternion.imag.y), z: Double(quaternion.imag.z), w: Double(quaternion.real))
    }
}

public extension LoweyCore.Transform {
    /// Column-major model matrix (translation × rotation × scale).
    var matrix: simd_float4x4 {
        var result = simd_float4x4(rotation.simd)
        result.columns.0 *= Float(scale.x)
        result.columns.1 *= Float(scale.y)
        result.columns.2 *= Float(scale.z)
        result.columns.3 = SIMD4<Float>(position.float3, 1)
        return result
    }
}

extension simd_float4x4 {
    /// The inverse transpose of the upper 3×3 (for normals under non-uniform scale).
    var normalMatrix: simd_float4x4 {
        let upper = simd_float3x3(SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z), SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z),
                                  SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z))
        let inverseTranspose = upper.determinant.magnitude > 1e-12 ? upper.inverse.transpose : upper
        return simd_float4x4(columns: (SIMD4<Float>(inverseTranspose.columns.0, 0), SIMD4<Float>(inverseTranspose.columns.1, 0),
                                       SIMD4<Float>(inverseTranspose.columns.2, 0), SIMD4<Float>(0, 0, 0, 1)))
    }
}
