import Foundation

/// One-tap animations. Each one produces real, editable keyframes relative to how the object
/// looks at the start time — never a hidden effect.
public enum AnimationPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case popIn, popOut, grow, shrink, bounce, wiggle, float, spin, shake, pulse, fadeIn, fadeOut
    case slideIn, dropIn, typewriter

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .popIn: "Pop in"
        case .popOut: "Pop out"
        case .grow: "Grow"
        case .shrink: "Shrink"
        case .bounce: "Bounce"
        case .wiggle: "Wiggle"
        case .float: "Float"
        case .spin: "Spin"
        case .shake: "Shake"
        case .pulse: "Pulse"
        case .fadeIn: "Fade in"
        case .fadeOut: "Fade out"
        case .slideIn: "Slide in"
        case .dropIn: "Drop in"
        case .typewriter: "Typewriter"
        }
    }

    /// Sensible default length (seconds): snappy for entrances, longer for loops.
    public var defaultDuration: Double {
        switch self {
        case .popIn, .popOut: 0.45
        case .grow, .shrink: 0.8
        case .bounce: 0.9
        case .wiggle: 0.8
        case .float: 3
        case .spin: 1.5
        case .shake: 0.6
        case .pulse: 0.8
        case .fadeIn, .fadeOut: 0.6
        case .slideIn: 0.7
        case .dropIn: 0.9
        case .typewriter: 1.5
        }
    }

    /// Default strength: scale factor, meters or degrees depending on the preset.
    public var defaultAmplitude: Double {
        switch self {
        case .grow: 2
        case .shrink: 0.5
        case .bounce: 0.6
        case .wiggle: 12
        case .float: 0.15
        case .spin: 360
        case .shake: 0.12
        case .pulse: 1.15
        case .slideIn: 3
        case .dropIn: 3
        default: 1
        }
    }

    public var properties: [PropertyKey] {
        switch self {
        case .popIn, .popOut, .grow, .shrink, .pulse: [.scale]
        case .bounce, .float, .shake, .slideIn, .dropIn: [.position]
        case .wiggle, .spin: [.rotation]
        case .fadeIn, .fadeOut: [.opacity]
        case .typewriter: [.visible]
        }
    }
}

public struct PresetOptions: Hashable, Sendable {
    public var duration: Double
    public var amplitude: Double
    /// Slide-in direction in world space (unit); defaults to from the left.
    public var direction: Vec3

    public init(duration: Double, amplitude: Double, direction: Vec3 = Vec3(-1, 0, 0)) {
        self.duration = duration
        self.amplitude = amplitude
        self.direction = direction
    }

    public init(_ preset: AnimationPreset) {
        self.init(duration: preset.defaultDuration, amplitude: preset.defaultAmplitude)
    }
}

/// Order in which a multi-selection is staggered.
public enum StaggerOrder: Hashable, Sendable, Codable {
    /// The order things were selected.
    case selection
    /// Along a world axis (left → right is `.axis(.x, reversed: false)`).
    case axis(Axis, reversed: Bool)
    /// Distance from a point: a wave spreading out.
    case distance(from: Vec3)
}

public struct StaggerSettings: Hashable, Sendable {
    /// Delay between one object and the next (seconds).
    public var delay: Double
    public var order: StaggerOrder
    /// 0…1: random extra delay as a fraction of `delay`.
    public var randomTiming: Double
    /// 0…1: random ± variation of the amplitude.
    public var randomAmplitude: Double
    public var seed: UInt64

    public init(delay: Double = 0.08, order: StaggerOrder = .selection, randomTiming: Double = 0, randomAmplitude: Double = 0, seed: UInt64 = 7) {
        self.delay = delay
        self.order = order
        self.randomTiming = randomTiming
        self.randomAmplitude = randomAmplitude
        self.seed = seed
    }
}

/// Builds keys for presets (single objects or staggered crowds).
public struct PresetBuilder: Sendable {
    public var ids: IDFactory

    public init(ids: IDFactory = .random) {
        self.ids = ids
    }

