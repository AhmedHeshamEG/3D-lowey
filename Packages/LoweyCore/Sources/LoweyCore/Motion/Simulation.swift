import Foundation

/// Simulations that BAKE to keyframes: editable afterwards and deterministic in export.
///
/// They run in LoweyCore on a fixed timestep rather than in a live physics engine: a live simulation
/// advances with the display clock, can't be stepped headlessly and isn't guaranteed to replay
/// identically — while a baked take must be exact (see DECISIONS.md).
public enum PhysicsKind: String, Codable, Sendable, CaseIterable {
    /// Objects fall and bounce on the ground and on each other.
    case fall
    /// Objects fly apart from a centre point, then fall.
    case explode
}

public struct PhysicsSettings: Hashable, Sendable {
    public var kind: PhysicsKind
    public var duration: Double
    public var gravity: Double
    /// Bounciness 0…1.
    public var bounce: Double
    public var friction: Double
    /// Explosion strength (m/s at the centre).
    public var strength: Double
    public var center: Vec3?
    public var groundHeight: Double
    public var seed: UInt64

    public init(kind: PhysicsKind = .fall, duration: Double = 3, gravity: Double = 9.81, bounce: Double = 0.35, friction: Double = 0.5,
                strength: Double = 7, center: Vec3? = nil, groundHeight: Double = 0, seed: UInt64 = 3) {
        self.kind = kind
        self.duration = duration
        self.gravity = gravity
        self.bounce = bounce
        self.friction = friction
        self.strength = strength
        self.center = center
        self.groundHeight = groundHeight
        self.seed = seed
    }
}

public enum Simulation {
    struct Body {
        var id: ObjectID
        var position: Vec3
        var velocity: Vec3
        var rotation: Quat
        var spin: Vec3
        var radius: Double
        /// Offset from the pivot (object origin) down to the lowest point.
        var bottom: Double
        var parentWorld: Transform
        var scale: Vec3
    }

    /// Bakes rigid-body motion for objects (spheres approximate their bounds). One undo step.
    public static func physics(
        _ objects: [ObjectID], settings: PhysicsSettings, at start: Double, fps: Int, bounds: SceneBounds, current: Scene,
        timeline: Timeline, ids: inout IDFactory
    ) -> EditCommand? {
        var random = SeededRandom(seed: settings.seed)
        var bodies: [Body] = []
        let worldBoxes = objects.compactMap { id in bounds.worldBounds(of: id, in: current).map { (id, $0) } }
        let center = settings.center ?? {
            let points = worldBoxes.map { $0.1.center }
            return points.isEmpty ? .zero : points.reduce(.zero, +) / Double(points.count)
        }()
        for (id, box) in worldBoxes {
            guard let object = current.objects[id] else { continue }
            let world = current.worldTransform(of: id)
            let radius = max(min(box.size.x, box.size.y, box.size.z) * 0.5, 0.02)
            var velocity = Vec3.zero
            var spin = Vec3.zero
            if settings.kind == .explode {
                var away = box.center - center
                if away.length < 1e-3 { away = Vec3(random.range(-1, 1), 1, random.range(-1, 1)) }
                away = (away.normalized + Vec3(0, 0.6, 0)).normalized
                velocity = away * settings.strength * random.range(0.7, 1.2)
                spin = Vec3(random.range(-6, 6), random.range(-6, 6), random.range(-6, 6))
            } else {
                spin = Vec3(random.range(-0.3, 0.3), 0, random.range(-0.3, 0.3))
            }
            bodies.append(Body(
                id: id, position: world.position, velocity: velocity, rotation: world.rotation, spin: spin, radius: radius,
                bottom: world.position.y - box.min.y, parentWorld: object.parent.map { current.worldTransform(of: $0) } ?? .identity,
                scale: object.transform.scale
            ))
        }
        guard !bodies.isEmpty else { return nil }
        let substeps = 4
        let dt = 1 / Double(max(fps, 1)) / Double(substeps)
        let frames = Int((settings.duration * Double(fps)).rounded())
        var samples: [[(Vec3, Quat)]] = Array(repeating: [], count: bodies.count)
        for index in bodies.indices {
            samples[index].append((bodies[index].position, bodies[index].rotation))
        }
        for _ in 0 ..< frames {
            for _ in 0 ..< substeps {
                step(&bodies, dt: dt, settings: settings)
            }
            for index in bodies.indices {
                samples[index].append((bodies[index].position, bodies[index].rotation))
            }
        }
        var edits: [TrackEdit] = []
        for (index, body) in bodies.enumerated() {
            var positionKeys: [Keyframe] = []
            var rotationKeys: [Keyframe] = []
            for (frame, (position, rotation)) in samples[index].enumerated() {
                let local = Transform.relative(world: Transform(position: position, rotation: rotation, scale: body.scale), toParent: body.parentWorld)
                let time = start + Double(frame) / Double(fps)
                positionKeys.append(Keyframe(time: time, value: .vec3(local.position), easing: .linear))
                rotationKeys.append(Keyframe(time: time, value: .quat(local.rotation), easing: .linear))
            }
            positionKeys = PerformBaker.simplify(positionKeys, tolerance: 0.002)
            rotationKeys = PerformBaker.simplify(rotationKeys, tolerance: 0.004)
            edits.append(TrackEdit(bake(body.id, .position, positionKeys, timeline: timeline, ids: &ids)))
            edits.append(TrackEdit(bake(body.id, .rotation, rotationKeys, timeline: timeline, ids: &ids)))
        }
        return .batch(settings.kind == .explode ? "Explode" : "Fall", [.setTracks(edits)])
    }

