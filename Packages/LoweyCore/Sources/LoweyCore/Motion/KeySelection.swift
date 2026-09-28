import Foundation

/// Picking many keys at once (Procreate Dreams-style multi-select): a box over rows and time,
/// everything after/before the playhead, one column of keys, the loop region, invert.
/// Pure queries — selecting never changes the document.
public enum KeySelection {
    /// Every key of `tracks` (all tracks when `nil`).
    public static func all(in timeline: Timeline, tracks: Set<TrackID>? = nil) -> Set<KeyRef> {
        var result = Set<KeyRef>()
        for track in timeline.tracks where tracks?.contains(track.id) ?? true {
            for key in track.keyframes {
                result.insert(KeyRef(track: track.id, time: key.time))
            }
        }
        return result
    }

    /// Tracks animating `objects`.
    public static func tracks(of objects: Set<ObjectID>, in timeline: Timeline) -> Set<TrackID> {
        Set(timeline.tracks.filter { objects.contains($0.target) }.map(\.id))
    }

    /// Keys of `tracks` whose time falls inside `range` (a box drawn over rows and time).
    public static func keys(in range: TimeRange, tracks: Set<TrackID>, timeline: Timeline) -> Set<KeyRef> {
        all(in: timeline, tracks: tracks).filter { range.contains($0.time, tolerance: 0.0005) }
    }

    /// Keys at or after `time` ("everything from here on").
    public static func after(_ time: Double, in timeline: Timeline, tracks: Set<TrackID>? = nil) -> Set<KeyRef> {
        all(in: timeline, tracks: tracks).filter { $0.time >= time - 0.0005 }
    }

    /// Keys at or before `time`.
    public static func before(_ time: Double, in timeline: Timeline, tracks: Set<TrackID>? = nil) -> Set<KeyRef> {
        all(in: timeline, tracks: tracks).filter { $0.time <= time + 0.0005 }
    }

    /// One column: every key at `time` (within half a frame).
    public static func column(at time: Double, in timeline: Timeline, tracks: Set<TrackID>? = nil) -> Set<KeyRef> {
        let tolerance = 0.5 / Double(max(timeline.fps, 1))
        return all(in: timeline, tracks: tracks).filter { abs($0.time - time) <= tolerance }
    }

    /// Everything not selected (within `tracks`).
    public static func inverted(_ selection: Set<KeyRef>, in timeline: Timeline, tracks: Set<TrackID>? = nil) -> Set<KeyRef> {
        let selected = normalized(selection, in: timeline)
        return all(in: timeline, tracks: tracks).subtracting(selected)
    }

    /// First and last selected key times.
    public static func span(of selection: Set<KeyRef>) -> TimeRange? {
        let times = selection.map(\.time)
        guard let lo = times.min(), let hi = times.max() else { return nil }
        return TimeRange(start: lo, end: hi)
    }

    /// Drops refs that no longer point at a key and snaps the rest to the stored key times.
    public static func normalized(_ selection: Set<KeyRef>, in timeline: Timeline) -> Set<KeyRef> {
        var result = Set<KeyRef>()
        for ref in selection {
            guard let key = timeline.track(ref.track)?.key(at: ref.time) else { continue }
            result.insert(KeyRef(track: ref.track, time: key.time))
        }
        return result
    }

    /// Where selected keys land after stretching `from` onto `to` (same mapping the command uses).
    public static func stretchedTime(_ time: Double, from: TimeRange, to: TimeRange) -> Double {
        guard from.duration > 1e-9 else { return to.start + (time - from.start) }
        return to.start + (time - from.start) / from.duration * to.duration
    }
}

public extension KeyOperations {
    /// Stretches or squashes the timing of `keys` so their first key lands on `range.start` and their
    /// last on `range.end` (drag either end of a multi-key selection). Keys in between keep their
    /// proportional spacing; unselected keys they land on are replaced. One undo step.
    func stretch(_ keys: [KeyRef], to range: TimeRange, in timeline: Timeline) -> EditCommand? {
        guard let from = KeySelection.span(of: Set(keys)) else { return nil }
        let target = TimeRange(start: max(range.start, 0), end: max(range.end, 0))
        guard abs(from.start - target.start) > 1e-9 || abs(from.end - target.end) > 1e-9 else { return nil }
        return retimed(keys, in: timeline) { KeySelection.stretchedTime($0, from: from, to: target) }
    }

    /// Moves keys so the earliest one never goes below zero (the whole selection stops together
    /// instead of piling up at 0).
    func moveClamped(_ keys: [KeyRef], by delta: Double, in timeline: Timeline) -> EditCommand? {
        let earliest = keys.map(\.time).min() ?? 0
        let clamped = max(delta, -earliest)
        guard abs(clamped) > 1e-9 else { return nil }
        return move(keys, by: clamped, in: timeline)
    }

    private func retimed(_ keys: [KeyRef], in timeline: Timeline, _ transform: (Double) -> Double) -> EditCommand? {
        var edits: [TrackEdit] = []
        for track in timeline.tracks {
            let times = keys.filter { $0.track == track.id }.map(\.time)
            guard !times.isEmpty else { continue }
            let isSelected: (Keyframe) -> Bool = { key in times.contains { abs($0 - key.time) < 0.0005 } }
            let changed = track.keyframes.filter(isSelected).map { key -> Keyframe in
                var copy = key
                copy.time = max(0, transform(key.time))
                return copy
            }
            guard !changed.isEmpty else { continue }
            var rest = track.keyframes.filter { !isSelected($0) }
            rest.removeAll { key in changed.contains { abs($0.time - key.time) < 0.0005 } }
            var copy = track
            copy.setKeys(rest + changed)
            edits.append(TrackEdit(copy))
        }
        return edits.isEmpty ? nil : .setTracks(edits)
    }
}
