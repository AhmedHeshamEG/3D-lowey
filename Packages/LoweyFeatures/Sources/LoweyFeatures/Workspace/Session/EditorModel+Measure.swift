import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Measuring (Model ▸ Precision ▸ Measure): two taps, snapped to corners, edge middles, edges and faces, give the
/// distance and how far apart they are along each axis; Keep leaves it on the stage as a dimension that moves with the
/// object it measures.
extension EditorModel {
    static let groundPlane = PlaneFrame(origin: .zero, normal: .unitY, u: .unitX, v: Vec3(0, 0, -1))

    func measureTap(at point: CGPoint) {
        guard let result = snapPoint(at: point, plane: Self.groundPlane) else { return }
        if modeling.measure.count >= 2 {
            modeling.measure = []
            modeling.measureOwner = nil
        }
        let owner = stage?.pickObject(at: point)?.0
        modeling.measureOwner = modeling.measure.isEmpty ? owner : (owner == modeling.measureOwner ? owner : nil)
        modeling.measure.append(result.point)
        HmmHaptics.play(.selection)
        if modeling.measure.count == 1 { app.show("Tap the second point") }
        viewRevision &+= 1
    }

    /// The finished measurement: its length and how far apart along x, y and z.
    var measurement: (length: Double, along: Vec3)? {
        guard modeling.measure.count == 2 else { return nil }
        return PointSnap.measure(modeling.measure[0], modeling.measure[1])
    }

    /// "Δ 40 mm · 0 · 20 mm" for the bar.
    var measurementDetail: String? {
        guard let along = measurement?.along else { return nil }
        return "x \(format(along.x)) · y \(format(along.y)) · z \(format(along.z))"
    }

    func keepMeasurement() {
        guard modeling.measure.count == 2 else { return }
        var ids = operations.ids
        let id: ObjectID = ids.next()
        operations.ids = ids
        let command = ModelingOperations.keepDimension(from: modeling.measure[0], to: modeling.measure[1], owner: modeling.measureOwner,
                                                       in: baseScene, id: id)
        guard perform(command) else { return }
        HmmHaptics.play(.commit)
        modeling.measure = []
        modeling.measureOwner = nil
        if !precision.showsDimensions { precision.showsDimensions = true }
    }

    /// The overlay of the measure tool and the snap mark.
    func measureOverlays(_ stage: StageView) -> [EditorOverlay] {
        var overlays: [EditorOverlay] = []
        if !modeling.measure.isEmpty {
            var mesh = MeshData()
            for point in modeling.measure {
                ModelOverlay.dot(point, radius: stage.worldPerPoint(at: point) * 4, into: &mesh)
            }
            if modeling.measure.count == 2 { mesh.append(dimensionMesh(modeling.measure[0], modeling.measure[1], stage: stage)) }
            overlays.append(EditorOverlay(mesh: mesh, color: Self.modelAccent, onTop: true))
        }
        if let mark = modeling.snapMark {
            var mesh = MeshData()
            let radius = stage.worldPerPoint(at: mark.point) * (mark.kind == .corner ? 5 : 3.5)
            ModelOverlay.dot(mark.point, radius: radius, into: &mesh)
            overlays.append(EditorOverlay(mesh: mesh, color: mark.kind == .midpoint ? RGBA(0.45, 0.86, 0.4) : RGBA(0.98, 0.98, 1), onTop: true))
        }
        return overlays
    }

    /// The measured distance floating over its line (tap it to keep it).
    func measureLabels(_ stage: StageView) -> [DimensionLabel] {
        guard let length = measurement?.length, let point = stage.screenPoint(of: (modeling.measure[0] + modeling.measure[1]) * 0.5) else { return [] }
        return [DimensionLabel(field: .measured, point: CGPoint(x: point.x, y: point.y - 24), text: format(length))]
    }

    /// A tap on a floating number that does something other than typing: keep a measurement, select a kept dimension.
    /// Returns true when it was handled.
    func dimensionTapped(_ field: DimensionField) -> Bool {
        switch field {
        case .measured:
            keepMeasurement()
            return true
        case let .kept(id):
            HmmHaptics.play(.selection)
            if tool == .model { tool = .select }
            setSelection([id])
            return true
        default:
            return false
        }
    }
}