    static func step(_ bodies: inout [Body], dt: Double, settings: PhysicsSettings) {
        for index in bodies.indices {
            bodies[index].velocity.y -= settings.gravity * dt
            bodies[index].position += bodies[index].velocity * dt
            let spin = bodies[index].spin
            if spin.length > 1e-6 {
                bodies[index].rotation = (Quat(angle: spin.length * dt, axis: spin) * bodies[index].rotation).normalized
            }
            // Ground.
            let floor = settings.groundHeight + bodies[index].bottom
            if bodies[index].position.y < floor {
                bodies[index].position.y = floor
                if bodies[index].velocity.y < 0 {
                    bodies[index].velocity.y = -bodies[index].velocity.y * settings.bounce
                    if bodies[index].velocity.y < 0.3 { bodies[index].velocity.y = 0 }
                }
                let damping = max(0, 1 - settings.friction * 6 * dt)
                bodies[index].velocity.x *= damping
                bodies[index].velocity.z *= damping
                bodies[index].spin *= max(0, 1 - settings.friction * 8 * dt)
            }
        }
        // Body–body (spheres): push apart and exchange velocity along the normal.
        for i in bodies.indices {
            for j in bodies.indices where j > i {
                let delta = bodies[j].position - bodies[i].position
                let distance = delta.length
                let minimum = bodies[i].radius + bodies[j].radius
                guard distance < minimum, distance > 1e-9 else { continue }
                let normal = delta / distance
                let overlap = (minimum - distance) / 2
                bodies[i].position -= normal * overlap
                bodies[j].position += normal * overlap
                let relative = (bodies[j].velocity - bodies[i].velocity).dot(normal)
                if relative < 0 {
                    let impulse = normal * (-(1 + settings.bounce) * relative / 2)
                    bodies[i].velocity -= impulse
                    bodies[j].velocity += impulse
                }
            }
        }
    }

    static func bake(_ id: ObjectID, _ property: PropertyKey, _ keys: [Keyframe], timeline: Timeline, ids: inout IDFactory) -> Track {
        var track = timeline.track(for: id, property) ?? Track(id: ids.next(), target: id, property: property)
        if let first = keys.first?.time, let last = keys.last?.time {
            track.removeKeys(in: TimeRange(start: first, end: last))
        }
        for key in keys {
            track.setKey(key)
        }
        return track
    }

    // MARK: Flock (birds)

    public struct FlockSettings: Hashable, Sendable {
        public var duration: Double
        public var center: Vec3
        /// Half-size of the area the flock stays in.
        public var extent: Vec3
        public var speed: Double
        public var seed: UInt64

        public init(duration: Double = 6, center: Vec3 = Vec3(0, 6, 0), extent: Vec3 = Vec3(10, 3, 10), speed: Double = 4, seed: UInt64 = 11) {
            self.duration = duration
            self.center = center
            self.extent = extent
            self.speed = speed
            self.seed = seed
        }
    }

