import Foundation
import LoweyCore

/// The inspector's Motion row (CONTEXT §4.1): tap a thing, tap a motion, it moves. Six looping motions (Core's
/// `LoopMotion`), one speed for all of them, and Make keyframes when they should become keys. No timeline needed.
extension EditorModel {
    /// What a motion is put on: the selection's top-level objects.
    private var motionTargets: [ObjectID] { operations.topLevel(selection, in: baseScene) }

    /// The looping motions running on the selection.
    var loopMotions: [(behavior: Behavior, motion: LoopMotion, speed: Double)] {
        let targets = Set(motionTargets)
        return timeline.behaviors.compactMap { behavior in
            guard targets.contains(behavior.target), behavior.enabled, let reading = LoopMotion.reading(behavior.kind) else { return nil }
            return (behavior, reading.motion, reading.speed)
        }
    }

    func hasLoopMotion(_ motion: LoopMotion) -> Bool {
        loopMotions.contains { $0.motion == motion }
    }

    /// The row's one speed: the running motions' (the first one's, if they differ), else what the next one gets.
    var loopMotionSpeed: Double { loopMotions.first?.speed ?? motionSpeed }

    /// Drawn lines a thing can follow (never the selection itself).
    var followablePaths: [ObjectID] {
        baseScene.orderedIDs().filter { id in
            guard !selection.contains(id), case .drawing = baseScene.objects[id]?.kind else { return false }
            return true
        }
    }

    /// One tap: the motion starts on everything selected and the stage plays; a second tap stops it.
    func toggleLoopMotion(_ motion: LoopMotion, path: ObjectID? = nil) {
        let targets = motionTargets
        guard !targets.isEmpty else { return }
        let running = loopMotions.filter { $0.motion == motion }.map(\.behavior.id)
        if !running.isEmpty {
            updateTimeline("Stop \(motion.title)") { $0.behaviors.removeAll { running.contains($0.id) } }
            return
        }
        guard let kind = motion.behavior(speed: loopMotionSpeed, path: path ?? followablePaths.first) else {
            app.show("Draw a line with Draw first: that's the path to follow")
            return
        }
        updateTimeline(motion.title) { timeline in
            for target in targets {
                timeline.behaviors.append(Behavior(id: UUID().uuidString.lowercased(), target: target, kind: kind, start: 0))
            }
        }
        if !isPlaying { play() }
    }

    /// The speed slider: every motion running on the selection goes at this pace (one undo step per drag).
    func setLoopMotionSpeed(_ speed: Double) {
        motionSpeed = speed
        let running = Set(loopMotions.map(\.behavior.id))
        guard !running.isEmpty else { return }
        updateTimeline("Motion speed", coalesce: "loop-motion-speed") { timeline in
            for index in timeline.behaviors.indices where running.contains(timeline.behaviors[index].id) {
                timeline.behaviors[index].kind = LoopMotion.retimed(timeline.behaviors[index].kind, speed: speed)
            }
        }
    }

    /// Make keyframes: the running motions become keys over the whole timeline, in one undo step.
    func makeLoopMotionKeyframes() {
        let running = loopMotions.map(\.behavior.id)
        guard !running.isEmpty else { return }
        var ids = IDFactory.random
        perform(Simulation.bake(running, label: "Make keyframes", in: session.document, rigs: rigs(), ids: &ids))
    }
}
