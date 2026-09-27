import Foundation

/// Camera move presets. Each generates editable keys on the camera (position, rotation, field of view),
/// starting from where the camera is at `start` and framed around a subject point.
public enum CameraMove: String, Codable, Sendable, CaseIterable, Identifiable {
    case pushIn, pullOut, punchIn, orbit, dolly, truck, crane, whipPan, shake, reveal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pushIn: "Push in"
        case .pullOut: "Pull out"
        case .punchIn: "Punch in"
        case .orbit: "Orbit"
        case .dolly: "Dolly"
        case .truck: "Truck"
        case .crane: "Crane"
        case .whipPan: "Whip pan"
        case .shake: "Shake"
        case .reveal: "Reveal"
        }
    }

    public var defaultDuration: Double {
        switch self {
        case .punchIn: 0.25
        case .whipPan: 0.35
        case .shake: 0.8
        case .pushIn, .pullOut: 2.5
        case .orbit: 4
        case .dolly, .truck, .crane: 3
        case .reveal: 3
        }
    }
}

public struct CameraMoveOptions: Hashable, Sendable {
    public var duration: Double
    /// 0…2: how strong (1 = default distances / angles).
    public var strength: Double

    public init(duration: Double, strength: Double = 1) {
        self.duration = duration
        self.strength = strength
    }
}

public enum CameraMoves {
    /// Keys for a move. `subject` is the point the shot is about (selection centre, or the focus point).
    public static func keys(
        _ move: CameraMove, camera: SceneObject, world: Transform, parentWorld: Transform, subject: Vec3, at start: Double,
        options: CameraMoveOptions
    ) -> [(PropertyKey, [Keyframe])] {
        let d = max(options.duration, 1.0 / 60)
        let s = options.strength
        let fov = camera[.fieldOfView]?.floatValue ?? 50
        let eye = world.position
        let forward = world.rotation.act(Vec3(0, 0, -1))
        let right = world.rotation.act(.unitX)
        let toSubject = subject - eye
        let distance = max(toSubject.length, 0.5)

        func local(_ worldTransform: Transform) -> Transform { Transform.relative(world: worldTransform, toParent: parentWorld) }
        func pose(_ position: Vec3, _ rotation: Quat) -> Transform {
            local(Transform(position: position, rotation: rotation, scale: world.scale))
        }
        func k(_ time: Double, _ value: PropertyValue, _ easing: Easing = .easeInOut) -> Keyframe {
            Keyframe(time: start + time, value: value, easing: easing)
        }
        func look(from position: Vec3, at target: Vec3) -> Quat {
            BehaviorEvaluator.facing(target - position, cameraStyle: true)
        }
        func positionKeys(_ positions: [(Double, Vec3)], easing: Easing = .easeInOut) -> (PropertyKey, [Keyframe]) {
            (.position, positions.map { k($0.0, .vec3(pose($0.1, world.rotation).position), easing) })
        }
        let startLocal = local(world)

        switch move {
        case .pushIn, .pullOut, .dolly:
            let amount: Double = switch move {
            case .pushIn: distance * 0.35 * s
            case .pullOut: -distance * 0.5 * s
            default: 2 * s
            }
            let direction = move == .dolly ? forward : toSubject.normalized
            let end = eye + direction * amount
            return [(.position, [k(0, .vec3(startLocal.position)), k(d, .vec3(pose(end, world.rotation).position))])]

        case .punchIn:
            let zoomed = max(fov * (1 - 0.4 * min(s, 2) / 1.2), 5)
            return [(.fieldOfView, [k(0, .float(fov), .easeOut), k(d, .float(zoomed))])]

        case .truck:
            let end = eye + right * (2 * s)
            return [positionKeys([(0, eye), (d, end)])]

        case .crane:
            let end = eye + Vec3(0, 2 * s, 0)
            let endRotation = look(from: end, at: subject)
            return [
                (.position, [k(0, .vec3(startLocal.position)), k(d, .vec3(pose(end, endRotation).position))]),
                (.rotation, [k(0, .quat(startLocal.rotation)), k(d, .quat(pose(end, endRotation).rotation))])
            ]

        case .orbit:
            let total = 60 * s * .pi / 180
            let steps = max(Int((abs(total) / (.pi / 12)).rounded(.up)), 2)
            var positions: [Keyframe] = []
            var rotations: [Keyframe] = []
            for index in 0 ... steps {
                let fraction = Double(index) / Double(steps)
                let spin = Quat(angle: total * fraction, axis: .unitY)
                let position = subject + spin.act(eye - subject)
                let rotation = look(from: position, at: subject)
                let easing: Easing = index == 0 ? .easeIn : (index == steps - 1 ? .easeOut : .linear)
                positions.append(k(d * fraction, .vec3(pose(position, rotation).position), easing))
                rotations.append(k(d * fraction, .quat(pose(position, rotation).rotation), easing))
            }
            return [(.position, positions), (.rotation, rotations)]

        case .whipPan:
            let angle = 90 * s * .pi / 180
            let mid = (Quat(angle: angle * 0.5, axis: .unitY) * world.rotation).normalized
            let end = (Quat(angle: angle, axis: .unitY) * world.rotation).normalized
            return [(.rotation, [
                k(0, .quat(startLocal.rotation), .easeIn), k(d * 0.5, .quat(pose(eye, mid).rotation), .easeOut),
                k(d, .quat(pose(eye, end).rotation))
            ])]

        case .shake:
            let seed = Noise.seed(camera.id.raw)
            let steps = 12
            var rotations: [Keyframe] = [k(0, .quat(startLocal.rotation), .linear)]
            for index in 1 ..< steps {
                let falloff = 1 - Double(index) / Double(steps)
                let amount: Double = 2.5 * s * falloff
                let euler = Vec3(Noise.lattice(Int64(index), seed: seed) * amount, Noise.lattice(Int64(index), seed: seed &+ 9) * amount, 0)
                let rotation = (world.rotation * Quat(eulerDegrees: euler)).normalized
                rotations.append(k(d * Double(index) / Double(steps), .quat(pose(eye, rotation).rotation), .linear))
            }
            rotations.append(k(d, .quat(startLocal.rotation)))
            return [(.rotation, rotations)]

        case .reveal:
            // Start low and tilted down, rise while tilting up onto the subject.
            let startEye = eye - Vec3(0, 1.2 * s, 0) - forward * (0.8 * s)
            let tilt = Quat(angle: -35 * .pi / 180, axis: right)
            let startRotation = (tilt * look(from: startEye, at: subject)).normalized
            let endRotation = look(from: eye, at: subject)
            return [
                (.position, [k(0, .vec3(pose(startEye, startRotation).position)), k(d, .vec3(startLocal.position))]),
                (.rotation, [k(0, .quat(pose(startEye, startRotation).rotation)), k(d, .quat(pose(eye, endRotation).rotation))])
            ]
        }
    }

