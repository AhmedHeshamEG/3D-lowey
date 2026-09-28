@testable import LoweyCore
import XCTest

final class ScriptCompilerTests: XCTestCase {
    private func narratedDocument() -> Document {
        var document = makeDocument()
        var timeline = document.scene.timeline
        timeline.duration = 12
        timeline.audio = [AudioClip(id: "vo", role: .voiceover, name: "VO", file: "vo.m4a", duration: 12)]
        let text = ["This", "is", "a", "German", "army", "message", "from", "1941.", "Nobody", "could."]
        timeline.transcripts = [Transcript(clip: "vo", language: "en-US", words: text.enumerated().map { index, word in
            TranscriptWord(text: word, start: 0.5 + Double(index) * 0.5, end: 0.9 + Double(index) * 0.5)
        })]
        document.scene.timeline = timeline
        return document
    }

    private func script(_ json: String) throws -> SceneScript {
        try LoweyJSON.decode(SceneScript.self, from: Data(json.utf8))
    }

    func testAShotFromOneLineOfTheScript() throws {
        let document = narratedDocument()
        let shot = try script("""
        {"version": 2, "title": "This is a German army message", "actions": [
          {"do": "look", "mood": "night", "post": "cinematic"},
          {"do": "add", "shape": "cube", "name": "Desk", "at": [0, 0, 0], "size": [1.6, 0.75, 0.8], "color": "#6B4A2E"},
          {"do": "add", "shape": "plane", "name": "Paper", "at": [0, 0.76, 0], "size": [0.3, 1, 0.42], "color": "palette:0"},
          {"do": "light", "type": "point", "name": "Lamp", "at": [0.5, 1.4, 0.2], "color": "#FFB347", "intensity": 2},
          {"do": "text", "text": "1941", "at": [0, 0.77, 0], "size": 0.08},
          {"do": "camera", "name": "Desk cam", "from": [0, 1.6, 2.2], "lookAt": "Paper", "focalLength": 35},
          {"do": "cut", "camera": "Desk cam", "at": 0},
          {"do": "cameraMove", "move": "pushIn", "subject": "Paper", "at": {"word": "message"}, "duration": 2},
          {"do": "preset", "target": "Paper", "preset": "grow", "at": {"word": "Nobody", "offset": -0.2}},
          {"do": "overlay", "shape": "cross", "at": {"word": "Nobody"}},
          {"do": "effect", "kind": "flash", "at": {"word": "could", "edge": "end"}},
          {"do": "particles", "preset": "embers", "at": "Lamp"},
          {"do": "character", "name": "Me", "at": [1.5, 0, 0]},
          {"do": "clip", "character": "Me", "clip": "Talk", "at": 0},
          {"do": "lipSync", "character": "Me"},
          {"do": "marker", "name": "enigma", "at": {"word": "German"}},
          {"do": "captions", "style": "punchy"}
        ]}
        """)
        let context = ScriptContext(now: 0, ids: .sequential("ai"))
        let result = try ScriptCompiler.compile(shot, document: document, context: context)
        let command = try XCTUnwrap(result.command)
        // One undo step, and it reverts exactly.
        let applied = try assertReverts(command, on: document)
        XCTAssertEqual(result.report.count, 17 - 1 /* overlay "at" isn't a time */ + 1)
        let scene = applied.scene
        let paper = try XCTUnwrap(result.created["Paper"])
        XCTAssertEqual(scene.objects[paper]?.transform.position.y ?? 0, 0.76, accuracy: 1e-9)
        XCTAssertEqual(applied.effectiveLook.lightingPreset, .night)
        XCTAssertFalse(applied.effectiveLook.post.isNeutral)
        // Synced to the words: the push-in starts on "message" (0.5 + 5 × 0.5 = 3 s).
        let camera = try XCTUnwrap(result.created["Desk cam"])
        XCTAssertEqual(scene.timeline.tracks.first { $0.target == camera && $0.property == .position }?.keyframes.first?.time ?? -1, 3, accuracy: 1e-9)
        XCTAssertEqual(scene.timeline.cuts.first?.camera, camera)
        XCTAssertEqual(scene.timeline.effects.first?.start ?? -1, 0.5 + 9 * 0.5 + 0.4, accuracy: 1e-9)
        XCTAssertEqual(scene.timeline.markers.first?.time ?? -1, 2, accuracy: 1e-9)
        let grow = try XCTUnwrap(scene.timeline.track(for: paper, .scale))
        XCTAssertEqual(grow.keyframes.first?.time ?? -1, 4.3, accuracy: 1e-9)
        let me = try XCTUnwrap(result.created["Me"])
        XCTAssertNotNil(scene.timeline.track(for: me, .mouth))
        XCTAssertEqual(scene.timeline.clipTracks.first?.target, me)
        XCTAssertEqual(scene.timeline.captions?.style, .punchy)
        // The camera looks at the paper.
        let forward = scene.worldTransform(of: camera).rotation.act(Vec3(0, 0, -1))
        let toPaper = (scene.worldTransform(of: paper).position - scene.worldTransform(of: camera).position).normalized
        XCTAssertGreaterThan(forward.dot(toPaper), 0.99)
        // The preview describes it in plain words.
        let preview = try ScriptCompiler.preview(shot, document: document, context: ScriptContext(ids: .sequential("p")))
        XCTAssertTrue(preview.added.contains("Paper"))
        XCTAssertTrue(preview.lookChanged)
        XCTAssertFalse(preview.lines.isEmpty)
        XCTAssertFalse(preview.isEmpty)
    }

