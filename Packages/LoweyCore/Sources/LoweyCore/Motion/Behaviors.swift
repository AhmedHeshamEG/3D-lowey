import Foundation

/// Where a path comes from: explicit world points, or a drawn object (its first stroke, in world space).
public enum PathSource: Hashable, Sendable, Codable {
    case points([Vec3])
    case object(ObjectID)

    private enum Key: String, CodingKey { case points, object }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        if let id = try c.decodeIfPresent(ObjectID.self, forKey: .object) {
            self = .object(id)
        } else {
            self = try .points(c.decode([Vec3].self, forKey: .points))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .points(points): try c.encode(points, forKey: .points)
        case let .object(id): try c.encode(id, forKey: .object)
        }
    }
}

/// Procedural motion that is evaluated at any time (deterministic) and can be baked to keys.
public enum BehaviorKind: Hashable, Sendable {
    /// Move along a path in `duration` seconds (constant speed), optionally turning to face along it.
    case followPath(PathSource, duration: Double, loop: Bool, orient: Bool)
    /// Keep turning to face another object.
    case lookAt(ObjectID)
    /// Stay at a fixed offset from another object, `lag` seconds behind it (a camera following a runner).
    case follow(ObjectID, offset: Vec3, lag: Double)
    /// Circle around a point (or an object's position) once every `period` seconds.
    case orbit(center: Vec3, around: ObjectID?, period: Double, faceCenter: Bool)
    /// Organic wobble of position (m) and rotation (degrees) at `frequency` Hz.
    case noise(position: Vec3, rotation: Vec3, frequency: Double)
    /// Trees in the wind: bend from the base by `angle` degrees, wind coming from `direction` (yaw degrees).
    case windSway(angle: Double, frequency: Double, direction: Double)
    /// Floating on water: up and down by `height`, gently rocking by `tilt` degrees.
    case bob(height: Double, period: Double, tilt: Double)
    /// Continuous spin around a local axis.
    case spin(degreesPerSecond: Double, axis: Axis)
    /// Hopping on the spot like a ball: up to `height` and back down once every `period` seconds.
    case bounce(height: Double, period: Double)
    /// Swinging like a pendulum around its own pivot: `angle` degrees each way, there and back every `period` seconds.
    case swing(angle: Double, period: Double)

    public var title: String {
        switch self {
        case .followPath: "Follow path"
        case .lookAt: "Look at"
        case .follow: "Follow"
        case .orbit: "Orbit"
        case .noise: "Wobble"
        case .windSway: "Wind sway"
        case .bob: "Bob on water"
        case .spin: "Spin"
        case .bounce: "Bounce"
        case .swing: "Swing"
        }
    }

    /// Properties the behaviour writes (what baking produces keys for).
    public var drives: [PropertyKey] {
        switch self {
        case let .followPath(_, _, _, orient): orient ? [.position, .rotation] : [.position]
        case .lookAt: [.rotation]
        case .follow: [.position]
        case let .orbit(_, _, _, face): face ? [.position, .rotation] : [.position]
        case .noise: [.position, .rotation]
        case .windSway: [.rotation]
        case .bob: [.position, .rotation]
        case .spin, .swing: [.rotation]
        case .bounce: [.position]
        }
    }
}

