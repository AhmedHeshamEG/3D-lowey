import Foundation

/// Phase 3's proof: the Enigma opening, narrated. A voiceover with word timings, a narrator (the character builder's
/// "Me") who lip-syncs the last line, captions, overlays, particles, screen effects, a transition and post — all added
/// by ONE Scene Script of friendly actions (the same language Claude uses through lowey-mcp), synced to spoken words.
public extension EnigmaSample {
    static let storyName = "5 · The story (narrated)"
    static let voiceoverFile = "enigma-voiceover.m4a"

    /// The narration, sentence by sentence, with where each word is spoken (seconds).
    static let narration: [(sentence: String, start: Double, end: Double)] = [
        ("This is a German army message from 1941,", 0.2, 2.1),
        ("encrypted with Enigma.", 2.2, 3.0),
        ("People have been trying to read it since 2005.", 3.3, 6.4),
        ("Nobody could.", 6.9, 7.7),
        ("Last week, an AI did it.", 8.1, 9.5),
        ("What's the big secret hidden for 85 years?", 10.0, 12.0)
    ]

    /// Words spread over their sentence's time by length (the app's placeholder voice speaks each sentence there).
    static func narrationTranscript() -> Transcript {
        var words: [TranscriptWord] = []
        for line in narration {
            words += TranscriptEditing.words(from: line.sentence, start: line.start, end: line.end, confidence: 1)
        }
        return Transcript(clip: "voiceover", language: "en-US", words: words)
    }

    /// Sets + the animated opening + the narrated story.
    static func buildFull(ids: IDFactory = .sequential("enigma")) throws -> (ProjectInfo, [Scene]) {
        let (info, scenes) = try buildWithOpening(ids: ids)
        guard let opening = scenes.last else { return (info, scenes) }
        let deterministic = ids.isSequential
        let story = try storyScene(from: opening, info: info, ids: deterministic ? .sequential("story") : .random)
        return (info, scenes + [story])
    }

    static func storyScene(from opening: Scene, info: ProjectInfo, ids: IDFactory) throws -> Scene {
        var scene = opening
        scene.id = SceneID(raw: ids.isSequential ? "story-scene" : UUID().uuidString.lowercased())
        scene.name = storyName
        scene.timeline.duration = 12.8
        scene.timeline.audio = [AudioClip(id: "voiceover", role: .voiceover, name: "Voiceover", file: voiceoverFile, duration: 12.6)]
        scene.timeline.transcripts = [narrationTranscript()]
        // Word-synced markers replace the opening's hand-placed ones.
        scene.timeline.markers = []
        let document = Document(project: info, scene: scene)
        let script = try LoweyJSON.decode(SceneScript.self, from: Data(storyScript.utf8))
        let result = try ScriptCompiler.compile(script, document: document, context: ScriptContext(ids: ids))
        return result.document.scene
    }

