import Foundation
import HmmDesign
import LoweyCore

/// Solid shapes drawn in 3D on a guide (tube, ribbon, extrude, lathe), and the Shadow Brush.
extension EditorModel {
    /// The guide the drawing tool draws on now.
    var currentGuide: GuideSurface? {
        guard tool == .draw, let stage else { return nil }
        let target = stage.viewpoint.target
        let center = selectionBounds.map { Vec3($0.center.x, $0.min.y, $0.center.z) } ?? Vec3(target.x, 0, target.z)
        let size = draw.guideSize
        switch draw.guide {
        case .plane:
            let normal = planeNormal(stage.viewpoint)
            let origin = normal == .unitY ? center : Vec3(center.x, center.y + size / 2, center.z)
            return .plane(origin: origin + normal * draw.planeOffset, normal: normal)
        case .box:
            return .box(center: center + Vec3(0, size / 2, 0), size: Vec3(size, size, size))
        case .cylinder:
            return .cylinder(base: center, radius: size / 2, height: size)
        case .sphere:
            return .sphere(center: center + Vec3(0, size / 2, 0), radius: size / 2)
        case .object:
            return nil
        }
    }

    private func planeNormal(_ viewpoint: Viewpoint) -> Vec3 {
        switch draw.planeLock {
        case .ground: return .unitY
        case .front: return .unitZ
        case .side: return .unitX
        case .view:
            // The principal axis closest to where you look (Feather-style lock).
            let forward = (viewpoint.eye - viewpoint.target).normalized
            return [Vec3.unitX, .unitY, .unitZ].max { abs($0.dot(forward)) < abs($1.dot(forward)) } ?? .unitY
        }
    }

    /// A finished stroke becomes a drawn object (one undo step).
    func commitStroke(points rawPoints: [Vec3], pressures: [Double], normals: [Vec3], guide: GuideSurface?) {
        guard rawPoints.count >= 2 || draw.style == .tube else { return }
        let widths = pressures.map { draw.width * (0.35 + 0.65 * min(max($0, 0), 1)) }
        let filtered = StrokeFilter.process(points: rawPoints, widths: widths, smoothing: draw.smoothing)
        guard !filtered.points.isEmpty else { return }
        let normal = strokeNormal(normals: normals, guide: guide)
        let origin = strokeOrigin(filtered.points)
        let points = filtered.points.map { $0 - origin }
        var strokes = [DrawingRecipe.Stroke(points: points, widths: filtered.widths)]
        if draw.mirror, draw.style != .lathe {
            let mirrorX = (guideCenterX ?? origin.x) - origin.x
            strokes.append(DrawingRecipe.Stroke(points: points.map { Vec3(2 * mirrorX - $0.x, $0.y, $0.z) }, widths: filtered.widths))
        }
        let recipe = DrawingRecipe(style: draw.style, strokes: strokes, normal: normal, depth: draw.extrudeDepth,
                                   segments: draw.style == .lathe ? max(draw.segments, 6) : draw.segments)
        guard !DrawingMesher.mesh(for: recipe).isEmpty else {
            app.show(draw.style == .extrude ? "Draw a closed outline to extrude" : "That stroke was too small")
            return
        }
        var object = factory.drawing(recipe, transform: CoreTransform(position: origin), color: currentColor)
        object.name = ObjectFactory.uniqueName(object.name, in: scene)
        perform(operations.add(object))
    }

    /// Ribbons and extrusions face the guide's normal (a plane), else the average surface normal.
    private func strokeNormal(normals: [Vec3], guide: GuideSurface?) -> Vec3 {
        if case let .plane(_, normal)? = guide { return normal }
        guard !normals.isEmpty else { return .unitY }
        let averaged = normals.reduce(Vec3.zero, +).normalized
        return averaged.length > 0.5 ? averaged : .unitY
    }

    /// The object's origin: the lathe axis base, else the first point.
    private func strokeOrigin(_ points: [Vec3]) -> Vec3 {
        guard draw.style == .lathe else { return points[0] }
        let target = stage?.viewpoint.target ?? .zero
        let center = selectionBounds.map { Vec3($0.center.x, $0.min.y, $0.center.z) } ?? Vec3(target.x, 0, target.z)
        return Vec3(center.x, points.map(\.y).min() ?? center.y, center.z)
    }

    private var guideCenterX: Double? {
        switch currentGuide {
        case let .plane(origin, _): origin.x
        case let .box(center, _): center.x
        case let .cylinder(base, _, _): base.x
        case let .sphere(center, _): center.x
        case nil: selectionBounds?.center.x
        }
    }

    // MARK: Shadow Brush

    /// One dab of the Shadow Brush at a world point on an object: pushes its toon shadow in (or pulls it out) there.
    /// Dabs of one stroke coalesce into one undo step.
    func paintShadow(on id: ObjectID, at world: Vec3, pressure: Double, gesture: String) {
        guard let object = baseScene.objects[id], object.kind.hasSurface, !baseScene.isEffectivelyLocked(id) else { return }
        let transform = displayed.scene.worldTransform(of: id)
        let local = transform.inverseApply(to: world)
        let scale = max(abs(transform.scale.x), abs(transform.scale.y), abs(transform.scale.z), 1e-3)
        let amount = shadowBrush.strength * min(max(pressure, 0.1), 1) * (shadowBrush.pushesShadow ? -1 : 1)
        let dab = ShadowDab(position: local, radius: shadowBrush.radius / scale, amount: amount)
        let dabs = ShadowPaint.adding(dab, to: object.shadowDabs)
        perform(.setShadowPaint(id, dabs), coalesceKey: gesture)
    }

    func clearShadowPaint() {
        let painted = selection.filter { !(baseScene.objects[$0]?.shadowDabs.isEmpty ?? true) }
        guard !painted.isEmpty else { return }
        perform(.batch("Clear shadows", painted.map { EditCommand.setShadowPaint($0, []) }))
        HmmHaptics.play(.commit)
    }

    var selectionHasShadowPaint: Bool {
        selection.contains { !(baseScene.objects[$0]?.shadowDabs.isEmpty ?? true) }
    }
}
