import Foundation
@testable import LoweyCore
import XCTest

/// Phase 1 "done when": the Enigma sets exist as static scenes, save, reopen identical.
final class EnigmaSampleTests: XCTestCase {
    func testBuildsThreeValidScenes() throws {
        let (info, scenes) = try EnigmaSample.build()
        XCTAssertEqual(info.name, EnigmaSample.projectName)
        XCTAssertEqual(scenes.count, 3)
        for scene in scenes {
            XCTAssertTrue(scene.validate().isEmpty, "\(scene.name): \(scene.validate())")
            XCTAssertNotNil(scene.look, "each set has its own mood")
        }
        let names = scenes.map { $0.objects.values.map(\.name) }
        XCTAssertTrue(names[0].contains("Army message"))
        XCTAssertTrue(names[0].contains("Desk lamp"))
        XCTAssertTrue(names[0].contains("Lamp arm"), "uses a drawn stroke")
        XCTAssertEqual(names[1].filter { $0 == "Person" }.count, 12, "a room full of people (4 × 3)")
        XCTAssertEqual(names[1].filter { $0 == "Screen" }.count, 12)
        XCTAssertTrue(names[2].contains("Hero robot"))
        XCTAssertTrue(names[2].contains("Stalagmite"), "uses drawn lathe shapes")
        // Warm light in the desk scene.
        XCTAssertTrue(scenes[0].objects.values.contains { $0.kind == .light(.point) })
    }

    func testDeterministic() throws {
        let first = try EnigmaSample.build()
        let second = try EnigmaSample.build()
        XCTAssertEqual(first.0, second.0)
        XCTAssertEqual(first.1, second.1)
    }

