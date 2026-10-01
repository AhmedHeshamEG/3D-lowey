import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// Two fingers: pan and pinch-zoom the view; on the selection, twist turns it and pinch sizes it; on a selected overlay,
/// pinch and twist size and turn it; in the Director view they truck, dolly and roll the shot camera; while performing,
/// they turn and size what you perform.
extension StageGestures {
    /// Whether this two-finger gesture holds the selection (decided once, where the fingers first land).
    func onSelection(_ recognizer: UIGestureRecognizer) -> Bool {
        let id = ObjectIdentifier(recognizer)
        switch recognizer.state {
        case .began:
            twoFingerActive.insert(id)
            if twoFingerOnSelection == nil { twoFingerOnSelection = touchesSelection(at: recognizer.location(in: stage)) }
        case .ended, .cancelled, .failed:
            twoFingerActive.remove(id)
        default:
            break
        }
        let result = twoFingerOnSelection ?? false
        if twoFingerActive.isEmpty, recognizer.state != .began, recognizer.state != .changed {
            twoFingerOnSelection = nil
            twoFingerRotation = nil
        }
        return result
    }

    /// Two fingers on a selected, unlocked object (Select tool): they hold the object, not the camera.
    private func touchesSelection(at point: CGPoint) -> Bool {
        guard let editor, let stage, editor.tool == .select, !editor.selection.isEmpty, editor.performPhase == .idle, !operatesCamera,
              editor.selectedOverlay == nil, !editor.selection.contains(where: { editor.scene.isEffectivelyLocked($0) }),
              let (id, _) = stage.pickObject(at: point) else { return false }
        return editor.selection.contains { $0 == id || editor.scene.isAncestor($0, of: id) }
    }

    @objc func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        guard let stage else { return }
        if onSelection(recognizer) {
            recognizer.setTranslation(.zero, in: stage)
            return
        }
        let translation = recognizer.translation(in: stage)
        recognizer.setTranslation(.zero, in: stage)
        if operatesCamera, let editor {
            if recognizer.state == .began { panKey = UUID().uuidString }
            if recognizer.state == .ended || recognizer.state == .cancelled { editor.endGesture() }
            // Truck and pedestal in the camera's own frame.
            let step = 0.01 * navigationSpeed
            editor.moveCamera(local: Vec3(-Double(translation.x) * step, Double(translation.y) * step, 0), gesture: panKey)
            return
        }
        guard recognizer.state == .changed || recognizer.state == .began else { return }
        var viewpoint = stage.viewpoint
        // 1× keeps the ground under the fingers.
        let metresPerPoint = 2 * viewpoint.distance * tan(viewpoint.fieldOfView * .pi / 360) / Double(max(stage.bounds.height, 1)) * navigationSpeed
        viewpoint.target -= viewpoint.rotation.act(.unitX) * (Double(translation.x) * metresPerPoint)
        viewpoint.target += viewpoint.rotation.act(.unitY) * (Double(translation.y) * metresPerPoint)
        stage.setViewpoint(viewpoint)
    }

    @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let holdsSelection = onSelection(recognizer)
        defer { recognizer.scale = 1 }
        guard let editor, let stage else { return }
        if isRecordingPerform {
            switch recognizer.state {
            case .began: editor.performTouchBegan([.scale])
            case .changed: editor.performScale(by: Double(recognizer.scale))
            default: editor.performTouchEnded()
            }
            return
        }
        if recognizer.state == .began { pinchKey = UUID().uuidString }
        let ended = recognizer.state == .ended || recognizer.state == .cancelled
        if let overlay = editor.selectedOverlay {
            if ended { editor.endGesture() } else { editor.scaleOverlay(overlay, by: Double(recognizer.scale), gesture: pinchKey) }
        } else if holdsSelection {
            // Pinch on the object: it grows or shrinks from its base.
            let factor = min(max(Double(recognizer.scale), 0.5), 2)
            if ended { editor.finishTransform(gesture: pinchKey) } else if abs(factor - 1) > 1e-4 {
                editor.scaleSelection(by: Vec3(factor, factor, factor), gesture: pinchKey)
            }
        } else if operatesCamera {
            // Dolly: pinching out moves the camera forward.
            if ended { editor.endGesture() } else {
                editor.moveCamera(local: Vec3(0, 0, -Double(recognizer.scale - 1) * 3 * navigationSpeed), gesture: pinchKey)
            }
        } else if recognizer.state == .changed || recognizer.state == .began {
            var viewpoint = stage.viewpoint
            viewpoint.distance /= pow(Double(max(recognizer.scale, 0.01)), navigationSpeed)
            stage.setViewpoint(viewpoint)
        }
    }

    @objc func handleTwist(_ recognizer: UIRotationGestureRecognizer) {
        guard let editor else { return }
        let holdsSelection = onSelection(recognizer)
        defer { recognizer.rotation = 0 }
        if isRecordingPerform {
            switch recognizer.state {
            case .began: editor.performTouchBegan([.rotation])
            case .changed: editor.performRotate(by: -Double(recognizer.rotation))
            default: editor.performTouchEnded()
            }
            return
        }
        if recognizer.state == .began { twistKey = UUID().uuidString }
        let ended = recognizer.state == .ended || recognizer.state == .cancelled
        if let overlay = editor.selectedOverlay {
            if ended { editor.endGesture() } else { editor.rotateOverlay(overlay, by: -Double(recognizer.rotation), gesture: twistKey) }
        } else if operatesCamera {
            if ended { editor.endGesture() } else { editor.rollCamera(by: Double(recognizer.rotation), gesture: twistKey) }
        } else if holdsSelection {
            twistSelection(recognizer, editor: editor)
        }
    }

    /// Fingers turning clockwise on screen turn the object clockwise seen from above (snapping in steps when on).
    private func twistSelection(_ recognizer: UIRotationGestureRecognizer, editor: EditorModel) {
        switch recognizer.state {
        case .began:
            twoFingerRotation = editor.rotationPivot.map { (pivot: $0, total: 0.0, applied: 0.0) }
        case .changed:
            guard var turn = twoFingerRotation else { return }
            turn.total -= Double(recognizer.rotation)
            let step = editor.snap.rotation ? editor.snap.rotationStep * .pi / 180 : 0
            let wanted = step > 0 ? (turn.total / step).rounded() * step : turn.total
            if abs(wanted - turn.applied) > 1e-9 {
                editor.rotateSelection(by: wanted - turn.applied, axis: .y, around: turn.pivot, gesture: twistKey)
                if step > 0 { HmmHaptics.play(.selection) }
                turn.applied = wanted
            }
            twoFingerRotation = turn
        default:
            editor.endGesture()
            twoFingerRotation = nil
        }
    }
}
