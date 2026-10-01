import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// The Pencil: solid shapes drawn on a guide (draw, then hold to snap to a clean shape), and the Shadow Brush painting
/// shadow shapes onto a surface.
extension StageGestures {
    @objc func handleStroke(_ recognizer: StrokeGestureRecognizer) {
        guard let editor, let stage else { return }
        if editor.tool == .shadowBrush {
            brushStroke(recognizer, editor: editor, stage: stage)
            return
        }
        switch recognizer.state {
        case .began:
            snapped = nil
            strokePoints = []
            strokePressures = []
            strokeNormals = []
            consumedSamples = 0
            strokeGuide = editor.currentGuide
            strokeTargetMesh = nil
            if editor.draw.guide == .object, let first = recognizer.samples.first {
                strokeTargetMesh = stage.pickObject(at: first.location).flatMap { stage.worldMesh(of: $0.0) }
                if strokeTargetMesh == nil { editor.app.show("Start the stroke on an object") }
            }
            consume(Array(recognizer.samples), editor: editor, stage: stage)
        case .changed:
            continueStroke(recognizer, editor: editor, stage: stage)
        case .ended:
            continueStroke(recognizer, editor: editor, stage: stage)
            stage.showStrokePreview(nil, color: .white)
            editor.commitStroke(points: strokePoints, pressures: strokePressures, normals: strokeNormals, guide: strokeGuide)
            consumedSamples = 0
            snapped = nil
        default:
            stage.showStrokePreview(nil, color: .white)
            consumedSamples = 0
            snapped = nil
        }
    }

    private func continueStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) {
        if snapped != nil {
            adjustQuickShape(editor: editor, stage: stage)
        } else {
            consume(Array(recognizer.samples.suffix(from: min(consumedSamples, recognizer.samples.count))), editor: editor, stage: stage)
        }
    }

    // MARK: QuickShape

    /// Draw, then hold: the stroke becomes the clean shape it was meant to be.
    func snapToQuickShape() {
        guard let editor, let stage, editor.tool == .draw, stroke.state == .began || stroke.state == .changed,
              let anchor = stroke.samples.last?.location else { return }
        let points = stroke.samples.map { Vec2(Double($0.location.x), Double($0.location.y)) }
        guard let shape = QuickShape.fit(points) else { return }
        let pressure = stroke.samples.map(\.pressure).reduce(0, +) / Double(max(stroke.samples.count, 1))
        snapped = (shape, anchor, pressure)
        redrawStroke(shape.points, pressure: pressure, editor: editor, stage: stage)
        HmmHaptics.play(.selection)
        editor.app.show("\(shape.kind.title). Keep holding and drag to adjust")
    }

    /// Still holding after the snap: a line's end follows the tip; other shapes turn and scale.
    private func adjustQuickShape(editor: EditorModel, stage: StageView) {
        guard let snapped, let tip = stroke.samples.last?.location else { return }
        let shape = QuickShape.adjusted(snapped.shape, anchor: Vec2(Double(snapped.anchor.x), Double(snapped.anchor.y)),
                                        current: Vec2(Double(tip.x), Double(tip.y)))
        redrawStroke(shape.points, pressure: snapped.pressure, editor: editor, stage: stage)
    }

    private func redrawStroke(_ points: [Vec2], pressure: Double, editor: EditorModel, stage: StageView) {
        strokePoints = []
        strokePressures = []
        strokeNormals = []
        project(points.map { StrokeGestureRecognizer.Sample(location: CGPoint(x: $0.x, y: $0.y), pressure: pressure) }, editor: editor, stage: stage)
        updatePreview(editor: editor, stage: stage)
    }

    private func consume(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel, stage: StageView) {
        consumedSamples += samples.count
        project(samples, editor: editor, stage: stage)
        updatePreview(editor: editor, stage: stage)
    }

    /// Screen samples → points on the stroke's guide (or the object it started on).
    private func project(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel, stage: StageView) {
        for sample in samples {
            guard let ray = stage.worldRay(at: sample.location) else { continue }
            let hit: SurfaceHit? = if let mesh = strokeTargetMesh {
                MeshRaycast.intersect(ray, mesh: mesh)
            } else {
                strokeGuide?.intersect(ray)
            }
            guard let hit else { continue }
            // Tubes sit on the surface instead of half buried in it.
            let lift = editor.draw.style == .tube ? editor.draw.width * 0.5 : 0.002
            strokePoints.append(hit.point + hit.normal * lift)
            strokePressures.append(sample.pressure)
            strokeNormals.append(hit.normal)
        }
    }

    private func updatePreview(editor: EditorModel, stage: StageView) {
        guard strokePoints.count >= 2 else { return }
        let widths = strokePressures.map { editor.draw.width * (0.35 + 0.65 * $0) }
        let thin = editor.draw.style == .extrude || editor.draw.style == .lathe
        let preview = DrawingRecipe.Stroke(points: strokePoints, widths: thin ? widths.map { _ in 0.012 } : widths)
        let mesh = editor.draw.style == .ribbon ? DrawingMesher.ribbon(preview, normal: strokeNormals.last ?? .unitY)
            : DrawingMesher.tube(preview, sides: 5)
        stage.showStrokePreview(mesh, color: editor.currentColor.resolved(in: editor.look.palette))
    }

    // MARK: Shadow Brush

    /// Paints where the Pencil touches the object the stroke started on (raycast on its world mesh, so every sample
    /// lands even between frames). One stroke is one undo step.
    private func brushStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) {
        switch recognizer.state {
        case .began:
            gestureKey = UUID().uuidString
            consumedSamples = 0
            brushTarget = recognizer.samples.first.flatMap { sample in
                stage.pickObject(at: sample.location).flatMap { hit in stage.worldMesh(of: hit.0).map { (hit.0, $0) } }
            }
            if brushTarget == nil { editor.app.show("Start the stroke on an object") }
            paint(Array(recognizer.samples), editor: editor, stage: stage)
        case .changed:
            paint(Array(recognizer.samples.suffix(from: min(consumedSamples, recognizer.samples.count))), editor: editor, stage: stage)
        default:
            brushTarget = nil
            consumedSamples = 0
            editor.endGesture()
        }
    }

    private func paint(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel, stage: StageView) {
        consumedSamples += samples.count
        guard let target = brushTarget else { return }
        // A dab every few points is plenty (the brush is soft); fewer dabs keep the undo step small.
        for (index, sample) in samples.enumerated() where index % 3 == 0 {
            guard let ray = stage.worldRay(at: sample.location), let hit = MeshRaycast.intersect(ray, mesh: target.mesh) else { continue }
            editor.paintShadow(on: target.id, at: hit.point, pressure: sample.pressure, gesture: gestureKey)
        }
    }
}
