import Foundation
import HmmDesign
import LoweyCore

/// Keys on the timeline: key the selection, move, stretch, nudge, select by query, easing, copy / paste, mirror,
/// reverse, retime, and whole animations slid in Compose.
extension EditorModel {
    /// The Key button: position, rotation and scale of the selection as they are now.
    func keySelection() {
        var keys = KeyOperations()
        guard let command = keys.keyTransforms(selection, at: time, current: displayed.scene, timeline: timeline) else { return }
        perform(command)
        HmmHaptics.play(.commit)
    }

    func deleteSelectedKeys() {
        perform(KeyOperations().delete(Array(selectedKeys), in: timeline))
        selectedKeys = []
    }

    func moveSelectedKeys(by delta: Double, snapToWords wordSnap: Bool = true) {
        let earliest = selectedKeys.map(\.time).min() ?? 0
        var snapped = max(timeline.snapped(delta), -earliest)
        // The selection's first key lands on a spoken word when dropped close to one.
        if wordSnap, snapToWords, let word = WordSnap.snap(earliest + snapped, to: words, tolerance: 8 / max(timelineZoom, 1)) {
            snapped = max(word - earliest, -earliest)
        }
        guard abs(snapped) > 1e-9, perform(KeyOperations().moveClamped(Array(selectedKeys), by: snapped, in: timeline)) else { return }
        selectedKeys = Set(selectedKeys.map { KeyRef(track: $0.track, time: max(0, $0.time + snapped)) })
    }

    /// The selected keys by whole frames ([ and ], the key menu).
    func nudgeSelectedKeys(frames: Int) {
        moveSelectedKeys(by: Double(frames) / Double(max(timeline.fps, 1)), snapToWords: false)
    }

    /// Stretches the selected keys to span `range` (drag an end of the selection band).
    func stretchSelectedKeys(to range: TimeRange) {
        guard let from = KeySelection.span(of: selectedKeys) else { return }
        let target = TimeRange(start: timeline.snapped(max(range.start, 0)), end: timeline.snapped(max(range.end, 0)))
        guard perform(KeyOperations().stretch(Array(selectedKeys), to: target, in: timeline)) else { return }
        selectedKeys = KeySelection.normalized(Set(selectedKeys.map {
            KeyRef(track: $0.track, time: max(0, KeySelection.stretchedTime($0.time, from: from, to: target)))
        }), in: timeline)
        HmmHaptics.play(.commit)
    }

    func selectKeys(_ keys: Set<KeyRef>, additive: Bool = false) {
        selectedKeys = additive ? selectedKeys.union(keys) : keys
        if !keys.isEmpty { HmmHaptics.play(.selection) }
    }

    /// Tracks the key-selection commands act on: the selected objects' tracks, or every track.
    var keyScope: Set<TrackID>? {
        selection.isEmpty ? nil : KeySelection.tracks(of: Set(selection.flatMap { baseScene.subtree(of: $0) }), in: timeline)
    }

    func selectKeys(_ query: KeyQuery) {
        let scope = keyScope
        switch query {
        case .all: selectKeys(KeySelection.all(in: timeline, tracks: scope))
        case .afterPlayhead: selectKeys(KeySelection.after(time, in: timeline, tracks: scope))
        case .beforePlayhead: selectKeys(KeySelection.before(time, in: timeline, tracks: scope))
        case .atPlayhead: selectKeys(KeySelection.column(at: time, in: timeline, tracks: scope))
        case .loop:
            guard let loop = timeline.loop else { return }
            selectKeys(KeySelection.keys(in: loop, tracks: scope ?? Set(timeline.tracks.map(\.id)), timeline: timeline))
        case .invert: selectKeys(KeySelection.inverted(selectedKeys, in: timeline, tracks: scope))
        case .none: selectedKeys = []
        }
    }

    /// Replaces a whole track (the graph editor's edits), one undo step.
    func replaceTrack(_ track: Track, label: String) {
        perform(.batch(label, [.setTracks([TrackEdit(track)])]))
    }

    /// The first key of the selection's first curve (position, rotation, scale or a number), where the graph opens.
    var firstGraphKey: KeyRef? {
        let ids = Set(selection)
        guard let track = timeline.tracks.first(where: { ids.contains($0.target) && $0.keyframes.first.flatMap { GraphCurves.components($0.value) } != nil }),
              let first = track.keyframes.first else { return nil }
        return KeyRef(track: track.id, time: first.time)
    }

    func setEasing(_ easing: Easing) {
        perform(KeyOperations().setEasing(easing, for: Array(selectedKeys), in: timeline))
    }

    func copyKeys() {
        keyClipboard = KeyOperations().copy(Array(selectedKeys), in: timeline)
        app.show("Copied \(selectedKeys.count) key\(selectedKeys.count == 1 ? "" : "s")")
    }

    func pasteKeys() {
        guard let clipboard = keyClipboard else { return }
        var keys = KeyOperations()
        let onto = selection.count == 1 && clipboard.entries.count == 1 ? selection.first : nil
        perform(keys.paste(clipboard, at: time, onto: onto, in: timeline))
    }

    var hasKeyClipboard: Bool { keyClipboard != nil }

    func mirrorKeys() {
        perform(KeyOperations().mirror(Array(selectedKeys), in: timeline))
    }

    func reverseKeys() {
        perform(KeyOperations().reverse(Array(selectedKeys), in: timeline))
    }

    func retimeKeys(_ factor: Double) {
        guard perform(KeyOperations().retime(Array(selectedKeys), factor: factor, in: timeline)) else { return }
        let pivot = selectedKeys.map(\.time).min() ?? 0
        selectedKeys = Set(selectedKeys.map { KeyRef(track: $0.track, time: pivot + ($0.time - pivot) * factor) })
    }

    /// Compose: slides whole animations in time.
    func shiftAnimation(of objects: Set<ObjectID>, by delta: Double) {
        perform(KeyOperations().shift(objects, by: timeline.snapped(delta), in: timeline))
    }

    func clearAnimation() {
        let ids = Set(selection.flatMap { baseScene.subtree(of: $0) })
        var cleaned = TimelineTools.removingReferences(to: ids, from: timeline)
        cleaned.cuts = timeline.cuts
        guard cleaned != timeline else { return }
        perform(.batch("Clear animation", [.setTimeline(cleaned)]))
    }

    var selectionHasAnimation: Bool {
        !timeline.animatedObjects.isDisjoint(with: Set(selection))
    }
}
