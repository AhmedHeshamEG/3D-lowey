import Foundation

/// Easing curves. Presets plus a free cubic-bezier (for the Phase 2 graph editor).
public enum Easing: Hashable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    /// Overshoots then settles — the snappy pose-to-pose default.
    case backOut
    case bounce
    case elastic
    /// Holds the previous value until the next key.
    case step
    case cubicBezier(Double, Double, Double, Double)

    /// Maps progress `t` in 0...1 to eased progress.
    public func apply(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t * t
        case .easeOut:
            let u = 1 - t
            return 1 - u * u * u
        case .easeInOut:
            return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .backOut:
            let c1 = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
        case .bounce:
            return Easing.bounceOut(t)
        case .elastic:
            if t == 0 || t == 1 { return t }
            let c4 = (2 * Double.pi) / 3
            return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
        case .step:
            return t >= 1 ? 1 : 0
        case let .cubicBezier(x1, y1, x2, y2):
            return Easing.solveBezier(t, x1, y1, x2, y2)
        }
    }

    private static func bounceOut(_ t: Double) -> Double {
        let n1 = 7.5625
        let d1 = 2.75
        if t < 1 / d1 {
            return n1 * t * t
        } else if t < 2 / d1 {
            let u = t - 1.5 / d1
            return n1 * u * u + 0.75
        } else if t < 2.5 / d1 {
            let u = t - 2.25 / d1
            return n1 * u * u + 0.9375
        } else {
            let u = t - 2.625 / d1
            return n1 * u * u + 0.984375
        }
    }

    /// CSS-style cubic bezier from (0,0) to (1,1): find s with x(s) = t, return y(s).
    private static func solveBezier(_ t: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func coordinate(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
        }
        func derivative(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * p1 + 6 * u * s * (p2 - p1) + 3 * s * s * (1 - p2)
        }
        var s = t
        for _ in 0 ..< 8 {
            let x = coordinate(s, x1, x2) - t
            let dx = derivative(s, x1, x2)
            if abs(x) < 1e-7 { break }
            if abs(dx) < 1e-7 { break }
            s -= x / dx
        }
        // Bisection fallback keeps it robust for extreme handles.
        if abs(coordinate(s, x1, x2) - t) > 1e-5 || s < 0 || s > 1 {
            var lo = 0.0
            var hi = 1.0
            s = t
            for _ in 0 ..< 60 {
                let x = coordinate(s, x1, x2)
                if abs(x - t) < 1e-7 { break }
                if x < t { lo = s } else { hi = s }
                s = (lo + hi) / 2
            }
        }
        return coordinate(s, y1, y2)
    }
}

extension Easing: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            switch name {
            case "linear": self = .linear
            case "easeIn": self = .easeIn
            case "easeOut": self = .easeOut
            case "easeInOut": self = .easeInOut
            case "backOut": self = .backOut
            case "bounce": self = .bounce
            case "elastic": self = .elastic
            case "step": self = .step
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown easing \(name)")
            }
        } else {
            let values = try container.decode([Double].self)
            guard values.count == 4 else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bezier easing needs 4 numbers")
            }
            self = .cubicBezier(values[0], values[1], values[2], values[3])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .linear: try container.encode("linear")
        case .easeIn: try container.encode("easeIn")
        case .easeOut: try container.encode("easeOut")
        case .easeInOut: try container.encode("easeInOut")
        case .backOut: try container.encode("backOut")
        case .bounce: try container.encode("bounce")
        case .elastic: try container.encode("elastic")
        case .step: try container.encode("step")
        case let .cubicBezier(a, b, c, d): try container.encode([a, b, c, d])
        }
    }
}

/// A key: at `time`, the property has `value`. `easing` shapes the segment *leaving* this key.
public struct Keyframe: Codable, Hashable, Sendable {
    public var time: Double
    public var value: PropertyValue
    public var easing: Easing

    public init(time: Double, value: PropertyValue, easing: Easing = .easeInOut) {
        self.time = time
        self.value = value
        self.easing = easing
    }
}

/// Animation of one property of one object.
public struct Track: Codable, Hashable, Sendable, Identifiable {
    public var id: TrackID
    public var target: ObjectID
    public var property: PropertyKey
    /// Kept sorted by time.
    public private(set) var keyframes: [Keyframe]

