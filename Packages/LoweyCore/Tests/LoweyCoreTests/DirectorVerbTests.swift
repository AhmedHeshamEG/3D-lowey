import Foundation
@testable import LoweyCore
import XCTest

/// The v3 director's verbs behind MCP v2: frameShot, lighting recipes, intents and the Look.
final class DirectorVerbTests: XCTestCase {
    /// A blob "Hesham" at the origin, a "Door" cube 4 m to the right, a camera looking at them.
    static func document() throws -> Document {
        var ids = IDFactory.sequential("dv")
        let blob = BlobCharacter.build(BlobRecipe(name: "Hesham"), ids: &ids)
        var scene = Scene(id: "s", name: "Director")
        for object in blob.fragment.objects {
            scene.objects[object.id] = object
        }
        scene.roots = blob.fragment.roots
        let door = SceneObject(id: "door", name: "Door", kind: .primitive(.cube), transform: Transform(position: Vec3(4, 0, 0)))
        var camera = SceneObject(id: "cam", name: "Cam", kind: .camera, transform: Transform(position: Vec3(0, 1.4, 6)))
        camera[.fieldOfView] = .float(40)
        for object in [door, camera] {
            scene.objects[object.id] = object
            scene.roots.append(object.id)
        }
        scene.activeCamera = "cam"
        scene.timeline = Timeline(fps: 24, duration: 8)
        scene.timeline.audio = [AudioClip(id: "vo", role: .voiceover, name: "VO", file: "vo.m4a", start: 0, offset: 0, duration: 8, sourceDuration: 8)]
        scene.timeline.transcripts = [Transcript(clip: "vo", language: "en-US", words: [
            TranscriptWord(text: "Nobody", start: 2, end: 2.5), TranscriptWord(text: "could", start: 2.5, end: 2.9)
        ])]
        return Document(project: ProjectInfo(id: "p", name: "P"), scene: scene)
    }

    private func run(_ actions: String, on document: Document? = nil) throws -> ScriptResult {
        let script = try LoweyJSON.decode(SceneScript.self, from: Data("{\"version\": 3, \"title\": \"T\", \"actions\": [\(actions)]}".utf8))
        return try ScriptCompiler.compile(script, document: document ?? Self.document(), context: ScriptContext(ids: .sequential("run")))
    }

    private func hesham(_ scene: Scene) throws -> ObjectID {
        try XCTUnwrap(scene.objects.values.first { $0.name == "Hesham" }?.id)
    }

