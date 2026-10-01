import Foundation
import HmmDesign
import LoweyCore

/// One-tap motion: presets (with stagger for many objects), behaviours, simulations, puppet joints.
extension EditorModel {
    func presetOptions(_ preset: AnimationPreset) -> PresetOptions {
        var options = PresetOptions(preset)
        if let presetDuration { options.duration = presetDuration }
        options.amplitude = PresetBuilder.scaledAmplitude(preset, options.amplitude, by: presetStrength)
        if preset == .slideIn, let stage {
            // From the left of the screen.
            let right = stage.viewpoint.rotation.act(.unitX)
            options.direction = -Vec3(right.x, 0, right.z).normalized
        }
        return options
    }

    func applyPreset(_ preset: AnimationPreset) {
        let targets = operations.topLevel(selection, in: baseScene)
        guard !targets.isEmpty else {
            app.show("Select what to animate first")
            return
        }
        let current = Animator.keyedScene(session.document, at: time)
        var builder = PresetBuilder()
        guard perform(builder.apply(preset, to: targets, at: time, options: presetOptions(preset), stagger: staggerSettings(),
                                    current: current, timeline: timeline)) else { return }
        HmmHaptics.play(.commit)
    }

    private func staggerSettings() -> StaggerSettings {
        var settings = StaggerSettings(delay: stagger.delay, randomTiming: stagger.randomTiming, randomAmplitude: stagger.randomStrength,
                                       seed: UInt64.random(in: 1 ... 1_000_000))
        switch stagger.order {
        case .selection: settings.order = .selection
        case .leftToRight: settings.order = .axis(.x, reversed: false)
        case .rightToLeft: settings.order = .axis(.x, reversed: true)
        case .frontToBack: settings.order = .axis(.z, reversed: true)
        case .wave: settings.order = .distance(from: selectionBounds?.center ?? .zero)
        }
        return settings
    }

    /// Arrays and scatters grow in one by one.
    func growGenerator() {
        guard let group = singleSelection, group.kind == .group else { return }
        var builder = PresetBuilder()
        let current = Animator.keyedScene(session.document, at: time)
        perform(builder.animateGenerator(group.id, at: time, current: current, timeline: timeline))
    }

    var selectionIsGenerator: Bool {
        guard let object = singleSelection, object.kind == .group else { return false }
        return object.name.contains("array") || object.name.contains("scatter")
    }

    // MARK: Behaviours

    func behaviors(of id: ObjectID) -> [Behavior] {
        timeline.behaviors.filter { $0.target == id }
    }

    func addBehavior(_ kind: BehaviorKind) {
        let targets = operations.topLevel(selection, in: baseScene)
        guard !targets.isEmpty else { return }
        updateTimeline("Add \(kind.title)") { timeline in
            for target in targets {
                timeline.behaviors.append(Behavior(id: UUID().uuidString.lowercased(), target: target, kind: kind, start: 0))
            }
        }
    }

    func removeBehavior(_ id: String) {
        updateTimeline("Remove behaviour") { $0.behaviors.removeAll { $0.id == id } }
    }

    func toggleBehavior(_ id: String) {
        updateTimeline("Toggle behaviour") { timeline in
            if let index = timeline.behaviors.firstIndex(where: { $0.id == id }) { timeline.behaviors[index].enabled.toggle() }
        }
    }

    func setBehaviorTiming(_ id: String, startAtPlayhead: Bool) {
        updateTimeline("Behaviour timing") { timeline in
            guard let index = timeline.behaviors.firstIndex(where: { $0.id == id }) else { return }
            if startAtPlayhead { timeline.behaviors[index].start = time } else { timeline.behaviors[index].end = time }
        }
    }

    func bakeBehavior(_ id: String) {
        var ids = IDFactory.random
        perform(Simulation.bake(id, in: session.document, rigs: rigs(), ids: &ids))
    }

    // MARK: Simulations

    func simulatePhysics(_ kind: PhysicsKind) {
        let targets = operations.topLevel(selection, in: baseScene)
        guard !targets.isEmpty else { return }
        var ids = IDFactory.random
        let settings = PhysicsSettings(kind: kind, duration: min(4, max(timeline.duration - time, 1)), center: selectionBounds?.center)
        perform(Simulation.physics(targets, settings: settings, at: time, fps: timeline.fps, bounds: operations.bounds,
                                   current: Animator.keyedScene(session.document, at: time), timeline: timeline, ids: &ids))
    }

    func simulateFlock() {
        let targets = operations.topLevel(selection, in: baseScene)
        guard targets.count > 1 else {
            app.show("Select several birds (or anything) to flock")
            return
        }
        var ids = IDFactory.random
        let center = selectionBounds?.center ?? Vec3(0, 6, 0)
        let settings = Simulation.FlockSettings(duration: max(timeline.duration - time, 2), center: center, extent: Vec3(10, 2.5, 10))
        perform(Simulation.flock(targets, settings: settings, at: time, fps: timeline.fps,
                                 current: Animator.keyedScene(session.document, at: time), timeline: timeline, ids: &ids))
    }

    // MARK: Puppets

    /// Wraps the selection in a joint that turns around a pivot (shoulder, hip, hinge).
    func makeJoint(_ place: PivotPlace) {
        guard let bounds = selectionBounds else { return }
        let pivot: Vec3 = switch place {
        case .top: Vec3(bounds.center.x, bounds.max.y, bounds.center.z)
        case .center: bounds.center
        case .bottom: Vec3(bounds.center.x, bounds.min.y, bounds.center.z)
        }
        let name = (singleSelection?.name).map { "\($0) joint" } ?? "Joint"
        guard let (command, group) = operations.group(selection, in: scene, name: name, pivot: pivot) else { return }
        if perform(command) {
            setSelection([group])
            app.show("Rotate “\(name)” to bend around its joint")
        }
    }
}
