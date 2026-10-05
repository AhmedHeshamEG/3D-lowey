import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Sketching with the Model tool: taps place a shape's points on the face under the first tap (or the ground),
/// closed shapes fill into regions, and the sizes of the shape just drawn float beside it, ready to type.
extension EditorModel {
    func sketch(_ id: ObjectID) -> Sketch? {
        guard case let .sketch(sketch)? = baseScene.objects[id]?.kind else { return nil }
        return sketch
    }

    /// The sketch objects in the scene, shown ones only.
    var sketches: [(id: ObjectID, sketch: Sketch)] {
        baseScene.objects.values.compactMap { object in
            guard case let .sketch(sketch) = object.kind, baseScene.isEffectivelyVisible(object.id) else { return nil }
            return (object.id, sketch)
        }.sorted { $0.id.raw < $1.id.raw }
    }

    /// The nearest sketch region under a screen point.
    func sketchRegion(at point: CGPoint) -> SketchRegionRef? {
        guard let ray = stage?.worldRay(at: point) else { return nil }
        var best: (ref: SketchRegionRef, distance: Double)?
        for (id, sketch) in sketches {
            guard let (local, distance) = intersect(ray, sketch.plane), distance < (best?.distance ?? .infinity),
                  let index = sketch.region(at: local) else { continue }
            best = (SketchRegionRef(sketch: id, index: index), distance)
        }
        return best?.ref
    }

    func selectRegion(_ region: SketchRegionRef) {
        cancelPushPull()
        modeling.elements = nil
        modeling.target = nil
        modeling.region = region
        HmmHaptics.play(.selection)
    }

    private func intersect(_ ray: Ray, _ plane: PlaneFrame) -> (Vec2, Double)? {
        let denominator = ray.direction.dot(plane.normal)
        guard abs(denominator) > 1e-9 else { return nil }
        let distance = (plane.origin - ray.origin).dot(plane.normal) / denominator
        guard distance > 0 else { return nil }
        return (plane.project(ray.point(at: distance)), distance)
    }

    // MARK: Taps

    /// A tap while a sketch shape is chosen.
    func sketchTap(at point: CGPoint) {
        guard let kind = modeling.mode.sketchKind else { return }
        if kind == .offset {
            pickOffsetSource(at: point)
            return
        }
        if modeling.pending == nil {
            // The first tap on a region picks it (to pull); a tap inside the picked region starts a shape there.
            if let region = sketchRegion(at: point), region != modeling.region {
                selectRegion(region)
                return
            }
            guard let start = startShape(at: point) else { return }
            modeling.pending = start
            modeling.region = nil
            modeling.lastCurve = nil
        }
        guard let pending = modeling.pending, let ray = stage?.worldRay(at: point), let (local, _) = intersect(ray, pending.plane) else { return }
        addPoint(snapped(local, on: pending), kind: kind)
    }

    /// Where a new shape lies: the face under the tap (it can be pulled into or cut from that object), else the ground.
    private func startShape(at point: CGPoint) -> PendingSketch? {
        guard let stage else { return nil }
        var plane = PlaneFrame(origin: .zero, normal: .unitY, u: .unitX, v: Vec3(0, 0, -1))
        var target: ObjectID?
        if let (id, _) = stage.pickObject(at: point), let (mesh, world) = modelMesh(of: id), let ray = stage.worldRay(at: point) {
            let local = Ray(origin: world.inverseApply(to: ray.origin), direction: world.inverseApplyDirection(ray.direction))
            if let hit = MeshPicking.face(local, in: mesh) {
                let normal = world.applyDirection(mesh.normal(of: hit.face)).normalized
                let corner = world.apply(to: mesh.vertices[mesh.faces[hit.face].outline[0]])
                plane = Self.planeFacing(normal: normal, origin: corner)
                target = id
            }
        }
        // Join a sketch already on this plane (and object), so shapes drawn together make regions together.
        let existing = sketches.first { _, sketch in
            sketch.target == target && sketch.plane.normal.dot(plane.normal) > 1 - 1e-9 && abs(sketch.plane.height(of: plane.origin)) < 1e-7
        }
        if let existing { plane = existing.sketch.plane }
        return PendingSketch(plane: plane, target: target, sketch: existing?.id, points: [])
    }

