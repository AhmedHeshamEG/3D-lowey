import Foundation
import HmmCommands

public extension HistoryJournal {
    /// Opens (or starts) the journal in `url`: the latest checkpoint, the undo history it stored, then every change
    /// recorded after it, replayed. Without a journal the document comes from `fresh` (the app's own files) and the
    /// journal starts from it. Synchronous file IO: open documents off the main thread.
    static func open(
        at url: URL, format: HistoryJournalFormat<Command>, historyLimit: Int = 500,
        onError: @escaping @Sendable (Error) -> Void = { _ in },
        fresh: () throws -> Command.Target
    ) throws -> (journal: HistoryJournal, opened: OpenedHistory<Command>) {
        let files = JournalFiles(url: url)
        var history = CommandStack<Command>(limit: historyLimit)
        guard let (checkpoint, document, usedBackup) = try readCheckpoint(files, format: format) else {
            let document = try fresh()
            let journal = try start(at: url, format: format, limit: historyLimit, onError: onError, document: document)
            history.recordsOps = true
            return (journal, OpenedHistory(document: document, history: history, replayed: 0, skipped: 0, source: .fresh))
        }
        var state = JournalState(
            segment: checkpoint.segment, lastSeq: checkpoint.seq, checkpointSeq: checkpoint.seq, checkpointSegment: checkpoint.segment
        )
        let eager = Array(checkpoint.undo.suffix(format.eagerUndo))
        state.olderUndo = Array(checkpoint.undo.dropLast(eager.count))
        state.previousEntryFiles = (checkpoint.undo + checkpoint.redo).map(\.file)
        let undo: [HistoryEntry<Command>] = try files.readEntries(eager)
        let redo: [HistoryEntry<Command>] = try files.readEntries(checkpoint.redo)
        for (ref, entry) in zip(eager + checkpoint.redo, undo + redo) {
            state.stored[entry.id] = ref
        }
        history.restore(undo: undo, redo: redo)
        var target = document
        let tail = try replayTail(files, format: format, after: checkpoint, history: &history, document: &target, state: &state)
        // Steps replayed on top count against the limit: the oldest ones still on disk fall off first.
        state.olderUndo = Array(state.olderUndo.suffix(max(historyLimit - history.undoStack.count, 0)))
        let journal = HistoryJournal(url: url, format: format, limit: historyLimit, state: state, onError: onError)
        try journal.resume(at: tail.lastSegment, damaged: tail.skipped > 0 || usedBackup)
        history.recordsOps = true
        if tail.skipped > 0 || usedBackup {
            journal.checkpoint(target, history: history)
        }
        let opened = OpenedHistory(
            document: target, history: history, replayed: tail.replayed, skipped: tail.skipped, source: usedBackup ? .backup : .checkpoint
        )
        return (journal, opened)
    }

    /// The document as it was when the journal began (a time-lapse's first frame), if it is still there.
    func baseDocument() throws -> Command.Target? {
        guard let data = try? Data(contentsOf: files.baseURL) else { return nil }
        return try format.decodeDocument(data)
    }

    // MARK: Private

    private static func start(
        at url: URL, format: HistoryJournalFormat<Command>, limit: Int, onError: @escaping @Sendable (Error) -> Void, document: Command.Target
    ) throws -> HistoryJournal {
        let files = JournalFiles(url: url)
        var state = JournalState(segment: 1, lastSeq: 0, checkpointSeq: 0, checkpointSegment: 1)
        try files.writeSnapshot(format.encodeDocument(document), segment: 1)
        try files.startSegment(1, schema: format.schemaVersion, state: &state)
        try files.writeCheckpoint(JournalCheckpoint(format: formatVersion, seq: 0, segment: 1, undo: [], redo: [], saved: Date()))
        return HistoryJournal(url: url, format: format, limit: limit, state: state, onError: onError)
    }

