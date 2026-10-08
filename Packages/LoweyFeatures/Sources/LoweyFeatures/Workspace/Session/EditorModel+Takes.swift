import Foundation
import HmmDesign
import LoweyCore

/// Takes (`TakeComp`): every recording is kept; the timeline plays the comp. Using a take over a stretch writes its
/// keys there, one undo step.
extension EditorModel {
    var recordedTakes: [Take] { timeline.takes }

    /// The stretch a take is used over when nobody dragged one: the loop region if there is one, else all of it.
    func useTake(_ id: String, over range: TimeRange? = nil) {
        var ids = IDFactory.random
        guard let command = TakeComp.using(id, over: range ?? timeline.loop, timeline: timeline, ids: &ids) else {
            app.show("That take wasn't performed there")
            return
        }
        perform(command)
        live.selectedTake = id
        HmmHaptics.play(.commit)
    }

    func deleteTake(_ id: String) {
        perform(TakeComp.removing(id, timeline: timeline))
        if live.selectedTake == id { live.selectedTake = nil }
    }

    func renameTake(_ id: String, to name: String) {
        perform(TakeComp.renaming(id, to: name.trimmingCharacters(in: .whitespaces), timeline: timeline))
    }

    /// How much of a take the comp plays (0…1).
    func share(of take: Take) -> Double {
        guard take.range.duration > 1e-6 else { return take.used.isEmpty ? 0 : 1 }
        return min(take.used.reduce(0) { $0 + $1.duration } / take.range.duration, 1)
    }
}
