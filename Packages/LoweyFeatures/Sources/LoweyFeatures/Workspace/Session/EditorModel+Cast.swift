import Foundation
import HmmDesign
import LoweyCore

/// The cast: Blob characters (the house character), built Puppets and Rigged imports, their clips, IK and crowds,
/// expressions and lip sync.
extension EditorModel {
    /// Every character in the scene, with its type.
    var cast: [(id: ObjectID, name: String, type: CastType)] {
        baseScene.orderedIDs().compactMap { id in
            guard let object = baseScene.objects[id], let type = castType(of: id, object: object) else { return nil }
            return (id, object.name, type)
        }
    }

    func castType(of id: ObjectID, object: SceneObject? = nil) -> CastType? {
        guard let object = object ?? baseScene.objects[id] else { return nil }
        if object[.rigStandard]?.stringValue == "blob" { return .blob }
        if object[.rigStandard] != nil, object.kind == .group { return .puppet }
        if let asset = object.kind.assetID, library.manifest.asset(asset)?.rig.isRigged == true { return .rigged }
        return nil
    }

    /// A built character in the selection (or the character a selected part belongs to).
    var selectedPuppet: ObjectID? {
        guard let id = selection.first else { return nil }
        let chain = [id] + baseScene.ancestors(of: id)
        return chain.first { baseScene.objects[$0]?[.rigStandard] != nil && baseScene.objects[$0]?.kind == .group }
    }

    var selectedCharacter: (object: SceneObject, asset: LibraryAsset)? {
        guard let object = singleSelection, let id = object.kind.assetID, let asset = library.manifest.asset(id), asset.rig.isRigged else { return nil }
        return (object, asset)
    }

    func isBlob(_ id: ObjectID) -> Bool { castType(of: id) == .blob }

    func recipe(of character: ObjectID) -> CharacterRecipe? {
        guard let json = baseScene.objects[character]?[.characterRecipe]?.stringValue else { return nil }
        return try? LoweyJSON.decode(CharacterRecipe.self, from: Data(json.utf8))
    }

    // MARK: Adding

    func buildCharacter(_ recipe: CharacterRecipe) {
        var ids = IDFactory.random
        var fragment = CharacterBuilder.build(recipe, ids: &ids)
        guard let rootIndex = fragment.objects.firstIndex(where: { $0.id == fragment.roots.first }) else { return }
        fragment.objects[rootIndex].name = ObjectFactory.uniqueName(recipe.name, in: scene)
        fragment.objects[rootIndex].transform.position = dropPoint()
        let root = fragment.objects[rootIndex].id
        if perform(.insert(fragment, parent: nil, index: nil)) {
            select(root)
            app.show("\(recipe.name) is ready. Try a clip, lip sync or your face")
        }
    }

    /// A Blob where you're looking, floating.
    func buildBlob(_ recipe: BlobRecipe) {
        var ids = IDFactory.random
        let build = BlobCharacter.build(recipe, ids: &ids)
        var fragment = build.fragment
        guard let rootIndex = fragment.objects.firstIndex(where: { $0.id == fragment.roots.first }) else { return }
        fragment.objects[rootIndex].name = ObjectFactory.uniqueName(recipe.name, in: scene)
        fragment.objects[rootIndex].transform.position = dropPoint()
        let root = fragment.objects[rootIndex].id
        var floating = timeline
        floating.behaviors += build.behaviors
        if perform(.batch("Add \(recipe.name)", [.insert(fragment, parent: nil, index: nil), .setTimeline(floating)])) {
            select(root)
            app.show("\(recipe.name) is here. Try an expression or lip sync")
        }
    }

    /// Rebuilds a puppet from an edited recipe; the root keeps its id, place and animation.
    func rebuildCharacter(_ root: ObjectID, with recipe: CharacterRecipe) {
        guard let old = baseScene.objects[root] else { return }
        var ids = IDFactory.random
        var fragment = CharacterBuilder.build(recipe, ids: &ids)
        guard let newRoot = fragment.roots.first, let rootIndex = fragment.objects.firstIndex(where: { $0.id == newRoot }) else { return }
        for index in fragment.objects.indices where fragment.objects[index].parent == newRoot {
            fragment.objects[index].parent = root
        }
        var rebuilt = fragment.objects[rootIndex]
        rebuilt.id = root
        rebuilt.name = old.name
        rebuilt.transform = old.transform
        rebuilt.parent = old.parent
        for key in PropertyKey.faceChannels + [.mouth] {
            if let value = old[key] { rebuilt[key] = value }
        }
        fragment.objects[rootIndex] = rebuilt
        fragment.roots = [root]
        let siblings = baseScene.childIDs(of: old.parent)
        let partIDs = Set(baseScene.subtree(of: root)).subtracting([root])
        var cleaned = TimelineTools.removingReferences(to: partIDs, from: timeline)
        cleaned.cuts = timeline.cuts
        perform(.batch("Edit character", [.setTimeline(cleaned), .delete([root]), .insert(fragment, parent: old.parent, index: siblings.firstIndex(of: root))]))
        select(root)
    }

