import Foundation

/// A saved state of a document: one the person named, or one the app kept on its own (each session, each hour of
/// work, the future left behind when the history scrubber restores an earlier moment).
public struct HistoryVersion: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var date: Date
    public var automatic: Bool

    public init(id: UUID = UUID(), name: String, date: Date = Date(), automatic: Bool) {
        self.id = id
        self.name = name
        self.date = date
        self.automatic = automatic
    }
}

/// The versions of one document, in `versions/`: `index.json` lists them, `<id>.json` holds each document in the
/// app's own format. Automatic versions are pruned to the newest `automaticLimit`; named ones stay until deleted.
/// Synchronous file IO: call it off the main thread.
public struct HistoryVersions<Document: Sendable>: Sendable {
    public let folder: URL
    public var automaticLimit = 40
    private let encode: @Sendable (Document) throws -> Data
    private let decode: @Sendable (Data) throws -> Document

    public init(
        folder: URL, encode: @escaping @Sendable (Document) throws -> Data, decode: @escaping @Sendable (Data) throws -> Document
    ) {
        self.folder = folder
        self.encode = encode
        self.decode = decode
    }

    private var indexURL: URL { folder.appendingPathComponent("index.json") }
    private func fileURL(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).json") }

    /// Newest first.
    public func list() -> [HistoryVersion] {
        guard let result = try? SafeFileWriter.read(indexURL, validate: { _ = try HmmJSON.decode([HistoryVersion].self, from: $0) }),
              let versions = try? HmmJSON.decode([HistoryVersion].self, from: result.data) else { return [] }
        return versions.sorted { $0.date > $1.date }
    }

    @discardableResult
    public func save(_ document: Document, name: String, automatic: Bool, date: Date = Date()) throws -> HistoryVersion {
        let version = HistoryVersion(name: name, date: date, automatic: automatic)
        try SafeFileWriter.write(encode(document), to: fileURL(version.id), keepBackup: false)
        var versions = list()
        versions.insert(version, at: 0)
        let automatic = versions.filter(\.automatic)
        let dropped = automatic.dropFirst(automaticLimit)
        versions.removeAll { version in dropped.contains { $0.id == version.id } }
        try SafeFileWriter.write(HmmJSON.encode(versions), to: indexURL)
        for version in dropped {
            try? FileManager.default.removeItem(at: fileURL(version.id))
        }
        return version
    }

    public func load(_ id: UUID) throws -> Document {
        try decode(Data(contentsOf: fileURL(id)))
    }

    public func rename(_ id: UUID, to name: String) throws {
        let versions = list().map { version in
            guard version.id == id else { return version }
            var renamed = version
            renamed.name = name
            renamed.automatic = false
            return renamed
        }
        try SafeFileWriter.write(HmmJSON.encode(versions), to: indexURL)
    }

    public func delete(_ id: UUID) throws {
        let versions = list().filter { $0.id != id }
        try SafeFileWriter.write(HmmJSON.encode(versions), to: indexURL)
        try? FileManager.default.removeItem(at: fileURL(id))
    }
}
