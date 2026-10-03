import Foundation

/// The arc an object travels (its keyed motion, parents included), with a dot per position key that can be dragged
/// to reshape the arc.
public struct MotionPath: Hashable, Sendable {
    public struct KeyDot: Hashable, Sendable {
        public var time: Double
        public var world: Vec3
    }

    /// World positions every sample, in time order.
    public var points: [Vec3]
    public var times: [Double]
    public var keys: [KeyDot]

    /// The path of `id` over the span of its own and its parents' keys (nil when nothing moves it).
    public static func compute(_ document: Document, object id: ObjectID, samplesPerSecond: Double = 15) -> MotionPath? {
        let scene = document.scene
        let timeline = scene.timeline
        let chain = [id] + scene.ancestors(of: id)
        let moving = timeline.tracks.filter { chain.contains($0.target) && [.position, .rotation, .scale].contains($0.property) }
        guard let first = moving.compactMap({ $0.timeRange?.start }).min(), let last = moving.compactMap({ $0.timeRange?.end }).max(),
              last > first else { return nil }
        let rates = FrameRates(document)
        let count = min(max(Int(((last - first) * samplesPerSecond).rounded(.up)), 2), 2000)
        var points: [Vec3] = []
        var times: [Double] = []
        for index in 0 ... count {
            let time = first + (last - first) * Double(index) / Double(count)
            times.append(time)
            points.append(worldPosition(of: id, in: document, at: time, rates: rates))
        }
        let keys = (timeline.track(for: id, .position)?.keyframes ?? []).map { key in
            KeyDot(time: key.time, world: worldPosition(of: id, in: document, at: key.time, rates: rates))
        }
        return MotionPath(points: points, times: times, keys: keys)
    }

    /// Where `id` is at `time` from keys alone (cheap: only the object and its parents are evaluated).
    public static func worldPosition(of id: ObjectID, in document: Document, at time: Double, rates: FrameRates? = nil) -> Vec3 {
        worldTransform(of: id, in: document, at: time, rates: rates ?? FrameRates(document)).position
    }

    static func worldTransform(of id: ObjectID, in document: Document, at time: Double, rates: FrameRates) -> Transform {
        let scene = document.scene
        guard let object = scene.objects[id] else { return .identity }
        let local = keyedTransform(object, in: scene, at: rates.sampleTime(time, for: id, in: scene))
        guard let parent = object.parent else { return local }
        return worldTransform(of: parent, in: document, at: time, rates: rates) * local
    }

    static func keyedTransform(_ object: SceneObject, in scene: Scene, at time: Double) -> Transform {
        let timeline = scene.timeline
        var transform = object.transform
        if let value = timeline.track(for: object.id, .position)?.value(at: time)?.vec3Value { transform.position = value }
        if let value = timeline.track(for: object.id, .rotation)?.value(at: time)?.quatValue { transform.rotation = value }
        if let value = timeline.track(for: object.id, .scale)?.value(at: time)?.vec3Value { transform.scale = value }
        return transform
    }

    /// The edit that moves the position key at `time` so the object is at `world` then (the parent's motion at that
    /// moment taken out). Nil when there's no key there.
    public static func movingKey(at time: Double, of id: ObjectID, to world: Vec3, in document: Document) -> TrackEdit? {
        let scene = document.scene
        guard var track = scene.timeline.track(for: id, .position), let key = track.key(at: time) else { return nil }
        let parentWorld = scene.objects[id]?.parent.map { worldTransform(of: $0, in: document, at: time, rates: FrameRates(document)) } ?? .identity
        track.setKey(Keyframe(time: key.time, value: .vec3(parentWorld.inverseApply(to: world)), easing: key.easing))
        return TrackEdit(track)
    }

    /// The keyed moments around `time` (any key of the object or its parts): the poses an onion skin shows.
    public static func neighbourKeyTimes(of id: ObjectID, in scene: Scene, around time: Double, before: Int,
                                         after: Int) -> (before: [Double], after: [Double]) {
        let ids = Set(scene.subtree(of: id) + scene.ancestors(of: id))
        let times = Set(scene.timeline.tracks.filter { ids.contains($0.target) }.flatMap { $0.keyframes.map(\.time) })
            .map { ($0 * 1000).rounded() / 1000 }
        let unique = Array(Set(times)).sorted()
        let earlier = unique.filter { $0 < time - 1e-4 }.suffix(max(before, 0))
        let later = unique.filter { $0 > time + 1e-4 }.prefix(max(after, 0))
        return (Array(earlier.reversed()), Array(later))
    }
}