    // MARK: Clips

    /// Clips a rigged model can play: its own, those of library models with the same kind of skeleton (retargeted),
    /// and the built-in set for humanoids.
    func availableClips(for asset: LibraryAsset) -> [ClipRef] {
        var clips = asset.clips.map { ClipRef(asset: asset.id, name: $0) }
        // The library's own models and the Kit's (its animation library is a humanoid clip source).
        for other in library.manifest.assets + library.manifest.kit where other.id != asset.id && other.rig == asset.rig {
            clips += other.clips.map { ClipRef(asset: other.id, name: $0) }
        }
        if asset.rig == .humanoid { clips += BuiltinClips.names.map { ClipRef(asset: BuiltinClips.assetID, name: $0) } }
        return clips
    }

    /// Clips a built puppet can play: the built-in set, then every humanoid clip in the library.
    func puppetClips() -> [ClipRef] {
        var result = BuiltinClips.names.map { ClipRef(asset: BuiltinClips.assetID, name: $0) }
        for asset in library.manifest.assets + library.manifest.kit where asset.rig == .humanoid {
            result += asset.clips.map { ClipRef(asset: asset.id, name: $0) }
        }
        return result
    }

    func clipTrack(for id: ObjectID) -> ClipTrack? {
        timeline.clipTracks.first { $0.target == id }
    }

    /// Plays a clip from the playhead to the end (looping); it crossfades from what played before.
    func addClip(_ clip: ClipRef) {
        guard let character = selectedCharacter?.object.id ?? selectedPuppet else { return }
        let duration = max(timeline.duration - time, 1)
        updateTimeline("Play \(clip.name)") { timeline in
            var track = timeline.clipTracks.first { $0.target == character } ?? ClipTrack(id: UUID().uuidString.lowercased(), target: character)
            // A new clip cuts the previous one short where it starts (plus the crossfade).
            track.segments = track.segments.map { segment in
                var trimmed = segment
                if segment.start < time, segment.end > time { trimmed.duration = max(time - segment.start + 0.3, 0.1) }
                return trimmed
            }.filter { $0.start < time + 1e-6 }
            track.segments.append(ClipSegment(id: UUID().uuidString.lowercased(), clip: clip, start: time, duration: duration,
                                              blend: track.segments.isEmpty ? 0 : 0.3))
            track.segments.sort { $0.start < $1.start }
            timeline.clipTracks.removeAll { $0.target == character }
            timeline.clipTracks.append(track)
        }
    }

    func updateSegment(_ id: String, coalesce: String? = nil, _ change: @escaping (inout ClipSegment) -> Void) {
        updateTimeline("Edit clip", coalesce: coalesce) { timeline in
            for trackIndex in timeline.clipTracks.indices {
                if let index = timeline.clipTracks[trackIndex].segments.firstIndex(where: { $0.id == id }) {
                    change(&timeline.clipTracks[trackIndex].segments[index])
                }
            }
        }
    }

    func removeSegment(_ id: String) {
        updateTimeline("Remove clip") { timeline in
            for index in timeline.clipTracks.indices {
                timeline.clipTracks[index].segments.removeAll { $0.id == id }
            }
            timeline.clipTracks.removeAll { $0.segments.isEmpty }
        }
    }

    func setIK(_ change: @escaping (inout IKSettings) -> Void) {
        guard let character = selectedCharacter?.object.id ?? selectedPuppet else { return }
        updateTimeline("Character IK") { timeline in
            if let index = timeline.clipTracks.firstIndex(where: { $0.target == character }) { change(&timeline.clipTracks[index].ik) }
        }
    }

    // MARK: Expressions & lip sync

