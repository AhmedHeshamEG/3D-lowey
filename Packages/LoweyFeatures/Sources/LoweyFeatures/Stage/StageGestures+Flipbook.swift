import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// The Pencil on a flipbook: draws a stroke into the drawing at the playhead, or erases from it.
extension StageGestures {
    func flipbookStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel) {
        let samples = recognizer.samples
        switch recognizer.state {
        case .began:
            gestureKey = UUID().uuidString
            strokeSeed = EditorModel.strokeSeed()
            consumedSamples = 0
            inkPath = []
            flipSamples = []
            flipbookContinue(Array(samples), recognizer: recognizer, editor: editor)
        case .changed:
            flipbookContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), recognizer: recognizer, editor: editor)
        case .ended:
            flipbookContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), recognizer: recognizer, editor: editor)
            if editor.flipbook.mode == .draw { editor.commitFlipbookStrokes(flipbookCopies(flipSamples, editor: editor), seed: strokeSeed) }
            flipbookFinish(editor: editor)
        default:
            flipbookFinish(editor: editor)
        }
    }

    private func flipbookContinue(_ samples: [StrokeGestureRecognizer.Sample], recognizer: StrokeGestureRecognizer, editor: EditorModel) {
        consumedSamples += samples.count
        let points = samples.map(\.location)
        inkPath += points
        flipSamples += samples.map { BrushInput(point: Vec2(Double($0.location.x), Double($0.location.y)), pressure: $0.pressure,
                                                altitude: $0.altitude, time: $0.time) }
        if editor.flipbook.mode == .erase {
            editor.eraseFlipbook(at: points, gesture: gestureKey)
        } else if let stage {
            showFlipbookPreview(recognizer, editor: editor, stage: stage)
        }
    }

    private func flipbookFinish(editor: EditorModel) {
        stage?.showLiveStroke(nil)
        editor.strokeEnded()
        editor.endGesture()
        inkPath = []
        flipSamples = []
        consumedSamples = 0
    }
}
