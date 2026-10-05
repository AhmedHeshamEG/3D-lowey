import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// One finger: orbit, or (decided where it lands) move the selection, a gizmo handle, a rotate ring, a lasso, a
/// scatter area, a performance, the Director view's camera or an overlay in the frame.
extension StageGestures {
    @objc func handleOneFingerPan(_ recognizer: UIPanGestureRecognizer) {
        guard let editor, let stage else { return }
        let point = recognizer.location(in: stage)
        switch recognizer.state {
        case .began:
            gestureKey = UUID().uuidString
            editor.showChrome()
            let translation = recognizer.translation(in: stage)
            drag = beginDrag(at: CGPoint(x: point.x - translation.x, y: point.y - translation.y), editor: editor, stage: stage)
            continueDrag(to: point, translation: translation, editor: editor, stage: stage)
            recognizer.setTranslation(.zero, in: stage)
        case .changed:
            continueDrag(to: point, translation: recognizer.translation(in: stage), editor: editor, stage: stage)
            recognizer.setTranslation(.zero, in: stage)
        case .ended, .cancelled, .failed:
            endDrag(editor: editor, stage: stage, cancelled: recognizer.state != .ended)
            drag = .none
        default:
            break
        }
    }

    private func groundHit(at point: CGPoint, planeY: Double, stage: StageView) -> Vec3? {
        guard let ray = stage.worldRay(at: point) else { return nil }
        return GuideSurface.plane(origin: Vec3(0, planeY, 0), normal: .unitY).intersect(ray)?.point
    }

    private func beginDrag(at point: CGPoint, editor: EditorModel, stage: StageView) -> DragKind {
        if isRecordingPerform {
            let planeY = editor.selectionPivot?.y ?? 0
            editor.performTouchBegan([.position])
            return .perform(planeY: planeY, last: groundHit(at: point, planeY: planeY, stage: stage) ?? .zero)
        }
        if let overlay = editor.selectedOverlay, editor.overlayHit(at: point) == overlay { return .moveOverlay(overlay, last: point) }
        if operatesCamera { return .aimCamera }
        switch editor.tool {
        case .lasso:
            editor.lassoPoints = [point]
            return .lasso
        case .scatter:
            guard !editor.selection.isEmpty, let center = stage.groundPoint(at: point) else { return .orbit }
            editor.scatterPreview = (point, 0)
            return .scatter(center: center)
        case .ink, .draw, .shadowBrush, .flipbook:
            return .orbit
        case .model:
            return beginModelDrag(at: point, editor: editor)
        case .select:
            return beginSelectDrag(at: point, editor: editor, stage: stage)
        }
    }

    private func beginSelectDrag(at point: CGPoint, editor: EditorModel, stage: StageView) -> DragKind {
        guard !editor.directorView else { return .orbit }
        if let handle = editor.ikHandle(at: point) { return .ik(handle) }
        if let time = editor.motionPathKey(at: point) {
            editor.setTime(time)
            return .pathKey(time: time)
        }
        if editor.gizmoMode == .rotate, let (axis, grab) = stage.pickRotationRing(at: point), let pivot = editor.rotationPivot,
           let ring = ringDrag(axis: axis, pivot: pivot, grab: grab, start: point, stage: stage) {
            return .turn(ring)
        }
        if editor.gizmoMode != .rotate, let handle = stage.pickGizmo(at: point), let pivot = editor.selectionPivot {
            return .gizmo(handle, pivot: pivot, lastPoint: point, accumulated: 0)
        }
        if let (id, hit) = stage.pickObject(at: point), editor.selection.contains(where: { $0 == id || editor.scene.isAncestor($0, of: id) }),
           !editor.selection.contains(where: { editor.scene.isEffectivelyLocked($0) }) {
            let planeY = editor.selectionPivot?.y ?? hit.point.y
            return .moveObjects(planeY: planeY, last: groundHit(at: point, planeY: planeY, stage: stage) ?? hit.point)
        }
        return .orbit
    }

