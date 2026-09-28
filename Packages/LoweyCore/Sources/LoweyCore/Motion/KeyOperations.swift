import Foundation

/// A key on a track (selection, copy/paste).
public struct KeyRef: Hashable, Sendable, Codable {
    public var track: TrackID
    public var time: Double

    public init(track: TrackID, time: Double) {
        self.track = track
        self.time = time
    }
}

/// Copied keys: per (object, property), times relative to the earliest copied key.
public struct KeyClipboard: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public var object: ObjectID
        public var property: PropertyKey
        public var keys: [Keyframe]
    }

    public var entries: [Entry]
    public var span: Double

    public var isEmpty: Bool { entries.isEmpty }
}

/// Keyframe editing. Every function returns a command (one undo step) — nothing mutates directly.
public struct KeyOperations: Sendable {
    public var ids: IDFactory

    public init(ids: IDFactory = .random) {
        self.ids = ids
    }

    // MARK: Setting keys

    /// Keys `value` for `object.property` at `time`. A new track also gets a key at time 0 holding the
    /// value before the edit (`previous`), so the change animates immediately instead of snapping.
    public mutating func setKey(
        _ object: ObjectID, _ property: PropertyKey, value: PropertyValue, at time: Double, previous: PropertyValue?,
        easing: Easing = .easeInOut, in timeline: Timeline
    ) -> TrackEdit {
        if var track = timeline.track(for: object, property) {
            var key = track.key(at: time) ?? Keyframe(time: time, value: value, easing: easingBefore(time, in: track) ?? easing)
            key.value = value
            track.setKey(key)
            return TrackEdit(track)
        }
        var track = Track(id: ids.next(), target: object, property: property)
        if let previous, time > 1e-6, previous != value {
            track.setKey(Keyframe(time: 0, value: previous, easing: easing))
        }
        track.setKey(Keyframe(time: time, value: value, easing: easing))
        return TrackEdit(track)
    }

    /// The easing of the key right before `time` (so a new key in the middle keeps the curve style).
    private func easingBefore(_ time: Double, in track: Track) -> Easing? {
        track.keyframes.last { $0.time < time }?.easing
    }

    /// Turns property changes into keys at `time` (auto-key / editing an animated property).
    /// `current` is the scene as displayed (evaluated) — it provides the "before" values.
    public mutating func keying(_ changes: [PropertyChange], at time: Double, current: Scene, timeline: Timeline) -> [TrackEdit] {
        var working = timeline
        var edits: [TrackEdit] = []
        for change in changes {
            guard let value = change.value else { continue }
            let previous = current.objects[change.object]?.properties[change.key] ?? PropertyDefaults.value(for: change.key)
            let edit = setKey(change.object, change.key, value: value, at: time, previous: previous, in: working)
            if let track = edit.track {
                if let index = working.tracks.firstIndex(where: { $0.id == track.id }) {
                    working.tracks[index] = track
                } else {
                    working.tracks.append(track)
                }
            }
            if let index = edits.firstIndex(where: { $0.id == edit.id }) {
                edits[index] = edit
            } else {
                edits.append(edit)
            }
        }
        return edits
    }

    /// Keys position, rotation and scale of objects as they are at `time` ("key everything here").
    public mutating func keyTransforms(_ objects: [ObjectID], at time: Double, current: Scene, timeline: Timeline) -> EditCommand? {
        var changes: [PropertyChange] = []
        for id in objects {
            guard let object = current.objects[id] else { continue }
            let transform = object.transform
            changes.append(PropertyChange(object: id, key: .position, value: .vec3(transform.position)))
            changes.append(PropertyChange(object: id, key: .rotation, value: .quat(transform.rotation)))
            changes.append(PropertyChange(object: id, key: .scale, value: .vec3(transform.scale)))
        }
        let edits = keying(changes, at: time, current: current, timeline: timeline)
        return edits.isEmpty ? nil : .setTracks(edits)
    }

    // MARK: Editing selected keys

    private func grouped(_ keys: [KeyRef], in timeline: Timeline) -> [(Track, [Keyframe])] {
        var result: [(Track, [Keyframe])] = []
        for track in timeline.tracks {
            let times = keys.filter { $0.track == track.id }.map(\.time)
            guard !times.isEmpty else { continue }
            let selected = track.keyframes.filter { key in times.contains { abs($0 - key.time) < 0.0005 } }
            if !selected.isEmpty { result.append((track, selected)) }
        }
        return result
    }

    private static func isSelected(_ key: Keyframe, _ selected: [Keyframe]) -> Bool {
        selected.contains { abs($0.time - key.time) < 0.0005 }
    }

