import Foundation
@testable import LoweyCore
import XCTest

final class CommandTests: XCTestCase {
    // MARK: Every command reverts perfectly

    func testInsertReverts() throws {
        let document = makeDocument()
        let new = SceneObject(id: "n", name: "New", kind: .primitive(.cone))
        try assertReverts(.insert(SceneFragment(object: new), parent: nil, index: nil), on: document)
        try assertReverts(.insert(SceneFragment(object: new), parent: "a", index: 0), on: document)
        try assertReverts(.insert(SceneFragment(object: new), parent: nil, index: 0), on: document)
        // Insert with children.
        var parent = SceneObject(id: "p", name: "P", kind: .group)
        parent.children = ["q"]
        let child = SceneObject(id: "q", name: "Q", kind: .primitive(.cube), parent: "p")
        let applied = try assertReverts(.insert(SceneFragment(objects: [parent, child], roots: ["p"]), parent: "c", index: nil), on: document)
        XCTAssertEqual(applied.scene.objects["p"]?.parent, "c")
        XCTAssertEqual(applied.scene.objects["q"]?.parent, "p")
    }

    func testDeleteReverts() throws {
        let document = makeDocument()
        let applied = try assertReverts(.delete(["a"]), on: document)
        XCTAssertNil(applied.scene.objects["b"], "children are deleted with the parent")
        try assertReverts(.delete(["b"]), on: document)
        try assertReverts(.delete(["a", "c"]), on: document)
        try assertReverts(.delete(["c", "a", "b"]), on: document) // b already gone with a
    }

    func testSetPropertiesReverts() throws {
        let document = makeDocument()
        try assertReverts(.setProperties([
            PropertyChange(object: "a", key: .position, value: .vec3(Vec3(5, 5, 5))),
            PropertyChange(object: "b", key: .color, value: .color(.palette(2))),
            PropertyChange(object: "a", key: .color, value: nil),
            PropertyChange(object: "c", key: "custom", value: .string("hello"))
        ]), on: document)
        // Same key twice in one command.
        try assertReverts(.setProperties([
            PropertyChange(object: "a", key: .visible, value: .bool(false)),
            PropertyChange(object: "a", key: .visible, value: .bool(true))
        ]), on: document)
        // Int is accepted where float is expected.
        try assertReverts(.setProperties([PropertyChange(object: "a", key: .emissiveIntensity, value: .int(2))]), on: document)
    }

    func testRenameKindLookSceneReverts() throws {
        let document = makeDocument()
        try assertReverts(.rename("a", "Renamed"), on: document)
        try assertReverts(.setKind("a", .asset("tree")), on: document)
        try assertReverts(.setLook(LookPresets.look(for: .night), scope: .project), on: document)
        try assertReverts(.setLook(LookPresets.look(for: .dusk), scope: .scene), on: document)
        try assertReverts(.renameScene("New name"), on: document)
        let cameraDoc = try assertReverts(
            .insert(SceneFragment(object: SceneObject(id: "cam", name: "Cam", kind: .camera)), parent: nil, index: nil),
            on: document
        )
        try assertReverts(.setActiveCamera("cam"), on: cameraDoc)
        var timeline = Timeline()
        var track = Track(id: "t", target: "a", property: .position)
        track.setKey(Keyframe(time: 0, value: .vec3(.zero)))
        timeline.tracks = [track]
        try assertReverts(.setTimeline(timeline), on: document)
    }

    func testReparentReverts() throws {
        let document = makeDocument()
        try assertReverts(.reparent([ReparentEntry(object: "c", parent: "a", index: 0)]), on: document)
        try assertReverts(.reparent([ReparentEntry(object: "b", parent: nil, index: 1, transform: Transform(position: Vec3(1, 1, 0)))]), on: document)
        try assertReverts(.reparent([ReparentEntry(object: "c", parent: nil, index: 0)]), on: document) // reorder
        try assertReverts(.reparent([
            ReparentEntry(object: "c", parent: "b"),
            ReparentEntry(object: "c", parent: nil, index: 0)
        ]), on: document)
    }

    func testBatchRevertsAndIsAtomic() throws {
        let document = makeDocument()
        let batch = EditCommand.batch("Many", [
            .rename("a", "X"),
            .setProperties([PropertyChange(object: "c", key: .position, value: .vec3(.one))]),
            .delete(["b"]),
            .insert(SceneFragment(object: SceneObject(id: "z", name: "Z", kind: .group)), parent: nil, index: nil),
            .reparent([ReparentEntry(object: "c", parent: "z")])
        ])
        try assertReverts(batch, on: document)
        // A failing step leaves the document untouched.
        var working = document
        let failing = EditCommand.batch("Fail", [.rename("a", "X"), .delete(["does-not-exist-parent"]), .rename("missing", "boom")])
        XCTAssertThrowsError(try failing.apply(to: &working))
        XCTAssertEqual(working, document)
    }

