import Foundation

/// Smears: on fast frames an object stretches along its motion and trails behind it, the way animators draw a fast
/// move (one long frame instead of a blur). Opt-in per object with the `smear` amount; computed from where the object
/// was a frame earlier, so it's the same on the stage and in every export.
public struct Smear: Hashable, Sendable {
    /// Unit direction of travel (world space).
    public var direction: Vec3
    /// Length multiplier along the direction (> 1).
    public var stretch: Double
    /// How far the stretched shape slides back so its leading edge stays where the object is (metres).
    public var shift: Double
    /// The point it stretches about (world).
    public var pivot: Vec3

    /// Below this many object lengths per frame there's no smear (slow moves stay clean).
    public static let threshold = 0.15

    /// The smear of an object moving from `previous` to `current` in one frame, `extent` metres long, `amount` 0…1.
    public static func make(previous: Vec3, current: Vec3, extent: Double, amount: Double) -> Smear? {
        let travel = current - previous
        let distance = travel.length
        let size = max(extent, 0.01)
        guard amount > 0.001, distance / size > threshold else { return nil }
        let speed = min(distance / size - threshold, 2.5)
        let stretch = 1 + min(amount, 1) * speed * 0.8
        return Smear(direction: travel / distance, stretch: stretch, shift: (stretch - 1) * size / 2, pivot: current)
    }

    /// Applies the smear to a world point.
    public func apply(to point: Vec3) -> Vec3 {
        let offset = point - pivot
        let along = offset.dot(direction)
        return pivot + offset + direction * (along * (stretch - 1)) - direction * shift
    }

    /// Smears of every smearing object at `time` (one frame back at the timeline's rate).
    public static func smears(in document: Document, at time: Double) -> [ObjectID: Smear] {
        let scene = document.scene
        let fps = Double(max(scene.timeline.fps, 1))
        let smearing = scene.objects.values.filter { ($0[.smear]?.floatValue ?? 0) > 0.001 }
        guard !smearing.isEmpty, time > 0 else { return [:] }
        let rates = FrameRates(document)
        var result: [ObjectID: Smear] = [:]
        for object in smearing {
            let current = MotionPath.worldPosition(of: object.id, in: document, at: time, rates: rates)
            let previous = MotionPath.worldPosition(of: object.id, in: document, at: max(time - 1 / fps, 0), rates: rates)
            let scale = scene.worldTransform(of: object.id).scale
            let extent = max(abs(scale.x), abs(scale.y), abs(scale.z))
            result[object.id] = make(previous: previous, current: current, extent: extent, amount: object[.smear]?.floatValue ?? 0)
        }
        return result
    }
}

public extension PropertyKey {
    /// 0…1: how much an object stretches along fast moves (0 = never).
    static let smear: PropertyKey = "smear"
}