    /// Keys for one object. `current` is the object as it looks at `start`.
    public static func keys(
        _ preset: AnimationPreset, for object: SceneObject, children: [ObjectID] = [], at start: Double, options: PresetOptions
    ) -> [(ObjectID, PropertyKey, [Keyframe])] {
        let d = max(options.duration, 1.0 / 60)
        let a = options.amplitude
        let t = object.transform
        let id = object.id
        func k(_ time: Double, _ value: PropertyValue, _ easing: Easing = .easeInOut) -> Keyframe {
            Keyframe(time: start + time, value: value, easing: easing)
        }
        switch preset {
        case .popIn:
            return [(id, .scale, [k(0, .vec3(t.scale * 0.001), .backOut), k(d, .vec3(t.scale))])]
        case .popOut:
            return [(id, .scale, [k(0, .vec3(t.scale), .easeIn), k(d, .vec3(t.scale * 0.001))])]
        case .grow, .shrink:
            return [(id, .scale, [k(0, .vec3(t.scale), .easeInOut), k(d, .vec3(t.scale * a))])]
        case .pulse:
            return [(id, .scale, [
                k(0, .vec3(t.scale)), k(d * 0.25, .vec3(t.scale * a)), k(d * 0.5, .vec3(t.scale)),
                k(d * 0.75, .vec3(t.scale * a)), k(d, .vec3(t.scale))
            ])]
        case .bounce:
            let up = t.position + Vec3(0, a, 0)
            return [(id, .position, [k(0, .vec3(t.position), .easeOut), k(d * 0.35, .vec3(up), .bounce), k(d, .vec3(t.position))])]
        case .dropIn:
            let above = t.position + Vec3(0, a, 0)
            return [(id, .position, [k(0, .vec3(above), .bounce), k(d, .vec3(t.position))])]
        case .slideIn:
            let from = t.position + options.direction.normalized * a
            return [(id, .position, [k(0, .vec3(from), .backOut), k(d, .vec3(t.position))])]
        case .float:
            let steps = 8
            var keys: [Keyframe] = []
            for index in 0 ... steps {
                let phase = Double(index) / Double(steps) * 2 * .pi * 2
                keys.append(k(d * Double(index) / Double(steps), .vec3(t.position + Vec3(0, sin(phase) * a, 0))))
            }
            return [(id, .position, keys)]
        case .shake:
            var random = SeededRandom(seed: Noise.seed(id.raw))
            var keys: [Keyframe] = [k(0, .vec3(t.position), .linear)]
            let steps = 8
            for index in 1 ..< steps {
                let falloff = 1 - Double(index) / Double(steps)
                let jitter = Vec3(random.range(-1, 1), random.range(-0.3, 0.3), random.range(-1, 1))
                let offset: Vec3 = jitter * (a * falloff)
                keys.append(k(d * Double(index) / Double(steps), .vec3(t.position + offset), .linear))
            }
            keys.append(k(d, .vec3(t.position)))
            return [(id, .position, keys)]
        case .wiggle:
            var keys: [Keyframe] = [k(0, .quat(t.rotation))]
            let steps = 6
            for index in 1 ..< steps {
                let falloff = 1 - Double(index - 1) / Double(steps)
                let angle = (index % 2 == 0 ? -1.0 : 1.0) * a * falloff * .pi / 180
                keys.append(k(d * Double(index) / Double(steps), .quat((t.rotation * Quat(angle: angle, axis: .unitZ)).normalized)))
            }
            keys.append(k(d, .quat(t.rotation)))
            return [(id, .rotation, keys)]
        case .spin:
            // Quarter turns so slerp never takes the short way back.
            let quarters = max(Int((abs(a) / 90).rounded(.up)), 1)
            let step = a / Double(quarters) * .pi / 180
            var keys: [Keyframe] = []
            for index in 0 ... quarters {
                let easing: Easing = quarters == 1 ? .easeInOut : (index == 0 ? .easeIn : (index == quarters - 1 ? .easeOut : .linear))
                // Overlays turn in the frame; everything else spins around its vertical axis.
                let rotation = (t.rotation * Quat(angle: step * Double(index), axis: object.kind.isOverlay ? .unitZ : .unitY)).normalized
                keys.append(k(d * Double(index) / Double(quarters), .quat(rotation), easing))
            }
            return [(id, .rotation, keys)]
        case .fadeIn:
            return [(id, .opacity, [k(0, .float(0), .easeOut), k(d, .float(object.opacity))])]
        case .fadeOut:
            return [(id, .opacity, [k(0, .float(object.opacity), .easeIn), k(d, .float(0))])]
        case .typewriter:
            // Text and overlays type themselves out (and arrows draw themselves).
            switch object.kind {
            case .text, .overlay:
                return [(id, .reveal, [k(0, .float(0), .linear), k(d, .float(1))])]
            default:
                break
            }
            // Reveal parts one by one (titles, lists, a row of desks). Without parts: appear at start.
            let parts = children.isEmpty ? [id] : children
            let step = d / Double(max(parts.count, 1))
            return parts.enumerated().map { index, part in
                (part, PropertyKey.visible, [
                    Keyframe(time: 0, value: .bool(false), easing: .step),
                    Keyframe(time: start + step * Double(index), value: .bool(true), easing: .step)
                ])
            }
        }
    }

