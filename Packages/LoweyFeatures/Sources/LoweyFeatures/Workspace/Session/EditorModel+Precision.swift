import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Precision (Model ▸ Precision): snapping a point to what's under it, the section view, the printer's build volume
/// and kept dimensions on the stage. The section, the printer and showing dimensions are how the project shows, so
/// they live in `workspace.json` with the units and snapping.
extension EditorModel {
    func precisionChanged(from old: PrecisionState) {
        if precision.section != old.section || precision.printBed != old.printBed || precision.showsDimensions != old.showsDimensions {
            workspaceChanged()
        }
        stage?.section = precision.section
        refreshPrecisionOverlay()
    }

    // MARK: Snapping a point

    /// The point under a screen point, snapped to corners, edge middles, edges and faces near it (12 points on screen),
    /// else to the grid on `plane`. The mark it leaves shows what it snapped to.
    func snapPoint(at point: CGPoint, plane: PlaneFrame?, only target: ObjectID? = nil) -> SnapResult? {
        guard let stage, let ray = stage.worldRay(at: point) else { return nil }
        var nearby = PointSnap.Nearby()
        var surface: Vec3?
        if let (id, _) = stage.pickObject(at: point), target == nil || target == id, let (mesh, world) = modelMesh(of: id) {
            let solid = mesh.transformed(by: world)
            nearby.meshes.append(solid)
            let local = Ray(origin: world.inverseApply(to: ray.origin), direction: world.inverseApplyDirection(ray.direction))
            if let hit = MeshPicking.face(local, in: mesh) { surface = world.apply(to: hit.point) }
        }
        if let target, nearby.meshes.isEmpty, let (mesh, world) = modelMesh(of: target) { nearby.meshes.append(mesh.transformed(by: world)) }
        for (_, sketch) in sketches {
            nearby.lines += sketch.curves.map { $0.points.map { sketch.plane.lift($0) } }
        }
        var settings = snap
        if settings.grid { settings.gridSize = min(settings.gridSize, pullStep * 10) }
        let result = PointSnap.snap(screen: Vec2(Double(point.x), Double(point.y)), ray: ray, surface: surface, in: nearby, plane: plane,
                                    settings: settings, radius: 12) { [weak stage] world in
            stage?.screenPoint(of: world).map { Vec2(Double($0.x), Double($0.y)) }
        }
        modeling.snapMark = result.flatMap { [.corner, .midpoint, .edge].contains($0.kind) ? $0 : nil }
        return result
    }

    // MARK: Section view

    /// Cuts the stage across an axis through the middle of the selection (or of everything), or along the picked face.
    func setSection(_ axis: SymmetryAxis?) {
        HmmHaptics.play(.selection)
        guard let axis else {
            precision.section = nil
            return
        }
        let centre = (selectionBounds ?? allBounds)?.center ?? .zero
        precision.section = SectionPlane(axis: axis, through: centre)
    }

    func sectionAlongPickedFace() {
        guard let (id, face) = pickedFace, let (mesh, world) = modelMesh(of: id), mesh.faces.indices.contains(face) else {
            app.show("Pick a face first (Model ▸ Shape ▸ Face)")
            return
        }
        HmmHaptics.play(.selection)
        // A hair in front of the face, so the face itself stays.
        let normal = world.applyDirection(mesh.normal(of: face)).normalized
        precision.section = SectionPlane(face: normal, through: world.apply(to: mesh.centroid(of: face)) + normal * 1e-6)
    }

    func flipSection() {
        precision.section = precision.section?.flipped
    }

    /// Moves the cut along its normal (the slider: -1…1 across the scene).
    var sectionPosition: Double {
        get {
            guard let section = precision.section, let bounds = allBounds else { return 0 }
            let (low, high) = Self.extent(of: bounds, along: section.normal)
            return high > low ? (section.offset - low) / (high - low) * 2 - 1 : 0
        }
        set {
            guard var section = precision.section, let bounds = allBounds else { return }
            let (low, high) = Self.extent(of: bounds, along: section.normal)
            section.offset = low + (min(max(newValue, -1), 1) + 1) / 2 * (high - low)
            precision.section = section
        }
    }

    static func extent(of bounds: Bounds, along normal: Vec3) -> (Double, Double) {
        let heights = bounds.corners.map { $0.dot(normal) }
        return (heights.min() ?? 0, heights.max() ?? 0)
    }

    // MARK: Marks that stay

    /// The printer's build volume and the kept dimensions, whatever tool is on.
    func refreshPrecisionOverlay() {
        guard let stage else { return }
        var overlays: [EditorOverlay] = []
        if let bed = precision.bed {
            let volume = bed.volume
            let width = stage.worldPerPoint(at: volume.center) * 1.2
            var box = MeshData()
            let c = volume.corners
            for (a, b) in [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)] {
                ModelOverlay.line(c[a], c[b], width: width, into: &box)
            }
            overlays.append(EditorOverlay(mesh: box, color: RGBA(0.55, 0.75, 1), opacity: 0.6))
        }
        if precision.showsDimensions {
            for kept in ModelingOperations.dimensions(in: scene) {
                overlays.append(EditorOverlay(mesh: dimensionMesh(kept.start, kept.end, stage: stage), color: RGBA(0.98, 0.98, 1), onTop: true))
            }
        }
        stage.showPrecisionOverlay(overlays)
    }

    /// A dimension line: the line and a short tick across each end.
    func dimensionMesh(_ start: Vec3, _ end: Vec3, stage: StageView) -> MeshData {
        var mesh = MeshData()
        let width = stage.worldPerPoint(at: (start + end) * 0.5) * 1.2
        ModelOverlay.line(start, end, width: width, into: &mesh)
        let along = (end - start).normalized
        let helper = abs(along.y) < 0.9 ? Vec3.unitY : Vec3.unitX
        let tick = along.cross(helper).normalized * (width * 5)
        for point in [start, end] {
            ModelOverlay.line(point - tick, point + tick, width: width, into: &mesh)
        }
        return mesh
    }

    /// Kept dimensions' numbers (tap one to select it).
    func keptDimensionLabels(_ stage: StageView) -> [DimensionLabel] {
        guard precision.showsDimensions else { return [] }
        return ModelingOperations.dimensions(in: scene).compactMap { kept in
            guard let point = stage.screenPoint(of: (kept.start + kept.end) * 0.5) else { return nil }
            return DimensionLabel(field: .kept(kept.id), point: CGPoint(x: point.x, y: point.y - 18), text: format(kept.start.distance(to: kept.end)))
        }
    }

    // MARK: Printer

    func setPrintBed(_ id: String?) {
        HmmHaptics.play(.selection)
        precision.printBed = id
        precision.printReport = nil
    }
}