    func testSaveCloseReopenIdentical() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (info, scenes) = try EnigmaSample.build()
        let url = try store.writeProject(info: info, scenes: scenes)
        for scene in scenes {
            let document = try store.openDocument(at: url, scene: scene.id)
            XCTAssertEqual(document.scene, scene)
            // Save again through the normal path and reopen.
            try store.save(document, to: url, touch: false)
            XCTAssertEqual(try store.openDocument(at: url, scene: scene.id).scene, scene)
        }
    }

    func testEveryObjectHasBoundsAndMeshes() throws {
        let (_, scenes) = try EnigmaSample.build()
        let bounds = SceneBounds()
        for scene in scenes {
            for (id, object) in scene.objects where object.kind.hasSurface {
                XCTAssertNotNil(bounds.worldBounds(of: id, in: scene), object.name)
                if case let .drawing(recipe) = object.kind {
                    XCTAssertFalse(DrawingMesher.mesh(for: recipe).isEmpty, object.name)
                }
            }
        }
    }

    // MARK: Phase 2 — the animated opening

    func testOpeningIsAnimatedEndToEnd() throws {
        let (info, scenes) = try EnigmaSample.buildWithOpening()
        XCTAssertEqual(scenes.count, 4)
        let opening = try XCTUnwrap(scenes.last)
        XCTAssertEqual(opening.name, EnigmaSample.openingName)
        XCTAssertTrue(opening.validate().isEmpty, "\(opening.validate())")
        let document = Document(project: info, scene: opening)
        let timeline = opening.timeline
        XCTAssertEqual(timeline.cuts.count, 3)
        XCTAssertEqual(timeline.markers.count, 5)
        XCTAssertGreaterThan(timeline.tracks.count, 20)
        XCTAssertGreaterThan(timeline.behaviors.count, 20, "everyone types")
        XCTAssertLessThanOrEqual(timeline.contentEnd, timeline.duration)
        let ids = Set(timeline.tracks.map(\.id))
        XCTAssertEqual(ids.count, timeline.tracks.count, "track ids are unique")

        func object(_ name: String, near: Vec3, at time: Double) throws -> (SceneObject, Transform) {
            let animated = Animator.evaluate(document, at: time).scene
            let match = try XCTUnwrap(animated.objects.values.filter { $0.name == name }.min {
                animated.worldTransform(of: $0.id).position.distance(to: near) < animated.worldTransform(of: $1.id).position.distance(to: near)
            })
            return (match, animated.worldTransform(of: match.id))
        }
        let room = EnigmaSample.roomOffset
        let cave = EnigmaSample.caveOffset
        // Cameras cut desk → room → cave.
        let names = { (time: Double) in Animator.evaluate(document, at: time).camera.flatMap { opening.objects[$0]?.name } }
        XCTAssertEqual(names(1), "Desk camera")
        XCTAssertEqual(names(5), "Room camera")
        XCTAssertEqual(names(9), "Cave camera")
        // The desk camera pushes in.
        let deskCam = try XCTUnwrap(opening.objects.values.first { $0.name == "Desk camera" }).id
        let paper = try object("Army message", near: .zero, at: 0).1.position
        let d0 = Animator.evaluate(document, at: 0.2).scene.worldTransform(of: deskCam).position.distance(to: paper)
        let d1 = Animator.evaluate(document, at: 3.2).scene.worldTransform(of: deskCam).position.distance(to: paper)
        XCTAssertLessThan(d1, d0 * 0.7)
        // The giant paper is hidden, pops, then grows huge over the room.
        XCTAssertLessThan(try object("Giant army message", near: room, at: 2).1.scale.x, 0.01)
        XCTAssertGreaterThan(try object("Giant army message", near: room, at: 7.05).1.scale.x, 6)
        // Screens light up in a wave: some on, some not yet.
        let screens = Animator.evaluate(document, at: 3.55).scene.objects.values
            .filter { $0.name == "Screen" && Animator.evaluate(document, at: 0).scene.worldTransform(of: $0.id).position.x > room.x - 5 }
        let lit = screens.filter { $0.transform.scale.x > 0.2 }.count
        XCTAssertGreaterThan(lit, 0)
        XCTAssertLessThan(lit, screens.count)
        // The X pops.
        XCTAssertLessThan(try object("Big X", near: room, at: 7).1.scale.x, 0.01)
        XCTAssertEqual(try object("Big X", near: room, at: 7.6).1.scale.x, 1, accuracy: 1e-6)
        // The robot rises out of the ground; its eyes light up.
        XCTAssertLessThan(try object("Hero robot", near: cave, at: 8).1.position.y, -2)
        XCTAssertEqual(try object("Hero robot", near: cave, at: 9.8).1.position.y, 0, accuracy: 1e-6)
        XCTAssertEqual(try object("Eye L", near: cave, at: 8.5).0.emissiveIntensity, 0)
        XCTAssertEqual(try object("Eye L", near: cave, at: 9.6).0.emissiveIntensity, 6)
        // The question mark pops at the end.
        XCTAssertLessThan(try object("Question mark", near: cave, at: 10).1.scale.x, 0.01)
        XCTAssertGreaterThan(try object("Question mark", near: cave, at: 11.5).1.scale.x, 0.9)
        // People are on twos: their typing arms hold for two frames.
        let arm = try XCTUnwrap(Animator.evaluate(document, at: 0).scene.objects.values.first {
            $0.name == "Arm" && opening.worldTransform(of: $0.id).position.x > room.x - 5
        }).id
        let f30 = Animator.evaluate(document, at: 30.0 / 30).scene.objects[arm]!.transform.rotation
        let f31 = Animator.evaluate(document, at: 31.0 / 30).scene.objects[arm]!.transform.rotation
        let f32 = Animator.evaluate(document, at: 32.0 / 30).scene.objects[arm]!.transform.rotation
        XCTAssertEqual(f30, f31)
        XCTAssertNotEqual(f31, f32)
        // Deterministic and saves / reopens identically.
        XCTAssertEqual(try EnigmaSample.buildWithOpening().1.last, opening)
        let store = try ProjectStore(root: temporaryDirectory())
        let url = try store.writeProject(info: info, scenes: scenes)
        XCTAssertEqual(try store.openDocument(at: url, scene: opening.id).scene, opening)
    }
}
