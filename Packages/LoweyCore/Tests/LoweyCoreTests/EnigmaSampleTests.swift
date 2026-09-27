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
}
