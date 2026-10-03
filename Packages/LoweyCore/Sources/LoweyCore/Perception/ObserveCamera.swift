import Foundation

/// The pictures `observe` can return: the shot itself, three orthographic layout diagrams (how a model understands 3D
/// layout without guessing from one perspective image), the value "squint" and the subject's silhouette.
public enum ObserveView: String, Codable, Sendable, CaseIterable, Identifiable {
    case camera, top, front, side, value, silhouette

    public var id: String { rawValue }

    /// The diagrams drawn from an orthographic camera of their own.
    public var isDiagram: Bool { self == .top || self == .front || self == .side }
}

/// A point of the frame: normalised (0…1, top-left origin, y down) and how far in front of the camera it is.
public struct FramePoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var depth: Double
}

/// A camera as perception sees it: the shot camera (perspective), or a top / front / side diagram (orthographic).
public struct ObserveCamera: Hashable, Sendable {
    public var position: Vec3
    public var rotation: Quat
    /// Vertical field of view in degrees (perspective).
    public var fieldOfView: Double
    /// Visible height in metres (orthographic); nil for perspective.
    public var orthographicHeight: Double?
    /// Width ÷ height of the frame.
    public var aspect: Double
    public var near = 0.05

    public init(position: Vec3, rotation: Quat, fieldOfView: Double, orthographicHeight: Double? = nil, aspect: Double) {
        self.position = position
        self.rotation = rotation
        self.fieldOfView = fieldOfView
        self.orthographicHeight = orthographicHeight
        self.aspect = aspect
    }

    /// The shot at a moment, exactly as the export sees it: the cut's camera framed for `aspect` (portrait zoom and
    /// pan included), else the scene's saved view.
    public static func shot(_ animated: AnimatedScene, fallback: Viewpoint, aspect: Double) -> ObserveCamera {
        guard let id = animated.camera, let object = animated.scene.objects[id] else { return viewpoint(fallback, aspect: aspect) }
        let world = animated.scene.worldTransform(of: id)
        let framing = CameraLens(object).framing(aspect: aspect)
        let rotation = (world.rotation * Quat(angle: framing.yaw, axis: .unitY)).normalized
        return ObserveCamera(position: world.position, rotation: rotation, fieldOfView: framing.fieldOfView, aspect: aspect)
    }

    /// The editor's orbit view.
    public static func viewpoint(_ viewpoint: Viewpoint, aspect: Double) -> ObserveCamera {
        guard viewpoint.projection == .orthographic else {
            return ObserveCamera(position: viewpoint.eye, rotation: viewpoint.rotation, fieldOfView: viewpoint.fieldOfView, aspect: aspect)
        }
        let height = 2 * viewpoint.distance * tan(viewpoint.fieldOfView * .pi / 360)
        return ObserveCamera(position: viewpoint.eye, rotation: viewpoint.rotation, fieldOfView: viewpoint.fieldOfView,
                             orthographicHeight: height, aspect: aspect)
    }

    /// A layout diagram: from above (far side at the top of the picture), from the front (+z looking back) or from
    /// the right side (+x), fitting `box` with a margin.
    public static func diagram(_ view: ObserveView, fitting box: Bounds, aspect: Double) -> ObserveCamera {
        let size = box.size
        let (rotation, across, upward, depth): (Quat, Double, Double, Double) = switch view {
        case .top: (Quat(angle: -.pi / 2, axis: .unitX), size.x, size.z, size.y)
        case .side: (Quat(angle: .pi / 2, axis: .unitY), size.z, size.y, size.x)
        default: (.identity, size.x, size.y, size.z)
        }
        let height = max(upward, across / max(aspect, 1e-3), 0.5) * 1.15
        let back = rotation.act(Vec3(0, 0, 1))
        return ObserveCamera(position: box.center + back * (depth / 2 + 10), rotation: rotation, fieldOfView: 2,
                             orthographicHeight: height, aspect: aspect)
    }

    public var forward: Vec3 { rotation.act(Vec3(0, 0, -1)) }
    public var right: Vec3 { rotation.act(Vec3(1, 0, 0)) }
    public var up: Vec3 { rotation.act(Vec3(0, 1, 0)) }

    /// Camera space (looking down −z).
    public func local(_ point: Vec3) -> Vec3 { rotation.inverse.act(point - position) }

    /// Where a camera-space point lands (nil behind a perspective camera).
    public func project(local point: Vec3) -> FramePoint? {
        let depth = -point.z
        if let orthographicHeight {
            return FramePoint(x: 0.5 + point.x / (orthographicHeight * aspect), y: 0.5 - point.y / orthographicHeight, depth: depth)
        }
        guard depth > near * 0.5 else { return nil }
        let tanHalf = tan(fieldOfView * .pi / 360)
        return FramePoint(x: 0.5 + point.x / depth / (tanHalf * aspect) / 2, y: 0.5 - point.y / depth / tanHalf / 2, depth: depth)
    }

    public func project(_ point: Vec3) -> FramePoint? { project(local: local(point)) }

    /// Roll of the frame in degrees: how far the horizon tilts (positive: clockwise).
    public var roll: Double {
        let right = right
        return atan2(right.y, (right.x * right.x + right.z * right.z).squareRoot()) * 180 / .pi
    }
}