    func testFrameShotPlacesANewCameraAndCutsToIt() throws {
        let frame = #"{"do": "frameShot", "subject": "Hesham", "shotType": "full", "composition": "rightThird", "lens": 85, "camera": "Close", "#
        let result = try run(frame + #""at": {"word": "Nobody"}}"#)
        let scene = result.document.scene
        let camera = try XCTUnwrap(scene.objects.values.first { $0.name == "Close" })
        XCTAssertEqual(camera.kind, .camera)
        XCTAssertEqual(try XCTUnwrap(camera[.fieldOfView]?.floatValue), CameraLens.fieldOfView(focalLength: 85), accuracy: 1e-6)
        XCTAssertEqual(scene.timeline.cuts.last?.camera, camera.id)
        XCTAssertEqual(try XCTUnwrap(scene.timeline.cuts.last).time, 2, accuracy: 1e-9)
        // The whole subject lands on the right third of what the new camera sees.
        let report = ShotObserver(document: result.document).observe(at: 2.2, subject: "Hesham")
        XCTAssertEqual(report.camera, "Close")
        XCTAssertEqual(report.frame.thirds, "right third")
        XCTAssertTrue(result.report.contains { $0.contains("Full, right third, 85 mm") }, "\(result.report)")
        // Again on an existing camera: it moves, nothing new is made.
        let again = try run(#"{"do": "frameShot", "subject": "Hesham", "shotType": "wide", "camera": "Cam"}"#)
        XCTAssertEqual(again.document.scene.objects.values.filter { $0.kind == .camera }.count, 1)
        XCTAssertEqual(again.document.scene.activeCamera, "cam")
        XCTAssertThrowsError(try run(#"{"do": "frameShot", "subject": "Hesham", "shotType": "sideways"}"#)) {
            XCTAssertTrue(String(describing: $0).contains("closeUp"))
        }
    }

    func testLightingRecipesPlaceLampsForTheCameraAndReplaceThem() throws {
        let first = try run(#"{"do": "lighting", "recipe": "key-warm-world-cool", "subject": "Hesham"}"#)
        let key = try XCTUnwrap(first.document.scene.objects.values.first { $0.name == "Key light" })
        let position = first.document.scene.worldTransform(of: key.id).position
        XCTAssertLessThan(position.x, 0, "key from camera-left")
        XCTAssertGreaterThan(position.z, 0, "on the camera's side")
        let lighting = first.document.effectiveLook.lighting
        XCTAssertEqual(lighting.sunAzimuth, 140, accuracy: 1e-6, "the cool world light from behind, camera-right")
        XCTAssertEqual(lighting.sunColor, RGBA.hex("#9DB4FF"))
        // A second recipe replaces the lamps.
        let second = try run(#"{"do": "lighting", "recipe": "noir-single-source", "subject": "Hesham", "intensity": 1.5}"#, on: first.document)
        let lamps = second.document.scene.objects.values.filter { LightRecipe.lampNames.contains($0.name) }
        XCTAssertEqual(lamps.map(\.name), ["Key light"])
        XCTAssertEqual(try XCTUnwrap(lamps.first?[.lightIntensity]?.floatValue), 3.2 * 1.5, accuracy: 1e-6)
        XCTAssertLessThan(second.document.effectiveLook.lighting.sunIntensity, 0.2)
        XCTAssertEqual(LightRecipe.allCases.count, 6)
        for recipe in LightRecipe.allCases {
            XCTAssertNoThrow(try run("{\"do\": \"lighting\", \"recipe\": \"\(recipe.rawValue)\"}"), recipe.rawValue)
            XCTAssertFalse(recipe.reason.isEmpty)
        }
        XCTAssertThrowsError(try run(#"{"do": "lighting", "recipe": "disco"}"#))
    }

    func testIntentsBecomeAnimation() throws {
        let result = try run("""
        {"do": "intent", "target": "Hesham", "what": "enter", "at": 0.5},
        {"do": "intent", "target": "Hesham", "what": "react", "how": "shocked", "on_word": "Nobody"},
        {"do": "intent", "target": "Hesham", "what": "walk_to", "to": "Door", "at": 3},
        {"do": "intent", "target": "Hesham", "what": "look_at", "to": "Door", "at": 6},
        {"do": "intent", "target": "Door", "what": "emphasise", "at": 1, "frameRate": "twos"},
        {"do": "intent", "target": "Door", "what": "idle", "at": 7}
        """)
        let scene = result.document.scene
        let id = try hesham(scene)
        let clips = try XCTUnwrap(scene.timeline.clipTracks.first { $0.target == id }).segments.map(\.clip.name)
        XCTAssertEqual(clips, ["Wave", "Nod", "Walk", "Idle"])
        XCTAssertTrue(scene.timeline.tracks.contains { $0.target == id && $0.property == .position }, "walks by keys")
        XCTAssertTrue(scene.timeline.behaviors.contains { $0.target == id && $0.kind == .lookAt("door") })
        XCTAssertEqual(scene.objects["door"]?[.stepping], .enumeration("twos"))
        XCTAssertTrue(scene.timeline.tracks.contains { $0.target == "door" }, "the door pulses and floats")
        // The walk ends in front of the door, not in it, on the ground.
        let end = Animator.evaluate(result.document, at: 7.9).scene.worldTransform(of: id).position
        XCTAssertEqual(end.y, 0, accuracy: 0.15)
        XCTAssertLessThan(end.x, 3.5)
        XCTAssertGreaterThan(end.x, 2.5)
        let talk = try run(#"{"do": "intent", "target": "Hesham", "what": "talk", "at": 2}"#)
        XCTAssertTrue(talk.report.contains { $0.contains("Lip sync") }, "\(talk.report)")
        XCTAssertThrowsError(try run(#"{"do": "intent", "target": "Hesham", "what": "dance"}"#)) {
            XCTAssertTrue(String(describing: $0).contains("walk_to"))
        }
        XCTAssertThrowsError(try run(#"{"do": "intent", "target": "Hesham", "what": "walk_to"}"#))
    }

    func testTranscriptPutsKnownWordsOnTheVoiceover() throws {
        let spread = try run(#"{"do": "transcript", "text": "Two plus two equals four.", "from": 1, "to": 3}"#)
        let words = spread.document.scene.timeline.words
        XCTAssertEqual(words.map(\.text), ["Two", "plus", "two", "equals", "four."])
        XCTAssertEqual(try XCTUnwrap(words.first).start, 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(words.last).end, 3, accuracy: 1e-9)
        let timed = try run(#"{"do": "transcript", "words": [{"w": "Then", "t": 0.5, "e": 0.8}, {"w": "BOOM", "t": 1.2}]}"#)
        XCTAssertEqual(timed.document.scene.timeline.words.map(\.start), [0.5, 1.2])
        XCTAssertEqual(timed.document.scene.timeline.transcripts.count, 1, "replaces the clip's transcript")
        XCTAssertThrowsError(try run(#"{"do": "transcript", "clip": "nope", "text": "x"}"#))
        XCTAssertThrowsError(try run(#"{"do": "transcript"}"#))
    }

    func testTheLookVerbSetsTheLookAndPerObjectLooks() throws {
        let result = try run(#"{"do": "look", "look": "comic", "mood": "dusk", "perObject": {"Door": "sketch"}}"#)
        XCTAssertEqual(result.document.effectiveLook.presetID, "comic")
        XCTAssertEqual(result.document.scene.objects["door"]?[.lookPreset], .enumeration("sketch"))
        XCTAssertThrowsError(try run(#"{"do": "look", "look": "anime"}"#)) {
            XCTAssertTrue(String(describing: $0).contains("ink"))
        }
    }

    func testTheReferenceNamesEveryVerb() {
        for verb in ["frameShot", "lighting", "intent", "flipbook", "place", "scaleTo", "recolor", "look"] {
            XCTAssertTrue(ScriptReference.text.contains("\"do\":\"\(verb)\""), verb)
        }
        for verb in ["frameShot", "lighting", "intent"] {
            XCTAssertNotNil(ScriptState.handlers[verb], verb)
        }
    }
}

/// MCP v2's data replies and the v3 schema.
final class BridgeV2Tests: XCTestCase {
    func testFindAssetsPutsTheKitFirstWithWhatPlacingNeeds() throws {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("Kit")
        var manifest = LibraryManifest()
        manifest.kit = try KitIndex.load(from: root).assets
        let found = FoundAsset.find("desk", in: manifest)
        let desk = try XCTUnwrap(found.first)
        XCTAssertEqual(desk.id, "kit.office-desk")
        XCTAssertFalse(desk.surfaces.isEmpty, "the desk top")
        XCTAssertEqual(desk.size?.count, 3)
        XCTAssertNotEqual(desk.set, "Library")
        XCTAssertTrue(FoundAsset.find("desk", set: "Nowhere", in: manifest).isEmpty)
        XCTAssertEqual(FoundAsset.find("", in: manifest, limit: 1).count, 1)
    }

    func testReadProjectSummarisesShotsCastAndWords() throws {
        var document = try DirectorVerbTests.document()
        document.scene.timeline.cuts = [CameraCut(time: 2, camera: "cam")]
        let summary = ProjectReading(document, scenes: [("Opening", 4, 24, "comic"), (document.scene.name, 8, 24, nil)])
        XCTAssertEqual(summary.scenes.map(\.name), ["Opening", "Director"])
        XCTAssertEqual(summary.scenes.filter(\.open).map(\.name), ["Director"])
        XCTAssertEqual(summary.scenes.first?.look, "comic")
        XCTAssertEqual(summary.words, 2)
        XCTAssertEqual(summary.transcript, "Nobody could")
        XCTAssertEqual(summary.shots.map(\.camera), ["Cam"])
        XCTAssertEqual(summary.shots.first?.words, ["Nobody"], "the cut lands on “Nobody”")
        XCTAssertEqual(summary.cast, ["Hesham"])
        XCTAssertTrue(summary.summary.hasPrefix("“P”, scene “Director”"), summary.summary)
        let data = try LoweyJSON.encode(summary)
        XCTAssertEqual(try LoweyJSON.decode(ProjectReading.self, from: data), summary)
    }

    /// The schema at schemas/scene-script.v3.schema.json names every verb the compiler knows (aliases aside).
    func testTheV3SchemaCoversEveryVerb() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("schemas/scene-script.v3.schema.json")
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let action = try XCTUnwrap(defs["action"] as? [String: Any])
        let properties = try XCTUnwrap(action["properties"] as? [String: Any])
        let verbs = try XCTUnwrap((properties["do"] as? [String: Any])?["enum"] as? [String])
        let aliases: Set = ["relate", "frame_shot", "scale_to", "animate", "move", "person", "key", "duration", "delete"]
        XCTAssertEqual(Set(verbs), Set(ScriptState.handlers.keys).subtracting(aliases))
    }
}