    public init(id: TrackID, target: ObjectID, property: PropertyKey, keyframes: [Keyframe] = []) {
        self.id = id
        self.target = target
        self.property = property
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    /// Inserts or replaces the key at `time` (within half a millisecond).
    public mutating func setKey(_ key: Keyframe) {
        if let index = keyframes.firstIndex(where: { abs($0.time - key.time) < 0.0005 }) {
            keyframes[index] = key
        } else {
            keyframes.append(key)
            keyframes.sort { $0.time < $1.time }
        }
    }

    public mutating func removeKey(at time: Double) {
        keyframes.removeAll { abs($0.time - time) < 0.0005 }
    }

    /// Replaces every key (sorted on the way in).
    public mutating func setKeys(_ keys: [Keyframe]) {
        keyframes = keys.sorted { $0.time < $1.time }
    }

    /// Removes the keys inside a time range (inclusive, half-millisecond tolerance).
    public mutating func removeKeys(in range: TimeRange) {
        keyframes.removeAll { range.contains($0.time, tolerance: 0.0005) }
    }

    public func key(at time: Double) -> Keyframe? {
        keyframes.first { abs($0.time - time) < 0.0005 }
    }

    public var timeRange: TimeRange? {
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        return TimeRange(start: first.time, end: last.time)
    }

    /// Value at `time`: holds before the first and after the last key.
    public func value(at time: Double, palette: Palette = .empty) -> PropertyValue? {
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        // Binary search for the segment.
        var lo = 0
        var hi = keyframes.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if keyframes[mid].time <= time { lo = mid } else { hi = mid }
        }
        let a = keyframes[lo]
        let b = keyframes[hi]
        let span = b.time - a.time
        guard span > 0 else { return b.value }
        let progress = a.easing.apply((time - a.time) / span)
        return a.value.interpolated(to: b.value, progress, palette: palette)
    }
}

/// Stepping for the "on twos" look: animation sampled every N frames.
public enum Stepping: Int, Codable, Sendable, CaseIterable {
    case onOnes = 1, onTwos = 2, onThrees = 3

    /// Quantizes `time` to the stepped frame grid at `fps`.
    public func quantize(_ time: Double, fps: Int) -> Double {
        guard rawValue > 1, fps > 0 else { return time }
        // A hair of tolerance so frame times computed as `frame / fps` land on their own frame.
        let frame = (time * Double(fps) + 1e-6).rounded(.down)
        let stepped = (frame / Double(rawValue)).rounded(.down) * Double(rawValue)
        return stepped / Double(fps)
    }

    /// Name used by the per-object `stepping` property.
    public var name: String {
        switch self {
        case .onOnes: "ones"
        case .onTwos: "twos"
        case .onThrees: "threes"
        }
    }

    public init?(name: String) {
        switch name {
        case "ones": self = .onOnes
        case "twos": self = .onTwos
        case "threes": self = .onThrees
        default: return nil
        }
    }
}

/// A named point in time ("Enigma", "the X pops").
public struct Marker: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var time: Double
    public var name: String

    public init(id: String, time: Double, name: String) {
        self.id = id
        self.time = time
        self.name = name
    }
}

/// A span of time (loop region, export range, perform range).
public struct TimeRange: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public var duration: Double { end - start }

    public func contains(_ time: Double, tolerance: Double = 1e-9) -> Bool {
        time >= start - tolerance && time <= end + tolerance
    }

    public func clamp(_ time: Double) -> Double { min(max(time, start), end) }
}

/// From `time` on, the scene is seen through `camera` (the camera-cut track).
public struct CameraCut: Codable, Hashable, Sendable {
    public var time: Double
    public var camera: ObjectID

    public init(time: Double, camera: ObjectID) {
        self.time = time
        self.camera = camera
    }
}

/// The scene timeline: keyframe tracks, clip tracks (characters), behaviours, camera cuts,
/// markers and a loop region. Full evaluation (per-object stepping, behaviours, clips) lives in `Animator`.
public struct Timeline: Hashable, Sendable {
    public static let frameRates = [24, 25, 30, 60]

    public var fps: Int
    public var duration: Double
    /// Project-wide stepping. Objects can override it (`stepping` property); cameras stay smooth.
    public var stepping: Stepping
    public var tracks: [Track]
    public var markers: [Marker]
    public var loop: TimeRange?
    public var cuts: [CameraCut]
    public var behaviors: [Behavior]
    public var clipTracks: [ClipTrack]
    /// Voiceover, sound effects and music (Phase 3).
    public var audio: [AudioClip]
    /// Recognised words of audio clips (one transcript per clip).
    public var transcripts: [Transcript]