extension BehaviorKind: Codable {
    private enum Key: String, CodingKey {
        case type, path, duration, loop, orient, target, offset, lag, center, around, period, faceCenter
        case position, rotation, frequency, angle, direction, height, tilt, degreesPerSecond, axis
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "followPath":
            self = try .followPath(c.decode(PathSource.self, forKey: .path), duration: c.decode(Double.self, forKey: .duration),
                                   loop: c.decodeIfPresent(Bool.self, forKey: .loop) ?? false,
                                   orient: c.decodeIfPresent(Bool.self, forKey: .orient) ?? true)
        case "lookAt":
            self = try .lookAt(c.decode(ObjectID.self, forKey: .target))
        case "follow":
            self = try .follow(c.decode(ObjectID.self, forKey: .target), offset: c.decode(Vec3.self, forKey: .offset),
                               lag: c.decodeIfPresent(Double.self, forKey: .lag) ?? 0)
        case "orbit":
            self = try .orbit(center: c.decodeIfPresent(Vec3.self, forKey: .center) ?? .zero,
                              around: c.decodeIfPresent(ObjectID.self, forKey: .around),
                              period: c.decode(Double.self, forKey: .period),
                              faceCenter: c.decodeIfPresent(Bool.self, forKey: .faceCenter) ?? false)
        case "noise":
            self = try .noise(position: c.decodeIfPresent(Vec3.self, forKey: .position) ?? .zero,
                              rotation: c.decodeIfPresent(Vec3.self, forKey: .rotation) ?? .zero,
                              frequency: c.decodeIfPresent(Double.self, forKey: .frequency) ?? 1)
        case "windSway":
            self = try .windSway(angle: c.decode(Double.self, forKey: .angle), frequency: c.decodeIfPresent(Double.self, forKey: .frequency) ?? 0.5,
                                 direction: c.decodeIfPresent(Double.self, forKey: .direction) ?? 0)
        case "bob":
            self = try .bob(height: c.decode(Double.self, forKey: .height), period: c.decodeIfPresent(Double.self, forKey: .period) ?? 3,
                            tilt: c.decodeIfPresent(Double.self, forKey: .tilt) ?? 4)
        case "spin":
            self = try .spin(degreesPerSecond: c.decode(Double.self, forKey: .degreesPerSecond),
                             axis: c.decodeIfPresent(Axis.self, forKey: .axis) ?? .y)
        case "bounce":
            self = try .bounce(height: c.decode(Double.self, forKey: .height), period: c.decodeIfPresent(Double.self, forKey: .period) ?? 1)
        case "swing":
            self = try .swing(angle: c.decode(Double.self, forKey: .angle), period: c.decodeIfPresent(Double.self, forKey: .period) ?? 2)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown behavior \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .followPath(path, duration, loop, orient):
            try c.encode("followPath", forKey: .type)
            try c.encode(path, forKey: .path)
            try c.encode(duration, forKey: .duration)
            try c.encode(loop, forKey: .loop)
            try c.encode(orient, forKey: .orient)
        case let .lookAt(target):
            try c.encode("lookAt", forKey: .type)
            try c.encode(target, forKey: .target)
        case let .follow(target, offset, lag):
            try c.encode("follow", forKey: .type)
            try c.encode(target, forKey: .target)
            try c.encode(offset, forKey: .offset)
            try c.encode(lag, forKey: .lag)
        case let .orbit(center, around, period, faceCenter):
            try c.encode("orbit", forKey: .type)
            try c.encode(center, forKey: .center)
            try c.encodeIfPresent(around, forKey: .around)
            try c.encode(period, forKey: .period)
            try c.encode(faceCenter, forKey: .faceCenter)
        case let .noise(position, rotation, frequency):
            try c.encode("noise", forKey: .type)
            try c.encode(position, forKey: .position)
            try c.encode(rotation, forKey: .rotation)
            try c.encode(frequency, forKey: .frequency)
        case let .windSway(angle, frequency, direction):
            try c.encode("windSway", forKey: .type)
            try c.encode(angle, forKey: .angle)
            try c.encode(frequency, forKey: .frequency)
            try c.encode(direction, forKey: .direction)
        case let .bob(height, period, tilt):
            try c.encode("bob", forKey: .type)
            try c.encode(height, forKey: .height)
            try c.encode(period, forKey: .period)
            try c.encode(tilt, forKey: .tilt)
        case let .spin(speed, axis):
            try c.encode("spin", forKey: .type)
            try c.encode(speed, forKey: .degreesPerSecond)
            try c.encode(axis, forKey: .axis)
        case let .bounce(height, period):
            try c.encode("bounce", forKey: .type)
            try c.encode(height, forKey: .height)
            try c.encode(period, forKey: .period)
        case let .swing(angle, period):
            try c.encode("swing", forKey: .type)
            try c.encode(angle, forKey: .angle)
            try c.encode(period, forKey: .period)
        }
    }
}

