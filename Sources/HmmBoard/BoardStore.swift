import Foundation
import HmmBrush
import HmmCommands
import HmmDocuments

/// A board on disk: a folder any document package can hold.
///
///     board.json     the board (a versioned envelope)
///     view.json      where the person was looking (not part of the history)
///     history/       the history journal: every change, undo that survives a relaunch
///     assets/        pictures, by content name
///
/// Nothing is written until the board is first opened, so a document that never uses its board carries none.
public struct BoardStore: Sendable {
    public static let schemaVersion = 1
    public static let kind = "board"
    public static let boardFile = "board.json"
    public static let viewFile = "view.json"
    public static let historyFolder = "history"
    public static let assetsFolder = "assets"

    public let folder: URL
    let coder: SchemaCoder

    /// `appName` is who a "made by a newer version" message names.
    public init(folder: URL, appName: String) {
        self.folder = folder
        coder = SchemaCoder(appName: appName, currentVersion: Self.schemaVersion, migrations: [])
    }

    public var boardURL: URL { folder.appendingPathComponent(Self.boardFile) }
    public var viewURL: URL { folder.appendingPathComponent(Self.viewFile) }
    public var historyURL: URL { folder.appendingPathComponent(Self.historyFolder, isDirectory: true) }
    public var assetsURL: URL { folder.appendingPathComponent(Self.assetsFolder, isDirectory: true) }

    /// Whether this document has a board yet.
    public var exists: Bool { FileManager.default.fileExists(atPath: boardURL.path) }

    // MARK: The board

    /// The saved board (an empty one when there is none yet).
    public func load() throws -> Board {
        guard exists else { return Board() }
        var board = Board()
        _ = try SafeFileWriter.read(boardURL) { data in
            board = try coder.decode(Board.self, kind: Self.kind, from: data)
        }
        return board
    }

    public func save(_ board: Board) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try SafeFileWriter.write(coder.encode(board, kind: Self.kind), to: boardURL)
    }

    // MARK: The view

    public func loadView() -> BoardViewport? {
        guard let data = try? Data(contentsOf: viewURL) else { return nil }
        return try? HmmJSON.decode(BoardViewport.self, from: data)
    }

    public func saveView(_ viewport: BoardViewport) {
        guard exists, let data = try? HmmJSON.encode(viewport) else { return }
        try? data.write(to: viewURL, options: .atomic)
    }

    // MARK: History

    /// Opens the board with its history: the latest checkpoint and every change after it, the undo stack rebuilt.
    /// Synchronous file IO: call it off the main thread.
    public func open(historyLimit: Int = 500, onError: @escaping @Sendable (Error) -> Void = { _ in })
        throws -> (journal: HistoryJournal<BoardCommand>, opened: OpenedHistory<BoardCommand>) {
        let coder = coder
        let format = HistoryJournalFormat<BoardCommand>(
            schemaVersion: Self.schemaVersion,
            encodeDocument: { try coder.encode($0, kind: Self.kind) },
            decodeDocument: { try coder.decode(Board.self, kind: Self.kind, from: $0) }
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try HistoryJournal.open(at: historyURL, format: format, historyLimit: historyLimit, onError: onError) { try load() }
    }

    // MARK: Pictures

    /// Stores a picture under a name made from its bytes (the same picture is the same file) and returns the name.
    public func storeAsset(_ data: Data, fileExtension: String) throws -> String {
        let cleaned = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        let name = "\(BrushKey.hex(BrushKey.fnv(data))).\(cleaned.isEmpty ? "png" : cleaned)"
        let url = assetURL(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return name
    }

    /// Where a picture's file is. Names never leave the assets folder.
    public func assetURL(_ name: String) -> URL {
        assetsURL.appendingPathComponent((name as NSString).lastPathComponent)
    }
}
