import Foundation
import HmmCommands

/// The journal's files. Used only on the journal's queue (or while opening, before the journal exists).
struct JournalFiles: Sendable {
    static let checkpointFile = "checkpoint.json"
    static let baseFile = "base.json"

    let url: URL

    var checkpointURL: URL { url.appendingPathComponent(Self.checkpointFile) }
    var baseURL: URL { url.appendingPathComponent(Self.baseFile) }

    func snapshotURL(_ segment: Int) -> URL { folder("snapshots").appendingPathComponent("\(Self.name(segment)).json") }
    func segmentURL(_ segment: Int) -> URL { folder("segments").appendingPathComponent("\(Self.name(segment)).jsonl") }
    func entriesURL(_ file: Int) -> URL { folder("entries").appendingPathComponent("\(Self.name(file)).jsonl") }

    static func name(_ number: Int) -> String {
        let digits = String(number)
        return String(repeating: "0", count: max(6 - digits.count, 0)) + digits
    }

    private func folder(_ name: String) -> URL { url.appendingPathComponent(name, isDirectory: true) }

    /// One line of JSON per value: compact, dates as reference-date seconds like every hmm. file.
    static func lineEncoder() -> JSONEncoder {
        let encoder = HmmJSON.encoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    // MARK: Segments

    struct Header: Codable {
        var journal: Int
        var schema: Int
        var segment: Int
    }

    struct Line<Command: EditCommand & Codable>: Codable {
        var seq: Int64
        var t: Date
        var op: HistoryOp<Command>
    }

    /// Creates `segments/<n>.jsonl` with its header and makes it the one being appended to.
    func startSegment(_ segment: Int, schema: Int, state: inout JournalState) throws {
        let file = segmentURL(segment)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let header = try Self.lineEncoder().encode(Header(journal: 1, schema: schema, segment: segment))
        try (header + Data([0x0A])).write(to: file, options: .atomic)
        try? state.segmentHandle?.close()
        state.segmentHandle = try FileHandle(forWritingTo: file)
        try state.segmentHandle?.seekToEnd()
        state.segment = segment
    }

    /// Appends ops to the current segment, one line each, numbered after the last one.
    func append<Command: EditCommand & Codable>(_ ops: [HistoryOp<Command>], state: inout JournalState) throws {
        guard let handle = state.segmentHandle else { return }
        let encoder = Self.lineEncoder()
        var data = Data()
        let now = Date()
        for op in ops {
            state.lastSeq += 1
            try data.append(encoder.encode(Line(seq: state.lastSeq, t: now, op: op)))
            data.append(0x0A)
        }
        try handle.write(contentsOf: data)
    }

    /// The segments from `first` on, in order.
    func segments(from first: Int) -> [Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder("segments").path)) ?? []
        return names.compactMap { name in name.hasSuffix(".jsonl") ? Int(name.dropLast(6)) : nil }
            .filter { $0 >= first }
            .sorted()
    }

    /// Cuts a line left half-written by a killed app, so the next append starts on a fresh line.
    func trimPartialLine(_ segment: Int) throws {
        let file = segmentURL(segment)
        guard let data = try? Data(contentsOf: file), let last = data.last, last != 0x0A else { return }
        let keep = (data.lastIndex(of: 0x0A).map { $0 + 1 }) ?? 0
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(keep))
        try handle.close()
    }

    // MARK: Checkpoints and snapshots

    func writeSnapshot(_ data: Data, segment: Int) throws {
        try SafeFileWriter.write(data, to: snapshotURL(segment), keepBackup: false)
        if !FileManager.default.fileExists(atPath: baseURL.path) {
            try SafeFileWriter.write(data, to: baseURL, keepBackup: false)
        }
    }

    func writeCheckpoint(_ checkpoint: JournalCheckpoint) throws {
        try SafeFileWriter.write(HmmJSON.encode(checkpoint), to: checkpointURL)
    }

    /// Removes snapshots other than `keeping` and entry files nothing refers to.
    func clean(keeping snapshots: Set<Int>, referenced entries: Set<Int>) {
        let fileManager = FileManager.default
        for (name, keep) in [("snapshots", snapshots), ("entries", entries)] {
            let names = (try? fileManager.contentsOfDirectory(atPath: folder(name).path)) ?? []
            for file in names {
                guard let number = Int(file.split(separator: ".").first ?? ""), !keep.contains(number) else { continue }
                try? fileManager.removeItem(at: folder(name).appendingPathComponent(file))
            }
        }
    }

    // MARK: Undo steps

    /// Appends steps to `entries/<file>.jsonl` and returns where each one landed.
    func appendEntries<Command: EditCommand & Codable>(_ entries: [HistoryEntry<Command>], file: Int) throws -> [EntryRef] {
        guard !entries.isEmpty else { return [] }
        let target = entriesURL(file)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: target.path) {
            try Data().write(to: target)
        }
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        var offset = try Int(handle.seekToEnd())
        let encoder = Self.lineEncoder()
        var data = Data()
        var refs: [EntryRef] = []
        for entry in entries {
            let line = try encoder.encode(entry)
            refs.append(EntryRef(id: entry.id, file: file, offset: offset, length: line.count, label: entry.label))
            data.append(line)
            data.append(0x0A)
            offset += line.count + 1
        }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        return refs
    }

    /// Reads steps by their refs (one open per file).
    func readEntries<Command: EditCommand & Codable>(_ refs: [EntryRef]) throws -> [HistoryEntry<Command>] {
        var handles: [Int: FileHandle] = [:]
        defer { handles.values.forEach { try? $0.close() } }
        let decoder = HmmJSON.decoder()
        return try refs.map { ref in
            let handle = try handles[ref.file] ?? FileHandle(forReadingFrom: entriesURL(ref.file))
            handles[ref.file] = handle
            try handle.seek(toOffset: UInt64(ref.offset))
            guard let data = try handle.read(upToCount: ref.length), data.count == ref.length else {
                throw HistoryJournalError.unreadable(entriesURL(ref.file).lastPathComponent)
            }
            return try decoder.decode(HistoryEntry<Command>.self, from: data)
        }
    }
}
