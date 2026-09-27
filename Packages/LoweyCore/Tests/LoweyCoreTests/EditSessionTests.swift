import Foundation
@testable import LoweyCore
import XCTest

final class EditSessionTests: XCTestCase {
    func testUndoRedoAcrossEveryKindOfAction() throws {
        let original = makeDocument()
        var session = EditSession(document: original)
        var snapshots = [session.document]
        let commands: [EditCommand] = [
            .insert(SceneFragment(object: SceneObject(id: "n", name: "N", kind: .primitive(.torus))), parent: nil, index: nil),
            .setProperties([PropertyChange(object: "n", key: .position, value: .vec3(Vec3(3, 0, 0)))]),
            .rename("n", "Donut"),
            .setKind("c", .asset("tree")),
            .reparent([ReparentEntry(object: "n", parent: "a")]),
            .setLook(LookPresets.look(for: .goldenHour), scope: .project),
            .setLook(LookPresets.look(for: .night), scope: .scene),
            .renameScene("Renamed"),
            .delete(["a"])
        ]
        for command in commands {
            try session.perform(command)
            snapshots.append(session.document)
        }
        XCTAssertEqual(session.undoStack.count, commands.count)
        // Undo everything, checking every intermediate state.
        for expected in snapshots.dropLast().reversed() {
            try session.undo()
            XCTAssertEqual(session.document, expected)
        }
        XCTAssertFalse(session.canUndo)
        XCTAssertNil(try session.undo())
        // Redo everything.
        for expected in snapshots.dropFirst() {
            try session.redo()
            XCTAssertEqual(session.document, expected)
        }
        XCTAssertFalse(session.canRedo)
        XCTAssertNil(try session.redo())
        XCTAssertEqual(session.document, snapshots.last)
    }

    func testNewCommandClearsRedo() throws {
        var session = EditSession(document: makeDocument())
        try session.perform(.rename("a", "1"))
        try session.undo()
        XCTAssertTrue(session.canRedo)
        XCTAssertEqual(session.redoLabel, "Rename")
        try session.perform(.rename("a", "2"))
        XCTAssertFalse(session.canRedo)
        XCTAssertEqual(session.undoLabel, "Rename")
    }

    func testCoalescingMakesOneUndoStep() throws {
        let original = makeDocument()
        var session = EditSession(document: original)
        for step in 1 ... 30 {
            try session.perform(.setProperties([
                PropertyChange(object: "a", key: .position, value: .vec3(Vec3(Double(step), 0, 0)))
            ]), coalesceKey: "joystick")
        }
        // Mid-gesture a different property of another object joins in.
        try session.perform(.setProperties([PropertyChange(object: "c", key: .rotation, value: .quat(Quat(angle: 1, axis: .unitY)))]),
                            coalesceKey: "joystick")
        session.endCoalescing()
        XCTAssertEqual(session.undoStack.count, 1)
        let moved = session.document
        try session.undo()
        XCTAssertEqual(session.document, original)
        try session.redo()
        XCTAssertEqual(session.document, moved)
        // After endCoalescing, the same key starts a new step.
        try session.perform(.setProperties([PropertyChange(object: "a", key: .position, value: .vec3(.zero))]), coalesceKey: "joystick")
        XCTAssertEqual(session.undoStack.count, 2)
    }

    func testCoalescingNonPropertyCommands() throws {
        let original = makeDocument()
        var session = EditSession(document: original)
        try session.perform(.rename("a", "1"), coalesceKey: "k")
        try session.perform(.rename("c", "2"), coalesceKey: "k")
        try session.perform(.rename("b", "3"), coalesceKey: "k")
        XCTAssertEqual(session.undoStack.count, 1)
        let after = session.document
        try session.undo()
        XCTAssertEqual(session.document, original)
        try session.redo()
        XCTAssertEqual(session.document, after)
    }

    func testDifferentKeysDoNotCoalesce() throws {
        var session = EditSession(document: makeDocument())
        try session.perform(.rename("a", "1"), coalesceKey: "x")
        try session.perform(.rename("a", "2"), coalesceKey: "y")
        try session.perform(.rename("a", "3"))
        XCTAssertEqual(session.undoStack.count, 3)
    }

    func testHistoryLimit() throws {
        var session = EditSession(document: makeDocument(), historyLimit: 5)
        for index in 0 ..< 12 {
            try session.perform(.rename("a", "\(index)"))
        }
        XCTAssertEqual(session.undoStack.count, 5)
        session.clearHistory()
        XCTAssertFalse(session.canUndo)
    }

    func testFailedCommandLeavesSessionUntouched() {
        var session = EditSession(document: makeDocument())
        XCTAssertThrowsError(try session.perform(.rename("missing", "x")))
        XCTAssertEqual(session.revision, 0)
        XCTAssertFalse(session.canUndo)
    }

    func testViewpointAndInfoAreNotUndoable() {
        var session = EditSession(document: makeDocument())
        var viewpoint = Viewpoint()
        viewpoint.distance = 42
        session.setViewpoint(viewpoint)
        session.setViewpoint(viewpoint) // no-op
        XCTAssertEqual(session.revision, 1)
        XCTAssertFalse(session.canUndo)
        session.updateProjectInfo { $0.name = "Other" }
        XCTAssertEqual(session.document.project.name, "Other")
        XCTAssertEqual(session.revision, 2)
    }
}