    /// A plane frame whose axes follow the world where they can (u along x on floors and walls facing z).
    static func planeFacing(normal: Vec3, origin: Vec3) -> PlaneFrame {
        // Floors and ceilings: u is x laid onto the plane. Walls: u runs level (up × normal), so v points up.
        let u = abs(normal.y) > 0.9 ? (Vec3.unitX - normal * normal.x).normalized : Vec3.unitY.cross(normal).normalized
        return PlaneFrame(origin: origin, normal: normal, u: u, v: normal.cross(u))
    }

    /// Snaps to the corners already drawn on the plane (within 12 points), else to the grid.
    private func snapped(_ point: Vec2, on pending: PendingSketch) -> Vec2 {
        guard let stage, let screen = stage.screenPoint(of: pending.plane.lift(point)) else { return point }
        var corners = pending.points
        if let id = pending.sketch, let sketch = sketch(id) { corners += sketch.curves.flatMap(\.points) }
        let near = corners.min { lhs, rhs in
            distanceOnScreen(lhs, pending.plane, to: screen) < distanceOnScreen(rhs, pending.plane, to: screen)
        }
        if let near, distanceOnScreen(near, pending.plane, to: screen) < 12 { return near }
        guard snap.grid, snap.gridSize > 0 else { return point }
        let step = min(snap.gridSize, units.metres * 10)
        return Vec2((point.x / step).rounded() * step, (point.y / step).rounded() * step)
    }

    private func distanceOnScreen(_ point: Vec2, _ plane: PlaneFrame, to screen: CGPoint) -> CGFloat {
        guard let projected = stage?.screenPoint(of: plane.lift(point)) else { return .infinity }
        return hypot(projected.x - screen.x, projected.y - screen.y)
    }

    private func addPoint(_ point: Vec2, kind: SketchKind) {
        guard var pending = modeling.pending else { return }
        let first = pending.points.first
        let closes = first.map { $0 == point } ?? false
        switch kind {
        case .rectangle:
            if let first, abs(first.x - point.x) > 1e-9, abs(first.y - point.y) > 1e-9 {
                commit(.rectangle(first, point))
            } else {
                push(point)
            }
        case .circle:
            if let first, (first - point).length > 1e-9 {
                commit(.circle(center: first, radius: (first - point).length))
            } else {
                push(point)
            }
        case .arc:
            if pending.points.count == 2 {
                commit(.arc(pending.points[0], point, pending.points[1]))
            } else {
                push(point)
            }
        case .line:
            if let last = pending.points.last, last != point {
                commit(.line(last, point), keepGoing: !closes)
                if !closes, var updated = modeling.pending {
                    updated.points = [first ?? last, point]
                    modeling.pending = updated
                }
            } else if pending.points.isEmpty {
                push(point)
            }
        case .spline:
            if closes, pending.points.count >= 3 {
                commit(.spline(pending.points, closed: true))
            } else {
                push(point)
            }
        case .offset:
            break
        }
        pending = modeling.pending ?? pending
        if modeling.pending != nil { app.show(kind.hint(points: pending.points.count)) }
    }

    private func push(_ point: Vec2) {
        modeling.pending?.points.append(point)
        HmmHaptics.play(.selection)
    }

    /// Ends a line run or an open spline (the bar's Done).
    func finishSketchShape() {
        guard let pending = modeling.pending else { return }
        if modeling.mode.sketchKind == .spline, pending.points.count >= 2 {
            commit(.spline(pending.points, closed: false))
        }
        modeling.pending = nil
    }

    /// Adds a finished curve to its sketch (one undo step), making the sketch when it's the first.
    private func commit(_ curve: SketchCurve, keepGoing: Bool = false) {
        guard var pending = modeling.pending else { return }
        let command: EditCommand?
        let sketchID: ObjectID
        if let id = pending.sketch, sketch(id) != nil {
            sketchID = id
            command = ModelingOperations.addCurves([curve], to: id, in: baseScene)
        } else {
            var ids = operations.ids
            sketchID = ids.next()
            operations.ids = ids
            let object = ModelingOperations.newSketch(on: pending.plane, curves: [curve], target: pending.target, id: sketchID)
            command = .batch("Draw", [.insert(SceneFragment(object: object), parent: nil, index: nil)])
        }
        guard perform(command), let count = sketch(sketchID)?.curves.count else { return }
        HmmHaptics.play(.commit)
        modeling.lastCurve = SketchCurveRef(sketch: sketchID, index: count - 1)
        pending.sketch = sketchID
        modeling.pending = keepGoing ? pending : nil
    }