    /// Reopens the last segment for appending (after cutting any half-written line).
    private func resume(at segment: Int, damaged: Bool) throws {
        try queue.sync {
            try files.trimPartialLine(segment)
            state.segment = segment
            let file = files.segmentURL(segment)
            if FileManager.default.fileExists(atPath: file.path), !damaged {
                state.segmentHandle = try FileHandle(forWritingTo: file)
                try state.segmentHandle?.seekToEnd()
            } else {
                try files.startSegment(segment + (damaged ? 1 : 0), schema: format.schemaVersion, state: &state)
            }
        }
    }

    /// The checkpoint and its document; the previous checkpoint (`.bak`) when the latest one can't be read.
    private static func readCheckpoint(
        _ files: JournalFiles, format: HistoryJournalFormat<Command>
    ) throws -> (JournalCheckpoint, Command.Target, Bool)? {
        let backup = SafeFileWriter.backupURL(for: files.checkpointURL)
        guard FileManager.default.fileExists(atPath: files.checkpointURL.path) || FileManager.default.fileExists(atPath: backup.path) else {
            return nil
        }
        var found: (JournalCheckpoint, Command.Target)?
        let result = try SafeFileWriter.read(files.checkpointURL) { data in
            let checkpoint = try HmmJSON.decode(JournalCheckpoint.self, from: data)
            guard checkpoint.format <= formatVersion else {
                throw HistoryJournalError.newerThanApp(found: checkpoint.format, supported: formatVersion)
            }
            let snapshot = try Data(contentsOf: files.snapshotURL(checkpoint.segment))
            found = try (checkpoint, format.decodeDocument(snapshot))
        }
        guard let found else { return nil }
        return (found.0, found.1, result.recoveredFromBackup)
    }

    private struct Tail {
        var replayed = 0
        var skipped = 0
        var lastSegment: Int
    }

    /// Replays every op recorded after the checkpoint, across segments. Stops at the first one that can't be read or
    /// applied (a line cut short by a killed app): what follows it is skipped.
    private static func replayTail(
        _ files: JournalFiles, format: HistoryJournalFormat<Command>, after checkpoint: JournalCheckpoint,
        history: inout CommandStack<Command>, document: inout Command.Target, state: inout JournalState
    ) throws -> Tail {
        let segments = files.segments(from: checkpoint.segment)
        var tail = Tail(lastSegment: segments.last ?? checkpoint.segment)
        let decoder = HmmJSON.decoder()
        for segment in segments {
            let lines = (try? Data(contentsOf: files.segmentURL(segment)))?.split(separator: 0x0A, omittingEmptySubsequences: true) ?? []
            guard let headerLine = lines.first else { continue }
            let header = try decoder.decode(JournalFiles.Header.self, from: Data(headerLine))
            guard header.schema <= format.schemaVersion else {
                throw HistoryJournalError.newerThanApp(found: header.schema, supported: format.schemaVersion)
            }
            for (index, line) in lines.dropFirst().enumerated() {
                do {
                    let decoded: JournalFiles.Line<Command> = try decodeLine(Data(line), schema: header.schema, format: format, decoder: decoder)
                    guard decoded.seq > checkpoint.seq else { continue }
                    try history.replay(decoded.op, on: &document)
                    state.lastSeq = decoded.seq
                    tail.replayed += 1
                } catch let error as HistoryJournalError {
                    throw error
                } catch {
                    tail.skipped = lines.count - 1 - index
                    return tail
                }
            }
        }
        return tail
    }

    private static func decodeLine(
        _ data: Data, schema: Int, format: HistoryJournalFormat<Command>, decoder: JSONDecoder
    ) throws -> JournalFiles.Line<Command> {
        guard schema < format.schemaVersion else { return try decoder.decode(JournalFiles.Line<Command>.self, from: data) }
        var json = try decoder.decode(JSONValue.self, from: data)
        guard case var .object(fields) = json, let op = fields["op"] else { return try decoder.decode(JournalFiles.Line<Command>.self, from: data) }
        var migrated = op
        for version in schema ..< format.schemaVersion {
            guard let migration = format.migrations[version] else { throw HistoryJournalError.missingMigration(from: version) }
            migrated = try migration(migrated)
        }
        fields["op"] = migrated
        json = .object(fields)
        return try decoder.decode(JournalFiles.Line<Command>.self, from: HmmJSON.encode(json))
    }
}
