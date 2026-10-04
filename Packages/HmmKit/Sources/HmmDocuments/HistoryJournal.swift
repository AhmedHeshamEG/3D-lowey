import Foundation
import HmmCommands

/// How a journal reads and writes one app's documents and commands.
public struct HistoryJournalFormat<Command: EditCommand & Codable>: Sendable where Command.Target: Sendable {
    public typealias Migration = @Sendable (JSONValue) throws -> JSONValue

    /// The app's command schema, written in every segment's header.
    public var schemaVersion: Int
    /// Upgrades one recorded op (as JSON) from the schema it is keyed by to the next one.
    public var migrations: [Int: Migration]
    public var encodeDocument: @Sendable (Command.Target) throws -> Data
    public var decodeDocument: @Sendable (Data) throws -> Command.Target
    /// Undo steps read when a document opens; older ones load when undo reaches them.
    public var eagerUndo: Int

    public init(
        schemaVersion: Int, migrations: [Int: Migration] = [:], eagerUndo: Int = 64,
        encodeDocument: @escaping @Sendable (Command.Target) throws -> Data,
        decodeDocument: @escaping @Sendable (Data) throws -> Command.Target
    ) {
        self.schemaVersion = schemaVersion
        self.migrations = migrations
        self.eagerUndo = max(eagerUndo, 1)
        self.encodeDocument = encodeDocument
        self.decodeDocument = decodeDocument
    }
}

public enum HistoryJournalError: Error, Equatable, CustomStringConvertible {
    case newerThanApp(found: Int, supported: Int)
    case missingMigration(from: Int)
    case unreadable(String)

    public var description: String {
        switch self {
        case let .newerThanApp(found, supported):
            "This history was written by a newer version of the app (format \(found); this one reads up to \(supported)). Update the app."
        case let .missingMigration(from): "No way to upgrade history from format \(from)."
        case let .unreadable(file): "\(file) can't be read."
        }
    }
}

/// What opening a journal found.
public struct OpenedHistory<Command: EditCommand>: Sendable where Command.Target: Sendable {
    public enum Source: Sendable, Equatable {
        /// The latest checkpoint and its tail.
        case checkpoint
        /// The checkpoint was damaged; the one before it and a longer tail were used.
        case backup
        /// No journal yet: the document came from the app's own files and the journal starts now.
        case fresh
    }

    public var document: Command.Target
    /// The undo history as it was, recording into the journal again.
    public var history: CommandStack<Command>
    /// Ops replayed on top of the checkpoint (what a killed app hadn't checkpointed yet).
    public var replayed: Int
    /// Ops at the end of the journal that couldn't be read or applied (a write cut short); they are left out.
    public var skipped: Int
    public var source: Source
}

/// The history journal of one document (CONTEXT §5): every committed change is one JSON line, written moments after
/// it happens, so a killed app loses nothing; checkpoints keep opening fast; undo survives a relaunch.
///
///     <journal folder>/
///       checkpoint.json        {format, seq, segment, undo: [ref], redo: [ref]}   (+ .bak, the one before)
///       snapshots/<n>.json     the document at checkpoint n (the app's own file format)
///       segments/<n>.jsonl     a header line, then {"seq", "t", "op"} per change since checkpoint n
///       entries/<n>.jsonl      undo steps first stored by checkpoint n, read by offset when undo reaches them
///       base.json              the document when the journal began (where a time-lapse starts)
///       versions/              named and automatic versions (`HistoryVersions`)
///
/// Writes run on a serial queue: changes are group-committed within 50 ms, checkpoints encode the document there too.
/// Segments are never deleted: together they are the whole making-of.
public final class HistoryJournal<Command: EditCommand & Codable>: @unchecked Sendable where Command.Target: Sendable {
    // @unchecked Sendable: `files` and `state` are touched only on `queue`; `buffer` and `flushScheduled` only under
    // `lock`; `format`, `url` and `limit` are immutable.
    public static var formatVersion: Int { 1 }

    public let url: URL
    public let format: HistoryJournalFormat<Command>
    public let versions: HistoryVersions<Command.Target>
    let limit: Int
    let queue = DispatchQueue(label: "studio.h.history-journal", qos: .utility)
    private let lock = NSLock()
    private var buffer: [HistoryOp<Command>] = []
    private var flushScheduled = false
    var state: JournalState
    let files: JournalFiles
    /// Reports a write that failed (the app shows it; the next checkpoint tries again).
    private let onError: @Sendable (Error) -> Void

    init(url: URL, format: HistoryJournalFormat<Command>, limit: Int, state: JournalState, onError: @escaping @Sendable (Error) -> Void) {
        self.url = url
        self.format = format
        self.limit = limit
        self.state = state
        self.onError = onError
        files = JournalFiles(url: url)
        versions = HistoryVersions(folder: url.appendingPathComponent("versions"), encode: format.encodeDocument, decode: format.decodeDocument)
    }

    // MARK: Writing