    // MARK: Offset

    private func pickOffsetSource(at point: CGPoint) {
        guard let stage else { return }
        var best: (ref: SketchCurveRef, distance: CGFloat)?
        for (id, sketch) in sketches {
            for (index, curve) in sketch.curves.enumerated() {
                let screen = curve.points.compactMap { stage.screenPoint(of: sketch.plane.lift($0)) }
                let distance = Self.distance(from: point, toPolyline: screen, closed: curve.isClosed)
                if distance < (best?.distance ?? 24) { best = (SketchCurveRef(sketch: id, index: index), distance) }
            }
        }
        modeling.offsetSource = best?.ref
        if best != nil {
            modeling.editing = .offset
            HmmHaptics.play(.selection)
        }
    }

    static func distance(from point: CGPoint, toPolyline points: [CGPoint], closed: Bool) -> CGFloat {
        guard points.count >= 2 else { return .infinity }
        let count = closed ? points.count : points.count - 1
        return (0 ..< count).map { index in
            let a = points[index], b = points[(index + 1) % points.count]
            let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let lengthSquared = max(ab.x * ab.x + ab.y * ab.y, 1e-9)
            let t = min(max(((point.x - a.x) * ab.x + (point.y - a.y) * ab.y) / lengthSquared, 0), 1)
            return hypot(point.x - (a.x + ab.x * t), point.y - (a.y + ab.y * t))
        }.min() ?? .infinity
    }

    func applyOffset(_ distance: Double) {
        guard let source = modeling.offsetSource, let sketch = sketch(source.sketch), sketch.curves.indices.contains(source.index) else { return }
        guard let offset = sketch.curves[source.index].offset(by: distance) else {
            app.show("That would turn the shape inside out", kind: .error)
            return
        }
        guard perform(ModelingOperations.addCurves([offset], to: source.sketch, in: baseScene)) else { return }
        HmmHaptics.play(.commit)
        modeling.lastCurve = SketchCurveRef(sketch: source.sketch, index: sketch.curves.count)
        modeling.offsetSource = nil
    }

    // MARK: Sizes of the shape just drawn

    /// The current value of a size on the stage (metres).
    func dimensionValue(_ field: DimensionField) -> Double? {
        if field == .pull { return modeling.pull ?? 0 }
        if field == .offset { return 0 }
        guard let ref = modeling.lastCurve, let curve = sketch(ref.sketch)?.curves[safe: ref.index] else { return nil }
        switch (field, curve) {
        case let (.rectangleSide(horizontal), .rectangle(a, b)): return horizontal ? abs(b.x - a.x) : abs(b.y - a.y)
        case let (.diameter, .circle(_, radius)): return radius * 2
        case let (.lineLength, .line(a, b)): return (b - a).length
        default: return nil
        }
    }

    /// Sets a size of the shape just drawn (its first corner, centre or start stays put).
    func setDimension(_ field: DimensionField, to metres: Double) {
        guard metres > 1e-9, let ref = modeling.lastCurve, var sketch = sketch(ref.sketch), let curve = sketch.curves[safe: ref.index] else { return }
        let resized: SketchCurve? = switch (field, curve) {
        case let (.rectangleSide(true), .rectangle(a, b)): .rectangle(a, Vec2(a.x + (b.x >= a.x ? metres : -metres), b.y))
        case let (.rectangleSide(false), .rectangle(a, b)): .rectangle(a, Vec2(b.x, a.y + (b.y >= a.y ? metres : -metres)))
        case let (.diameter, .circle(center, _)): .circle(center: center, radius: metres / 2)
        case let (.lineLength, .line(a, b)): .line(a, a + (b - a) * (metres / max((b - a).length, 1e-12)))
        default: nil
        }
        guard let resized else { return }
        sketch.curves[ref.index] = resized
        if perform(.batch("Change size", [.setKind(ref.sketch, .sketch(sketch))])) { HmmHaptics.play(.commit) }
    }

    /// Typed into a floating number: a length, then whatever that number does.
    func submitDimension(_ field: DimensionField, text: String) {
        modeling.editing = nil
        guard let metres = parseLength(text) else { return }
        switch field {
        case .pull: commitPull(metres)
        case .offset: applyOffset(metres)
        default: setDimension(field, to: metres)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
