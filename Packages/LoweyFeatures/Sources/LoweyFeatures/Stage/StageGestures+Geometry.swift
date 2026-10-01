import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// Screen geometry of the gizmo: dragging along a handle, turning a ring, and the lasso.
extension StageGestures {
    func ringDrag(axis: CoreAxis, pivot: Vec3, grab: Vec3, start: CGPoint, stage: StageView) -> RingDrag? {
        guard let center = stage.screenPoint(of: pivot), let grabScreen = stage.screenPoint(of: grab) else { return nil }
        // Turning forwards (right-hand rule about the axis) moves the grabbed point along axis × (grab − pivot).
        let arm = grab - pivot
        let forward = axis.unit.cross(arm).normalized
        guard let ahead = stage.screenPoint(of: grab + forward * max(arm.length * 0.05, 1e-3)) else { return nil }
        var tangent = CGVector(dx: ahead.x - grabScreen.x, dy: ahead.y - grabScreen.y)
        let length = hypot(tangent.dx, tangent.dy)
        guard length > 1e-6 else { return nil }
        tangent = CGVector(dx: tangent.dx / length, dy: tangent.dy / length)
        let facing = abs(axis.unit.dot((Vec3(stage.camera.position) - pivot).normalized))
        let radius = max(hypot(grabScreen.x - center.x, grabScreen.y - center.y), 30)
        return RingDrag(axis: axis, pivot: pivot, start: start, tangent: tangent, radius: radius, circular: facing > 0.45)
    }

    /// How far the ring has turned (radians) with the finger at `point`.
    func ringAngle(_ ring: RingDrag, at point: CGPoint, stage: StageView) -> Double {
        if ring.circular, let center = stage.screenPoint(of: ring.pivot) {
            // Face-on: the angle swept around the pivot on screen, unwrapped so several turns add up.
            let a0 = atan2(Double(ring.start.y - center.y), Double(ring.start.x - center.x))
            let a1 = atan2(Double(point.y - center.y), Double(point.x - center.x))
            let toCamera = (Vec3(stage.camera.position) - ring.pivot).normalized
            let swept = (a1 - a0) * (ring.axis.unit.dot(toCamera) > 0 ? -1 : 1)
            let turns = ((ring.total - swept) / (2 * .pi)).rounded()
            return swept + turns * 2 * .pi
        }
        // Edge-on: slide along the ring where it was grabbed; one ring radius of travel is one radian.
        let moved = Double((point.x - ring.start.x) * ring.tangent.dx + (point.y - ring.start.y) * ring.tangent.dy)
        return moved / Double(ring.radius)
    }

    /// A screen drag as movement along a handle (metres) or a size change (relative).
    func gizmoDelta(handle: GizmoHandle, pivot: Vec3, from: CGPoint, to: CGPoint, stage: StageView) -> Double {
        guard handle.kind == .move || handle.kind == .scale, let p0 = stage.screenPoint(of: pivot) else { return 0 }
        let reach = max(stage.gizmoScale, 0.05)
        guard let p1 = stage.screenPoint(of: pivot + handle.axis.unit * reach) else { return 0 }
        let axisScreen = CGVector(dx: p1.x - p0.x, dy: p1.y - p0.y)
        let pixels = hypot(axisScreen.dx, axisScreen.dy)
        guard pixels > 2 else { return 0 }
        let moved = Double((to.x - from.x) * axisScreen.dx / pixels + (to.y - from.y) * axisScreen.dy / pixels)
        // Scale: dragging one gizmo length doubles the size.
        return handle.kind == .scale ? moved / Double(pixels) : moved * reach / Double(pixels)
    }

    /// Selects what the lasso loop encloses (by the centre of each thing, top-level first).
    func selectInLasso(editor: EditorModel, stage: StageView) {
        let polygon = editor.lassoPoints
        guard polygon.count >= 3 else { return }
        var hits: [ObjectID] = []
        for id in editor.scene.orderedIDs() {
            guard let object = editor.scene.objects[id], editor.scene.isEffectivelyVisible(id),
                  !(object.parent.map(hits.contains) ?? false),
                  let bounds = stage.visualBounds(of: [id]), let screen = stage.screenPoint(of: bounds.center) else { continue }
            if Self.contains(polygon, screen), !hits.contains(where: { editor.scene.isAncestor($0, of: id) }) { hits.append(id) }
        }
        editor.setSelection(hits)
        if !hits.isEmpty { HmmHaptics.play(.selection) }
    }

    static func contains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
