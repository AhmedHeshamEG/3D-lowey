import Foundation

/// The six looping motions of the inspector's Motion row (CONTEXT §4.1): tap a thing, tap a motion, it moves. Each is
/// a behaviour with sensible numbers and one speed (1 = its own pace), so there's nothing to set up and one slider to
/// change. Making keyframes of one is baking that behaviour.
public enum LoopMotion: String, CaseIterable, Sendable, Identifiable {
    case spin, float, bounce, wiggle, swing, followPath

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .spin: "Spin"
        case .float: "Float"
        case .bounce: "Bounce"
        case .wiggle: "Wiggle"
        case .swing: "Swing"
        case .followPath: "Follow a path"
        }
    }

    /// How slow and how fast the one slider goes.
    public static let speedRange: ClosedRange<Double> = 0.25 ... 4

    /// Seconds for one trip along a path at speed 1.
    static let pathSeconds = 6.0

    /// The behaviour for this motion at a speed. Follow a path needs the drawn path to follow.
    public func behavior(speed: Double = 1, path: ObjectID? = nil) -> BehaviorKind? {
        let pace = min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
        switch self {
        case .spin: return .spin(degreesPerSecond: 90 * pace, axis: .y)
        case .float: return .bob(height: 0.12, period: 3 / pace, tilt: 4)
        case .bounce: return .bounce(height: 0.4, period: 1 / pace)
        case .wiggle: return .noise(position: Vec3(0.04, 0.04, 0.04), rotation: Vec3(5, 5, 5), frequency: 1.2 * pace)
        case .swing: return .swing(angle: 25, period: 2 / pace)
        case .followPath:
            guard let path else { return nil }
            return .followPath(.object(path), duration: Self.pathSeconds / pace, loop: true, orient: true)
        }
    }

    /// Which motion a behaviour is, and at what speed (nil: not one of the six, such as a path followed once).
    public static func reading(_ kind: BehaviorKind) -> (motion: LoopMotion, speed: Double)? {
        switch kind {
        case let .spin(degreesPerSecond, _): (.spin, abs(degreesPerSecond) / 90)
        case let .bob(_, period, _) where period > 0: (.float, 3 / period)
        case let .bounce(_, period) where period > 0: (.bounce, 1 / period)
        case let .noise(_, _, frequency): (.wiggle, frequency / 1.2)
        case let .swing(_, period) where period > 0: (.swing, 2 / period)
        case let .followPath(_, duration, true, _) where duration > 0: (.followPath, pathSeconds / duration)
        default: nil
        }
    }

    /// The same behaviour at another speed, keeping everything else about it (its size, its path, its axis).
    public static func retimed(_ kind: BehaviorKind, speed: Double) -> BehaviorKind {
        let pace = min(max(speed, speedRange.lowerBound), speedRange.upperBound)
        switch kind {
        case let .spin(degreesPerSecond, axis): return .spin(degreesPerSecond: (degreesPerSecond < 0 ? -90 : 90) * pace, axis: axis)
        case let .bob(height, _, tilt): return .bob(height: height, period: 3 / pace, tilt: tilt)
        case let .bounce(height, _): return .bounce(height: height, period: 1 / pace)
        case let .noise(position, rotation, _): return .noise(position: position, rotation: rotation, frequency: 1.2 * pace)
        case let .swing(angle, _): return .swing(angle: angle, period: 2 / pace)
        case let .followPath(source, _, true, orient): return .followPath(source, duration: pathSeconds / pace, loop: true, orient: orient)
        default: return kind
        }
    }
}
