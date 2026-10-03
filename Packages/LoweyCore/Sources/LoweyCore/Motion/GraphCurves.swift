import Foundation

/// The graph editor's maths: a keyed property as curves (one per component: X / Y / Z of a position or scale, the
/// three turn angles of a rotation, or the value of a number), its key dots, and the tangent handles of the segment
/// leaving a key, which are that segment's easing (a cubic Bézier between the two keys).
public enum GraphCurves {
    /// The numbers a value is drawn as (nil for values that aren't curves: colours, text, switches).
    public static func components(_ value: PropertyValue) -> [Double]? {
        switch value {
        case let .float(number): return [number]
        case let .int(number): return [Double(number)]
        case let .vec3(vector): return [vector.x, vector.y, vector.z]
        case let .quat(rotation):
            let euler = rotation.eulerDegrees
            return [euler.x, euler.y, euler.z]
        default: return nil
        }
    }

    /// Names of a property's curves.
    public static func componentNames(_ value: PropertyValue) -> [String] {
        switch value {
        case .vec3: ["X", "Y", "Z"]
        case .quat: ["Tilt", "Turn", "Roll"]
        default: ["Value"]
        }
    }

    /// `value` with one component changed.
    public static func replacing(component: Int, with number: Double, in value: PropertyValue) -> PropertyValue {
        switch value {
        case .float: return .float(number)
        case .int: return .int(Int(number.rounded()))
        case var .vec3(vector):
            vector[Axis.allCases[min(max(component, 0), 2)]] = number
            return .vec3(vector)
        case let .quat(rotation):
            var euler = rotation.eulerDegrees
            euler[Axis.allCases[min(max(component, 0), 2)]] = number
            return .quat(Quat(eulerDegrees: euler))
        default:
            return value
        }
    }

    /// A component sampled `count` times across the track's keys (plus a margin), for drawing.
    public static func curve(_ track: Track, component: Int, from start: Double, to end: Double, count: Int = 120) -> [(time: Double, value: Double)] {
        guard count > 1, end > start else { return [] }
        return (0 ..< count).compactMap { index in
            let time = start + (end - start) * Double(index) / Double(count - 1)
            guard let value = track.value(at: time), let numbers = components(value), numbers.indices.contains(component) else { return nil }
            return (time, numbers[component])
        }
    }

    /// The handles of the segment leaving key `index` (time, value) on one component, or nil for the last key or a
    /// segment whose easing isn't a curve (a step).
    public static func handles(_ track: Track, key index: Int, component: Int) -> (first: (time: Double, value: Double),
                                                                                   second: (time: Double, value: Double))? {
        let keys = track.keyframes
        guard keys.indices.contains(index), index + 1 < keys.count, let bezier = bezier(of: keys[index].easing),
              let from = components(keys[index].value), let to = components(keys[index + 1].value),
              from.indices.contains(component), to.indices.contains(component) else { return nil }
        let t0 = keys[index].time
        let span = keys[index + 1].time - t0
        let v0 = from[component]
        let rise = to[component] - v0
        return ((t0 + bezier.0 * span, v0 + bezier.1 * rise), (t0 + bezier.2 * span, v0 + bezier.3 * rise))
    }

    /// The segment's easing after dragging one of its handles to (`time`, `value`). Flat segments keep the handle's
    /// height (there's no rise to scale it by).
    public static func easing(_ track: Track, key index: Int, component: Int, first: Bool, to time: Double, value: Double) -> Easing? {
        let keys = track.keyframes
        guard keys.indices.contains(index), index + 1 < keys.count, let from = components(keys[index].value),
              let to = components(keys[index + 1].value), from.indices.contains(component) else { return nil }
        var bezier = bezier(of: keys[index].easing) ?? (0.42, 0, 0.58, 1)
        let span = max(keys[index + 1].time - keys[index].time, 1e-6)
        let rise = to[component] - from[component]
        let x = min(max((time - keys[index].time) / span, 0), 1)
        let y = abs(rise) > 1e-9 ? min(max((value - from[component]) / rise, -1.5), 2.5) : (first ? bezier.1 : bezier.3)
        if first { bezier = (x, y, bezier.2, bezier.3) } else { bezier = (bezier.0, bezier.1, x, y) }
        return .cubicBezier(bezier.0, bezier.1, bezier.2, bezier.3)
    }

    /// The Bézier handles of an easing (presets approximated by their CSS curves).
    public static func bezier(of easing: Easing) -> (Double, Double, Double, Double)? {
        switch easing {
        case .linear: (0.25, 0.25, 0.75, 0.75)
        case .easeIn: (0.55, 0.06, 0.68, 0.19)
        case .easeOut: (0.22, 0.61, 0.36, 1)
        case .easeInOut: (0.65, 0, 0.35, 1)
        case .backOut: (0.34, 1.56, 0.64, 1)
        case let .cubicBezier(a, b, c, d): (a, b, c, d)
        case .bounce, .elastic, .step: nil
        }
    }

    /// The track with key `index` moved to `time` (kept between its neighbours, a frame apart) and one component set.
    public static func moving(key index: Int, in track: Track, to time: Double, component: Int, value: Double, fps: Int) -> Track {
        var keys = track.keyframes
        guard keys.indices.contains(index) else { return track }
        let frame = 1 / Double(max(fps, 1))
        let earliest = index > 0 ? keys[index - 1].time + frame : -Double.infinity
        let latest = index + 1 < keys.count ? keys[index + 1].time - frame : Double.infinity
        let snapped = (min(max(time, earliest), latest) * Double(max(fps, 1))).rounded() / Double(max(fps, 1))
        keys[index].time = max(snapped, 0)
        keys[index].value = replacing(component: component, with: value, in: keys[index].value)
        var result = track
        result.setKeys(keys)
        return result
    }
}
