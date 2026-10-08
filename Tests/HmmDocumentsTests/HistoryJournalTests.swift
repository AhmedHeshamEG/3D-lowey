import Foundation
import HmmCommands
@testable import HmmDocuments
import XCTest

/// A tiny document: a list of numbers and a title.
private struct Sheet: Codable, Equatable, Sendable {
    var numbers: [Int] = []
    var title = ""
}

private enum SheetCommand: EditCommand, Codable, Equatable {
    case push(Int)
    case pop
    case title(String)
    indirect case batch(String, [SheetCommand])

    struct Empty: Error {}

    var label: String {
        switch self {
        case .push: "Add Number"
        case .pop: "Remove Number"
        case .title: "Rename"
        case let .batch(label, _): label
        }
    }

    func apply(to target: inout Sheet) throws -> (inverse: SheetCommand, changes: Int) {
        switch self {
        case let .push(value):
            target.numbers.append(value)
            return (.pop, 1)
        case .pop:
            guard let last = target.numbers.popLast() else { throw Empty() }
            return (.push(last), 1)
        case let .title(title):
            let old = target.title
            target.title = title
            return (.title(old), 1)
        case let .batch(label, commands):
            var inverses: [SheetCommand] = []
            var copy = target
            for command in commands {
                try inverses.append(command.apply(to: &copy).inverse)
            }
            target = copy
            return (.batch(label, inverses.reversed()), commands.count)
        }
    }

    static func group(_ label: String, _ commands: [SheetCommand]) -> SheetCommand { .batch(label, commands) }
}

