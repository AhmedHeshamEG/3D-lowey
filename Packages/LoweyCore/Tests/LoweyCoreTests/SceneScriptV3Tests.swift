import Foundation
@testable import LoweyCore
import XCTest

final class SceneScriptV3Tests: XCTestCase {
    private func context() throws -> ScriptContext {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("Kit")
        var library = LibraryManifest()
        library.kit = try KitIndex.load(from: root).assets
        return ScriptContext(library: library, ids: .sequential("v3"))
    }

    private func run(_ json: String) throws -> ScriptResult {
        let script = try LoweyJSON.decode(SceneScript.self, from: Data(json.utf8))
        return try ScriptCompiler.compile(ScriptMigration.upgraded(script), document: makeDocument(), context: context())
    }

    func testAddFromTheKitAndPlaceByRelation() throws {
        let result = try run("""
        {"version": 3, "title": "Desk", "actions": [
          {"do": "add", "asset": "desk", "name": "Desk", "at": [3, 0, 0]},
          {"do": "add", "asset": "lamp", "name": "Lamp", "relation": "on", "reference": "Desk"},
          {"do": "place", "target": "C", "relation": "beside_left", "reference": "Desk"},
          {"do": "scaleTo", "target": "C", "meters": 0.5},
          {"do": "recolor", "target": "Desk", "slot": 1}
        ]}
        """)
        let scene = result.document.scene
        let lamp = try XCTUnwrap(result.created["Lamp"])
        let desk = try XCTUnwrap(result.created["Desk"])
        let solver = try RelationSolver(scene: scene, library: context().library)
        XCTAssertTrue(solver.isGrounded(lamp).grounded)
        let lampBox = try XCTUnwrap(solver.bounds.worldBounds(of: lamp, in: scene))
        let deskBox = try XCTUnwrap(solver.bounds.worldBounds(of: desk, in: scene))
        XCTAssertEqual(lampBox.min.y, deskBox.max.y, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(solver.bounds.worldBounds(of: "c", in: scene)).size.y, 0.5, accuracy: 1e-6)
        XCTAssertEqual(scene.objects[desk]?.color, .palette(1))
        XCTAssertTrue(result.report.contains { $0.contains("on “Desk”") }, "\(result.report)")
        XCTAssertNotNil(result.command, "one undo step")
    }

    func testErrorsAreInstructions() throws {
        XCTAssertThrowsError(try run(#"{"version": 3, "actions": [{"do": "place", "target": "A", "relation": "sideways", "reference": "C"}]}"#)) {
            XCTAssertTrue(String(describing: $0).contains("beside_left"), "lists the relations")
        }
        XCTAssertThrowsError(try run(#"{"version": 3, "actions": [{"do": "add", "asset": "zeppelin"}]}"#)) {
            XCTAssertTrue(String(describing: $0).contains("Desk"), "suggests what there is")
        }
    }

    func testVersion2ScriptsUpgrade() throws {
        let old = try LoweyJSON.decode(SceneScript.self, from: Data(#"""
        {"version": 2, "title": "Old", "actions": [{"do": "place", "asset": "desk"}, {"do": "animate", "target": "A", "preset": "popIn"},
         {"action": "move", "move": "pushIn"}]}
        """#.utf8))
        let new = ScriptMigration.upgraded(old)
        XCTAssertEqual(new.version, 3)
        XCTAssertEqual(new.actions.map { $0["do"]?.stringValue }, ["add", "preset", "cameraMove"])
        XCTAssertEqual(new.actions[0]["asset"]?.stringValue, "desk")
        XCTAssertNil(new.actions[2]["action"])
        XCTAssertEqual(ScriptMigration.upgraded(new), new, "v3 stays as it is")
    }
}
