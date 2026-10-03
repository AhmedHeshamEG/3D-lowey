import Foundation

// MARK: - Animating things

extension ScriptState {
    mutating func set(_ action: JSONValue) throws {
        guard let keyName = string(action, "property") else { throw fail("set needs “property”") }
        let key = PropertyKey(keyName)
        let value = try propertyValue(key, action["value"])
        let ids = try targets(action["target"])
        if action["at"] != nil {
            let at = try time(action["at"])
            try addKeys(ids, key, [(at, value, easing(action["easing"]))])
        } else {
            try run(.setProperties(ids.map { PropertyChange(object: $0, key: key, value: value) }), label: "Set \(keyName) on \(ids.count) object(s)")
        }
    }

    mutating func transform(_ action: JSONValue) throws {
        let ids = try targets(action["target"])
        var changes: [(ObjectID, PropertyKey, PropertyValue)] = []
        let relative = bool(action, "relative") ?? false
        for id in ids {
            guard let object = scene.objects[id] else { continue }
            if let position = vec3(action["position"]) {
                changes.append((id, .position, .vec3(relative ? object.transform.position + position : position)))
            }
            if let rotation = rotation(action["rotation"]) {
                changes.append((id, .rotation, .quat(relative ? (object.transform.rotation * rotation).normalized : rotation)))
            }
            if let scale = vec3(action["scale"]) {
                let current = object.transform.scale
                changes.append((id, .scale, .vec3(relative ? Vec3(current.x * scale.x, current.y * scale.y, current.z * scale.z) : scale)))
            }
        }
        guard !changes.isEmpty else { throw fail("transform needs position, rotation or scale") }
        if action["at"] != nil {
            let at = try time(action["at"])
            var keys = KeyOperations(ids: context.ids)
            var working = timeline
            var edits: [TrackEdit] = []
            for (id, property, value) in changes {
                let edit = keys.setKey(
                    id,
                    property,
                    value: value,
                    at: at,
                    previous: scene.objects[id]?[property],
                    easing: easing(action["easing"]),
                    in: working
                )
                if let track = edit.track { working.tracks.removeAll { $0.id == track.id }; working.tracks.append(track) }
                edits.removeAll { $0.id == edit.id }
                edits.append(edit)
            }
            context.ids = keys.ids
            try run(.setTracks(edits), label: "Key transform at \(format(at))")
        } else {
            try run(.setProperties(changes.map { PropertyChange(object: $0.0, key: $0.1, value: $0.2) }), label: "Transform \(ids.count) object(s)")
        }
    }

    mutating func addKeys(_ ids: [ObjectID], _ property: PropertyKey, _ values: [(Double, PropertyValue, Easing)]) throws {
        var keys = KeyOperations(ids: context.ids)
        var edits: [TrackEdit] = []
        for id in ids {
            var track = timeline.track(for: id, property) ?? Track(id: keys.ids.next(), target: id, property: property)
            for (at, value, easing) in values {
                track.setKey(Keyframe(time: at, value: value, easing: easing))
            }
            edits.append(TrackEdit(track))
        }
        context.ids = keys.ids
        try run(.setTracks(edits), label: "\(values.count) key\(values.count == 1 ? "" : "s") on \(property) × \(ids.count)")
    }

    mutating func keys(_ action: JSONValue) throws {
        guard let keyName = string(action, "property") else { throw fail("keys need “property”") }
        let property = PropertyKey(keyName)
        guard let list = action["keys"]?.arrayValue, !list.isEmpty else { throw fail("keys need a “keys” list of {t, value}") }
        let values = try list.map { entry in try (time(entry["t"] ?? entry["at"]), propertyValue(property, entry["value"]), easing(entry["easing"])) }
        try addKeys(targets(action["target"]), property, values)
    }

