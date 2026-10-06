import CoreGraphics
import Foundation
import LoweyCore
import LoweyEngine

/// A number floating on the stage beside what it measures; tap it to type.
struct DimensionLabel: Identifiable, Hashable {
    var field: DimensionField
    var point: CGPoint
    var text: String

    var id: DimensionField { field }
}

/// What the Model tool draws on the stage (`EditorOverlay`s in the editor pass, never exported) and the numbers that
/// float beside it.
extension EditorModel {
    static let modelAccent = RGBA(1, 0.722, 0.278)

    func refreshModelOverlay() {
        guard let stage else { return }
        guard tool == .model else {
            stage.showModelOverlay(tool == .rig ? rigOverlays(stage) : [])
            return
        }
        var overlays = sketchOverlays(stage) + measureOverlays(stage) + buildOverlays(stage)
        if let id = modeling.target ?? singleSelection.flatMap({ ModelingOperations.canModel($0) ? $0.id : nil }), let (mesh, world) = modelMesh(of: id) {
            let width = stage.worldPerPoint(at: world.position) * 1.2
            overlays.append(EditorOverlay(mesh: ModelOverlay.wireframe(mesh, world: world, width: width), color: RGBA(0.08, 0.08, 0.1), opacity: 0.7))
            if let elements = modeling.elements, modeling.target == id, !elements.isEmpty {
                let picked = ModelOverlay.selection(elements, of: mesh, world: world, width: width)
                overlays.append(EditorOverlay(mesh: picked, color: Self.modelAccent, opacity: elements.mode == .face ? 0.45 : 1,
                                              onTop: elements.mode == .vertex))
            }
        }
        if let preview = pullPreview() {
            overlays.append(EditorOverlay(mesh: preview.renderMesh(), color: Self.modelAccent, opacity: 0.3))
            let width = stage.worldPerPoint(at: preview.bounds?.center ?? .zero) * 1.2
            overlays.append(EditorOverlay(mesh: ModelOverlay.wireframe(preview, world: .identity, width: width), color: Self.modelAccent))
        }
        stage.showModelOverlay(overlays)
    }

    private func sketchOverlays(_ stage: StageView) -> [EditorOverlay] {
        var overlays: [EditorOverlay] = []
        for (id, sketch) in sketches {
            let width = stage.worldPerPoint(at: sketch.plane.origin) * 1.5
            overlays.append(EditorOverlay(mesh: ModelOverlay.sketchLines(sketch, width: width), color: RGBA(0.98, 0.98, 1), opacity: 0.95))
            for (index, region) in sketch.regions.enumerated() {
                let picked = modeling.region == SketchRegionRef(sketch: id, index: index)
                overlays.append(EditorOverlay(mesh: ModelOverlay.region(region, of: sketch, lift: width * 0.3),
                                              color: picked ? Self.modelAccent : RGBA(0.98, 0.98, 1), opacity: picked ? 0.45 : 0.1))
            }
            if let source = modeling.offsetSource, source.sketch == id, let curve = sketch.curves[safe: source.index] {
                let one = Sketch(plane: sketch.plane, curves: [curve])
                overlays.append(EditorOverlay(mesh: ModelOverlay.sketchLines(one, width: width * 2.5), color: Self.modelAccent))
            }
        }
        if let pending = modeling.pending, !pending.points.isEmpty {
            let width = stage.worldPerPoint(at: pending.plane.origin) * 1.5
            var dots = MeshData()
            for point in pending.points {
                ModelOverlay.dot(pending.plane.lift(point), radius: width * 3, into: &dots)
            }
            if pending.points.count >= 2 {
                let run = Sketch(plane: pending.plane, curves: [.polyline(pending.points, closed: false)])
                dots.append(ModelOverlay.sketchLines(run, width: width))
            }
            overlays.append(EditorOverlay(mesh: dots, color: Self.modelAccent, onTop: true))
        }
        return overlays
    }