final class HistoryJournalTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("hmm-journal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func format(
        schema: Int = 1, migrations: [Int: HistoryJournalFormat<SheetCommand>.Migration] = [:]
    ) -> HistoryJournalFormat<SheetCommand> {
        HistoryJournalFormat(
            schemaVersion: schema, migrations: migrations, eagerUndo: 8,
            encodeDocument: { try HmmJSON.encode($0) }, decodeDocument: { try HmmJSON.decode(Sheet.self, from: $0) }
        )
    }

    private func open(_ format: HistoryJournalFormat<SheetCommand>? = nil) throws -> (HistoryJournal<SheetCommand>, OpenedHistory<SheetCommand>) {
        try HistoryJournal.open(at: folder, format: format ?? self.format()) { Sheet(title: "new") }
    }

    /// Performs and records like an app would.
    private func perform(_ command: SheetCommand, _ history: inout CommandStack<SheetCommand>, _ sheet: inout Sheet,
                         _ journal: HistoryJournal<SheetCommand>, key: String? = nil) throws {
        try history.perform(command, on: &sheet, coalesceKey: key)
        journal.record(history.takePendingOps())
    }

    func testAKilledAppLosesNothingAndUndoSurvivesRelaunch() throws {
        var (journal, opened) = try open()
        XCTAssertEqual(opened.source, .fresh)
        var sheet = opened.document
        var history = opened.history
        for value in 1 ... 5 {
            try perform(.push(value), &history, &sheet, journal)
        }
        try history.undo(on: &sheet)
        journal.record(history.takePendingOps())
        journal.flush() // the group commit has happened; then the app is killed (no checkpoint)

        (journal, opened) = try open()
        XCTAssertEqual(opened.source, .checkpoint)
        XCTAssertEqual(opened.replayed, 6)
        XCTAssertEqual(opened.document, sheet)
        history = opened.history
        sheet = opened.document
        XCTAssertEqual(history.redoLabel, "Add Number")
        try history.redo(on: &sheet)
        XCTAssertEqual(sheet.numbers, [1, 2, 3, 4, 5])
        for _ in 1 ... 5 {
            try history.undo(on: &sheet)
        }
        XCTAssertEqual(sheet, Sheet(title: "new"))
    }

    func testAHalfWrittenLineIsSkippedAndTheJournalCarriesOn() throws {
        var (journal, opened) = try open()
        var sheet = opened.document
        var history = opened.history
        try perform(.push(1), &history, &sheet, journal)
        try perform(.push(2), &history, &sheet, journal)
        journal.flush()
        let segment = folder.appendingPathComponent("segments/000001.jsonl")
        let handle = try FileHandle(forWritingTo: segment)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"op":{"op":"push","comm"#.utf8))
        try handle.close()

        (journal, opened) = try open()
        XCTAssertEqual(opened.document.numbers, [1, 2])
        XCTAssertEqual(opened.skipped, 1)
        sheet = opened.document
        history = opened.history
        try perform(.push(3), &history, &sheet, journal)
        journal.flush()
        (journal, opened) = try open()
        XCTAssertEqual(opened.document.numbers, [1, 2, 3])
        XCTAssertEqual(opened.skipped, 0)
    }

    func testCheckpointsKeepOpeningShortAndOlderUndoLoadsLazily() throws {
        var (journal, opened) = try open()
        var sheet = opened.document
        var history = opened.history
        for value in 1 ... 120 {
            try perform(.push(value), &history, &sheet, journal)
            if value.isMultiple(of: 50) { journal.checkpoint(sheet, history: history) }
        }
        journal.flush()

        (journal, opened) = try open()
        XCTAssertEqual(opened.replayed, 20)
        XCTAssertEqual(opened.document, sheet)
        history = opened.history
        sheet = opened.document
        XCTAssertEqual(history.undoStack.count, 8 + 20)
        XCTAssertEqual(journal.olderUndoCount, 92)
        var undone = 0
        while history.canUndo {
            try history.undo(on: &sheet)
            undone += 1
            if history.undoStack.count < 4, journal.olderUndoCount > 0 {
                try history.prependUndo(journal.loadOlderUndo(16))
            }
        }
        XCTAssertEqual(undone, 120)
        XCTAssertEqual(sheet.numbers, [])
    }

    func testReplayedStepsCountAgainstTheLimit() throws {
        var (journal, opened) = try HistoryJournal.open(at: folder, format: format(), historyLimit: 30) { Sheet() }
        var sheet = opened.document
        var history = opened.history
        for value in 1 ... 40 {
            try perform(.push(value), &history, &sheet, journal)
        }
        journal.checkpoint(sheet, history: history)
        for value in 41 ... 50 {
            try perform(.push(value), &history, &sheet, journal)
        }
        journal.flush()
        (journal, opened) = try HistoryJournal.open(at: folder, format: format(), historyLimit: 30) { Sheet() }
        XCTAssertEqual(opened.history.undoStack.count, 8 + 10)
        XCTAssertEqual(journal.olderUndoCount, 12)
    }

    func testGesturesAndGroupsReplayIntoTheSameSteps() throws {
        var (journal, opened) = try open()
        var sheet = opened.document
        var history = opened.history
        for title in ["a", "ab", "abc"] {
            try perform(.title(title), &history, &sheet, journal, key: "typing")
        }
        history.endCoalescing()
        history.beginGroup("Fill")
        try history.perform(.push(7), on: &sheet)
        try history.perform(.push(8), on: &sheet)
        try history.endGroup()
        journal.record(history.takePendingOps())
        journal.flush()

        (journal, opened) = try open()
        XCTAssertEqual(opened.history.undoStack.map(\.label), history.undoStack.map(\.label))
        history = opened.history
        sheet = opened.document
        try history.undo(on: &sheet)
        try history.undo(on: &sheet)
        XCTAssertEqual(sheet, Sheet(title: "new"))
    }

    func testADamagedCheckpointFallsBackToThePreviousOne() throws {
        var (journal, opened) = try open()
        var sheet = opened.document
        var history = opened.history
        try perform(.push(1), &history, &sheet, journal)
        journal.checkpoint(sheet, history: history)
        try perform(.push(2), &history, &sheet, journal)
        journal.checkpoint(sheet, history: history)
        try perform(.push(3), &history, &sheet, journal)
        journal.flush()
        try Data("garbage".utf8).write(to: folder.appendingPathComponent("checkpoint.json"))

        (journal, opened) = try open()
        XCTAssertEqual(opened.source, .backup)
        XCTAssertEqual(opened.document.numbers, [1, 2, 3])
        journal.flush()
        (journal, opened) = try open()
        XCTAssertEqual(opened.source, .checkpoint)
        XCTAssertEqual(opened.document.numbers, [1, 2, 3])
    }

    func testOlderOpsAreMigratedAndNewerHistoryIsRefused() throws {
        var (journal, opened) = try open()
        var sheet = opened.document
        var history = opened.history
        try perform(.push(4), &history, &sheet, journal)
        journal.flush()
        // Schema 2 stores every number doubled: the migration from 1 doubles old pushes ({"push": {"_0": n}}).
        let double: HistoryJournalFormat<SheetCommand>.Migration = { op in
            guard case var .object(fields) = op, case let .object(command)? = fields["command"],
                  case let .object(push)? = command["push"], case let .number(value)? = push["_0"] else { return op }
            var changed = command
            changed["push"] = .object(["_0": .number(value * 2)])
            fields["command"] = .object(changed)
            return .object(fields)
        }
        (journal, opened) = try open(format(schema: 2, migrations: [1: double]))
        XCTAssertEqual(opened.document.numbers, [8])
        XCTAssertThrowsError(try open(format(schema: 2))) { error in
            XCTAssertEqual(error as? HistoryJournalError, .missingMigration(from: 1))
        }
        _ = journal
    }

    func testVersionsAreKeptNamedAndPruned() throws {
        let (journal, _) = try open()
        var versions = journal.versions
        versions.automaticLimit = 2
        let named = try versions.save(Sheet(numbers: [1], title: "kept"), name: "Before the roof", automatic: false)
        for index in 1 ... 3 {
            try versions.save(Sheet(numbers: [index]), name: "Session \(index)", automatic: true, date: Date(timeIntervalSinceNow: Double(index)))
        }
        XCTAssertEqual(versions.list().map(\.name), ["Session 3", "Session 2", "Before the roof"])
        XCTAssertEqual(try versions.load(named.id).title, "kept")
        try versions.rename(named.id, to: "Roof")
        try versions.delete(versions.list()[0].id)
        XCTAssertEqual(versions.list().map(\.name), ["Session 2", "Roof"])
    }
}
