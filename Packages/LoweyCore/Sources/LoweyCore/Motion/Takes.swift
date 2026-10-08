import Foundation

/// One recorded performance, kept whole: the keys every performed channel got. The timeline's tracks are always the
/// comp (what plays); takes are what the comp is chosen from, so a second try never destroys the first.
public struct Take: Codable, Hashable, Sendable, Identifiable {
    /// The keys of one property of one object.
    public struct Channel: Codable, Hashable, Sendable {
        public var target: ObjectID
        public var property: PropertyKey
        public var keyframes: [Keyframe]

        public init(target: ObjectID, property: PropertyKey, keyframes: [Keyframe]) {
            self.target = target
            self.property = property
            self.keyframes = keyframes.sorted { $0.time < $1.time }
        }

        /// The channel's value at `time`, as a track would play it.
        public func value(at time: Double) -> PropertyValue? {
            Track(id: "take", target: target, property: property, keyframes: keyframes).value(at: time)
        }
    }

    public var id: String
    public var name: String
    /// From its first key to its last.
    public var range: TimeRange
    public var channels: [Channel]
    /// Where the comp plays this take, in order, never overlapping (`TakeComp` keeps it true).
    public var used: [TimeRange]

    public init(id: String, name: String, range: TimeRange, channels: [Channel], used: [TimeRange] = []) {
        self.id = id
        self.name = name
        self.range = range
        self.channels = channels
        self.used = used
    }

    /// Whether this take and `other` perform any of the same channels (so one replaces the other in the comp).
    public func shares(with other: Take) -> Bool {
        let own = Set(channels.map { ChannelKey($0.target, $0.property) })
        return other.channels.contains { own.contains(ChannelKey($0.target, $0.property)) }
    }

    struct ChannelKey: Hashable {
        var target: ObjectID
        var property: PropertyKey

        init(_ target: ObjectID, _ property: PropertyKey) {
            self.target = target
            self.property = property
        }
    }
}

/// Inserts, replaces or removes one take (`take == nil` removes).
public struct TakeEdit: Codable, Hashable, Sendable {
    public var id: String
    public var take: Take?
    public var index: Int?

    public init(id: String, take: Take?, index: Int? = nil) {
        self.id = id
        self.take = take
        self.index = index
    }

    public init(_ take: Take) {
        self.init(id: take.id, take: take)
    }
}

/// Recording takes and comping them: "use this take from here to there". Using a take writes its keys over that
/// stretch of the tracks, so the animator, exports and every key tool see an ordinary timeline.
public enum TakeComp {
    /// One command for a finished recording: the take is kept, and it becomes the comp wherever it was performed.
    public static func recording(_ performed: [PerformTake], name: String? = nil, fps: Int, smoothing: Double, timeline: Timeline,
                                 ids: inout IDFactory) -> EditCommand? {
        var channels: [Take.Channel] = []
        var stretches: [TimeRange] = []
        for take in performed.sorted(by: { ($0.object.raw, $0.property.rawValue) < ($1.object.raw, $1.property.rawValue) }) {
            var keys: [Keyframe] = []
            for segment in take.segments where !segment.isEmpty {
                let baked = PerformBaker.keys(from: segment, fps: fps, smoothing: smoothing, stepped: take.isStepped)
                guard let first = baked.first, let last = baked.last else { continue }
                keys.removeAll { $0.time >= first.time - 0.0005 && $0.time <= last.time + 0.0005 }
                keys.append(contentsOf: baked)
                stretches.append(TimeRange(start: first.time, end: last.time))
            }
            if !keys.isEmpty { channels.append(Take.Channel(target: take.object, property: take.property, keyframes: keys)) }
        }
        guard !channels.isEmpty, let start = stretches.map(\.start).min(), let end = stretches.map(\.end).max() else { return nil }
        let take = Take(id: ids.next(TrackID.self).raw, name: name ?? "Take \(timeline.takes.count + 1)", range: TimeRange(start: start, end: end),
                        channels: channels)
        var working = timeline
        working.takes.append(take)
        var tracks: [TrackID: Track] = [:]
        for stretch in merged(stretches) {
            for track in writing(take, over: stretch, timeline: working, fps: fps, ids: &ids) {
                tracks[track.id] = track
                working.tracks.removeAll { $0.id == track.id }
                working.tracks.append(track)
            }
            working.takes = marking(stretch, of: take.id, in: working.takes)
        }
        return .batch("Perform", [.setTracks(tracks.values.sorted { $0.id.raw < $1.id.raw }.map(TrackEdit.init)),
                                  .setTakes(edits(from: timeline.takes, to: working.takes))])
    }

