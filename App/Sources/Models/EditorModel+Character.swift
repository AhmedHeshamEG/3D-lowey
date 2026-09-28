import Foundation
import LoweyCore
import LoweyRender
import QuartzCore
import SwiftUI

/// Hesham's own character: the builder, clips on built characters, lip sync, face performance.
extension EditorModel {
    // MARK: Builder

    /// A built character (a puppet on the Humanoid standard) in the selection, or the character a selected part belongs to.
    var selectedPuppet: ObjectID? {
        guard let id = selection.first else { return nil }
        let chain = [id] + baseScene.ancestors(of: id)
        return chain.first { baseScene.objects[$0]?[.rigStandard] != nil && baseScene.objects[$0]?.kind == .group }
    }

    func recipe(of character: ObjectID) -> CharacterRecipe? {
        guard let json = baseScene.objects[character]?[.characterRecipe]?.stringValue else { return nil }
        return try? LoweyJSON.decode(CharacterRecipe.self, from: Data(json.utf8))
    }

    /// Adds a new character where you're looking.
    func buildCharacter(_ recipe: CharacterRecipe) {
        var ids = IDFactory.random
        var fragment = CharacterBuilder.build(recipe, ids: &ids)
        guard let rootIndex = fragment.objects.firstIndex(where: { $0.id == fragment.roots.first }) else { return }
        fragment.objects[rootIndex].name = ObjectFactory.uniqueName(recipe.name, in: scene)
        fragment.objects[rootIndex].transform.position = dropPoint()
        let root = fragment.objects[rootIndex].id
        if perform(.insert(fragment, parent: nil, index: nil)) {
            select(root)
            app.show("\(recipe.name) is ready — try Animate → Play a clip, Lip sync, or Face")
        }
    }

    /// A blob character (the house style: cartoon face with springs).
    func isBlob(_ id: ObjectID) -> Bool {
        baseScene.objects[id]?[.rigStandard]?.stringValue == "blob"
    }

    /// Keys a whole expression at the playhead (Character Animator's triggers). The rig overshoots into it and settles.
    func keyExpression(_ expression: FaceExpression, on character: ObjectID) {
        var ids = IDFactory.random
        let keyed = expression.keyed(on: character, at: time, in: timeline, ids: &ids)
        perform(.batch("\(expression.title) face", [.setTimeline(keyed)]))
        Haptics.tap()
    }

    /// How rubbery a blob's in-betweens are (0 = straight, 1 = Looney Tunes).
    func setCartoon(_ value: Double, on character: ObjectID) {
        perform(.setProperties([PropertyChange(object: character, key: .cartoon, value: .float(value))]), coalesceKey: "cartoon-\(character.raw)")
    }