    /// The prism a pull will add or cut (world space), while one is being dragged and isn't a plain slide.
    private func pullPreview() -> EditableMesh? {
        guard let distance = modeling.pull, abs(distance) > 1e-9, kindOverride.isEmpty else { return nil }
        if let region = modeling.region, let sketch = sketch(region.sketch), let shape = sketch.regions[safe: region.index] {
            return sketch.prism(of: shape, distance: distance)
        }
        guard let (id, face) = pickedFace, let (mesh, world) = modelMesh(of: id), mesh.faces.indices.contains(face) else { return nil }
        let normal = world.applyDirection(mesh.normal(of: face)).normalized
        let loops = mesh.faces[face].loops.map { $0.map { world.apply(to: mesh.vertices[$0]) } }
        return Prism.make(outline: loops[0], holes: Array(loops.dropFirst()), normal: normal, from: 0, to: distance)
    }

    // MARK: Floating numbers

    /// The numbers on the stage now: the pull distance, the sizes of the shape just drawn, the offset.
    var dimensionLabels: [DimensionLabel] {
        _ = viewRevision
        _ = displayRevision
        guard let stage else { return [] }
        var labels = keptDimensionLabels(stage)
        guard tool == .model else { return labels }
        labels += measureLabels(stage) + buildLabels(stage)
        if let op = modeling.shapeOp, modeling.target == op.object, let point = stage.screenPoint(of: op.anchor) {
            labels.append(DimensionLabel(field: .shapeAmount, point: CGPoint(x: point.x, y: point.y - 30), text: "\(op.kind.title) " + format(op.amount)))
        }
        if let axis = pullAxis, let point = stage.screenPoint(of: axis.anchor + axis.normal * (modeling.pull ?? 0)) {
            labels.append(DimensionLabel(field: .pull, point: CGPoint(x: point.x, y: point.y - 34), text: format(modeling.pull ?? 0)))
        }
        if let source = modeling.offsetSource, let sketch = sketch(source.sketch), let first = sketch.curves[safe: source.index]?.points.first,
           let point = stage.screenPoint(of: sketch.plane.lift(first)) {
            labels.append(DimensionLabel(field: .offset, point: point, text: String(localized: "Offset")))
        }
        if modeling.pending == nil { labels += curveLabels(stage) }
        return labels
    }

    /// Sizes of the shape just drawn, each pushed 30 points out from the shape's middle on screen so none covers it.
    private func curveLabels(_ stage: StageView) -> [DimensionLabel] {
        guard let ref = modeling.lastCurve, let sketch = sketch(ref.sketch), let curve = sketch.curves[safe: ref.index] else { return [] }
        let points = curve.points
        let middle = points.reduce(Vec2(0, 0)) { $0 + $1 } * (1 / Double(max(points.count, 1)))
        let centre = stage.screenPoint(of: sketch.plane.lift(middle))
        func label(_ field: DimensionField, at point: Vec2, prefix: String = "") -> DimensionLabel? {
            guard let value = dimensionValue(field), let screen = stage.screenPoint(of: sketch.plane.lift(point)) else { return nil }
            var away = CGVector(dx: screen.x - (centre?.x ?? screen.x), dy: screen.y - (centre?.y ?? screen.y))
            let length = hypot(away.dx, away.dy)
            away = length > 1 ? CGVector(dx: away.dx / length, dy: away.dy / length) : CGVector(dx: 0, dy: 1)
            return DimensionLabel(field: field, point: CGPoint(x: screen.x + away.dx * 30, y: screen.y + away.dy * 30), text: prefix + format(value))
        }
        switch curve {
        case let .rectangle(a, b):
            return [label(.rectangleSide(horizontal: true), at: Vec2((a.x + b.x) / 2, a.y)),
                    label(.rectangleSide(horizontal: false), at: Vec2(b.x, (a.y + b.y) / 2))].compactMap(\.self)
        case let .circle(center, radius):
            // Beside the rim, so the middle stays free to tap (and pick the disc).
            return [label(.diameter, at: Vec2(center.x + radius, center.y), prefix: "⌀ ")].compactMap(\.self)
        case let .line(a, b):
            return [label(.lineLength, at: Vec2((a.x + b.x) / 2, (a.y + b.y) / 2))].compactMap(\.self)
        default:
            return []
        }
    }
}