    /// Boids (separation, alignment, cohesion, stay-in-area), baked to position + heading keys.
    public static func flock(
        _ objects: [ObjectID], settings: FlockSettings, at start: Double, fps: Int, current: Scene, timeline: Timeline, ids: inout IDFactory
    ) -> EditCommand? {
        let birds = objects.filter { current.objects[$0] != nil }
        guard !birds.isEmpty else { return nil }
        var random = SeededRandom(seed: settings.seed)
        var positions = birds.map { current.worldTransform(of: $0).position }
        var velocities = birds.map { _ in
            Vec3(random.range(-1, 1), random.range(-0.2, 0.2), random.range(-1, 1)).normalized * settings.speed
        }
        let frames = Int((settings.duration * Double(fps)).rounded())
        let dt = 1 / Double(max(fps, 1))
        var positionKeys = [[Keyframe]](repeating: [], count: birds.count)
        var rotationKeys = [[Keyframe]](repeating: [], count: birds.count)
        func record(_ frame: Int) {
            for index in birds.indices {
                guard let object = current.objects[birds[index]] else { continue }
                let parentWorld = object.parent.map { current.worldTransform(of: $0) } ?? .identity
                let heading = BehaviorEvaluator.facing(velocities[index], cameraStyle: false)
                let local = Transform.relative(world: Transform(position: positions[index], rotation: heading, scale: object.transform.scale),
                                               toParent: parentWorld)
                let time = start + Double(frame) * dt
                positionKeys[index].append(Keyframe(time: time, value: .vec3(local.position), easing: .linear))
                rotationKeys[index].append(Keyframe(time: time, value: .quat(local.rotation), easing: .linear))
            }
        }
        record(0)
        for frame in 1 ... max(frames, 1) {
            let next = birds.indices.map { i in
                boidVelocity(i, positions: positions, velocities: velocities, settings: settings, frame: frame, dt: dt)
            }
            velocities = next
            for i in birds.indices {
                positions[i] += velocities[i] * dt
            }
            record(frame)
        }
        var edits: [TrackEdit] = []
        for (index, id) in birds.enumerated() {
            edits.append(TrackEdit(bake(id, .position, PerformBaker.simplify(positionKeys[index], tolerance: 0.01), timeline: timeline, ids: &ids)))
            edits.append(TrackEdit(bake(id, .rotation, PerformBaker.simplify(rotationKeys[index], tolerance: 0.01), timeline: timeline, ids: &ids)))
        }
        return .batch("Flock", [.setTracks(edits)])
    }

    /// One bird's next velocity: separation, alignment, cohesion, staying in the area and a little wandering.
    static func boidVelocity(_ i: Int, positions: [Vec3], velocities: [Vec3], settings: FlockSettings, frame: Int, dt: Double) -> Vec3 {
        var separation = Vec3.zero
        var alignment = Vec3.zero
        var cohesion = Vec3.zero
        var neighbours = 0.0
        for j in positions.indices where j != i {
            let offset = positions[j] - positions[i]
            let distance = offset.length
            guard distance < 3.5 else { continue }
            neighbours += 1
            alignment += velocities[j]
            cohesion += positions[j]
            if distance < 1.2, distance > 1e-6 { separation -= offset / (distance * distance) }
        }
        var steer = separation * 1.6
        if neighbours > 0 {
            steer += (alignment / neighbours - velocities[i]) * 0.08
            steer += (cohesion / neighbours - positions[i]) * 0.05
        }
        // Stay inside the area.
        let fromCenter = positions[i] - settings.center
        for axis in Axis.allCases where abs(fromCenter[axis]) > settings.extent[axis] {
            var push = Vec3.zero
            push[axis] = fromCenter[axis] > 0 ? -1 : 1
            steer += push * 2.5
        }
        // A little wandering keeps it alive.
        steer += Vec3(Noise.value(Double(frame) * 0.05, seed: settings.seed &+ UInt64(i)), 0,
                      Noise.value(Double(frame) * 0.05 + 50, seed: settings.seed &+ UInt64(i))) * 0.6
        var velocity = velocities[i] + steer * dt * 4
        let speed = velocity.length
        if speed > 1e-6 { velocity = velocity / speed * min(max(speed, settings.speed * 0.6), settings.speed * 1.3) }
        return velocity
    }

    // MARK: Crowd walks in

