import Foundation

/// Everything a camera move needs to know about the shot it starts from, and the keys for each move.
struct CameraShot {
    let cameraID: ObjectID
    let world: Transform
    let parentWorld: Transform
    let subject: Vec3
    let start: Double
    /// Duration and strength.
    let d: Double
    let s: Double
    let fov: Double
    let eye: Vec3
    let forward: Vec3
    let right: Vec3
    let toSubject: Vec3
    let distance: Double

    init(camera: SceneObject, world: Transform, parentWorld: Transform, subject: Vec3, start: Double, options: CameraMoveOptions) {
        cameraID = camera.id
        self.world = world
        self.parentWorld = parentWorld
        self.subject = subject
        self.start = start
        d = max(options.duration, 1.0 / 60)
        s = options.strength
        fov = camera[.fieldOfView]?.floatValue ?? 50
        eye = world.position
        forward = world.rotation.act(Vec3(0, 0, -1))
        right = world.rotation.act(.unitX)
        toSubject = subject - eye
        distance = max(toSubject.length, 0.5)
    }

    var startLocal: Transform { local(world) }

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

    // MARK: Moves

    func travel(_ move: CameraMove) -> [(PropertyKey, [Keyframe])] {
        let amount: Double = switch move {
        case .pushIn: distance * 0.35 * s
        case .pullOut: -distance * 0.5 * s
        default: 2 * s
        }
        let direction = move == .dolly ? forward : toSubject.normalized
        let end = eye + direction * amount
        return [(.position, [k(0, .vec3(startLocal.position)), k(d, .vec3(pose(end, world.rotation).position))])]
    }

    func punchIn() -> [(PropertyKey, [Keyframe])] {
        let zoomed = max(fov * (1 - 0.4 * min(s, 2) / 1.2), 5)
        return [(.fieldOfView, [k(0, .float(fov), .easeOut), k(d, .float(zoomed))])]
    }

    /// The explainer "snap": the camera shoots at the subject, overshoots a touch, settles, and the stop lands with a
    /// small jolt. Two keys for the rush, a few more for the landing.
    func snapZoom() -> [(PropertyKey, [Keyframe])] {
        let rush = distance * 0.55 * min(s, 1.6)
        let direction = toSubject.normalized
        let landed = eye + direction * rush
        let overshoot = eye + direction * (rush * 1.06)
        let seed = Noise.seed(cameraID.raw)
        let startLocal = startLocal
        var rotations: [Keyframe] = [k(0, .quat(startLocal.rotation), .linear), k(d * 0.3, .quat(startLocal.rotation), .linear)]
        for index in 1 ... 4 {
            let amount = 1.6 * s * (1 - Double(index) / 5)
            let euler = Vec3(Noise.lattice(Int64(index), seed: seed) * amount, Noise.lattice(Int64(index), seed: seed &+ 5) * amount, 0)
            let jolt = (world.rotation * Quat(eulerDegrees: euler)).normalized
            rotations.append(k(d * (0.3 + 0.14 * Double(index)), .quat(pose(landed, jolt).rotation), .linear))
        }
        rotations.append(k(d, .quat(startLocal.rotation)))
        return [
            (.position, [
                k(0, .vec3(startLocal.position), .easeIn),
                k(d * 0.3, .vec3(pose(overshoot, world.rotation).position), .easeOut),
                k(d * 0.6, .vec3(pose(landed, world.rotation).position))
            ]),
            (.rotation, rotations)
        ]
    }

    func crane() -> [(PropertyKey, [Keyframe])] {
        let end = eye + Vec3(0, 2 * s, 0)
        let endRotation = look(from: end, at: subject)
        return [
            (.position, [k(0, .vec3(startLocal.position)), k(d, .vec3(pose(end, endRotation).position))]),
            (.rotation, [k(0, .quat(startLocal.rotation)), k(d, .quat(pose(end, endRotation).rotation))])
        ]
    }

    func orbit() -> [(PropertyKey, [Keyframe])] {
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
    }

    func whipPan() -> [(PropertyKey, [Keyframe])] {
        let angle = 90 * s * .pi / 180
        let mid = (Quat(angle: angle * 0.5, axis: .unitY) * world.rotation).normalized
        let end = (Quat(angle: angle, axis: .unitY) * world.rotation).normalized
        return [(.rotation, [
            k(0, .quat(startLocal.rotation), .easeIn), k(d * 0.5, .quat(pose(eye, mid).rotation), .easeOut),
            k(d, .quat(pose(eye, end).rotation))
        ])]
    }

    func shake() -> [(PropertyKey, [Keyframe])] {
        let seed = Noise.seed(cameraID.raw)
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
    }

    /// Start low and tilted down, rise while tilting up onto the subject.
    func reveal() -> [(PropertyKey, [Keyframe])] {
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
