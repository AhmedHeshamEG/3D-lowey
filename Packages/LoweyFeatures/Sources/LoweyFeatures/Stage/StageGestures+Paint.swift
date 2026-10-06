import LoweyCore
import LoweyEngine
import UIKit

/// The Pencil on Paint ▸ Colour: a stroke paints (or erases) the object it starts on, drawn into the object's layer by
/// the very frame that shows it; when it ends, the tiles it changed become one undo step. Fill and the eyedropper act
/// where the Pencil (or a finger) touches.
extension StageGestures {
    func colourStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) {
        let samples = recognizer.samples
        switch recognizer.state {
        case .began:
            consumedSamples = 0
            flipSamples = []
            paintStroke = nil
            guard let first = samples.first else { return }
            guard editor.colourPaint.mode == .paint || editor.colourPaint.mode == .erase else {
                editor.paintTap(at: first.location)
                return
            }
            paintStroke = beginColourStroke(at: first.location, editor: editor, stage: stage)
            strokeSeed = EditorModel.strokeSeed()
            colourContinue(Array(samples), recognizer: recognizer, editor: editor, stage: stage)
        case .changed:
            colourContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), recognizer: recognizer, editor: editor, stage: stage)
        case .ended:
            colourContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), recognizer: recognizer, editor: editor, stage: stage,
                           predicted: false)
            colourFinish(editor: editor, stage: stage, keep: true)
        default:
            colourFinish(editor: editor, stage: stage, keep: false)
        }
    }

    /// The object and layer a stroke paints: the paintable object under the Pencil, made ready first if it isn't.
    private func beginColourStroke(at point: CGPoint, editor: EditorModel, stage: StageView) -> (object: ObjectID, layer: String, number: Int)? {
        guard let hit = stage.pickObject(at: point), let object = editor.displayed.scene.objects[hit.0] else {
            editor.app.show("Start the stroke on an object")
            return nil
        }
        guard object.isPaintable else {
            editor.app.show("This can't be painted (try a shape, a modelled part or a placed model)")
            return nil
        }
        editor.colourPaint.target = object.id
        guard object.paint != nil, let layer = editor.paintLayer(of: object) else {
            editor.preparePaint(object.id)
            return nil
        }
        guard editor.paintFitsShape(object) else {
            editor.rebasePaint(object.id)
            return nil
        }
        guard layer.visible else {
            editor.app.show("This layer is hidden")
            return nil
        }
        editor.paintStrokes += 1
        return (object.id, layer.id, editor.paintStrokes)
    }

    private func colourContinue(_ samples: [StrokeGestureRecognizer.Sample], recognizer: StrokeGestureRecognizer, editor: EditorModel,
                                stage: StageView, predicted: Bool = true) {
        consumedSamples += samples.count
        flipSamples += samples.map { BrushInput(point: Vec2(Double($0.location.x), Double($0.location.y)), pressure: $0.pressure,
                                                altitude: $0.altitude, time: $0.time) }
        guard let target = paintStroke, !flipSamples.isEmpty else { return }
        let ahead = predicted ? recognizer.predicted.map { BrushInput(point: Vec2(Double($0.location.x), Double($0.location.y)), pressure: $0.pressure,
                                                                      altitude: $0.altitude, time: $0.time) } : []
        let brush = editor.currentBrush(for: .paint)
        let dabs = BrushStroker.dabs(editor.paintPath(flipSamples + ahead), brush: brush, seed: strokeSeed)
        let erases = editor.colourPaint.mode == .erase
        stage.showLivePaint(LivePaint(object: target.object, layer: target.layer, stroke: target.number, source: .stamps(dabs, brush: brush),
                                      color: erases ? RGBA(0, 0, 0, 1) : editor.paintColor, erases: erases,
                                      pixelsPerPoint: Double(stage.contentScaleFactor)))
    }

    /// The stroke's last frame is drawn now, then its layer is read back and committed (or a cancelled stroke undone
    /// by putting the tiles it touched back).
    private func colourFinish(editor: EditorModel, stage: StageView, keep: Bool) {
        defer {
            paintStroke = nil
            flipSamples = []
            consumedSamples = 0
            editor.strokeEnded()
        }
        guard paintStroke != nil else { return }
        stage.draw()
        guard let pending = stage.finishPaintStroke() else { return }
        if keep {
            editor.commitPaintStroke(pending)
        } else {
            // A cancelled stroke: the layer goes back to the document's tiles.
            editor.revertPaint()
        }
    }
}
