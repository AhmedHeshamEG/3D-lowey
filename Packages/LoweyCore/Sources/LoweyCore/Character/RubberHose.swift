import Foundation

public extension PropertyKey {
    /// Rubber hose: the object (id) the tube starts at, e.g. a shoulder.
    static let hoseFrom: PropertyKey = "hoseFrom"
    /// Rubber hose: the object (id) it ends at, e.g. a hand.
    static let hoseTo: PropertyKey = "hoseTo"
    /// Where on the end object it attaches (the wrist), in that object's space.
    static let hoseWrist: PropertyKey = "hoseWrist"
    /// Tube radius (metres).
    static let hoseRadius: PropertyKey = "hoseRadius"
}

/// Rubber-hose limbs (the 1930s cartoon arm): a bendy tube from one object to another that follows wherever the
/// end goes. Move or key a hand and its arm bends to reach it; nothing to rig, nothing to key on the arm.
public enum RubberHose {
    /// Samples along the curve.
    static let samples = 14

    /// The tube's stroke for `hose` in its own space, or nil if its ends are missing.
    public static func stroke(for hose: ObjectID, in scene: Scene) -> DrawingRecipe.Stroke? {
        guard let object = scene.objects[hose],
              let fromRaw = object[.hoseFrom]?.stringValue, let toRaw = object[.hoseTo]?.stringValue else { return nil }
        let from = ObjectID(raw: fromRaw)
        let to = ObjectID(raw: toRaw)
        guard scene.objects[from] != nil, scene.objects[to] != nil else { return nil }
        // Everything in the hose's own space, so a character that tilts or floats keeps its arms' shape.
        let space = scene.worldTransform(of: hose)
        let fromWorld = scene.worldTransform(of: from)
        let end = scene.worldTransform(of: to)
        let start = space.inverseApply(to: fromWorld.position)
        let wrist = space.inverseApply(to: end.apply(to: object[.hoseWrist]?.vec3Value ?? .zero))
        let handUp = (space.inverseApply(to: end.apply(to: .unitY)) - space.inverseApply(to: end.position)).normalized
        // Leave the shoulder sideways (away from what the shoulder sits on), arrive along the hand's own up.
        let anchor = scene.objects[from]?.parent.map { space.inverseApply(to: scene.worldTransform(of: $0).position) } ?? start
        var outward = start - anchor
        outward.y = 0
        let side = outward.length > 1e-6 ? outward.normalized : Vec3(1, 0, 0)
        let reach = max(start.distance(to: wrist), 0.05)
        let c0 = start + side * (reach * 0.45) - Vec3(0, reach * 0.15, 0)
        let c1 = wrist + handUp * (reach * 0.45)
        let radius = object[.hoseRadius]?.floatValue ?? 0.017
        var points: [Vec3] = []
        for index in 0 ... samples {
            let t = Double(index) / Double(samples)
            let u = 1 - t
            points.append(start * (u * u * u) + c0 * (3 * u * u * t) + c1 * (3 * u * t * t) + wrist * (t * t * t))
        }
        return DrawingRecipe.Stroke(points: points, widths: Array(repeating: radius, count: points.count))
    }

    /// Re-bends every hose whose ends moved (a hose at rest is left alone, so it's never rebuilt for nothing).
    public static func apply(to scene: inout Scene, animated: inout Set<ObjectID>) {
        for (id, object) in scene.objects where object[.hoseFrom] != nil {
            guard case let .drawing(recipe) = object.kind, let stroke = stroke(for: id, in: scene) else { continue }
            if let current = recipe.strokes.first, current.points.count == stroke.points.count,
               zip(current.points, stroke.points).allSatisfy({ $0.isApproximately($1, tolerance: 1e-5) }) {
                continue
            }
            var bent = recipe
            bent.strokes = [stroke]
            scene.objects[id]?.kind = .drawing(bent)
            animated.insert(id)
        }
    }
}
