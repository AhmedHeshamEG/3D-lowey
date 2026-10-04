import Foundation

/// How often each object's animation is sampled (on ones … fours), resolved per frame:
///
/// 1. the object's own frame rate (the `stepping` property, which can be keyed: a character can drop to twos for a
///    punch and come back to ones);
/// 2. the nearest ancestor's (a stepped character group steps its parts);
/// 3. characters (blobs, built and imported characters) follow their Look's frame rate: the Comic Look puts them on
///    twos while the camera stays on ones, as in Spider-Verse;
/// 4. cameras stay on ones;
/// 5. everything else follows the project's stepping.
public struct FrameRates: Sendable {
    let timeline: Timeline
    let lookStepping: Stepping
    let customLooks: [LookPreset]
    let characters: Set<ObjectID>

    public init(_ document: Document) {
        timeline = document.scene.timeline
        lookStepping = document.lookPreset.stepping
        customLooks = document.project.customLooks
        var characters = Set(document.scene.timeline.clipTracks.map(\.target))
        for (id, object) in document.scene.objects where object[.rigStandard] != nil {
            characters.insert(id)
        }
        self.characters = characters
    }

    /// The stepping in effect for `id` at `time`.
    public func stepping(for id: ObjectID, in scene: Scene, at time: Double) -> Stepping {
        guard let object = scene.objects[id] else { return timeline.stepping }
        if let own = ownStepping(id, object: object, at: time) { return own }
        if object.kind == .camera { return .onOnes }
        let ancestors = scene.ancestors(of: id)
        for ancestor in ancestors {
            if let node = scene.objects[ancestor], let inherited = ownStepping(ancestor, object: node, at: time) { return inherited }
        }
        if characters.contains(id) || ancestors.contains(where: characters.contains) {
            return lookStepping(for: [id] + ancestors, in: scene)
        }
        return timeline.stepping
    }

    /// `time` quantised to the object's stepping.
    public func sampleTime(_ time: Double, for id: ObjectID, in scene: Scene) -> Double {
        stepping(for: id, in: scene, at: time).quantize(time, fps: timeline.fps)
    }

    private func ownStepping(_ id: ObjectID, object: SceneObject, at time: Double) -> Stepping? {
        if let track = timeline.track(for: id, .stepping), let name = track.value(at: time)?.stringValue {
            return Stepping(name: name)
        }
        return object.properties[.stepping]?.stringValue.flatMap(Stepping.init(name:))
    }

    /// The frame rate of the Look an object is drawn in (its own override or an ancestor's, else the scene's).
    private func lookStepping(for chain: [ObjectID], in scene: Scene) -> Stepping {
        for id in chain {
            if let override = scene.objects[id]?.lookOverride {
                return LookLibrary.resolve(override, custom: customLooks).stepping
            }
        }
        return lookStepping
    }
}