    /// Applies a preset to objects (staggered when more than one) as one undoable command.
    /// Existing keys of the same properties inside each preset's time span are replaced.
    public mutating func apply(
        _ preset: AnimationPreset, to objects: [ObjectID], at start: Double, options: PresetOptions,
        stagger: StaggerSettings = StaggerSettings(), current: Scene, timeline: Timeline
    ) -> EditCommand? {
        let ordered = Self.order(objects, by: stagger.order, in: current)
        var random = SeededRandom(seed: stagger.seed)
        var working = timeline
        var edits: [TrackEdit] = []
        for (rank, id) in ordered.enumerated() {
            guard let object = current.objects[id] else { continue }
            let jitter = stagger.randomTiming > 0 ? random.range(0, stagger.randomTiming) * stagger.delay : 0
            let amplitudeScale = stagger.randomAmplitude > 0 ? 1 + random.range(-stagger.randomAmplitude, stagger.randomAmplitude) : 1
            var options = options
            options.amplitude = Self.scaledAmplitude(preset, options.amplitude, by: amplitudeScale)
            let begin = start + Double(ordered.count > 1 ? rank : 0) * stagger.delay + jitter
            let children = current.objects[id]?.children ?? []
            for (target, property, keys) in Self.keys(preset, for: object, children: children, at: begin, options: options) {
                var track = working.track(for: target, property) ?? Track(id: ids.next(), target: target, property: property)
                if let first = keys.map(\.time).min(), let last = keys.map(\.time).max() {
                    track.removeKeys(in: TimeRange(start: first, end: last))
                }
                for key in keys {
                    track.setKey(key)
                }
                if let index = working.tracks.firstIndex(where: { $0.id == track.id }) {
                    working.tracks[index] = track
                } else {
                    working.tracks.append(track)
                }
                edits.removeAll { $0.id == track.id }
                edits.append(TrackEdit(track))
            }
        }
        guard !edits.isEmpty else { return nil }
        return .batch(ordered.count > 1 ? "\(preset.title) × \(ordered.count)" : preset.title, [.setTracks(edits)])
    }

    /// Amplitude variation that stays meaningful for multiplicative presets (grow, pulse).
    public static func scaledAmplitude(_ preset: AnimationPreset, _ amplitude: Double, by factor: Double) -> Double {
        switch preset {
        case .grow, .shrink, .pulse: 1 + (amplitude - 1) * factor
        default: amplitude * factor
        }
    }

    public static func order(_ objects: [ObjectID], by order: StaggerOrder, in scene: Scene) -> [ObjectID] {
        let existing = objects.filter { scene.objects[$0] != nil }
        switch order {
        case .selection:
            return existing
        case let .axis(axis, reversed):
            let sorted = existing.enumerated().sorted { lhs, rhs in
                let a = scene.worldTransform(of: lhs.element).position[axis]
                let b = scene.worldTransform(of: rhs.element).position[axis]
                return abs(a - b) > 1e-9 ? a < b : lhs.offset < rhs.offset
            }.map(\.element)
            return reversed ? sorted.reversed() : sorted
        case let .distance(point):
            return existing.enumerated().sorted { lhs, rhs in
                let a = scene.worldTransform(of: lhs.element).position.distance(to: point)
                let b = scene.worldTransform(of: rhs.element).position.distance(to: point)
                return abs(a - b) > 1e-9 ? a < b : lhs.offset < rhs.offset
            }.map(\.element)
        }
    }

    /// Animated generators: a growing array / an animated scatter — its parts pop in one after
    /// another, spreading from the first part (array) or from the centre (scatter).
    public mutating func animateGenerator(
        _ group: ObjectID, at start: Double, preset: AnimationPreset = .popIn, spread: Double = 1.2, current: Scene, timeline: Timeline
    ) -> EditCommand? {
        guard let object = current.objects[group], !object.children.isEmpty else { return nil }
        let positions = object.children.map { current.worldTransform(of: $0).position }
        let center = positions.reduce(Vec3.zero, +) / Double(positions.count)
        let isScatter = object.name.localizedCaseInsensitiveContains("scatter")
        let origin = isScatter ? center : (positions.first ?? center)
        let stagger = StaggerSettings(delay: spread / Double(max(object.children.count - 1, 1)), order: .distance(from: origin),
                                      randomTiming: isScatter ? 0.6 : 0, seed: Noise.seed(group.raw))
        return apply(preset, to: object.children, at: start, options: PresetOptions(preset), stagger: stagger, current: current, timeline: timeline)
    }
}
