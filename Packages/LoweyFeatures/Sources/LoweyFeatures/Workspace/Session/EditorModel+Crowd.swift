import Foundation
import LoweyCore

extension EditorModel {
    /// Copies of the selected character in a loose grid, each with its clips offset and slightly varied so they
    /// don't move in lock-step (one undo step).
    func makeCrowd(count: Int) {
        guard let (object, _) = selectedCharacter else { return }
        refreshOperationsLibrary()
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        let step = max(arrayStep, 0.6)
        guard let (arrayCommand, group) = operations.array(object.id, layout: .grid(columns: columns, rows: rows, spacingX: step, spacingZ: step),
                                                           in: scene) else { return }
        var working = session.document
        guard (try? arrayCommand.apply(to: &working)) != nil else { return }
        let members = (working.scene.objects[group]?.children ?? []).filter { $0 != object.id }
        var random = SeededRandom(seed: UInt64.random(in: 1 ... 1_000_000))
        let timeline = crowdTimeline(working.scene.timeline, source: object.id, members: members, random: &random)
        let changes = jitteredPlacement(members, in: working.scene, step: step, random: &random)
        // Placement, not animation: never keyed.
        let keying = autoKey
        autoKey = false
        defer { autoKey = keying }
        if perform(.batch("Crowd of \(members.count + 1)", [arrayCommand, .setProperties(changes), .setTimeline(timeline)])) {
            setSelection([group])
        }
    }

    private func crowdTimeline(_ timeline: Timeline, source: ObjectID, members: [ObjectID], random: inout SeededRandom) -> Timeline {
        guard let track = timeline.clipTracks.first(where: { $0.target == source }) else { return timeline }
        var result = timeline
        for member in members {
            var copy = track
            copy.id = UUID().uuidString.lowercased()
            copy.target = member
            copy.segments = track.segments.map { segment in
                var varied = segment
                varied.id = UUID().uuidString.lowercased()
                varied.offset += random.range(0, 1.5)
                varied.speed *= random.range(0.9, 1.1)
                return varied
            }
            result.clipTracks.append(copy)
        }
        return result
    }

    private func jitteredPlacement(_ members: [ObjectID], in scene: CoreScene, step: Double, random: inout SeededRandom) -> [PropertyChange] {
        var changes: [PropertyChange] = []
        for member in members {
            guard let transform = scene.objects[member]?.transform else { continue }
            let position = transform.position + Vec3(random.range(-0.2, 0.2), 0, random.range(-0.2, 0.2)) * step
            let rotation = (Quat(angle: random.range(-0.3, 0.3), axis: .unitY) * transform.rotation).normalized
            changes.append(PropertyChange(object: member, key: .position, value: .vec3(position)))
            changes.append(PropertyChange(object: member, key: .rotation, value: .quat(rotation)))
        }
        return changes
    }
}