    /// Adds a blob character (the house style) where you're looking, floating.
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
            app.show("\(recipe.name) is here. Try Animate → Lip sync, or Perform the hands")
        }
    }

    /// Rebuilds a character from an edited recipe. The root keeps its id, place and animation (clips, lip sync, face).
    func rebuildCharacter(_ root: ObjectID, with recipe: CharacterRecipe) {
        guard let old = baseScene.objects[root] else { return }
        var ids = IDFactory.random
        var fragment = CharacterBuilder.build(recipe, ids: &ids)
        guard let newRoot = fragment.roots.first, let rootIndex = fragment.objects.firstIndex(where: { $0.id == newRoot }) else { return }
        // Re-home the new parts under the old root id.
        for index in fragment.objects.indices {
            if fragment.objects[index].parent == newRoot { fragment.objects[index].parent = root }
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
        let parent = old.parent
        let siblings = baseScene.childIDs(of: parent)
        let index = siblings.firstIndex(of: root)
        // Tracks on the old parts are removed with them; the root's own animation stays.
        let partIDs = Set(baseScene.subtree(of: root)).subtracting([root])
        var cleaned = TimelineTools.removingReferences(to: partIDs, from: timeline)
        cleaned.cuts = timeline.cuts
        perform(.batch("Edit character", [.setTimeline(cleaned), .delete([root]), .insert(fragment, parent: parent, index: index)]))
        select(root)
    }

    // MARK: Clips on built characters

    /// Clips a built character can play: the built-in set, then every humanoid clip in the library.
    func puppetClips() -> [ClipRef] {
        var result = BuiltinClips.names.map { ClipRef(asset: BuiltinClips.assetID, name: $0) }
        for asset in library.manifest.assets where asset.rig == .humanoid {
            result += asset.clips.map { ClipRef(asset: asset.id, name: $0) }
        }
        return result
    }

    // MARK: Lip sync

    /// Mouth shapes from the voiceover's words (the selected words in the transcript, else all of them).
    func lipSync(_ character: ObjectID) {
        let all = words
        guard !all.isEmpty else {
            app.show("Transcribe the voiceover first — lip sync reads its words")
            return
        }
        let chosen = wordSelection.map { range in Array(all[range.clamped(to: 0 ... all.count - 1)]) } ?? all
        guard let first = chosen.first, let last = chosen.last else { return }
        // Loudness of the voice for words the dictionary doesn't know.
        var loudness: [Double] = []
        let clipID = first.clip
        if let clip = audioClip(clipID), let pcm = decoded(clip.file) {
            let perFileFrame = AudioAnalysis.loudness(pcm, fps: timeline.fps)
            // Re-index from file time to timeline time.
            let frames = Int((timeline.duration * Double(timeline.fps)).rounded()) + 1
            loudness = (0 ..< frames).map { frame in
                let time = Double(frame) / Double(timeline.fps)
                guard let fileTime = clip.fileTime(at: time) else { return 0 }
                let index = Int(fileTime * Double(timeline.fps))
                return perFileFrame.indices.contains(index) ? perFileFrame[index] : 0
            }
        }
        let language = timeline.transcript(for: clipID)?.language ?? transcriptLanguage
        let shapes = LipSync.shapes(for: chosen, language: language, loudness: loudness, fps: timeline.fps)
        var ids = IDFactory.random
        if perform(LipSync.keys(shapes, character: character, range: TimeRange(start: first.start, end: last.end + 0.2), timeline: timeline, ids: &ids)) {
            Haptics.success()
            app.show("Lip sync: \(shapes.count) mouth shapes for \(chosen.count) words")
        }
    }

    // MARK: Face performance

    /// The character whose face is performed (the selected character).
    var faceTarget: ObjectID? { selectedPuppet ?? selectedCharacter?.object.id }

    /// Live face (front camera or iPhone) → the character's face channels. While recording a Perform take, they
    /// are captured like any performed value (one undo step, replaces the performed range).
    func performFace(_ values: [PropertyKey: Double], detected: Bool) {
        guard let target = faceTarget else { return }
        for (key, value) in values {
            propertyOverride[target, default: [:]][key] = .float(value)
        }
        if performPhase == .recording, detected {
            for key in values.keys {
                let channel = PerformChannel(object: target, property: key)
                if takes[channel] == nil || !performTouching { takes[channel, default: PerformTake(object: target, property: key)].begin() }
                performChannels.insert(channel)
            }
        }
        performTouching = detected
        if !isPlaying { refreshDisplay() }
    }

    func startFaceCapture(useIPhone: Bool) {
        guard faceTarget != nil else {
            app.show("Select your character first")
            return
        }
        stopFaceCapture()
        if useIPhone {
            let receiver = FaceLinkReceiver()
            receiver.onStatus = { [weak self] message in self?.faceStatus = message }
            receiver.onChannels = { [weak self] channels in
                guard let self else { return }
                var values = channels
                if facePerformer.mirror {
                    let left = values[.blinkLeft]
                    values[.blinkLeft] = values[.blinkRight]
                    values[.blinkRight] = left
                    values[.headYaw] = values[.headYaw].map { -$0 }
                    values[.headRoll] = values[.headRoll].map { -$0 }
                    values[.lookX] = values[.lookX].map { -$0 }
                }
                performFace(values, detected: true)
            }
            receiver.start()
            faceLink = receiver
            faceStatus = "Open 3D-lowey on your iPhone"
        } else {
            Task {
                guard await FaceCapture.requestAccess() else {
                    app.show("Allow the camera in Settings to perform with your face")
                    return
                }
                let capture = FaceCapture { [weak self] face in
                    guard let self else { return }
                    guard let face else {
                        performFace([:], detected: false)
                        faceStatus = "Look at the iPad"
                        return
                    }
                    faceStatus = "Reading your face"
                    performFace(facePerformer.channels(for: face, at: CACurrentMediaTime()), detected: true)
                }
                do {
                    try capture.start()
                    faceCapture = capture
                    faceStatus = "Relax and look at the iPad…"
                } catch {
                    app.show("Face capture failed: \(error)")
                }
            }
        }
        faceActive = true
    }

    func stopFaceCapture() {
        faceCapture?.stop()
        faceCapture = nil
        faceLink?.stop()
        faceLink = nil
        faceActive = false
        faceStatus = nil
        if let target = faceTarget {
            for key in PropertyKey.faceChannels {
                propertyOverride[target]?[key] = nil
            }
        }
        refreshDisplay()
    }
}