    /// The command that makes `take` the comp over `range` (clipped to the take; nil when they don't meet).
    public static func using(_ id: String, over range: TimeRange? = nil, timeline: Timeline, ids: inout IDFactory) -> EditCommand? {
        guard let take = timeline.takes.first(where: { $0.id == id }) else { return nil }
        let wanted = range ?? take.range
        let stretch = TimeRange(start: max(wanted.start, take.range.start), end: min(wanted.end, take.range.end))
        guard wanted.end >= take.range.start, wanted.start <= take.range.end, stretch.duration > 1e-6 else { return nil }
        let tracks = writing(take, over: stretch, timeline: timeline, fps: timeline.fps, ids: &ids)
        let takes = marking(stretch, of: id, in: timeline.takes)
        return .batch("Use \(take.name)", [.setTracks(tracks.map(TrackEdit.init)), .setTakes(edits(from: timeline.takes, to: takes))])
    }

    /// Removing a take leaves the comp as it plays: the keys it gave the tracks stay.
    public static func removing(_ id: String, timeline: Timeline) -> EditCommand? {
        guard timeline.takes.contains(where: { $0.id == id }) else { return nil }
        return .batch("Delete take", [.setTakes([TakeEdit(id: id, take: nil)])])
    }

    public static func renaming(_ id: String, to name: String, timeline: Timeline) -> EditCommand? {
        guard var take = timeline.takes.first(where: { $0.id == id }), !name.isEmpty, take.name != name else { return nil }
        take.name = name
        return .batch("Rename take", [.setTakes([TakeEdit(take)])])
    }

    // MARK: Keys

    /// The tracks of the take's channels with `stretch` replaced by the take. What played before keeps playing right
    /// up to the stretch and right after it: a key a frame outside each end holds the old value there.
    static func writing(_ take: Take, over stretch: TimeRange, timeline: Timeline, fps: Int, ids: inout IDFactory) -> [Track] {
        let frame = 1 / Double(max(fps, 1))
        return take.channels.compactMap { channel in
            let inside = channel.keyframes.filter { stretch.contains($0.time, tolerance: 0.0005) }
            guard let startValue = channel.value(at: stretch.start), let endValue = channel.value(at: stretch.end) else { return nil }
            let old = timeline.track(for: channel.target, channel.property)
            var track = old ?? Track(id: ids.next(TrackID.self), target: channel.target, property: channel.property)
            let easing = channel.keyframes.last?.easing ?? .linear
            let before = stretch.start - frame
            let after = stretch.end + frame
            let guards = [before, after].compactMap { time -> Keyframe? in
                guard time >= 0, let old, let first = old.keyframes.first, let last = old.keyframes.last,
                      time >= first.time, time <= last.time, let value = old.value(at: time) else { return nil }
                return Keyframe(time: time, value: value, easing: old.keyframes.last { $0.time <= time }?.easing ?? easing)
            }
            track.removeKeys(in: TimeRange(start: max(before, 0), end: after))
            for key in guards {
                track.setKey(key)
            }
            track.setKey(Keyframe(time: stretch.start, value: startValue, easing: easing))
            track.setKey(Keyframe(time: stretch.end, value: endValue, easing: easing))
            for key in inside {
                track.setKey(key)
            }
            return track
        }
    }

    // MARK: Where each take plays

    /// `takes` with `stretch` given to one take and taken from every take that performs the same channels.
    static func marking(_ stretch: TimeRange, of id: String, in takes: [Take]) -> [Take] {
        guard let chosen = takes.first(where: { $0.id == id }) else { return takes }
        return takes.map { take in
            var result = take
            if take.id == id {
                result.used = merged(take.used + [stretch])
            } else if take.shares(with: chosen) {
                result.used = take.used.flatMap { subtract(stretch, from: $0) }
            }
            return result
        }
    }

    /// Ranges in order with touching and overlapping ones joined.
    static func merged(_ ranges: [TimeRange]) -> [TimeRange] {
        var result: [TimeRange] = []
        for range in ranges.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, range.start <= last.end + 1e-6 {
                result[result.count - 1] = TimeRange(start: last.start, end: max(last.end, range.end))
            } else {
                result.append(range)
            }
        }
        return result
    }

    static func subtract(_ cut: TimeRange, from range: TimeRange) -> [TimeRange] {
        guard cut.end > range.start + 1e-6, cut.start < range.end - 1e-6 else { return [range] }
        var result: [TimeRange] = []
        if cut.start > range.start + 1e-6 { result.append(TimeRange(start: range.start, end: cut.start)) }
        if cut.end < range.end - 1e-6 { result.append(TimeRange(start: cut.end, end: range.end)) }
        return result
    }

    static func edits(from old: [Take], to new: [Take]) -> [TakeEdit] {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return new.filter { before[$0.id] != $0 }.map(TakeEdit.init)
    }
}
