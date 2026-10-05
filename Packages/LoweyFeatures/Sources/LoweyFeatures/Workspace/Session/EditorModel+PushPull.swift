import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// The axis a push/pull drag moves along: where it starts and which way is out (world space).
struct PullAxis: Sendable {
    var anchor: Vec3
    var normal: Vec3
}

/// Push/pull with the Model tool: drag the picked face or sketch region along its normal, or type the distance. While
/// dragging, a face that slides shows its new shape for real (`kindOverride`); anything that needs a boolean shows
/// the prism it will add or cut. Release commits one command.
extension EditorModel {
    /// The picked face's or region's axis, when there is one to pull.
    var pullAxis: PullAxis? {
        if let region = modeling.region, let sketch = sketch(region.sketch), let shape = sketch.regions[safe: region.index] {
            let centre = shape.outline.reduce(Vec2(0, 0)) { $0 + $1 } * (1 / Double(max(shape.outline.count, 1)))
            return PullAxis(anchor: sketch.plane.lift(centre), normal: sketch.plane.normal)
        }
        guard let (id, face) = pickedFace, let (mesh, world) = modelMesh(of: id), mesh.faces.indices.contains(face) else { return nil }
        return PullAxis(anchor: world.apply(to: mesh.centroid(of: face)), normal: world.applyDirection(mesh.normal(of: face)).normalized)
    }

    /// Whether a push/pull drag can start at a screen point (on the picked face or region).
    func canPull(at point: CGPoint) -> Bool {
        guard pullAxis != nil, let stage else { return false }
        if let region = modeling.region { return sketchRegion(at: point) == region }
        guard let (id, face) = pickedFace, let (hitID, _) = stage.pickObject(at: point), hitID == id,
              let (mesh, world) = modelMesh(of: id), let ray = stage.worldRay(at: point) else { return false }
        let local = Ray(origin: world.inverseApply(to: ray.origin), direction: world.inverseApplyDirection(ray.direction))
        return MeshPicking.face(local, in: mesh)?.face == face
    }

    /// Before a face is dragged, its object becomes an editable mesh with real sizes (one undo step of its own).
    func prepareFacePull() -> Bool {
        guard let (id, _) = pickedFace, let object = baseScene.objects[id] else { return modeling.region != nil }
        if case .mesh = object.kind, object.transform.scale.isApproximately(.one, tolerance: 1e-12) || !object.children.isEmpty { return true }
        return runModeling { try ModelingOperations.makeEditable(id, in: baseScene) }
    }

    /// Where along the axis a screen point is (metres from the anchor): the closest point of the axis to the ray.
    func pullDistance(at point: CGPoint, axis: PullAxis) -> Double? {
        guard let ray = stage?.worldRay(at: point) else { return nil }
        let b = axis.normal.dot(ray.direction)
        let denominator = 1 - b * b
        guard denominator > 1e-6 else { return nil }
        let w = axis.anchor - ray.origin
        return (b * w.dot(ray.direction) - w.dot(axis.normal)) / denominator
    }

    /// Updates the live distance while dragging.
    func updatePull(_ raw: Double, axis: PullAxis) {
        let distance = snappedPull(raw, axis: axis)
        guard distance != modeling.pull else { return }
        if let old = modeling.pull, (old / pullStep).rounded() != (distance / pullStep).rounded() { HmmHaptics.play(.selection) }
        modeling.pull = distance
        previewPull(distance)
        viewRevision &+= 1
    }

    /// One unit of the project's units (a millimetre, a centimetre…) or a thousandth of a metre at least.
    var pullStep: Double {
        switch units {
        case .millimetre: 0.001
        case .centimetre: 0.001
        case .metre: 0.01
        case .inch: 0.0254 / 16
        case .foot: 0.0254
        }
    }

    /// Lines up with other corners along the axis (within 10 points on screen), else steps through the unit.
    private func snappedPull(_ raw: Double, axis: PullAxis) -> Double {
        let perPoint = stage?.worldPerPoint(at: axis.anchor) ?? 0.001
        var heights: [Double] = []
        for id in baseScene.objects.keys {
            guard let (mesh, world) = modelMesh(of: id) else { continue }
            heights += mesh.vertices.map { (world.apply(to: $0) - axis.anchor).dot(axis.normal) }
        }
        if let near = heights.filter({ abs($0) > 1e-9 }).min(by: { abs($0 - raw) < abs($1 - raw) }), abs(near - raw) < perPoint * 10 {
            return near
        }
        return snap.grid ? (raw / pullStep).rounded() * pullStep : raw
    }

    /// Shows the face slid for real, or (when it needs a boolean) leaves the prism to the overlay.
    private func previewPull(_ distance: Double) {
        guard let (id, face) = pickedFace, let object = baseScene.objects[id], case let .mesh(mesh) = object.kind,
              PushPull.slides(mesh, face: face) else {
            kindOverride = [:]
            refreshModelOverlay()
            return
        }
        if let moved = try? PushPull.apply(mesh, face: face, distance: localDistance(distance, object: object, mesh: mesh, face: face)) {
            kindOverride = [id: .mesh(moved)]
        }
        refreshDisplay()
    }

    /// A world distance along a face's normal in the object's own units (they differ when it keeps a scale).
    private func localDistance(_ distance: Double, object: SceneObject, mesh: EditableMesh, face: Int) -> Double {
        let stretch = mesh.normal(of: face).scaled(by: object.transform.scale).length
        return stretch > 1e-12 ? distance / stretch : distance
    }

    /// The drag let go: commit what it shows.
    func endPull(commit: Bool) {
        let distance = modeling.pull ?? 0
        kindOverride = [:]
        if commit, abs(distance) > 1e-9 {
            commitPull(distance)
        } else {
            modeling.pull = nil
            refreshDisplay()
        }
    }

    func cancelPushPull() {
        guard !kindOverride.isEmpty || modeling.pull != nil else { return }
        kindOverride = [:]
        modeling.pull = nil
        refreshDisplay()
    }

    /// Pulls (positive) or pushes (negative) the picked face or region by an exact distance.
    func commitPull(_ distance: Double) {
        defer {
            modeling.pull = nil
            refreshModelOverlay()
        }
        guard abs(distance) > 1e-9 else { return }
        if let region = modeling.region {
            let before = Set(baseScene.objects.keys)
            let target = sketch(region.sketch)?.target
            var ids = operations.ids
            let done = runModeling { try ModelingOperations.pull(sketch: region.sketch, region: region.index, distance: distance, in: baseScene, ids: &ids) }
            operations.ids = ids
            guard done else { return }
            modeling.region = nil
            modeling.lastCurve = nil
            let made = Set(baseScene.objects.keys).subtracting(before).first
            if let solid = target ?? made { setSelection([solid]) }
        } else if let (id, face) = pickedFace, prepareFacePull(), let object = baseScene.objects[id], case let .mesh(mesh) = object.kind {
            let slides = PushPull.slides(mesh, face: face)
            let local = localDistance(distance, object: object, mesh: mesh, face: face)
            guard runModeling({ try ModelingOperations.pushPull(id, face: face, distance: local, in: baseScene) }) else { return }
            // A slide keeps the faces; a boolean renumbers them.
            if !slides { modeling.elements = MeshSelection(mode: .face) }
        }
    }
}