    public func delete(_ keys: [KeyRef], in timeline: Timeline) -> EditCommand? {
        var edits: [TrackEdit] = []
        for (track, selected) in grouped(keys, in: timeline) {
            var copy = track
            copy.setKeys(track.keyframes.filter { !Self.isSelected($0, selected) })
            // A track without keys is removed entirely.
            edits.append(copy.keyframes.isEmpty ? TrackEdit(id: track.id, track: nil) : TrackEdit(copy))
        }
        return edits.isEmpty ? nil : .setTracks(edits)
    }

    /// Moves keys in time (retime by dragging). Keys that land on other keys replace them.
    public func move(_ keys: [KeyRef], by delta: Double, in timeline: Timeline) -> EditCommand? {
        var edits: [TrackEdit] = []
        for (track, selected) in grouped(keys, in: timeline) {
            let moved = selected.map { key -> Keyframe in
                var copy = key
                copy.time = max(0, key.time + delta)
                return copy
            }
            var rest = track.keyframes.filter { !Self.isSelected($0, selected) }
            rest.removeAll { key in moved.contains { abs($0.time - key.time) < 0.0005 } }
            var copy = track
            copy.setKeys(rest + moved)
            edits.append(TrackEdit(copy))
        }
        return edits.isEmpty ? nil : .setTracks(edits)
    }

    /// Scales the timing of keys around the earliest selected key (0.5 = twice as fast).
    public func retime(_ keys: [KeyRef], factor: Double, in timeline: Timeline) -> EditCommand? {
        guard factor > 0 else { return nil }
        let pivot = keys.map(\.time).min() ?? 0
        return transformTimes(keys, in: timeline) { pivot + ($0 - pivot) * factor }
    }

    /// Plays the selected keys backwards in place (values swap ends; easing follows the values).
    public func reverse(_ keys: [KeyRef], in timeline: Timeline) -> EditCommand? {
        let times = keys.map(\.time)
        guard let lo = times.min(), let hi = times.max(), hi > lo else { return nil }
        var edits: [TrackEdit] = []
        for (track, selected) in grouped(keys, in: timeline) {
            let reversed = Self.reversedKeys(selected, lo: lo, hi: hi)
            var copy = track
            copy.setKeys(track.keyframes.filter { !Self.isSelected($0, selected) } + reversed)
            edits.append(TrackEdit(copy))
        }
        return edits.isEmpty ? nil : .setTracks(edits)
    }

    /// Mirror: appends a reversed copy after the selection, so the motion returns to where it started
    /// (a wave out and back, a door that opens and closes).
    public func mirror(_ keys: [KeyRef], in timeline: Timeline) -> EditCommand? {
        let times = keys.map(\.time)
        guard let lo = times.min(), let hi = times.max(), hi > lo else { return nil }
        var edits: [TrackEdit] = []
        for (track, selected) in grouped(keys, in: timeline) {
            let reversed = Self.reversedKeys(selected, lo: lo, hi: hi).map { key -> Keyframe in
                var copy = key
                copy.time = key.time + (hi - lo)
                return copy
            }
            var copy = track
            let after = reversed.filter { $0.time > hi + 0.0005 }
            var kept = track.keyframes
            kept.removeAll { key in after.contains { abs($0.time - key.time) < 0.0005 } }
            copy.setKeys(kept + after)
            edits.append(TrackEdit(copy))
        }
        return edits.isEmpty ? nil : .setTracks(edits)
    }

    /// Reverses keys between `lo` and `hi`: the value at t moves to lo + hi - t. Each segment keeps
    /// its easing but mirrored in time (an ease-out becomes an ease-in).
    static func reversedKeys(_ keys: [Keyframe], lo: Double, hi: Double) -> [Keyframe] {
        let sorted = keys.sorted { $0.time < $1.time }
        var result: [Keyframe] = []
        for (index, key) in sorted.enumerated().reversed() {
            let easing: Easing = index > 0 ? mirrored(sorted[index - 1].easing) : key.easing
            result.append(Keyframe(time: lo + hi - key.time, value: key.value, easing: easing))
        }
        return result
    }

    /// Time-mirrored easing: e(t) → 1 - e(1 - t).
    public static func mirrored(_ easing: Easing) -> Easing {
        switch easing {
        case .easeIn: .easeOut
        case .easeOut: .easeIn
        case let .cubicBezier(x1, y1, x2, y2): .cubicBezier(1 - x2, 1 - y2, 1 - x1, 1 - y1)
        default: easing
        }
    }