/// A behaviour attached to an object for a span of time.
public struct Behavior: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var target: ObjectID
    public var kind: BehaviorKind
    public var start: Double
    /// `nil` = until the end of the timeline.
    public var end: Double?
    public var enabled: Bool

    public init(id: String, target: ObjectID, kind: BehaviorKind, start: Double = 0, end: Double? = nil, enabled: Bool = true) {
        self.id = id
        self.target = target
        self.kind = kind
        self.start = start
        self.end = end
        self.enabled = enabled
    }

    /// Local time inside the behaviour (clamped: before start it hasn't started, after end it holds).
    func localTime(_ time: Double) -> Double? {
        guard enabled, time >= start - 1e-9 else { return nil }
        let clamped = end.map { min(time, $0) } ?? time
        return clamped - start
    }

    private enum CodingKeys: String, CodingKey { case id, target, kind, start, end, enabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        target = try c.decode(ObjectID.self, forKey: .target)
        kind = try c.decode(BehaviorKind.self, forKey: .kind)
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        end = try c.decodeIfPresent(Double.self, forKey: .end)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// An arc-length parameterised polyline (constant speed along a drawn path).
public struct PathCurve: Hashable, Sendable {
    public let points: [Vec3]
    public let cumulative: [Double]

    public init(points: [Vec3]) {
        var cleaned: [Vec3] = []
        for point in points where cleaned.last.map({ $0.distance(to: point) > 1e-6 }) ?? true {
            cleaned.append(point)
        }
        self.points = cleaned
        var sums: [Double] = [0]
        for index in cleaned.indices.dropFirst() {
            sums.append(sums[index - 1] + cleaned[index].distance(to: cleaned[index - 1]))
        }
        cumulative = sums
    }

    public var length: Double { cumulative.last ?? 0 }

    /// Position and unit tangent at a fraction (0…1) of the length.
    public func sample(_ fraction: Double) -> (position: Vec3, tangent: Vec3)? {
        guard let first = points.first else { return nil }
        guard points.count > 1, length > 0 else { return (first, .unitZ) }
        let target = min(max(fraction, 0), 1) * length
        var lo = 0
        var hi = cumulative.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= target { lo = mid } else { hi = mid }
        }
        let span = cumulative[hi] - cumulative[lo]
        let t = span > 0 ? (target - cumulative[lo]) / span : 0
        let a = points[lo]
        let b = points[hi]
        return (a.lerp(to: b, t), (b - a).normalized)
    }
}

public enum BehaviorEvaluator {
    /// The world-space path a behaviour follows.
    public static func path(_ source: PathSource, in scene: Scene) -> PathCurve {
        switch source {
        case let .points(points):
            return PathCurve(points: points)
        case let .object(id):
            guard let object = scene.objects[id], case let .drawing(recipe) = object.kind,
                  let stroke = recipe.strokes.first else { return PathCurve(points: []) }
            let world = scene.worldTransform(of: id)
            return PathCurve(points: stroke.points.map { world.apply(to: $0) })
        }
    }

    /// Rotation that points the object's forward axis along `direction`, keeping it upright.
    /// Models face +Z (glTF convention); cameras look down -Z.
    public static func facing(_ direction: Vec3, cameraStyle: Bool) -> Quat {
        let flat = direction.normalized
        guard flat.length > 1e-9 else { return .identity }
        let forward = cameraStyle ? -flat : flat
        let yaw = atan2(forward.x, forward.z)
        let horizontal = (forward.x * forward.x + forward.z * forward.z).squareRoot()
        let pitch = -atan2(forward.y, horizontal)
        return (Quat(angle: yaw, axis: .unitY) * Quat(angle: pitch, axis: .unitX)).normalized
    }

    /// Applies one behaviour to `scene` (already holding keyed values) at `time`.
    /// `history(id, time)` returns an object's world position at an earlier time (for `follow` with lag).
    static func apply(
        _ behavior: Behavior, to scene: inout Scene, at time: Double, history: (ObjectID, Double) -> Vec3?
    ) {
        guard let local = behavior.localTime(time), var object = scene.objects[behavior.target] else { return }
        let parentWorld = object.parent.map { scene.worldTransform(of: $0) } ?? .identity
        var world = parentWorld * object.transform
        let isCamera = object.kind == .camera
        let seed = Noise.seed(behavior.id)

        switch behavior.kind {
        case let .followPath(source, duration, loop, orient):
            let curve = path(source, in: scene)
            guard duration > 0, !curve.points.isEmpty else { return }
            var fraction = local / duration
            fraction = loop ? fraction - fraction.rounded(.down) : min(fraction, 1)
            guard let sample = curve.sample(fraction) else { return }
            world.position = sample.position
            if orient { world.rotation = facing(sample.tangent, cameraStyle: isCamera) }

        case let .lookAt(targetID):
            guard scene.objects[targetID] != nil, targetID != behavior.target else { return }
            let target = scene.worldTransform(of: targetID).position
            world.rotation = facing(target - world.position, cameraStyle: isCamera)

        case let .follow(targetID, offset, lag):
            guard scene.objects[targetID] != nil, targetID != behavior.target else { return }
            // Lag reads where the target was `lag` seconds ago (no state: deterministic).
            let now = scene.worldTransform(of: targetID).position
            let target = lag > 0 ? (history(targetID, time - lag) ?? now) : now
            world.position = target + offset

        case let .orbit(center, around, period, faceCenter):
            guard period != 0 else { return }
            let pivot = around.flatMap { scene.objects[$0] != nil ? scene.worldTransform(of: $0).position : nil } ?? center
            world = orbited(world, pivot: pivot, angle: local / period * 2 * .pi, faceCenter: faceCenter, cameraStyle: isCamera)

        case let .noise(position, rotation, frequency):
            object.transform = wobbled(object.transform, position: position, rotation: rotation, at: local * frequency, seed: seed)
            scene.objects[behavior.target] = object
            return

        case let .windSway(angle, frequency, direction):
            world.rotation = (windBend(at: world.position, angle: angle, frequency: frequency, direction: direction, local: local, seed: seed)
                * world.rotation).normalized

        case let .bob(height, period, tilt):
            guard period > 0 else { return }
            let phase = 2 * .pi * local / period + Double(seed % 628) / 100
            world.position.y += sin(phase) * height
            let rock = Quat(eulerDegrees: Vec3(sin(phase * 0.7 + 1.3) * tilt, 0, sin(phase * 0.9) * tilt))
            world.rotation = (world.rotation * rock).normalized

        case let .spin(speed, axis):
            var transform = object.transform
            transform.rotation = (transform.rotation * Quat(angle: speed * local * .pi / 180, axis: axis.unit)).normalized
            object.transform = transform
            scene.objects[behavior.target] = object
            return

        case let .bounce(height, period):
            world.position.y += hop(height: height, period: period, local: local)

        case let .swing(angle, period):
            object.transform.rotation = swung(object.transform.rotation, angle: angle, period: period, local: local)
            scene.objects[behavior.target] = object
            return
        }
        let localTransform = Transform.relative(world: world, toParent: parentWorld)
        object.transform = Transform(position: localTransform.position, rotation: localTransform.rotation, scale: object.transform.scale)
        scene.objects[behavior.target] = object
    }

