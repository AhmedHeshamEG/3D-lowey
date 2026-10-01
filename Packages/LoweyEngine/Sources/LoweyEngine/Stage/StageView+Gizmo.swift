import LoweyCore
import UIKit

public extension StageView {
    /// The move or scale handle under a point: each handle is traced on screen and the nearest within `tolerance`
    /// points wins (the centre cube of the scale gizmo first).
    func pickGizmo(at point: CGPoint, tolerance: CGFloat = 24) -> GizmoHandle? {
        guard let pivot = gizmoCenter, gizmoMode != .rotate, let center = screenPoint(of: pivot) else { return nil }
        if gizmoMode == .scale, hypot(center.x - point.x, center.y - point.y) < tolerance * 0.9 {
            return GizmoHandle(kind: .uniformScale, axis: .y)
        }
        let reach = gizmoScale * 1.05
        var best: (CoreAxis, CGFloat)?
        for axis in CoreAxis.allCases {
            guard let end = screenPoint(of: pivot + axis.unit * reach) else { continue }
            let distance = Self.distance(from: point, toSegment: center, end)
            if distance < tolerance, distance < best?.1 ?? .infinity { best = (axis, distance) }
        }
        return best.map { GizmoHandle(kind: gizmoMode == .scale ? .scale : .move, axis: $0.0) }
    }

    /// The rotate ring under a point and the point of the ring you grabbed. Where rings cross, the half facing you
    /// wins, like grabbing a real one.
    func pickRotationRing(at point: CGPoint, tolerance: CGFloat = 28) -> (axis: CoreAxis, grab: Vec3)? {
        guard gizmoMode == .rotate, let center = gizmoCenter else { return nil }
        let radius = EditorScene.ringRadius * gizmoScale
        let eye = Vec3(camera.position)
        var best: (axis: CoreAxis, grab: Vec3, distance: CGFloat, front: Bool)?
        for axis in CoreAxis.allCases {
            let normal = axis.unit
            let u = (abs(normal.y) > 0.9 ? Vec3.unitX : Vec3.unitY).cross(normal).normalized
            let v = normal.cross(u)
            for index in 0 ..< 120 {
                let angle = Double(index) / 120 * 2 * .pi
                let world = center + (u * cos(angle) + v * sin(angle)) * radius
                guard let screen = screenPoint(of: world) else { continue }
                let distance = hypot(screen.x - point.x, screen.y - point.y)
                guard distance < tolerance else { continue }
                let front = (world - center).dot(eye - center) >= 0
                let better: Bool = if let current = best {
                    (front && !current.front) || (front == current.front && distance < current.distance)
                } else {
                    true
                }
                if better { best = (axis, world, distance, front) }
            }
        }
        return best.map { ($0.axis, $0.grab) }
    }

    internal static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1e-6 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
        return hypot(point.x - (a.x + dx * t), point.y - (a.y + dy * t))
    }
}