    /// Applies a move to a camera as one command (keys inside the move's span are replaced).
    public static func apply(
        _ move: CameraMove, camera id: ObjectID, subject: Vec3, at start: Double, options: CameraMoveOptions,
        current: Scene, timeline: Timeline, ids: inout IDFactory
    ) -> EditCommand? {
        guard let camera = current.objects[id] else { return nil }
        let parentWorld = camera.parent.map { current.worldTransform(of: $0) } ?? .identity
        let world = current.worldTransform(of: id)
        var edits: [TrackEdit] = []
        for (property, keys) in keys(move, camera: camera, world: world, parentWorld: parentWorld, subject: subject, at: start, options: options) {
            var track = timeline.track(for: id, property) ?? Track(id: ids.next(), target: id, property: property)
            if let first = keys.first?.time, let last = keys.last?.time {
                track.removeKeys(in: TimeRange(start: first, end: last))
            }
            for key in keys {
                track.setKey(key)
            }
            edits.append(TrackEdit(track))
        }
        return edits.isEmpty ? nil : .batch(move.title, [.setTracks(edits)])
    }

    /// Focus pull: animate the focus distance to `distance` over `duration`.
    public static func focusPull(camera id: ObjectID, to distance: Double, at start: Double, duration: Double, current: Scene,
                                 timeline: Timeline, ids: inout IDFactory) -> EditCommand? {
        guard let camera = current.objects[id] else { return nil }
        let from = camera[.focusDistance]?.floatValue ?? 5
        var track = timeline.track(for: id, .focusDistance) ?? Track(id: ids.next(), target: id, property: .focusDistance)
        track.removeKeys(in: TimeRange(start: start, end: start + duration))
        track.setKey(Keyframe(time: start, value: .float(from)))
        track.setKey(Keyframe(time: start + duration, value: .float(distance)))
        return .batch("Focus pull", [.setTracks([TrackEdit(track)])])
    }
}