    func testEditingExistingObjectsByName() throws {
        let document = narratedDocument()
        let edit = try script("""
        {"title": "Tweak", "actions": [
          {"do": "set", "target": "a", "property": "color", "value": "#FF0000"},
          {"do": "transform", "target": ["A", "C"], "position": [0, 0, 1], "relative": true},
          {"do": "transform", "target": "C", "scale": 2, "at": 1.5, "easing": "backOut"},
          {"do": "keys", "target": "C", "property": "opacity", "keys": [{"t": 0, "value": 0}, {"t": "1", "value": 1}]},
          {"do": "preset", "target": "*", "preset": "popIn", "at": 2, "stagger": 0.1, "order": "leftToRight"},
          {"do": "rename", "target": "C", "name": "Pillar"},
          {"do": "array", "target": "Pillar", "count": 4, "step": [1, 0, 0], "name": "Colonnade"},
          {"do": "group", "target": ["A", "Colonnade"], "name": "Set"},
          {"do": "command", "command": {"op": "renameScene", "name": "Edited"}}
        ]}
        """)
        let result = try ScriptCompiler.compile(edit, document: document, context: ScriptContext(ids: .sequential("e")))
        let applied = try assertReverts(try XCTUnwrap(result.command), on: document)
        XCTAssertEqual(applied.scene.objects["a"]?.color, .rgba(RGBA(1, 0, 0)))
        XCTAssertEqual(applied.scene.worldTransform(of: "a").position.z, 1, accuracy: 1e-9, "moved, then grouped (world kept)")
        XCTAssertEqual(applied.scene.timeline.track(for: "c", .scale)?.key(at: 1.5)?.easing, .backOut)
        XCTAssertEqual(applied.scene.timeline.track(for: "c", .opacity)?.keyframes.count, 2)
        XCTAssertEqual(applied.scene.objects["c"]?.name, "Pillar")
        XCTAssertEqual(applied.scene.name, "Edited")
        XCTAssertNotNil(result.created["Set"])
    }

    func testMistakesComeBackAsClearMessages() throws {
        let document = narratedDocument()
        func error(_ actions: String) -> String {
            do {
                _ = try ScriptCompiler.compile(try script("{\"title\": \"x\", \"actions\": [\(actions)]}"), document: document, context: ScriptContext())
                return "no error"
            } catch {
                return String(describing: error)
            }
        }
        XCTAssertTrue(error(##"{"do": "fly"}"##).contains("unknown action “fly”"))
        XCTAssertTrue(error(##"{"do": "set", "target": "Nope", "property": "color", "value": "#fff000"}"##).contains("no object called “Nope”"))
        XCTAssertTrue(error(##"{"do": "preset", "target": "A", "preset": "popIn", "at": {"word": "enigma"}}"##).contains("isn't in the transcript"))
        XCTAssertTrue(error(##"{"do": "add", "shape": "blob"}"##).contains("unknown shape"))
        XCTAssertTrue(error(##"{"do": "place", "asset": "tiger"}"##).contains("nothing in the library"))
        XCTAssertTrue(error(##"{"do": "add"}, {"do": "cameraMove", "move": "pushIn"}"##).hasPrefix("Action 2:"))
        XCTAssertTrue(error(##"{"do": "set", "target": "A", "property": "color", "value": "red"}"##).contains("isn't a colour"))
    }

    func testScriptsStillReadVersionOne() throws {
        let v1 = #"{"version": 1, "title": "Old", "commands": [{"op": "renameScene", "name": "Renamed"}]}"#
        let old = try script(v1)
        XCTAssertEqual(old.commands.count, 1)
        XCTAssertTrue(old.actions.isEmpty)
        let result = try ScriptCompiler.compile(old, document: makeDocument(), context: ScriptContext())
        XCTAssertEqual(result.document.scene.name, "Renamed")
        let v2 = SceneScript(title: "New", actions: [.object(["do": .string("add")])])
        let back = try LoweyJSON.decode(SceneScript.self, from: LoweyJSON.encode(v2))
        XCTAssertEqual(back, v2)
        XCTAssertNil(try ScriptCompiler.compile(SceneScript(title: "Empty"), document: makeDocument(), context: ScriptContext()).command)
    }
}
