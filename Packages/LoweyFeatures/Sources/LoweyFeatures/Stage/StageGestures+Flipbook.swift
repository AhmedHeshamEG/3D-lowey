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
            consumedSamples = 0
            inkPath = []
            strokePressures = []
            flipbookContinue(Array(samples), editor: editor)
        case .changed:
            flipbookContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), editor: editor)
        case .ended:
            flipbookContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), editor: editor)
            if editor.flipbook.mode == .draw { editor.commitFlipbookStroke(points: inkPath, pressures: strokePressures) }
            flipbookFinish(editor: editor)
        default:
            flipbookFinish(editor: editor)
        }
    }

    private func flipbookContinue(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel) {
        consumedSamples += samples.count
        let points = samples.map(\.location)
        inkPath += points
        strokePressures += samples.map(\.pressure)
        if editor.flipbook.mode == .erase {
            editor.eraseFlipbook(at: points, gesture: gestureKey)
        } else {
            editor.flipbook.livePoints = inkPath
        }
    }

    private func flipbookFinish(editor: EditorModel) {
        editor.flipbook.livePoints = []
        editor.endGesture()
        inkPath = []
        strokePressures = []
        consumedSamples = 0
    }
}
