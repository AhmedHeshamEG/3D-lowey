import LoweyCore
import LoweyEngine
import UIKit

/// The stroke under the Pencil, drawn by the brush engine as it will land: the real samples, UIKit's predicted ones
/// ahead of them (never kept), the drawing guide's straightening and symmetry copies, the stroke's own seed.
extension StageGestures {
    // MARK: Ink

    /// The ink stroke's samples so far (world points on the guide), with the predicted ones when asked.
    func inkSamples(predicted: [StrokeGestureRecognizer.Sample] = [], stage: StageView) -> [BrushInput<Vec3>] {
        var samples = strokePoints.indices.map { index in
            BrushInput(point: strokePoints[index], pressure: strokePressures[index], altitude: strokeAltitudes[index], time: strokeTimes[index])
        }
        for sample in predicted {
            guard let ray = stage.worldRay(at: sample.location), let hit = strokeGuide?.intersect(ray) else { continue }
            samples.append(BrushInput(point: hit.point + hit.normal * 0.002, pressure: sample.pressure, altitude: sample.altitude, time: sample.time))
        }
        return samples
    }

    /// The stroke and its copies as the guide plane's guide makes them (samples keep their pressure and time).
    func inkCopies(_ samples: [BrushInput<Vec3>], editor: EditorModel) -> [[BrushInput<Vec3>]] {
        editor.guidedOnPlane(samples.map(\.point), guide: strokeGuide).map { points in
            zip(samples, points).map { sample, point in
                var moved = sample
                moved.point = point
                return moved
            }
        }
    }

    func showInkPreview(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) {
        let samples = inkSamples(predicted: recognizer.predicted, stage: stage)
        guard samples.count >= 2 else { return }
        let brush = editor.currentBrush(for: .ink)
        // The drawing's opacity, as the renderer folds it into the stamps.
        let opacity = editor.activeInk?.opacity ?? editor.ink.opacity
        let dabs = inkCopies(samples, editor: editor).enumerated().flatMap { index, copy in
            var path = editor.inkPath(copy)
            if opacity < 0.999 { path.alphas = path.alphas.map { $0 * opacity } }
            return BrushStroker.dabs(path, brush: brush, seed: strokeSeed &+ UInt64(index))
        }
        let color = editor.currentColor.resolved(in: editor.look.palette)
        stage.showLiveStroke(LiveBrushStroke(stamps: .world(dabs), brush: brush, color: color), touchTime: strokeTimes.last)
    }

    // MARK: Flipbooks

    /// The flipbook stroke's samples so far (stage points), with the predicted ones when asked.
    func flipbookSamples(predicted: [StrokeGestureRecognizer.Sample] = []) -> [BrushInput<Vec2>] {
        flipSamples + predicted.map { BrushInput(point: Vec2(Double($0.location.x), Double($0.location.y)), pressure: $0.pressure,
                                                 altitude: $0.altitude, time: $0.time) }
    }

    /// The stroke and its copies as the frame's guide makes them.
    func flipbookCopies(_ samples: [BrushInput<Vec2>], editor: EditorModel) -> [[BrushInput<Vec2>]] {
        let points = samples.map { CGPoint(x: $0.point.x, y: $0.point.y) }
        return editor.guidedOnFrame(points).map { copy in
            zip(samples, copy).map { sample, point in
                var moved = sample
                moved.point = Vec2(Double(point.x), Double(point.y))
                return moved
            }
        }
    }

    func showFlipbookPreview(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) {
        let samples = flipbookSamples(predicted: recognizer.predicted)
        guard !samples.isEmpty else { return }
        let brush = editor.currentBrush(for: .flipbook)
        let dabs = flipbookCopies(samples, editor: editor).enumerated().flatMap { index, copy in
            BrushStroker.dabs(editor.flipbookPath(copy), brush: brush, seed: strokeSeed &+ UInt64(index))
        }
        let color = editor.currentColor.resolved(in: editor.look.palette)
        stage.showLiveStroke(LiveBrushStroke(stamps: .screen(dabs), brush: brush, color: color), touchTime: flipSamples.last?.time)
    }
}
