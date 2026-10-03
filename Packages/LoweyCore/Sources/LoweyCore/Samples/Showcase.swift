import Foundation

/// The samples that ship in the Theater, built from the Kit with Scene Script v3 (the same verbs and relations the
/// AI uses), each in the Look that suits it: the Welcome island in Ink at golden hour, and the Enigma story — a
/// desk at night in Ink, a room of computers in Comic on twos, a robot in a cave in Sketch with one accent — and the
/// narrated three-shot story cut on the voiceover's words.
public enum Showcase {
    public static let islandName = "Welcome island"
    public static let enigmaName = "Enigma — the story"
    public static let deskName = "1 · The message (Ink)"
    public static let roomName = "2 · Nobody could (Comic)"
    public static let caveName = "3 · The secret (Sketch)"
    public static let storyName = "4 · The story (narrated)"
    /// Where each set stands in the story scene (metres along x).
    static let roomOffset = 40.0
    static let caveOffset = 80.0

    /// The Welcome island: a camp on a small island, a Blob waving hello, a crane into an orbit.
    public static func island(kit: [LibraryAsset], ids: IDFactory = .sequential("island")) throws -> (ProjectInfo, [Scene]) {
        var look = MoodPresets.look(for: .goldenHour)
        look.presetID = LookPreset.ink.id
        look.ground.visible = false
        look.fog = Fog(enabled: true, color: RGBA.hex("#F6C48E"), distance: 90)
        let info = ProjectInfo(id: ids.isSequential ? "island-project" : .make(), name: islandName, look: look)
        var scene = Scene(id: ids.isSequential ? "island-scene" : .make(), name: "Hello")
        scene.timeline = Timeline(fps: 30, duration: 10)
        scene = try compile(ShowcaseScripts.island, title: "Welcome island", info: info, scene: scene, kit: kit, ids: ids)
        scene.viewpoint = Viewpoint(target: Vec3(0, 0.6, 0), yaw: 28, pitch: 30, distance: 22)
        return (info, [scene])
    }

    /// The Enigma story: three sets in three Looks, then the narrated story that cuts between them.
    public static func enigma(kit: [LibraryAsset], ids: IDFactory = .sequential("enigma")) throws -> (ProjectInfo, [Scene]) {
        var look = MoodPresets.look(for: .night)
        look.presetID = LookPreset.ink.id
        look.ground.visible = false
        look.palette = Palette(swatches: [
            .init(name: "Paper", color: RGBA.hex("#EFE4C8")), .init(name: "Wall", color: RGBA.hex("#2B3148")),
            .init(name: "Lamp", color: RGBA.hex("#FFB45C")), .init(name: "Floor", color: RGBA.hex("#23202A")),
            .init(name: "Screen", color: RGBA.hex("#7FD4FF")), .init(name: "Alarm", color: RGBA.hex("#FF3B3B")),
            .init(name: "Rock", color: RGBA.hex("#4A4E5A")), .init(name: "Ink", color: RGBA.hex("#15131C"))
        ])
        let info = ProjectInfo(id: ids.isSequential ? "enigma-project" : .make(), name: enigmaName, look: look)
        func scene(_ id: String, _ name: String, look preset: String, mood: LightingPreset, script: String, stepping: Stepping = .onOnes) throws -> Scene {
            var scene = Scene(id: ids.isSequential ? SceneID(raw: id) : .make(), name: name)
            var sceneLook = MoodPresets.look(for: mood)
            sceneLook.presetID = preset
            sceneLook.palette = info.look.palette
            sceneLook.ground.visible = false
            scene.look = sceneLook
            scene.timeline = Timeline(fps: 24, duration: 6, stepping: stepping)
            return try compile(script, title: name, info: info, scene: scene, kit: kit, ids: ids)
        }
        let desk = try scene("enigma-desk", deskName, look: LookPreset.ink.id, mood: .night, script: ShowcaseScripts.desk(at: 0, animated: true))
        let room = try scene("enigma-room", roomName, look: LookPreset.comic.id, mood: .dusk, script: ShowcaseScripts.room(at: 0, animated: true),
                             stepping: .onTwos)
        let cave = try scene("enigma-cave", caveName, look: LookPreset.sketch.id, mood: .night, script: ShowcaseScripts.cave(at: 0, animated: true))
        let story = try storyScene(info: info, kit: kit, ids: ids)
        return (info, [desk, room, cave, story])
    }

    static func storyScene(info: ProjectInfo, kit: [LibraryAsset], ids: IDFactory) throws -> Scene {
        var scene = Scene(id: ids.isSequential ? "enigma-story" : .make(), name: storyName)
        var look = info.look
        look.lighting.sunIntensity = 0.15
        scene.look = look
        scene.timeline = Timeline(fps: 24, duration: 12.8)
        scene.timeline.audio = [AudioClip(id: "voiceover", role: .voiceover, name: "Voiceover", file: EnigmaSample.voiceoverFile, duration: 12.6)]
        scene.timeline.transcripts = [EnigmaSample.narrationTranscript()]
        let sets = ShowcaseScripts.desk(at: 0, animated: false) + "," + ShowcaseScripts.room(at: roomOffset, animated: false) + ","
            + ShowcaseScripts.cave(at: caveOffset, animated: false) + "," + ShowcaseScripts.story
        return try compile(sets, title: "The story", info: info, scene: scene, kit: kit, ids: ids)
    }

    /// Compiles a list of v3 actions (without the surrounding brackets) into the scene.
    static func compile(_ actions: String, title: String, info: ProjectInfo, scene: Scene, kit: [LibraryAsset], ids: IDFactory) throws -> Scene {
        let json = "{\"version\": 3, \"title\": \"\(title)\", \"actions\": [\(actions)]}"
        let script = try LoweyJSON.decode(SceneScript.self, from: Data(json.utf8))
        var library = LibraryManifest()
        library.kit = kit
        let result = try ScriptCompiler.compile(script, document: Document(project: info, scene: scene), context: ScriptContext(library: library, ids: ids))
        return result.document.scene
    }
}