    /// What an AI (or Hesham) would send: word-synced polish over the opening.
    static let storyScript = """
    {"version": 2, "title": "Narrate the Enigma opening", "actions": [
      {"do": "look", "post": "cinematic", "sceneOnly": true},
      {"do": "marker", "name": "message", "at": {"word": "message"}},
      {"do": "marker", "name": "Nobody", "at": {"word": "Nobody"}},
      {"do": "marker", "name": "AI", "at": {"word": "AI"}},
      {"do": "marker", "name": "secret", "at": {"word": "secret"}},

      {"do": "overlay", "shape": "label", "name": "1941 label", "text": "BERLIN · 1941", "follow": "Army message", "at": [0, 0.18], "size": 0.9},
      {"do": "preset", "target": "1941 label", "preset": "typewriter", "at": {"word": "1941,", "offset": -0.3}, "duration": 0.8},
      {"do": "preset", "target": "1941 label", "preset": "fadeOut", "at": {"word": "encrypted", "edge": "end"}, "duration": 0.3},
      {"do": "text", "name": "ENIGMA", "text": "ENIGMA", "at": [0.55, 0.78, -0.25], "size": 0.09, "color": "#FF3B3B"},
      {"do": "set", "target": "ENIGMA", "property": "emissiveIntensity", "value": 2},
      {"do": "preset", "target": "ENIGMA", "preset": "popIn", "at": {"word": "Enigma."}, "duration": 0.35},
      {"do": "effect", "kind": "glitch", "at": {"word": "Enigma."}, "duration": 0.5, "strength": 0.8},

      {"do": "overlay", "shape": "title", "name": "2005", "text": "2005 → today", "at": [0, 0.7], "size": 0.8},
      {"do": "preset", "target": "2005", "preset": "typewriter", "at": {"word": "2005."}, "duration": 0.5},
      {"do": "preset", "target": "2005", "preset": "fadeOut", "at": {"word": "Nobody", "offset": -0.3}, "duration": 0.25},
      {"do": "effect", "kind": "flash", "at": {"word": "Nobody"}, "strength": 0.7, "color": "#FFFFFF"},
      {"do": "effect", "kind": "shake", "at": {"word": "Nobody"}, "duration": 0.45},

      {"do": "cut", "camera": "Cave camera", "at": 8, "transition": "dipToBlack", "duration": 0.5},
      {"do": "particles", "name": "Cave embers", "preset": "embers", "at": [60, 0.2, -1.2], "amount": 2},
      {"do": "particles", "name": "Rise sparks", "preset": "sparks", "at": [60, 0.1, -0.6], "amount": 1.5},
      {"do": "set", "target": "Rise sparks", "property": "emission", "value": 0},
      {"do": "keys", "target": "Rise sparks", "property": "emission", "keys": [
        {"t": {"word": "AI"}, "value": 1, "easing": "step"}, {"t": {"word": "did it", "edge": "end"}, "value": 0, "easing": "step"}]},
      {"do": "effect", "kind": "speedLines", "at": {"word": "AI"}, "duration": 1.2, "strength": 0.6},

      {"do": "light", "type": "point", "name": "Narrator light", "at": [61.9, 2.3, 1.6], "color": "#FFC58A", "intensity": 1.8, "range": 5},
      {"do": "character", "name": "Me", "at": [61.45, 0, -0.2], "facing": -12,
       "recipe": {"name": "Me", "hair": "short", "top": "hoodie", "extras": ["beard"], "eyes": "round"}},
      {"do": "clip", "character": "Me", "clip": "Idle", "at": 0},
      {"do": "clip", "character": "Me", "clip": "Talk", "at": {"word": "What's", "offset": -0.2}},
      {"do": "lipSync", "character": "Me", "words": "What's the big secret hidden for 85 years?"},
      {"do": "keys", "target": "Me", "property": "brows", "keys": [
        {"t": {"word": "big"}, "value": 0}, {"t": {"word": "secret"}, "value": 0.9, "easing": "backOut"},
        {"t": {"word": "years?", "edge": "end"}, "value": 0}]},
      {"do": "keys", "target": "Me", "property": "headYaw", "keys": [{"t": {"word": "What's"}, "value": 0}, {"t": {"word": "hidden"}, "value": -18}]},
      {"do": "keys", "target": "Me", "property": "blinkLeft", "keys": [
        {"t": 10.6, "value": 0}, {"t": 10.68, "value": 1}, {"t": 10.76, "value": 0}]},
      {"do": "keys", "target": "Me", "property": "blinkRight", "keys": [
        {"t": 10.6, "value": 0}, {"t": 10.68, "value": 1}, {"t": 10.76, "value": 0}]},

      {"do": "overlay", "shape": "question", "name": "Big question", "at": [0.62, 0.35], "size": 1.4},
      {"do": "set", "target": "Big question", "property": "opacity", "value": 0},
      {"do": "keys", "target": "Big question", "property": "opacity", "keys": [{"t": {"word": "secret"}, "value": 0, "easing": "step"},
        {"t": {"word": "secret", "offset": 0.01}, "value": 1}]},
      {"do": "preset", "target": "Big question", "preset": "popIn", "at": {"word": "secret"}, "duration": 0.4},
      {"do": "captions", "style": "punchy", "position": "bottom"}
    ]}
    """
}