    private func continueDrag(to point: CGPoint, translation: CGPoint, editor: EditorModel, stage: StageView) {
        switch drag {
        case .orbit:
            var viewpoint = stage.viewpoint
            let degreesPerPoint = 0.3 * navigationSpeed
            viewpoint.yaw -= Double(translation.x) * degreesPerPoint
            viewpoint.pitch += Double(translation.y) * degreesPerPoint
            stage.setViewpoint(viewpoint)
        case let .moveObjects(planeY, last):
            guard let hit = groundHit(at: point, planeY: planeY, stage: stage) else { return }
            var delta = hit - last
            delta.y = 0
            // Rays near the horizon jump huge distances: ignore them.
            guard delta.length <= 20 else { return }
            editor.translateSelection(by: delta, gesture: gestureKey)
            drag = .moveObjects(planeY: planeY, last: hit)
        case let .gizmo(handle, pivot, lastPoint, accumulated):
            continueGizmo(handle, pivot: pivot, from: lastPoint, to: point, accumulated: accumulated, editor: editor, stage: stage)
        case var .turn(ring):
            ring.total = ringAngle(ring, at: point, stage: stage)
            let step = editor.snap.rotation ? editor.snap.rotationStep * .pi / 180 : 0
            let wanted = step > 0 ? (ring.total / step).rounded() * step : ring.total
            if abs(wanted - ring.applied) > 1e-9 {
                editor.rotateSelection(by: wanted - ring.applied, axis: ring.axis, around: ring.pivot, gesture: gestureKey)
                if step > 0 { HmmHaptics.play(.selection) }
                ring.applied = wanted
            }
            drag = .turn(ring)
        case .lasso:
            if let last = editor.lassoPoints.last, hypot(last.x - point.x, last.y - point.y) > 4 { editor.lassoPoints.append(point) }
        case let .scatter(center):
            continueScatter(center: center, at: point, editor: editor, stage: stage)
        case let .perform(planeY, last):
            guard let hit = groundHit(at: point, planeY: planeY, stage: stage) else { return }
            var delta = hit - last
            delta.y = 0
            guard delta.length <= 20 else { return }
            editor.performMove(by: delta)
            drag = .perform(planeY: planeY, last: hit)
        case .aimCamera:
            editor.aimCamera(pan: -Double(translation.x) * 0.15 * navigationSpeed, tilt: -Double(translation.y) * 0.15 * navigationSpeed,
                             gesture: gestureKey)
        case let .moveOverlay(id, last):
            editor.moveOverlay(id, by: CGSize(width: point.x - last.x, height: point.y - last.y), gesture: gestureKey)
            drag = .moveOverlay(id, last: point)
        case let .pathKey(time):
            editor.moveMotionPathKey(at: time, to: point, gesture: gestureKey)
        case let .ik(handle):
            editor.dragIK(handle, to: point, gesture: gestureKey)
        case let .pushPull(axis, grab):
            if let along = editor.pullDistance(at: point, axis: axis) { editor.updatePull(along - grab, axis: axis) }
        case .modelLasso:
            if let last = editor.lassoPoints.last, hypot(last.x - point.x, last.y - point.y) > 4 { editor.lassoPoints.append(point) }
        case .none:
            break
        }
    }

    /// With the Model tool: a drag on the picked face or region pulls it; a Pencil loops in a pick mode; else orbit.
    private func beginModelDrag(at point: CGPoint, editor: EditorModel) -> DragKind {
        if editor.canPull(at: point), editor.prepareFacePull(), let axis = editor.pullAxis {
            return .pushPull(axis, grab: editor.pullDistance(at: point, axis: axis) ?? 0)
        }
        if panTouchIsPencil, editor.modeling.mode.pickMode != nil {
            editor.lassoPoints = [point]
            return .modelLasso
        }
        return .orbit
    }

    private func continueGizmo(_ handle: GizmoHandle, pivot: Vec3, from lastPoint: CGPoint, to point: CGPoint, accumulated: Double,
                               editor: EditorModel, stage: StageView) {
        let result = gizmoDelta(handle: handle, pivot: pivot, from: lastPoint, to: point, stage: stage)
        switch handle.kind {
        case .move:
            // With grid snapping, the object jumps cell by cell while the finger moves freely.
            let total = accumulated + result
            var step = result
            if editor.snap.grid {
                step = Snapping.snapToGrid(total, size: editor.snap.gridSize) - Snapping.snapToGrid(accumulated, size: editor.snap.gridSize)
            }
            if step != 0 { editor.translateSelection(by: handle.axis.unit * step, gesture: gestureKey) }
            drag = .gizmo(handle, pivot: pivot + handle.axis.unit * step, lastPoint: point, accumulated: total)
        case .scale:
            var vector = Vec3.one
            vector[handle.axis] = max(0.2, 1 + result)
            editor.scaleSelection(by: vector, gesture: gestureKey)
            drag = .gizmo(handle, pivot: pivot, lastPoint: point, accumulated: accumulated)
        case .uniformScale:
            let factor = max(0.2, exp(-Double(point.y - lastPoint.y) * 0.006 + Double(point.x - lastPoint.x) * 0.006))
            editor.scaleSelection(by: Vec3(factor, factor, factor), gesture: gestureKey)
            drag = .gizmo(handle, pivot: pivot, lastPoint: point, accumulated: accumulated)
        case .rotate:
            break
        }
    }

    private func continueScatter(center: Vec3, at point: CGPoint, editor: EditorModel, stage: StageView) {
        guard let ground = stage.groundPoint(at: point, height: center.y), let centerScreen = stage.screenPoint(of: center) else { return }
        let radius = Vec3(ground.x - center.x, 0, ground.z - center.z).length
        let right = stage.viewpoint.rotation.act(.unitX)
        let edgeScreen = stage.screenPoint(of: center + Vec3(right.x, 0, right.z).normalized * radius) ?? point
        editor.scatterPreview = (centerScreen, hypot(edgeScreen.x - centerScreen.x, edgeScreen.y - centerScreen.y))
        scatterRadius = radius
    }

    private func endDrag(editor: EditorModel, stage: StageView, cancelled: Bool) {
        switch drag {
        case .moveObjects, .gizmo:
            editor.finishTransform(gesture: gestureKey)
        case .lasso:
            if !cancelled { selectInLasso(editor: editor, stage: stage) }
            editor.lassoPoints = []
        case let .scatter(center):
            editor.scatterPreview = nil
            if !cancelled, scatterRadius > 0.2 { editor.scatterSelection(center: center, radius: scatterRadius) }
            scatterRadius = 0
        case .perform:
            editor.performTouchEnded()
        case .pushPull:
            editor.endPull(commit: !cancelled)
        case .modelLasso:
            if !cancelled { editor.pickElements(inLoop: editor.lassoPoints) }
            editor.lassoPoints = []
        case .turn, .orbit, .aimCamera, .moveOverlay, .pathKey, .ik, .none:
            break
        }
        editor.endGesture()
    }
}
