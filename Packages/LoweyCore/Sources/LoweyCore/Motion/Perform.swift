import Foundation

/// A Perform take: samples of one property recorded while the timeline played.
/// Lifting the finger pauses recording, so a take is a list of segments.
public struct PerformTake: Hashable, Sendable {
    public struct Sample: Hashable, Sendable {
        public var time: Double
        public var value: PropertyValue

        public init(time: Double, value: PropertyValue) {
            self.time = time
            self.value = value
        }
    }

    public var object: ObjectID
    public var property: PropertyKey
    public var segments: [[Sample]]
    /// A trigger's channel: each sample is a switch, kept as a held key at its own moment (never smoothed or resampled).
    public var stepped: Bool

    public init(object: ObjectID, property: PropertyKey, segments: [[Sample]] = [], stepped: Bool = false) {
        self.object = object
        self.property = property
        self.segments = segments
        self.stepped = stepped
    }

    /// Switches, and values that can't be blended (a mouth shape, shown or hidden), are held keys.
    public var isStepped: Bool {
        if stepped { return true }
        for segment in segments {
            guard let value = segment.first?.value else { continue }
            switch value {
            case .float, .vec3, .quat, .color: return false
            default: return true
            }
        }
        return false
    }

    public mutating func begin() {
        if segments.last?.isEmpty != true { segments.append([]) }
    }

    public mutating func add(_ sample: Sample) {
        if segments.isEmpty { segments.append([]) }
        segments[segments.count - 1].append(sample)
    }

    public var isEmpty: Bool { segments.allSatisfy(\.isEmpty) }
}

/// Turns Perform takes into keyframes ("motion capture by touch", like Procreate Dreams' Performing).
public enum PerformBaker {
    /// Resamples a segment at `fps`, smooths it (`smoothing` 0…1, zero-phase so it doesn't lag behind
    /// the finger) and — when smoothing > 0 — drops keys the curve doesn't need. 0 % keeps every frame.
    public static func keys(from samples: [PerformTake.Sample], fps: Int, smoothing: Double, stepped: Bool = false) -> [Keyframe] {
        let sorted = samples.sorted { $0.time < $1.time }
        guard let first = sorted.first, let last = sorted.last else { return [] }
        if stepped { return held(sorted) }
        guard sorted.count > 1, last.time > first.time else {
            return [Keyframe(time: first.time, value: first.value, easing: .linear)]
        }
        let step = 1 / Double(max(fps, 1))
        // Resample on the frame grid (plus the exact start and end of the segment).
        var times: [Double] = [first.time]
        var frame = (first.time / step).rounded(.up) * step
        while frame < last.time - 1e-9 {
            if frame > first.time + 1e-9 { times.append(frame) }
            frame += step
        }
        times.append(last.time)
        var values = times.map { interpolate(sorted, at: $0) }

        let amount = min(max(smoothing, 0), 1)
        if amount > 0 {
            values = smooth(values, amount: amount)
        }
        var keys = zip(times, values).map { Keyframe(time: $0, value: $1, easing: .linear) }
        if amount > 0, keys.count > 2 {
            keys = simplify(keys, tolerance: tolerance(for: values, amount: amount))
        }
        return keys
    }

    /// Held keys: one where the value changes, and one at the end so the stretch's length is known.
    static func held(_ sorted: [PerformTake.Sample]) -> [Keyframe] {
        var keys: [Keyframe] = []
        for sample in sorted where keys.last?.value != sample.value {
            if let last = keys.last, abs(last.time - sample.time) < 0.0005 {
                keys[keys.count - 1] = Keyframe(time: last.time, value: sample.value, easing: .step)
            } else {
                keys.append(Keyframe(time: sample.time, value: sample.value, easing: .step))
            }
        }
        if let last = sorted.last, let key = keys.last, last.time > key.time + 0.0005 {
            keys.append(Keyframe(time: last.time, value: last.value, easing: .step))
        }
        return keys
    }

    /// Replaces the recorded ranges of `track` with the take (other keys stay).
    public static func apply(_ take: PerformTake, to track: Track, fps: Int, smoothing: Double) -> Track {
        var result = track
        for segment in take.segments where !segment.isEmpty {
            let keys = keys(from: segment, fps: fps, smoothing: smoothing, stepped: take.isStepped)
            guard let first = keys.first, let last = keys.last else { continue }
            result.removeKeys(in: TimeRange(start: first.time, end: last.time))
            for key in keys {
                result.setKey(key)
            }
        }
        return result
    }

