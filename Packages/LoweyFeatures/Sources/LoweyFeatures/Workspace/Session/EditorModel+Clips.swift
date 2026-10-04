import Foundation
import HmmDesign
import LoweyCore

/// Several clips at once: pick clip segments (in the timeline or the Cast panel), then move, loop, speed up or remove
/// them together, one undo step each.
extension EditorModel {
    /// Picks a clip segment; `additive` adds it to (or takes it out of) the picked ones.
    func pickClip(_ id: String, additive: Bool) {
        if additive {
            selectedClips.formSymmetricDifference([id])
        } else {
            selectedClips = selectedClips == [id] ? [] : [id]
        }
        HmmHaptics.play(.selection)
    }

    /// The picked segments that still exist.
    var pickedSegments: [ClipSegment] {
        timeline.clipTracks.flatMap(\.segments).filter { selectedClips.contains($0.id) }
    }

    /// Moves the picked clips in time (none goes before 0).
    func shiftPickedClips(by delta: Double) {
        let earliest = pickedSegments.map(\.start).min() ?? 0
        let shift = max(delta, -earliest)
        guard abs(shift) > 1e-6 else { return }
        let fps = Double(timeline.fps)
        updatePickedClips("Move clips") { $0.start = (($0.start + shift) * fps).rounded() / fps }
    }

    func setPickedClips(loop: Bool) {
        updatePickedClips(loop ? "Loop clips" : "Don't loop clips") { $0.loop = loop }
    }

    func setPickedClips(speed: Double) {
        updatePickedClips("Clip speed", coalesce: "picked-speed") { $0.speed = speed }
    }

    func removePickedClips() {
        let picked = selectedClips
        guard !picked.isEmpty else { return }
        updateTimeline("Remove clips") { timeline in
            for index in timeline.clipTracks.indices {
                timeline.clipTracks[index].segments.removeAll { picked.contains($0.id) }
            }
            timeline.clipTracks.removeAll { $0.segments.isEmpty }
        }
        selectedClips = []
    }

    private func updatePickedClips(_ label: String, coalesce: String? = nil, _ change: @escaping (inout ClipSegment) -> Void) {
        let picked = selectedClips
        guard !picked.isEmpty else { return }
        updateTimeline(label, coalesce: coalesce) { timeline in
            for trackIndex in timeline.clipTracks.indices {
                for index in timeline.clipTracks[trackIndex].segments.indices where picked.contains(timeline.clipTracks[trackIndex].segments[index].id) {
                    change(&timeline.clipTracks[trackIndex].segments[index])
                }
            }
        }
    }
}