    public func setEasing(_ easing: Easing, for keys: [KeyRef], in timeline: Timeline) -> EditCommand? {
        var edits: [TrackEdit] = []
        for (track, selected) in grouped(keys, in: timeline) {
            var copy = track
            copy.setKeys(track.keyframes.map { key in
                guard Self.isSelected(key, selected) else { return key }
                var changed = key
                changed.easing = easing
                return changed
            })
            edits.append(TrackEdit(copy))
        }
        return edits.isEmpty ? nil : .setTracks(edits)
    }

    private func transformTimes(_ keys: [KeyRef], in timeline: Timeline, _ transform: (Double) -> Double) -> EditCommand? {
        var edits: [TrackEdit] = []
        for (track, selected) in grouped(keys, in: timeline) {
            let changed = selected.map { key -> Keyframe in
                var copy = key
                copy.time = max(0, transform(key.time))
                return copy
            }
            var rest = track.keyframes.filter { !Self.isSelected($0, selected) }
            rest.removeAll { key in changed.contains { abs($0.time - key.time) < 0.0005 } }
            var copy = track
            copy.setKeys(rest + changed)
            edits.append(TrackEdit(copy))
        }
        return edits.isEmpty ? nil : .setTracks(edits)
    }

    // MARK: Copy / paste

    public func copy(_ keys: [KeyRef], in timeline: Timeline) -> KeyClipboard {
        let groups = grouped(keys, in: timeline)
        let start = groups.flatMap { $0.1.map(\.time) }.min() ?? 0
        let end = groups.flatMap { $0.1.map(\.time) }.max() ?? 0
        let entries = groups.map { track, selected in
            KeyClipboard.Entry(object: track.target, property: track.property, keys: selected.map { key in
                var copy = key
                copy.time -= start
                return copy
            })
        }
        return KeyClipboard(entries: entries, span: end - start)
    }

    /// Pastes at `time`. With `onto`, all copied keys go to that object (copy one object's motion to another).
    public mutating func paste(_ clipboard: KeyClipboard, at time: Double, onto target: ObjectID? = nil, in timeline: Timeline) -> EditCommand? {
        var working = timeline
        var edits: [TrackEdit] = []
        for entry in clipboard.entries {
            let object = target ?? entry.object
            var track = working.track(for: object, entry.property) ?? Track(id: ids.next(), target: object, property: entry.property)
            for key in entry.keys {
                var shifted = key
                shifted.time = time + key.time
                track.setKey(shifted)
            }
            if let index = working.tracks.firstIndex(where: { $0.id == track.id }) {
                working.tracks[index] = track
            } else {
                working.tracks.append(track)
            }
            edits.removeAll { $0.id == track.id }
            edits.append(TrackEdit(track))
        }
        return edits.isEmpty ? nil : .setTracks(edits)
    }

    // MARK: Whole objects

    /// Shifts all animation of objects in time (Compose mode: slide an object's bar).
    public func shift(_ objects: Set<ObjectID>, by delta: Double, in timeline: Timeline) -> EditCommand? {
        let keys = timeline.tracks.filter { objects.contains($0.target) }.flatMap { track in
            track.keyframes.map { KeyRef(track: track.id, time: $0.time) }
        }
        guard !keys.isEmpty else { return nil }
        let earliest = keys.map(\.time).min() ?? 0
        return move(keys, by: max(delta, -earliest), in: timeline)
    }

    /// Removes every track of the objects (clear animation).
    public func clear(_ objects: Set<ObjectID>, properties: Set<PropertyKey>? = nil, in timeline: Timeline) -> EditCommand? {
        let edits = timeline.tracks.filter { objects.contains($0.target) && (properties?.contains($0.property) ?? true) }
            .map { TrackEdit(id: $0.id, track: nil) }
        return edits.isEmpty ? nil : .setTracks(edits)
    }
}

/// Values a property has when it isn't set (so the first key of a new track can hold "before").
public enum PropertyDefaults {
    public static func value(for key: PropertyKey) -> PropertyValue? {
        switch key {
        case .position: .vec3(.zero)
        case .rotation: .quat(.identity)
        case .scale: .vec3(.one)
        case .visible: .bool(true)
        case .opacity: .float(1)
        case .emissiveIntensity: .float(0)
        case .lightIntensity: .float(1)
        case .fieldOfView: .float(50)
        case .focusDistance: .float(5)
        case .aperture: .float(0)
        case .portraitZoom: .float(1)
        case .portraitShift: .float(0)
        case .roughness: .float(0.85)
        case .metallic: .float(0)
        default: nil
        }
    }
}