    static func orbited(_ world: Transform, pivot: Vec3, angle: Double, faceCenter: Bool, cameraStyle: Bool) -> Transform {
        var world = world
        let spin = Quat(angle: angle, axis: .unitY)
        world.position = pivot + spin.act(world.position - pivot)
        if faceCenter {
            world.rotation = facing(Vec3(pivot.x, world.position.y, pivot.z) - world.position, cameraStyle: cameraStyle)
        } else {
            world.rotation = (spin * world.rotation).normalized
        }
        return world
    }

    /// Smooth random drift on top of the object's own (local) transform.
    /// How high a bouncing thing is: one hop per period, a parabola from the ground to `height` and back (gravity's
    /// own curve).
    static func hop(height: Double, period: Double, local: Double) -> Double {
        guard period > 0 else { return 0 }
        let phase = local / period - (local / period).rounded(.down)
        return height * 4 * phase * (1 - phase)
    }

    /// A pendulum about the thing's own pivot: `angle` degrees each way around its local z, there and back per period.
    static func swung(_ rotation: Quat, angle: Double, period: Double, local: Double) -> Quat {
        guard period > 0 else { return rotation }
        return (rotation * Quat(angle: angle * sin(2 * .pi * local / period) * .pi / 180, axis: .unitZ)).normalized
    }

    static func wobbled(_ transform: Transform, position: Vec3, rotation: Vec3, at x: Double, seed: UInt64) -> Transform {
        let offset = Vec3(
            position.x * Noise.fractal(x, seed: seed),
            position.y * Noise.fractal(x, seed: seed &+ 1),
            position.z * Noise.fractal(x, seed: seed &+ 2)
        )
        let euler = Vec3(
            rotation.x * Noise.fractal(x, seed: seed &+ 3),
            rotation.y * Noise.fractal(x, seed: seed &+ 4),
            rotation.z * Noise.fractal(x, seed: seed &+ 5)
        )
        var transform = transform
        transform.position += offset
        transform.rotation = (transform.rotation * Quat(eulerDegrees: euler)).normalized
        return transform
    }

    /// The wind's bend at a spot. Phase from the position: a forest ripples instead of swaying in lock-step.
    static func windBend(at position: Vec3, angle: Double, frequency: Double, direction: Double, local: Double, seed: UInt64) -> Quat {
        let phase = position.x * 0.35 + position.z * 0.23
        let sway = sin(2 * .pi * frequency * local + phase) * 0.75 + Noise.fractal(local * frequency * 1.7 + phase, seed: seed) * 0.25
        let windYaw = direction * .pi / 180
        let bendAxis = Vec3(cos(windYaw), 0, -sin(windYaw))
        return Quat(angle: sway * angle * .pi / 180, axis: bendAxis)
    }
}
