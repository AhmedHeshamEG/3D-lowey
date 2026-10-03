import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// The Pencil on ink strokes: the eraser, and picking strokes (tap or loop) then dragging them.
extension StageGestures {
    func inkEditStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) {
        let samples = recognizer.samples
        switch recognizer.state {
        case .began:
            gestureKey = UUID().uuidString
            consumedSamples = 0
            inkPath = []
            inkDragLast = nil
            if editor.ink.mode == .select, let first = samples.first?.location, editor.isOnPickedStroke(first) {
                inkDragLast = first
            }
            inkEditContinue(Array(samples), editor: editor, stage: stage)
        case .changed:
            inkEditContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), editor: editor, stage: stage)
        case .ended:
            if editor.ink.mode == .select, inkDragLast == nil { editor.selectInkStrokes(path: inkPath) }
            inkEditFinish(editor: editor)
        default:
            inkEditFinish(editor: editor)
        }
    }

    private func inkEditContinue(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel, stage: StageView) {
        consumedSamples += samples.count
        let points = samples.map(\.location)
        inkPath += points
        switch editor.ink.mode {
        case .erase:
            editor.eraseInk(at: points, gesture: gestureKey)
        case .select:
            if let last = inkDragLast, let current = points.last {
                dragInkStrokes(from: last, to: current, editor: editor, stage: stage)
                inkDragLast = current
            } else {
                editor.lassoPoints = inkPath
            }
        case .draw:
            break
        }
    }

    private func inkEditFinish(editor: EditorModel) {
        editor.lassoPoints = []
        editor.endGesture()
        inkPath = []
        inkDragLast = nil
        consumedSamples = 0
    }

    /// Moves the picked strokes with the Pencil, on the plane facing the camera through the strokes.
    private func dragInkStrokes(from start: CGPoint, to end: CGPoint, editor: EditorModel, stage: StageView) {
        guard let object = editor.activeInk, let bounds = stage.visualBounds(of: [object.id]),
              let from = stage.worldRay(at: start), let to = stage.worldRay(at: end) else { return }
        let normal = (Vec3(stage.camera.position) - bounds.center).normalized
        let plane = GuideSurface.plane(origin: bounds.center, normal: normal)
        guard let a = plane.intersect(from)?.point, let b = plane.intersect(to)?.point else { return }
        editor.moveInkStrokes(byWorld: b - a, gesture: gestureKey)
    }
}
