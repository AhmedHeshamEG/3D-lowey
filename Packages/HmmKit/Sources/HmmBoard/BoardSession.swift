import Foundation
import HmmBrush
import HmmCommands

/// The tools of a board. Select moves and resizes; the others make.
public enum BoardTool: String, Sendable, CaseIterable, Codable {
    case select, draw, erase, note, arrow, frame
}

/// Names for new items: random by default, counted in tests.
public struct BoardIDs: Sendable {
    var counter: Int?

    public init(counted: Bool = false) {
        counter = counted ? 0 : nil
    }

    public mutating func next() -> String {
        guard let count = counter else { return UUID().uuidString }
        counter = count + 1
        return "item-\(count + 1)"
    }
}

/// What was copied: items and the brushes their strokes name.
public struct BoardClipboard: Sendable, Hashable {
    public var items: [BoardItem]
    public var brushes: [String: Brush]

    public var bounds: BoardRect? {
        items.dropFirst().reduce(items.first?.bounds) { $0?.union($1.bounds) }
    }
}

/// A board being worked on: the document with its undo history, what is selected, the tool in the hand, and the
/// stroke or drag in progress. Touches come in as board points; every finished gesture is one command. Pure state:
/// the canvas draws what it says and the app's model saves what it records.
public struct BoardSession: Sendable {
    public internal(set) var board: Board
    public internal(set) var history: CommandStack<BoardCommand>
    /// Goes up with every change to the board.
    public internal(set) var revision = 0
    var pendingChanges = BoardChanges()

    public var viewport = BoardViewport()
    public var tool: BoardTool = .draw
    public var selection: Set<String> = []
    public var brush: Brush = BuiltInBrushes.inkPen
    public var color: BoardColor
    /// The brush's radius at full pressure, the eraser's reach and an arrow's half thickness, in board units.
    public var size = 3.0
    public var opacity = 1.0
    /// The note whose words are being typed.
    public var editingNote: String?
    public var ids = BoardIDs()

    var samples: [BrushInput<Vec2>] = []
    var strokeSeed: UInt64 = 1
    var drag: Drag?
    var gesture = 0
    var lastErase: Vec2?
    /// The note a touch landed on that was already the only thing picked: lifting without moving opens it for typing.
    var tappedAgain: String?

    enum Drag: Sendable, Hashable {
        case move(from: Vec2, to: Vec2)
        case resize(handle: Int, start: BoardRect, to: Vec2)
        case marquee(from: Vec2, to: Vec2)
        case shape(from: Vec2, to: Vec2)
    }

    public init(board: Board = Board(), history: CommandStack<BoardCommand> = CommandStack()) {
        self.board = board
        self.history = history
        color = board.paper.ink
    }

    // MARK: Changing the board

    /// Performs a command (nil: nothing to do). Returns whether the board changed.
    @discardableResult
    public mutating func perform(_ command: BoardCommand?, coalesceKey: String? = nil) -> Bool {
        guard let command, !command.isEmpty, let changes = try? history.perform(command, on: &board, coalesceKey: coalesceKey) else { return false }
        note(changes)
        return true
    }

    @discardableResult
    public mutating func undo() -> Bool {
        cancel()
        guard let changes = try? history.undo(on: &board) else { return false }
        note(changes, rebuild: true)
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        cancel()
        guard let changes = try? history.redo(on: &board) else { return false }
        note(changes, rebuild: true)
        return true
    }

    mutating func note(_ changes: BoardChanges, rebuild: Bool = false) {
        revision += 1
        pendingChanges.merge(changes)
        if rebuild {
            pendingChanges.rebuild = true
            pendingChanges.appended = []
        }
        selection = selection.filter { board.item($0) != nil }
        if let editing = editingNote, board.item(editing) == nil { editingNote = nil }
    }

    /// What changed since this was last asked (the canvas redraws that much).
    public mutating func takeChanges() -> BoardChanges {
        defer { pendingChanges = BoardChanges() }
        return pendingChanges
    }

    /// The history ops to write to the journal since this was last asked.
    public mutating func takePendingOps() -> [HistoryOp<BoardCommand>] {
        history.takePendingOps()
    }

    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    // MARK: What the canvas shows

    /// The stroke under the Pencil, as it would be kept. `predicted` are samples the system guesses come next: drawn,
    /// never kept.
    public func liveStroke(predicted: [BrushInput<Vec2>] = []) -> BoardStroke? {
        guard tool == .draw, !samples.isEmpty else { return nil }
        let path = BrushStroker.path(samples + predicted, brush: brush, size: size, opacity: opacity)
        return BoardStroke(path: path, color: color, brush: nil, seed: strokeSeed)
    }

    /// Items shown where a drag would leave them (and the arrow or frame being pulled out), instead of where they
    /// are on the board.
    public var lifted: [BoardItem] {
        switch drag {
        case let .move(from, to):
            return BoardOperations.preview(selection, by: BoardTransform(movingBy: to - from), on: board)
        case let .resize(handle, start, to):
            let target = BoardShapes.resized(start, handle: handle, to: to, minimum: Self.minimumSide)
            return BoardOperations.preview(selection, by: BoardTransform(from: start, to: target), on: board)
        case let .shape(from, to):
            return pulledShape(from: from, to: to, id: "pulling").map { [$0] } ?? []
        case .marquee, nil:
            return []
        }
    }

    /// The board's items a drag is carrying (drawn from `lifted` instead).
    public var hidden: Set<String> {
        switch drag {
        case .move, .resize: Set(lifted.map(\.id))
        default: []
        }
    }

    public var marquee: BoardRect? {
        if case let .marquee(from, to) = drag { return BoardRect(from, to) }
        return nil
    }

    /// The box around the selection, where it is being dragged to.
    public var selectionBounds: BoardRect? {
        guard !selection.isEmpty, let bounds = board.bounds(of: board.carried(by: selection)) else { return nil }
        switch drag {
        case let .move(from, to): return bounds.moved(by: to - from)
        case let .resize(handle, start, to): return BoardShapes.resized(start, handle: handle, to: to, minimum: Self.minimumSide)
        default: return bounds
        }
    }

    /// Whether something is under the Pencil right now (a stroke or a drag).
    public var isBusy: Bool { !samples.isEmpty || drag != nil || lastErase != nil }

    static let minimumSide = 8.0
}