    /// Keys a whole expression at the playhead; the rig overshoots into it and settles.
    func keyExpression(_ expression: FaceExpression, on character: ObjectID) {
        var ids = IDFactory.random
        let keyed = expression.keyed(on: character, at: time, in: timeline, ids: &ids)
        perform(.batch("\(expression.title) face", [.setTimeline(keyed)]))
        HmmHaptics.play(.selection)
    }

    /// How rubbery a Blob's in-betweens are (0 = straight, 1 = Looney Tunes).
    func setCartoon(_ value: Double, on character: ObjectID) {
        perform(.setProperties([PropertyChange(object: character, key: .cartoon, value: .float(value))]), coalesceKey: "cartoon-\(character.raw)")
    }

    /// Mouth shapes from the voiceover's words (the selected words, else all of them).
    func lipSync(_ character: ObjectID) {
        let all = words
        guard !all.isEmpty else {
            app.show("Transcribe the voiceover first: lip sync reads its words")
            return
        }
        let chosen = wordSelection.map { Array(all[$0.clamped(to: 0 ... all.count - 1)]) } ?? all
        guard let first = chosen.first, let last = chosen.last else { return }
        let language = timeline.transcript(for: first.clip)?.language ?? transcriptLanguage
        let shapes = LipSync.shapes(for: chosen, language: language, loudness: loudness(of: first.clip), fps: timeline.fps)
        var ids = IDFactory.random
        if perform(LipSync.keys(shapes, character: character, range: TimeRange(start: first.start, end: last.end + 0.2), timeline: timeline, ids: &ids)) {
            HmmHaptics.play(.commit)
            app.show("Lip sync: \(shapes.count) mouth shapes for \(chosen.count) words")
        }
    }

    /// The voice's loudness per timeline frame (for words the dictionary doesn't know).
    private func loudness(of clipID: String) -> [Double] {
        guard let clip = audioClip(clipID), let pcm = decoded(clip.file) else { return [] }
        let perFileFrame = AudioAnalysis.loudness(pcm, fps: timeline.fps)
        let frames = Int((timeline.duration * Double(timeline.fps)).rounded()) + 1
        return (0 ..< frames).map { frame in
            guard let fileTime = clip.fileTime(at: Double(frame) / Double(timeline.fps)) else { return 0 }
            let index = Int(fileTime * Double(timeline.fps))
            return perFileFrame.indices.contains(index) ? perFileFrame[index] : 0
        }
    }

    // MARK: Crowds & paths

    /// Walking along a path without sliding: the walk plays at the speed the path demands.
    func matchClipSpeedToPath() {
        guard let (object, _) = selectedCharacter, let track = clipTrack(for: object.id),
              let (source, duration) = followedPath(of: object.id) else {
            app.show("Give the character a Follow path behaviour first")
            return
        }
        let length = BehaviorEvaluator.path(source, in: displayed.scene).length
        guard duration > 0, length > 0 else { return }
        let speed = length / duration
        let scale = displayed.scene.worldTransform(of: object.id).scale.y
        var changed = 0
        updateTimeline("Match walk to path") { timeline in
            guard let index = timeline.clipTracks.firstIndex(where: { $0.id == track.id }) else { return }
            timeline.clipTracks[index].ik.inPlace = true
            for segmentIndex in timeline.clipTracks[index].segments.indices {
                let clip = timeline.clipTracks[index].segments[segmentIndex].clip
                guard let rig = clip.asset == BuiltinClips.assetID ? BuiltinClips.rig : library.models.rig(clip.asset),
                      let motion = rig.clips[clip.name], let stride = rig.strideSpeed(of: motion) else { continue }
                timeline.clipTracks[index].segments[segmentIndex].speed = min(max(speed / (stride * max(scale, 0.01)), 0.1), 5)
                changed += 1
            }
        }
        app.show(changed > 0 ? "The walk matches the path now: no sliding" : "Couldn't measure the clip's stride")
    }

    private func followedPath(of id: ObjectID) -> (PathSource, Double)? {
        for behavior in behaviors(of: id) {
            if case let .followPath(source, duration, _, _) = behavior.kind { return (source, duration) }
        }
        return nil
    }
}

/// The three kinds of character in the Cast panel.
enum CastType: String, CaseIterable, Sendable {
    case blob, puppet, rigged

    var title: String {
        switch self {
        case .blob: "Blob"
        case .puppet: "Puppet"
        case .rigged: "Rigged"
        }
    }

    var systemImage: String {
        switch self {
        case .blob: "face.smiling"
        case .puppet: "figure.stand"
        case .rigged: "figure.walk"
        }
    }
}