    /// One command for a whole take (possibly several properties performed together).
    public static func command(for takes: [PerformTake], fps: Int, smoothing: Double, timeline: Timeline, ids: inout IDFactory) -> EditCommand? {
        var edits: [TrackEdit] = []
        for take in takes where !take.isEmpty {
            let existing = timeline.track(for: take.object, take.property) ?? Track(id: ids.next(), target: take.object, property: take.property)
            let track = apply(take, to: existing, fps: fps, smoothing: smoothing)
            guard !track.keyframes.isEmpty else { continue }
            edits.append(TrackEdit(track))
        }
        return edits.isEmpty ? nil : .batch("Perform", [.setTracks(edits)])
    }

    // MARK: Math

    static func interpolate(_ samples: [PerformTake.Sample], at time: Double) -> PropertyValue {
        if time <= samples[0].time { return samples[0].value }
        if time >= samples[samples.count - 1].time { return samples[samples.count - 1].value }
        var lo = 0
        var hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].time <= time { lo = mid } else { hi = mid }
        }
        let span = samples[hi].time - samples[lo].time
        let t = span > 0 ? (time - samples[lo].time) / span : 0
        return samples[lo].value.interpolated(to: samples[hi].value, t)
    }

    /// Zero-phase exponential smoothing (forward then backward pass).
    static func smooth(_ values: [PropertyValue], amount: Double) -> [PropertyValue] {
        guard values.count > 2 else { return values }
        // amount 1 ≈ a quarter-second window at 30 fps.
        let alpha = 1 - amount * 0.88
        var forward = values
        for index in 1 ..< forward.count {
            forward[index] = forward[index - 1].interpolated(to: values[index], alpha)
        }
        var backward = forward
        for index in stride(from: backward.count - 2, through: 0, by: -1) {
            backward[index] = backward[index + 1].interpolated(to: forward[index], alpha)
        }
        // Keep the exact end points the performer reached.
        backward[0] = values[0]
        backward[backward.count - 1] = values[values.count - 1]
        return backward
    }

    static func tolerance(for values: [PropertyValue], amount: Double) -> Double {
        var span = 0.0
        if let first = values.first {
            for value in values {
                span = max(span, distance(first, value))
            }
        }
        return max(span, 1e-3) * 0.004 * amount
    }

    static func distance(_ a: PropertyValue, _ b: PropertyValue) -> Double {
        switch (a, b) {
        case let (.float(x), .float(y)): abs(x - y)
        case let (.vec3(x), .vec3(y)): x.distance(to: y)
        case let (.quat(x), .quat(y)): 2 * acos(min(abs(x.normalized.dot(y.normalized)), 1))
        case let (.color(x), .color(y)):
            {
                let p = x.resolved(in: .empty)
                let q = y.resolved(in: .empty)
                return abs(p.r - q.r) + abs(p.g - q.g) + abs(p.b - q.b)
            }()
        default: a == b ? 0 : 1
        }
    }

    /// Ramer–Douglas–Peucker on the time series: removes keys that linear interpolation recreates.
    static func simplify(_ keys: [Keyframe], tolerance: Double) -> [Keyframe] {
        guard keys.count > 2 else { return keys }
        var keep = [Bool](repeating: false, count: keys.count)
        keep[0] = true
        keep[keys.count - 1] = true
        var stack = [(0, keys.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            var worst = 0.0
            var worstIndex = -1
            for index in a + 1 ..< b {
                let t = (keys[index].time - keys[a].time) / (keys[b].time - keys[a].time)
                let predicted = keys[a].value.interpolated(to: keys[b].value, t)
                let error = distance(predicted, keys[index].value)
                if error > worst {
                    worst = error
                    worstIndex = index
                }
            }
            if worst > tolerance, worstIndex >= 0 {
                keep[worstIndex] = true
                stack.append((a, worstIndex))
                stack.append((worstIndex, b))
            }
        }
        return keys.indices.filter { keep[$0] }.map { keys[$0] }
    }
}
