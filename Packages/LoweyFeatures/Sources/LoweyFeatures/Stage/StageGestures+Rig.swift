import LoweyCore
import LoweyEngine
import UIKit

/// The Pencil on Cast ▸ Rig: a stroke through a limb becomes a chain of bones (Bones), or paints the chosen bone's
/// weight (Skin). While a bone is drawn, the chain it will make shows inside the object, following the stroke; the
/// stroke becomes one undo step when it ends.
extension StageGestures {
    func rigStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) {
        let samples = recognizer.samples
        switch recognizer.state {
        case .began:
            consumedSamples = 0
            flipSamples = []
            if editor.rigging.person != nil {
                // Placing a person's dots: the Pencil taps them.
                if let first = samples.first { editor.personTap(at: first.location) }
                return
            }
            rigContinue(Array(samples), editor: editor, stage: stage)
        case .changed:
            guard editor.rigging.person == nil else { return }
            rigContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), editor: editor, stage: stage)
        case .ended:
            guard editor.rigging.person == nil else { return }
            rigContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), editor: editor, stage: stage)
            rigFinish(editor: editor, stage: stage, keep: true)
        default:
            rigFinish(editor: editor, stage: stage, keep: false)
        }
    }

    /// The stroke so far, under the tip: a thin line for a bone, the weight brush's soft dabs.
    private func rigContinue(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel, stage: StageView) {
        consumedSamples += samples.count
        flipSamples += samples.map { BrushInput(point: Vec2(Double($0.location.x), Double($0.location.y)), pressure: $0.pressure,
                                                altitude: $0.altitude, time: $0.time) }
        let path = rigPath(editor)
        let brush = rigBrush(editor)
        let color = editor.rigging.mode == .bone ? RGBA(1, 0.722, 0.278) : (editor.rigging.erase ? RGBA(0.35, 0.45, 1) : RGBA(1, 0.3, 0.2))
        stage.showLiveStroke(LiveBrushStroke(stamps: .screen(BrushStroker.dabs(path, brush: brush, seed: 1)), brush: brush, color: color))
        // The bones as they'll land, every few samples (each time, every sample looks through the object again).
        if editor.rigging.mode == .bone, flipSamples.count >= 4, flipSamples.count % 3 == 0 || samples.count > 2 {
            editor.previewBone(along: flipSamples.map { CGPoint(x: $0.point.x, y: $0.point.y) })
        }
    }

    private func rigBrush(_ editor: EditorModel) -> Brush {
        editor.rigging.mode == .bone ? BuiltInBrushes.technicalPen : BuiltInBrushes.airbrush
    }

    private func rigPath(_ editor: EditorModel) -> BrushPath<Vec2> {
        let weights = editor.rigging.mode == .weights
        return BrushStroker.path(flipSamples, brush: rigBrush(editor), size: weights ? editor.rigging.size / 2 : 2.5,
                                 opacity: weights ? max(editor.rigging.strength, 0.3) : 1, minimumSpacing: 1.5)
    }

    private func rigFinish(editor: EditorModel, stage: StageView, keep: Bool) {
        defer {
            stage.showLiveStroke(nil)
            flipSamples = []
            consumedSamples = 0
            editor.endBonePreview()
            editor.strokeEnded()
        }
        guard keep, !flipSamples.isEmpty else { return }
        switch editor.rigging.mode {
        case .bone:
            editor.drawBone(along: flipSamples.map { CGPoint(x: $0.point.x, y: $0.point.y) })
        case .weights:
            // The brush engine spaces the dabs; each carries its pressure as its opacity.
            let dabs = BrushStroker.dabs(rigPath(editor), brush: rigBrush(editor), seed: 1)
            let spaced = dabs.isEmpty ? flipSamples.map { (CGPoint(x: $0.point.x, y: $0.point.y), $0.pressure) }
                : dabs.map { (CGPoint(x: $0.center.x, y: $0.center.y), min($0.opacity / max(editor.rigging.strength, 0.3), 1)) }
            editor.paintWeights(spaced.map { (point: $0.0, pressure: $0.1) })
        }
    }
}