    func testErrors() {
        var document = makeDocument()
        XCTAssertThrowsError(try EditCommand.rename("nope", "x").apply(to: &document)) { error in
            XCTAssertEqual(error as? CommandError, .objectNotFound("nope"))
        }
        XCTAssertThrowsError(try EditCommand.setKind("nope", .group).apply(to: &document))
        XCTAssertThrowsError(try EditCommand.setProperties([PropertyChange(object: "nope", key: .visible, value: .bool(true))]).apply(to: &document))
        XCTAssertThrowsError(try EditCommand.setProperties([PropertyChange(object: "a", key: .position, value: .bool(true))]).apply(to: &document)) { error in
            XCTAssertEqual(error as? CommandError, .typeMismatch(key: .position, expected: .vec3, got: .bool))
        }
        XCTAssertThrowsError(try EditCommand.insert(SceneFragment(object: SceneObject(id: "a", name: "dup", kind: .group)), parent: nil, index: nil)
            .apply(to: &document)) { error in
                XCTAssertEqual(error as? CommandError, .duplicateObject("a"))
            }
        XCTAssertThrowsError(try EditCommand.insert(SceneFragment(object: SceneObject(id: "n", name: "n", kind: .group)), parent: "missing", index: nil)
            .apply(to: &document))
        XCTAssertThrowsError(try EditCommand.reparent([ReparentEntry(object: "a", parent: "b")]).apply(to: &document)) { error in
            XCTAssertEqual(error as? CommandError, .cycle("a"))
        }
        XCTAssertThrowsError(try EditCommand.reparent([ReparentEntry(object: "a", parent: "a")]).apply(to: &document))
        XCTAssertThrowsError(try EditCommand.reparent([ReparentEntry(object: "missing", parent: nil)]).apply(to: &document))
        XCTAssertThrowsError(try EditCommand.reparent([ReparentEntry(object: "a", parent: "missing")]).apply(to: &document))
        XCTAssertThrowsError(try EditCommand.setLook(nil, scope: .project).apply(to: &document))
        XCTAssertThrowsError(try EditCommand.setActiveCamera("missing").apply(to: &document))
        XCTAssertEqual(document, makeDocument())
        for error in [CommandError.objectNotFound("x"), .duplicateObject("x"), .typeMismatch(key: .color, expected: .color, got: .bool), .cycle("x"), .empty] {
            XCTAssertFalse(error.description.isEmpty)
        }
    }

    func testLabels() {
        let one = SceneObject(id: "x", name: "Tree", kind: .group)
        XCTAssertEqual(EditCommand.insert(SceneFragment(object: one), parent: nil, index: nil).label, "Add Tree")
        XCTAssertEqual(EditCommand.insert(SceneFragment(objects: [one, one], roots: ["x", "y"]), parent: nil, index: nil).label, "Add 2 objects")
        XCTAssertEqual(EditCommand.delete(["a"]).label, "Delete")
        XCTAssertEqual(EditCommand.delete(["a", "b"]).label, "Delete 2 objects")
        XCTAssertEqual(EditCommand.setProperties([PropertyChange(object: "a", key: .position, value: nil)]).label, "Transform")
        XCTAssertEqual(EditCommand.setProperties([PropertyChange(object: "a", key: .color, value: nil)]).label, "Change Color")
        XCTAssertEqual(EditCommand.setProperties([
            PropertyChange(object: "a", key: .color, value: nil), PropertyChange(object: "a", key: .visible, value: nil)
        ]).label, "Change properties")
        XCTAssertEqual(EditCommand.batch("Hello", []).label, "Hello")
        for command in [EditCommand.restore([]), .rename("a", "b"), .setKind("a", .group), .reparent([]),
                        .setLook(nil, scope: .scene), .renameScene("x"), .setActiveCamera(nil), .setTimeline(Timeline())] {
            XCTAssertFalse(command.label.isEmpty)
        }
    }

    func testChangeSets() throws {
        var document = makeDocument()
        let (_, changes) = try EditCommand.setProperties([PropertyChange(object: "a", key: .visible, value: .bool(false))]).apply(to: &document)
        XCTAssertEqual(changes.objects, ["a"])
        XCTAssertFalse(changes.hierarchy)
        let (_, deleteChanges) = try EditCommand.delete(["a"]).apply(to: &document)
        XCTAssertEqual(deleteChanges.objects, ["a", "b"])
        XCTAssertTrue(deleteChanges.hierarchy)
        var union = ChangeSet.none
        XCTAssertTrue(union.isEmpty)
        union.formUnion(ChangeSet(objects: ["x"], look: true))
        XCTAssertTrue(union.look)
        XCTAssertFalse(ChangeSet.everything(in: document).isEmpty)
    }

    func testSceneScriptRoundTrip() throws {
        let script = SceneScript(title: "Build a tree", commands: [
            .insert(SceneFragment(object: SceneObject(id: "trunk", name: "Trunk", kind: .primitive(.cylinder))), parent: nil, index: nil),
            .setProperties([PropertyChange(object: "trunk", key: .scale, value: .vec3(Vec3(0.3, 2, 0.3)))])
        ])
        let data = try LoweyJSON.encode(script)
        let decoded = try LoweyJSON.decode(SceneScript.self, from: data)
        XCTAssertEqual(decoded, script)
        var document = makeDocument()
        _ = try decoded.asCommand.apply(to: &document)
        XCTAssertEqual(document.scene.objects["trunk"]?.transform.scale, Vec3(0.3, 2, 0.3))
        // Hand-written JSON (as an AI would write it) decodes.
        let handwritten = """
        {"version":1,"title":"Lamp","commands":[
          {"op":"insert","fragment":{"roots":["l"],"objects":[{"id":"l","name":"Lamp","kind":{"type":"light","light":"point"},
            "children":[],"properties":{"position":{"vec3":[0,2,0]},"lightColor":{"color":"#FFAA00"}}}]}},
          {"op":"rename","id":"l","name":"Warm lamp"}
        ]}
        """
        let parsed = try LoweyJSON.decode(SceneScript.self, from: Data(handwritten.utf8))
        _ = try parsed.asCommand.apply(to: &document)
        XCTAssertEqual(document.scene.objects["l"]?.name, "Warm lamp")
        XCTAssertThrowsError(try LoweyJSON.decode(EditCommand.self, from: Data("{\"op\":\"explode\"}".utf8)))
    }
}