    /// Agents walk from where they stand to targets (e.g. their seats), keeping apart, facing
    /// where they go. Baked to keys; returns each agent's walking speed for clip matching.
    public static func crowdWalk(
        _ objects: [ObjectID], to targets: [Vec3], speed: Double = 1.3, at start: Double, fps: Int, current: Scene,
        timeline: Timeline, ids: inout IDFactory
    ) -> EditCommand? {
        let agents = Array(zip(objects, targets)).filter { current.objects[$0.0] != nil }
        guard !agents.isEmpty else { return nil }
        var positions = agents.map { current.worldTransform(of: $0.0).position }
        var headings = agents.map { current.worldTransform(of: $0.0).rotation }
        let dt = 1 / Double(max(fps, 1))
        var positionKeys = [[Keyframe]](repeating: [], count: agents.count)
        var rotationKeys = [[Keyframe]](repeating: [], count: agents.count)
        var arrived = [Bool](repeating: false, count: agents.count)
        var frame = 0
        func record() {
            for index in agents.indices {
                guard let object = current.objects[agents[index].0] else { continue }
                let parentWorld = object.parent.map { current.worldTransform(of: $0) } ?? .identity
                let local = Transform.relative(world: Transform(position: positions[index], rotation: headings[index], scale: object.transform.scale),
                                               toParent: parentWorld)
                let time = start + Double(frame) * dt
                positionKeys[index].append(Keyframe(time: time, value: .vec3(local.position), easing: .linear))
                rotationKeys[index].append(Keyframe(time: time, value: .quat(local.rotation), easing: .linear))
            }
        }
        record()
        while !arrived.allSatisfy({ $0 }), frame < fps * 60 {
            frame += 1
            for i in agents.indices where !arrived[i] {
                let target = agents[i].1
                var toTarget = target - positions[i]
                toTarget.y = 0
                if toTarget.length < 0.05 {
                    arrived[i] = true
                    continue
                }
                var desired = toTarget.normalized * min(speed, toTarget.length / dt)
                for j in agents.indices where j != i {
                    var away = positions[i] - positions[j]
                    away.y = 0
                    let distance = away.length
                    if distance < 0.6, distance > 1e-6 { desired += away / distance * (0.6 - distance) * 3 }
                }
                positions[i] += desired * dt
                if desired.length > 1e-3 {
                    let facing = BehaviorEvaluator.facing(Vec3(desired.x, 0, desired.z), cameraStyle: false)
                    headings[i] = headings[i].slerp(to: facing, 0.25)
                }
            }
            record()
        }
        var edits: [TrackEdit] = []
        for (index, agent) in agents.enumerated() {
            edits.append(TrackEdit(bake(agent.0, .position, PerformBaker.simplify(positionKeys[index], tolerance: 0.005), timeline: timeline, ids: &ids)))
            edits.append(TrackEdit(bake(agent.0, .rotation, PerformBaker.simplify(rotationKeys[index], tolerance: 0.01), timeline: timeline, ids: &ids)))
        }
        return .batch("Crowd walks in", [.setTracks(edits)])
    }

    // MARK: Baking behaviours

    /// Samples a behaviour at `fps` and replaces it with keys (editable, like a Perform take).
    public static func bake(_ behaviorID: String, in document: Document, rigs: [AssetID: RigAsset] = [:], ids: inout IDFactory) -> EditCommand? {
        let timeline = document.scene.timeline
        guard let behavior = timeline.behaviors.first(where: { $0.id == behaviorID }) else { return nil }
        let end = behavior.end ?? max(timeline.duration, behavior.start)
        let step = 1 / Double(max(timeline.fps, 1))
        var samples: [PropertyKey: [Keyframe]] = [:]
        var time = behavior.start
        while time <= end + 1e-9 {
            let animated = Animator.evaluate(document, at: time, rigs: rigs)
            if let object = animated.scene.objects[behavior.target] {
                for key in behavior.kind.drives {
                    if let value = object.properties[key] ?? PropertyDefaults.value(for: key) {
                        samples[key, default: []].append(Keyframe(time: time, value: value, easing: .linear))
                    }
                }
            }
            time += step
        }
        var newTimeline = timeline
        newTimeline.behaviors.removeAll { $0.id == behaviorID }
        for (property, keys) in samples {
            let simplified = PerformBaker.simplify(keys, tolerance: property == .rotation ? 0.002 : 0.001)
            let track = bake(behavior.target, property, simplified, timeline: newTimeline, ids: &ids)
            if let index = newTimeline.tracks.firstIndex(where: { $0.id == track.id }) {
                newTimeline.tracks[index] = track
            } else {
                newTimeline.tracks.append(track)
            }
        }
        return .batch("Bake \(behavior.kind.title)", [.setTimeline(newTimeline)])
    }
}