    mutating func preset(_ action: JSONValue) throws {
        guard let preset = string(action, "preset").flatMap(AnimationPreset.init(rawValue:)) else {
            throw fail("unknown preset (\(AnimationPreset.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let ids = try targets(action["target"])
        let at = try time(action["at"])
        var options = PresetOptions(preset)
        if let duration = number(action, "duration") { options.duration = duration }
        if let strength = number(action, "strength") { options.amplitude = PresetBuilder.scaledAmplitude(preset, options.amplitude, by: strength) }
        var stagger = StaggerSettings(delay: number(action, "stagger") ?? 0.08)
        switch string(action, "order") {
        case "leftToRight": stagger.order = .axis(.x, reversed: false)
        case "rightToLeft": stagger.order = .axis(.x, reversed: true)
        case "wave": stagger.order = try .distance(from: point(action["from"]) ?? context.focus)
        default: break
        }
        stagger.randomTiming = number(action, "random") ?? 0
        var builder = PresetBuilder(ids: context.ids)
        let current = Animator.keyedScene(document, at: at)
        let command = builder.apply(preset, to: ids, at: at, options: options, stagger: stagger, current: current, timeline: timeline)
        context.ids = builder.ids
        try run(command, label: "\(preset.title) × \(ids.count) at \(format(at))")
    }

    func shotCamera(_ value: JSONValue?) throws -> ObjectID {
        if let value { return try target(value) }
        if let active = timeline.cutCamera(at: context.now) ?? scene.activeCamera { return active }
        if let first = scene.cameras.first { return first }
        throw fail("no camera yet — add one with {\"do\": \"camera\", …}")
    }

    mutating func cameraMove(_ action: JSONValue) throws {
        guard let move = string(action, "move").flatMap(CameraMove.init(rawValue:)) else {
            throw fail("unknown move (\(CameraMove.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let camera = try shotCamera(action["camera"])
        let at = try time(action["at"])
        let subject = try point(action["subject"]) ?? context.focus
        let options = CameraMoveOptions(duration: number(action, "duration") ?? move.defaultDuration, strength: number(action, "strength") ?? 1)
        let current = Animator.keyedScene(document, at: at)
        let command = CameraMoves.apply(move, camera: camera, subject: subject, at: at, options: options, current: current, timeline: timeline,
                                        ids: &context.ids)
        guard command != nil else { throw fail("that camera can't do \(move.title)") }
        try run(command, label: "\(move.title) at \(format(at))")
    }

    mutating func cut(_ action: JSONValue) throws {
        let camera = try target(action["camera"] ?? action["target"])
        guard scene.objects[camera]?.kind == .camera else { throw fail("cuts go to cameras") }
        let at = try time(action["at"])
        var copy = timeline
        copy.cuts.removeAll { abs($0.time - at) < 0.5 / Double(max(copy.fps, 1)) }
        let transition = string(action, "transition").flatMap(TransitionSpec.Kind.init(rawValue:)).flatMap { kind in
            kind == .cut ? nil : TransitionSpec(kind: kind, duration: number(action, "duration") ?? 0.6)
        }
        copy.cuts.append(CameraCut(time: at, camera: camera, transition: transition))
        copy.cuts.sort { $0.time < $1.time }
        try run(.setTimeline(copy), label: "Cut to \(scene.objects[camera]?.name ?? "camera") at \(format(at))")
    }

    mutating func look(_ action: JSONValue) throws {
        let sceneOnly = bool(action, "sceneOnly") ?? (scene.look != nil)
        var look = document.effectiveLook
        if let mood = string(action, "mood").flatMap(LightingPreset.init(rawValue:)) { look = look.applying(mood) }
        // v3: the Look itself ("ink", "comic", "sketch", "clay", "lowpoly").
        if let preset = string(action, "look") ?? string(action, "preset") {
            guard LookPreset.builtIns.contains(where: { $0.id == preset }) else {
                throw fail("unknown Look “\(preset)” (\(LookPreset.builtIns.map(\.id).joined(separator: ", ")))")
            }
            look.presetID = preset
        }
        if let post = string(action, "post").flatMap(PostSettings.Preset.init(rawValue:)) { look.post = post.settings }
        if let shading = string(action, "shading").flatMap(ShadingStyle.init(rawValue:)) { look.shading = shading }
        if let fog = action["fog"] {
            if case let .bool(on) = fog { look.fog.enabled = on }
            if let distance = fog.numberValue {
                look.fog.enabled = true
                look.fog.distance = distance
            }
        }
        if let colors = action["palette"]?.arrayValue?.compactMap(\.stringValue) {
            look.palette.swatches = colors.enumerated().compactMap { index, hex in
                RGBA(hex: hex).map { Palette.Swatch(name: "Colour \(index + 1)", color: $0) }
            }
        }
        if let bloom = number(action, "bloom") { look.post.bloom = bloom }
        if let grain = number(action, "grain") { look.post.grain = grain }
        try run(.setLook(look, scope: sceneOnly ? .scene : .project), label: "Look")
        try perObjectLooks(action)
    }

    /// Per object: {"perObject": {"Robot": "sketch"}} (a thing drawn in another Look).
    mutating func perObjectLooks(_ action: JSONValue) throws {
        if case let .object(perObject)? = action["perObject"] ?? action["per_object"] {
            for (name, value) in perObject.sorted(by: { $0.key < $1.key }) {
                guard let preset = value.stringValue else { continue }
                try run(.setProperties(targets(.string(name)).map { PropertyChange(object: $0, key: .lookPreset, value: .enumeration(preset)) }),
                        label: "“\(name)” in \(preset)")
            }
        }
    }

    mutating func effect(_ action: JSONValue) throws {
        guard let kind = string(action, "kind").flatMap(ScreenEffect.Kind.init(rawValue:)) else {
            throw fail("unknown effect (\(ScreenEffect.Kind.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        var copy = timeline
        var effect = try ScreenEffect(id: context.ids.next(ObjectID.self).raw, kind: kind, start: time(action["at"]), duration: number(action, "duration"),
                                      strength: number(action, "strength") ?? 1)
        if let color = try color(action["color"]) { effect.color = color.resolved(in: document.palette) }
        copy.effects.append(effect)
        try run(.setTimeline(copy), label: "\(kind.title) at \(format(effect.start))")
    }

    mutating func clip(_ action: JSONValue) throws {
        let character = try target(action["character"] ?? action["target"])
        guard let name = string(action, "clip") else { throw fail("clip needs “clip” (\(BuiltinClips.names.joined(separator: ", ")))") }
        let at = try time(action["at"])
        let asset = string(action, "from").map { AssetID(raw: $0) } ?? BuiltinClips.assetID
        var copy = timeline
        var track = copy.clipTracks.first { $0.target == character } ?? ClipTrack(id: context.ids.next(ObjectID.self).raw, target: character)
        track.segments = track.segments.filter { $0.start < at - 1e-6 }.map { segment in
            var trimmed = segment
            if trimmed.end > at { trimmed.duration = max(at - trimmed.start + 0.3, 0.1) }
            return trimmed
        }
        let duration = number(action, "duration") ?? max(copy.duration - at, 1)
        track.segments.append(ClipSegment(id: context.ids.next(ObjectID.self).raw, clip: ClipRef(asset: asset, name: name), start: at, duration: duration,
                                          loop: bool(action, "loop") ?? true, blend: track.segments.isEmpty ? 0 : 0.3))
        copy.clipTracks.removeAll { $0.target == character }
        copy.clipTracks.append(track)
        try run(.setTimeline(copy), label: "\(scene.objects[character]?.name ?? "Character") plays \(name) at \(format(at))")
    }

    /// `{"do": "transcript", "text": "Two plus two equals four.", "from": 0.2, "to": 3.6}` (or "words": [{"w","t","e"}]):
    /// the words of a voiceover whose timings are known (a script, a TTS on the laptop), so things can sync to them.
    mutating func transcript(_ action: JSONValue) throws {
        let clipID = string(action, "clip")
        guard let clip = timeline.audio.first(where: { clipID == nil ? $0.role == .voiceover : $0.id == clipID }) else {
            throw fail("transcript needs a voiceover clip on the timeline (add the audio first)")
        }
        // Timeline seconds → the audio file's own time.
        let fileTime = { (time: Double) in time - clip.start + clip.offset }
        let words: [TranscriptWord]
        if let list = action["words"]?.arrayValue {
            words = list.compactMap { entry in
                guard let text = entry["w"]?.stringValue, let start = entry["t"]?.numberValue else { return nil }
                return TranscriptWord(text: text, start: fileTime(start), end: fileTime(entry["e"]?.numberValue ?? start + 0.3))
            }
        } else if let text = string(action, "text") {
            let from = number(action, "from") ?? clip.start
            let to = number(action, "to") ?? clip.end
            guard to > from else { throw fail("transcript needs “to” after “from”") }
            words = TranscriptEditing.words(from: text, start: fileTime(from), end: fileTime(to))
        } else {
            throw fail("transcript needs “text” (spread over from…to) or “words” [{w, t, e}]")
        }
        var copy = timeline
        copy.transcripts.removeAll { $0.clip == clip.id }
        copy.transcripts.append(Transcript(clip: clip.id, language: string(action, "language") ?? "en-US", words: words))
        try run(.setTimeline(copy), label: "Transcript: \(words.count) words on “\(clip.name)”")
    }

    mutating func lipSync(_ action: JSONValue) throws {
        let character = try target(action["character"] ?? action["target"])
        var words = timeline.words
        guard !words.isEmpty else { throw fail("no transcript yet — transcribe the voiceover first") }
        if let phrase = string(action, "words"), let match = WordSnap.find(phrase, in: words).first { words = Array(words[match]) }
        let language = timeline.transcripts.first?.language ?? "en-US"
        let shapes = LipSync.shapes(for: words, language: language)
        guard let first = words.first, let last = words.last else { return }
        let command = LipSync.keys(shapes, character: character, range: TimeRange(start: first.start, end: last.end + 0.2), timeline: timeline,
                                   ids: &context.ids)
        try run(command, label: "Lip sync: \(shapes.count) mouth shapes")
    }
}
