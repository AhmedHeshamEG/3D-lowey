import Foundation
import LoweyCore

/// Moving, turning and sizing (gizmo, fingers, joystick, inspector numbers), snapping when a move ends, and the
/// Euler numbers the inspector shows.
extension EditorModel {
    func translateSelection(by delta: Vec3, gesture: String) {
        perform(operations.translate(selection, by: delta, in: scene), coalesceKey: gesture)
    }

    /// Turns the selection around a world axis through `pivot` (default: `rotationPivot`, fixed for the whole gesture).
    func rotateSelection(by angle: Double, axis: CoreAxis, around pivot: Vec3? = nil, gesture: String) {
        guard let pivot = pivot ?? rotationPivot, abs(angle) > 1e-9 else { return }
        perform(operations.rotate(selection, by: Quat(angle: angle, axis: axis.unit), around: pivot, in: scene), coalesceKey: gesture)
    }

    func scaleSelection(by factor: Vec3, gesture: String) {
        guard let pivot = selectionPivot else { return }
        perform(operations.scale(selection, by: factor, around: pivot, in: scene), coalesceKey: gesture)
    }

    /// The end of a move: grid, flush against neighbours, onto the ground.
    func finishTransform(gesture: String) {
        refreshOperationsLibrary()
        if let bounds = selectionBounds {
            let correction = snapCorrection(for: bounds)
            if correction.lengthSquared > 1e-10 { perform(operations.translate(selection, by: correction, in: scene), coalesceKey: gesture) }
        }
        endGesture()
    }

    private func snapCorrection(for bounds: Bounds) -> Vec3 {
        var correction = Vec3.zero
        if snap.grid {
            let pivot = Vec3(bounds.center.x, bounds.min.y, bounds.center.z)
            correction = Snapping.snapToGrid(pivot, size: snap.gridSize) - pivot
            correction.y = 0
        }
        if snap.objects {
            let moved = Bounds(min: bounds.min + correction, max: bounds.max + correction)
            let others = baseScene.roots.filter { !selection.contains($0) }.compactMap { stage?.visualBounds(of: [$0]) }
            correction += Snapping.objectSnapOffset(moving: moved, others: others, threshold: snap.objectThreshold)
        }
        if snap.ground, abs(bounds.min.y + correction.y) < snap.objectThreshold {
            correction.y = -bounds.min.y
        }
        return correction
    }

    func snapRotation(gesture: String) {
        guard snap.rotation else {
            endGesture()
            return
        }
        let changes = selectedObjects.map { object in
            let euler = object.transform.rotation.eulerDegrees
            let snapped = Vec3(Snapping.snapAngle(euler.x, step: snap.rotationStep), Snapping.snapAngle(euler.y, step: snap.rotationStep),
                               Snapping.snapAngle(euler.z, step: snap.rotationStep))
            return PropertyChange(object: object.id, key: .rotation, value: .quat(Quat(eulerDegrees: snapped)))
        }
        perform(.setProperties(changes), coalesceKey: gesture)
        endGesture()
    }

    func setTransform(_ id: ObjectID, _ transform: CoreTransform) {
        perform(operations.setTransform(id, transform))
    }

    // MARK: Rotation numbers

    /// The Euler angles last typed or shown per object. A rotation has many Euler spellings (X 100° is also X 80°,
    /// Y 180°, Z 180°); showing the one you typed keeps the numbers from jumping around.
    func eulerDegrees(of object: SceneObject) -> Vec3 {
        let rotation = object.transform.rotation
        if let remembered = eulerMemory[object.id], Quat(eulerDegrees: remembered).isApproximately(rotation, tolerance: 1e-7) {
            return remembered
        }
        var euler = rotation.eulerDegrees
        if let remembered = eulerMemory[object.id] {
            let alternative = Vec3(180 - euler.x, euler.y + 180, euler.z + 180).map(Self.wrapDegrees)
            if alternative.distance(to: remembered) < euler.distance(to: remembered) { euler = alternative }
        }
        let rounded = euler.map { ($0 * 1000).rounded() / 1000 }
        eulerMemory[object.id] = rounded
        return rounded
    }

    func setEulerDegrees(_ euler: Vec3, of id: ObjectID) {
        guard var transform = scene.objects[id]?.transform else { return }
        eulerMemory[id] = euler
        transform.rotation = Quat(eulerDegrees: euler)
        setTransform(id, transform)
    }

    static func wrapDegrees(_ value: Double) -> Double {
        var angle = value.truncatingRemainder(dividingBy: 360)
        if angle > 180 { angle -= 360 }
        if angle <= -180 { angle += 360 }
        return angle
    }
}
