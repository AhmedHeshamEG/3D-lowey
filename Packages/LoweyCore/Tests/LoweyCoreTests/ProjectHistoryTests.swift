import Foundation

import HmmDocuments
@testable import LoweyCore
import XCTest

/// The history journal as Maquette uses it: nothing lost when the app is killed, undo across relaunches, fast opens.
final class ProjectHistoryTests: XCTestCase {
    private var store: ProjectStore!
    private var project: URL!

    override func setUpWithError() throws {
        store = try ProjectStore(root: temporaryDirectory())
        (project, _) = try store.createProject(name: "Journal")
    }

    /// Performs like the editor: the command, then its ops into the journal.
    private func edit(_ command: LoweyCore.EditCommand, _ opened: inout ProjectHistory.Opened, key: String? = nil) throws {
        try opened.session.perform(command, coalesceKey: key)
        opened.journal.record(opened.session.takePendingOps())
    }

    private func move(_ id: ObjectID, x: Double) -> LoweyCore.EditCommand {
        .setProperties([PropertyChange(object: id, key: .position, value: .vec3(Vec3(x, 0, 0)))])
    }

    func testAKilledAppKeepsTheLastEditAndCanUndoIt() throws {
        var opened = try ProjectHistory.open(project, store: store)
        XCTAssertTrue(opened.isNew)
        var factory = ObjectFactory(ids: .sequential("k"))
        var ops = Operations(ids: .sequential("o"))
        try edit(ops.add(factory.primitive(.cube)), &opened)
        try edit(move("k-1", x: 2), &opened)
        try edit(.renameScene("Kitchen"), &opened)
        let edited = opened.session.document
        opened.journal.flush() // the group commit landed; the app is then killed: no checkpoint, no save

        var reopened = try ProjectHistory.open(project, store: store)
        XCTAssertFalse(reopened.isNew)
        XCTAssertEqual(reopened.replayed, 3)
        XCTAssertEqual(reopened.session.document.scene, edited.scene)
        XCTAssertEqual(reopened.session.undoLabel, "Rename scene")
        try reopened.session.undo()
        XCTAssertEqual(reopened.session.document.scene.name, "Scene 1")
        try reopened.session.undo()
        try reopened.session.undo()
        XCTAssertTrue(reopened.session.document.scene.objects.isEmpty)
    }

    func testUndoSurvivesRelaunchAcrossCheckpoints() throws {
        var opened = try ProjectHistory.open(project, store: store)
        var factory = ObjectFactory(ids: .sequential("u"))
        var ops = Operations(ids: .sequential("o"))
        try edit(ops.add(factory.primitive(.sphere)), &opened)
        for step in 1 ... 30 {
            try edit(move("u-1", x: Double(step)), &opened, key: "drag")
        }
        opened.session.endCoalescing()
        opened.journal.record(opened.session.takePendingOps())
        try checkpoint(&opened)
        try edit(.renameScene("After"), &opened)
        opened.journal.flush()
        XCTAssertEqual(try store.openDocument(at: project).scene.name, "Scene 1", "the files are written at checkpoints")

        var reopened = try ProjectHistory.open(project, store: store)
        XCTAssertEqual(reopened.replayed, 1)
        XCTAssertEqual(reopened.session.undoStack.map(\.label), ["Add Sphere", "Transform", "Rename scene"])
        while reopened.session.canUndo {
            try reopened.session.undo()
        }
        XCTAssertTrue(reopened.session.document.scene.objects.isEmpty)
        XCTAssertEqual(reopened.session.document.scene.name, "Scene 1")
    }

    func testFiftyThousandCommandsOpenFast() throws {
        var opened = try ProjectHistory.open(project, store: store)
        var factory = ObjectFactory(ids: .sequential("p"))
        var ops = Operations(ids: .sequential("o"))
        for _ in 0 ..< 20 {
            try edit(ops.add(factory.primitive(.cube)), &opened)
        }
        var policy = CheckpointPolicy()
        // 50 150 changes: the last 150 come after the last checkpoint and are replayed on open.
        for step in 0 ..< 50150 {
            try opened.session.perform(move(ObjectID(raw: "p-\(step % 20 + 1)"), x: Double(step)))
            let pending = opened.session.takePendingOps()
            opened.journal.record(pending)
            if policy.recorded(pending.count, quiet: opened.session.isQuiet) {
                try checkpoint(&opened)
                policy.checkpointed()
            }
        }
        opened.journal.flush()
        let expected = opened.session.document.scene

        let start = Date()
        let reopened = try ProjectHistory.open(project, store: store)
        let elapsed = Date().timeIntervalSince(start)
        print("Opened 50 000 commands in \(Int(elapsed * 1000)) ms (replayed \(reopened.replayed))")
        XCTAssertEqual(reopened.session.document.scene, expected)
        XCTAssertEqual(reopened.session.undoStack.count, 64 + reopened.replayed, "older steps stay on disk until undo reaches them")
        XCTAssertEqual(reopened.journal.olderUndoCount, ProjectHistory.historyLimit - 64 - reopened.replayed)
        // The budget is 500 ms on device; CI's shared Linux runners get a generous margin.
        XCTAssertLessThan(elapsed, 1.5)
    }