    /// Queues ops for the journal. They reach the file within 50 ms (one write for everything queued by then).
    public func record(_ ops: [HistoryOp<Command>]) {
        guard !ops.isEmpty else { return }
        lock.lock()
        buffer.append(contentsOf: ops)
        let schedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        guard schedule else { return }
        queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [self] in writeBuffer() }
    }

    /// Writes a checkpoint: the document as it is now and the undo history (stored once per step). Opening then
    /// starts here. Call it at a quiet moment (`CommandStack.isQuiet`): every 200 changes, after 5 s idle, when the
    /// app leaves the screen.
    public func checkpoint(_ document: Command.Target, history: CommandStack<Command>, completion: (@Sendable () -> Void)? = nil) {
        // The ops recorded until now belong before the checkpoint; anything recorded while it waits goes after it.
        let before = takeBuffer()
        queue.async { [self] in
            write(before)
            do {
                try writeCheckpoint(document, history: history)
            } catch {
                onError(error)
            }
            completion?()
        }
    }

    /// Waits for every queued write and pushes the files to storage (going to the background, closing).
    public func flush() {
        queue.sync {
            writeBuffer()
            try? state.segmentHandle?.synchronize()
        }
    }

    /// Changes recorded since the last checkpoint.
    public var changesSinceCheckpoint: Int {
        queue.sync { Int(state.lastSeq - state.checkpointSeq) }
    }

    // MARK: Lazy undo

    /// Undo steps older than the loaded ones, still on disk.
    public var olderUndoCount: Int {
        queue.sync { state.olderUndo.count }
    }

    /// Reads up to `count` of the newest steps that are still on disk (oldest first) and forgets their refs, so the
    /// next checkpoint stores them from the stack.
    public func loadOlderUndo(_ count: Int) throws -> [HistoryEntry<Command>] {
        try queue.sync {
            let refs = Array(state.olderUndo.suffix(count))
            let entries: [HistoryEntry<Command>] = try files.readEntries(refs)
            state.olderUndo.removeLast(refs.count)
            for (ref, entry) in zip(refs, entries) {
                state.stored[entry.id] = ref
            }
            return entries
        }
    }

    /// The labels of every undo step, oldest first, including the ones still on disk (the history scrubber).
    public func olderUndoLabels() -> [String] {
        queue.sync { state.olderUndo.map(\.label) }
    }

    /// The history was cleared: the steps on disk are no longer part of it.
    public func discardOlderUndo() {
        queue.async { [self] in state.olderUndo.removeAll() }
    }

    // MARK: Internals

    private func takeBuffer() -> [HistoryOp<Command>] {
        lock.lock()
        defer { lock.unlock() }
        let ops = buffer
        buffer.removeAll(keepingCapacity: true)
        flushScheduled = false
        return ops
    }

    private func writeBuffer() {
        write(takeBuffer())
    }

    private func write(_ ops: [HistoryOp<Command>]) {
        guard !ops.isEmpty else { return }
        do {
            try files.append(ops, state: &state)
        } catch {
            onError(error)
        }
    }

    private func writeCheckpoint(_ document: Command.Target, history: CommandStack<Command>) throws {
        let segment = state.segment + 1
        let undo = try storeRefs(history.undoStack, segment: segment)
        let redo = try storeRefs(history.redoStack, segment: segment)
        let older = Array(state.olderUndo.suffix(max(limit - history.undoStack.count, 0)))
        try files.writeSnapshot(format.encodeDocument(document), segment: segment)
        try files.startSegment(segment, schema: format.schemaVersion, state: &state)
        let checkpoint = JournalCheckpoint(
            format: Self.formatVersion, seq: state.lastSeq, segment: segment, undo: older + undo, redo: redo, saved: Date()
        )
        try files.writeCheckpoint(checkpoint)
        let previous = state.checkpointSegment
        state.checkpointSeq = state.lastSeq
        state.checkpointSegment = segment
        state.olderUndo = older
        state.stored = Dictionary((undo + redo).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        files.clean(keeping: [previous, segment], referenced: Set((checkpoint.undo + checkpoint.redo).map(\.file) + state.previousEntryFiles))
        state.previousEntryFiles = (checkpoint.undo + checkpoint.redo).map(\.file)
    }

    /// Each step's place on disk; steps not stored yet are appended to `entries/<segment>.jsonl`.
    private func storeRefs(_ entries: [HistoryEntry<Command>], segment: Int) throws -> [EntryRef] {
        var refs: [EntryRef] = []
        var fresh: [HistoryEntry<Command>] = []
        for entry in entries where state.stored[entry.id] == nil {
            fresh.append(entry)
        }
        let written = try files.appendEntries(fresh, file: segment)
        for (entry, ref) in zip(fresh, written) {
            state.stored[entry.id] = ref
        }
        for entry in entries {
            if let ref = state.stored[entry.id] { refs.append(ref) }
        }
        return refs
    }
}

/// Where an undo step lives on disk.
struct EntryRef: Codable, Hashable, Sendable {
    var id: UUID
    var file: Int
    var offset: Int
    var length: Int
    var label: String
}

struct JournalCheckpoint: Codable, Sendable {
    var format: Int
    var seq: Int64
    var segment: Int
    var undo: [EntryRef]
    var redo: [EntryRef]
    var saved: Date
}

/// The journal's bookkeeping, touched only on its queue.
struct JournalState {
    var segment: Int
    var lastSeq: Int64
    var checkpointSeq: Int64
    var checkpointSegment: Int
    var segmentHandle: FileHandle?
    var stored: [UUID: EntryRef] = [:]
    var olderUndo: [EntryRef] = []
    var previousEntryFiles: [Int] = []
}