    public init(
        fps: Int = 30, duration: Double = 10, stepping: Stepping = .onOnes, tracks: [Track] = [],
        markers: [Marker] = [], loop: TimeRange? = nil, cuts: [CameraCut] = [], behaviors: [Behavior] = [],
        clipTracks: [ClipTrack] = [], audio: [AudioClip] = [], transcripts: [Transcript] = []
    ) {
        self.fps = fps
        self.duration = duration
        self.stepping = stepping
        self.tracks = tracks
        self.markers = markers
        self.loop = loop
        self.cuts = cuts
        self.behaviors = behaviors
        self.clipTracks = clipTracks
        self.audio = audio
        self.transcripts = transcripts
    }

    public var frameCount: Int { Int((duration * Double(fps)).rounded()) }

    public func frame(for time: Double) -> Int { Int((time * Double(fps) + 1e-6).rounded(.down)) }
    public func time(for frame: Int) -> Double { Double(frame) / Double(fps) }

    /// Snaps a time to the nearest frame.
    public func snapped(_ time: Double) -> Double { (time * Double(fps)).rounded() / Double(fps) }

    public var isEmpty: Bool { tracks.isEmpty && behaviors.isEmpty && clipTracks.isEmpty && cuts.isEmpty }

    public func track(_ id: TrackID) -> Track? { tracks.first { $0.id == id } }

    public func track(for object: ObjectID, _ property: PropertyKey) -> Track? {
        tracks.first { $0.target == object && $0.property == property }
    }

    /// Everything that moves (keyed, behaviour-driven or playing clips).
    public var animatedObjects: Set<ObjectID> {
        var result = Set(tracks.map(\.target))
        result.formUnion(behaviors.map(\.target))
        result.formUnion(clipTracks.map(\.target))
        return result
    }

    /// The camera in charge at `time` (`nil` before the first cut or without cuts).
    public func cutCamera(at time: Double) -> ObjectID? {
        var result: ObjectID?
        var best = -Double.infinity
        for cut in cuts where cut.time <= time + 1e-9 && cut.time >= best {
            result = cut.camera
            best = cut.time
        }
        return result
    }

    /// Time of the last key, behaviour end or clip end (for "fit duration").
    public var contentEnd: Double {
        var end = 0.0
        for track in tracks {
            end = max(end, track.keyframes.last?.time ?? 0)
        }
        for behavior in behaviors {
            end = max(end, behavior.end ?? behavior.start)
        }
        for clipTrack in clipTracks {
            for segment in clipTrack.segments {
                end = max(end, segment.end)
            }
        }
        for cut in cuts {
            end = max(end, cut.time)
        }
        for clip in audio {
            end = max(end, clip.end)
        }
        return end
    }

    /// Keyed values at `time` (tracks only, project stepping): `[object: [property: value]]`.
    /// `Animator` adds per-object stepping, behaviours and clips on top.
    public func evaluate(at time: Double, palette: Palette = .empty) -> [ObjectID: [PropertyKey: PropertyValue]] {
        let sampleTime = stepping.quantize(time, fps: fps)
        var result: [ObjectID: [PropertyKey: PropertyValue]] = [:]
        for track in tracks {
            if let value = track.value(at: sampleTime, palette: palette) {
                result[track.target, default: [:]][track.property] = value
            }
        }
        return result
    }
}

extension Timeline: Codable {
    private enum CodingKeys: String, CodingKey {
        case fps, duration, stepping, tracks, markers, loop, cuts, behaviors, clipTracks, audio, transcripts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? 30
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 10
        stepping = try c.decodeIfPresent(Stepping.self, forKey: .stepping) ?? .onOnes
        tracks = try c.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        markers = try c.decodeIfPresent([Marker].self, forKey: .markers) ?? []
        loop = try c.decodeIfPresent(TimeRange.self, forKey: .loop)
        cuts = try c.decodeIfPresent([CameraCut].self, forKey: .cuts) ?? []
        behaviors = try c.decodeIfPresent([Behavior].self, forKey: .behaviors) ?? []
        clipTracks = try c.decodeIfPresent([ClipTrack].self, forKey: .clipTracks) ?? []
        audio = try c.decodeIfPresent([AudioClip].self, forKey: .audio) ?? []
        transcripts = try c.decodeIfPresent([Transcript].self, forKey: .transcripts) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fps, forKey: .fps)
        try c.encode(duration, forKey: .duration)
        try c.encode(stepping, forKey: .stepping)
        try c.encode(tracks, forKey: .tracks)
        try c.encode(markers, forKey: .markers)
        try c.encodeIfPresent(loop, forKey: .loop)
        try c.encode(cuts, forKey: .cuts)
        try c.encode(behaviors, forKey: .behaviors)
        try c.encode(clipTracks, forKey: .clipTracks)
        if !audio.isEmpty { try c.encode(audio, forKey: .audio) }
        if !transcripts.isEmpty { try c.encode(transcripts, forKey: .transcripts) }
    }
}