    func testOlderUndoStepsLoadAsUndoReachesThem() throws {
        var opened = try ProjectHistory.open(project, store: store)
        var factory = ObjectFactory(ids: .sequential("l"))
        var ops = Operations(ids: .sequential("o"))
        for _ in 0 ..< 150 {
            try edit(ops.add(factory.primitive(.cube)), &opened)
        }
        try checkpoint(&opened)
        var reopened = try ProjectHistory.open(project, store: store)
        var undone = 0
        while reopened.session.canUndo {
            try reopened.session.undo()
            undone += 1
            if reopened.session.undoStack.count < 8, reopened.journal.olderUndoCount > 0 {
                try reopened.session.prependUndo(reopened.journal.loadOlderUndo(64))
            }
        }
        XCTAssertEqual(undone, 150)
        XCTAssertTrue(reopened.session.document.scene.objects.isEmpty)
    }

    func testAnotherScenesProjectChangesWinWhenThisSceneHasNoTail() throws {
        var opened = try ProjectHistory.open(project, store: store)
        try edit(.renameScene("First"), &opened)
        try checkpoint(&opened)
        // Later, another scene changes the project look and the scene list (written to project.json).
        var info = try store.loadProjectInfo(at: project).info
        let second = try store.addScene(named: "Second", to: project)
        info = try store.loadProjectInfo(at: project).info
        info.look = MoodPresets.look(for: .dusk)
        info.modified = Date().addingTimeInterval(10)
        try SafeFileWriter.write(store.coder.encode(info, kind: .project), to: project.appendingPathComponent(ProjectLayout.projectFile))

        let reopened = try ProjectHistory.open(project, scene: opened.session.document.scene.id, store: store)
        XCTAssertEqual(reopened.session.document.project.look, info.look)
        XCTAssertTrue(reopened.session.document.project.sceneOrder.contains(second.id))
        XCTAssertEqual(reopened.session.document.scene.name, "First")
    }

    func testARestoredVersionIsOneUndoStep() throws {
        var opened = try ProjectHistory.open(project, store: store)
        var factory = ObjectFactory(ids: .sequential("v"))
        var ops = Operations(ids: .sequential("o"))
        let before = opened.session.document.scene
        let version = try opened.journal.versions.save(opened.session.document, name: "Empty stage", automatic: false)
        try edit(ops.add(factory.primitive(.cube)), &opened)
        let built = opened.session.document.scene

        let saved = try opened.journal.versions.load(version.id)
        try edit(.replaceScene(saved.scene), &opened)
        XCTAssertEqual(opened.session.document.scene, before)
        XCTAssertEqual(opened.session.undoLabel, "Restore version")
        try opened.session.undo()
        XCTAssertEqual(opened.session.document.scene, built)
        let encoded = try JSONEncoder().encode(LoweyCore.EditCommand.replaceScene(built))
        XCTAssertEqual(try JSONDecoder().decode(LoweyCore.EditCommand.self, from: encoded), .replaceScene(built))
    }

    func testSnapshotsFromAnOlderSchemaMigrate() throws {
        let document = try store.openDocument(at: project)
        var raw = try HmmJSON.decode(JSONValue.self, from: ProjectHistory.encodeSnapshot(document))
        raw["schemaVersion"] = .number(3)
        let decoded = try ProjectHistory.decodeSnapshot(HmmJSON.encode(raw))
        XCTAssertEqual(decoded.scene.id, document.scene.id)
        XCTAssertEqual(decoded.project.id, document.project.id)
    }

    func testEverySchemaSinceTheFirstJournalHasAnOpMigration() {
        for version in ProjectHistory.firstJournalSchema ..< LoweySchema.currentVersion {
            XCTAssertNotNil(ProjectHistory.opMigrations[version], "A schema bump needs a journal op migration from \(version)")
        }
    }

    func testDeletingASceneDeletesItsJournal() throws {
        let second = try store.addScene(named: "Second", to: project)
        _ = try ProjectHistory.open(project, scene: second.id, store: store)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ProjectHistory.url(scene: second.id, in: project).path))
        try store.deleteScene(second.id, in: project)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProjectHistory.url(scene: second.id, in: project).path))
    }

    private func checkpoint(_ opened: inout ProjectHistory.Opened) throws {
        opened.session.updateProjectInfo { $0.modified = Date() }
        let done = expectation(description: "checkpoint")
        let failure = LockedBox<Error?>(nil)
        ProjectHistory.checkpoint(
            opened.session.document, history: opened.session.history, journal: opened.journal, store: store, project: project
        ) { error in
            failure.value = error
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        if let error = failure.value { throw error }
    }
}

/// A value shared with a `@Sendable` callback in tests.
private final class LockedBox<Value>: @unchecked Sendable {
    // @unchecked Sendable: every access goes through `lock`.
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

final class HistoryCursorTests: XCTestCase {
    func testTheCursorWalksTheHistoryBothWays() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (_, document) = try store.createProject(name: "Cursor")
        var session = EditSession(document: document)
        var factory = ObjectFactory(ids: .sequential("c"))
        var ops = Operations(ids: .sequential("o"))
        var states = [session.document]
        for _ in 0 ..< 4 {
            try session.perform(ops.add(factory.primitive(.cube)))
            states.append(session.document)
        }
        var cursor = HistoryCursor(document: session.document, steps: session.undoStack)
        XCTAssertTrue(cursor.isNow)
        XCTAssertEqual(cursor.label(at: 4), session.undoStack[3].label)
        XCTAssertNil(cursor.label(at: 0))
        let changes = try cursor.move(to: 1)
        XCTAssertEqual(cursor.document, states[1])
        XCTAssertEqual(changes.objects.count, 3)
        try cursor.move(to: 3)
        XCTAssertEqual(cursor.document, states[3])
        try cursor.move(to: -5)
        XCTAssertEqual(cursor.document, states[0])
        try cursor.move(to: 99)
        XCTAssertEqual(cursor.document, states[4])
    }
}
