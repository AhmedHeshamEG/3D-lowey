import Foundation
import HmmBrush
import HmmCommands

/// One primitive change to a board. Each has an exact inverse.
public enum BoardEdit: Hashable, Sendable {
    /// Items at the positions they take in the final order (ascending).
    case insert([Placed])
    case remove([String])
    /// Items replaced by new versions with the same ids.
    case replace([BoardItem])
    /// The whole back-to-front order, by id.
    case order([String])
    /// Brushes added to (or replaced in) the board's frozen copies; nil removes one.
    case brushes([String: Brush?])
    case paper(BoardPaper)

    public struct Placed: Hashable, Sendable, Codable {
        public var item: BoardItem
        public var index: Int

        public init(_ item: BoardItem, at index: Int) {
            self.item = item
            self.index = index
        }
    }
}

extension BoardEdit: Codable {
    private enum Key: String, CodingKey { case edit, items, ids, brushes, paper }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .edit) {
        case "insert": self = try .insert(c.decode([Placed].self, forKey: .items))
        case "remove": self = try .remove(c.decode([String].self, forKey: .ids))
        case "replace": self = try .replace(c.decode([BoardItem].self, forKey: .items))
        case "order": self = try .order(c.decode([String].self, forKey: .ids))
        case "brushes": self = try .brushes(c.decode([String: Brush?].self, forKey: .brushes))
        case "paper": self = try .paper(c.decode(BoardPaper.self, forKey: .paper))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .edit, in: c, debugDescription: "Unknown board edit \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .insert(items):
            try c.encode("insert", forKey: .edit)
            try c.encode(items, forKey: .items)
        case let .remove(ids):
            try c.encode("remove", forKey: .edit)
            try c.encode(ids, forKey: .ids)
        case let .replace(items):
            try c.encode("replace", forKey: .edit)
            try c.encode(items, forKey: .items)
        case let .order(ids):
            try c.encode("order", forKey: .edit)
            try c.encode(ids, forKey: .ids)
        case let .brushes(brushes):
            try c.encode("brushes", forKey: .edit)
            try c.encode(brushes, forKey: .brushes)
        case let .paper(paper):
            try c.encode("paper", forKey: .edit)
            try c.encode(paper, forKey: .paper)
        }
    }
}

public enum BoardError: Error, Equatable, CustomStringConvertible {
    case missing(String)
    case duplicate(String)
    case badOrder

    public var description: String {
        switch self {
        case let .missing(id): "There's no item \(id) on the board."
        case let .duplicate(id): "The board already has an item \(id)."
        case .badOrder: "The new order doesn't list the board's items."
        }
    }
}

/// What a command touched, so the canvas redraws only what it must.
public struct BoardChanges: Hashable, Sendable {
    /// Items that are new, gone or different.
    public var ids: Set<String> = []
    /// Strokes and other items laid on top of everything, in order, when that is all that happened (the canvas
    /// can draw them over what it has).
    public var appended: [String] = []
    /// Anything else changed: order, removals, edits, the paper.
    public var rebuild = false

    public init() {}

    public var isEmpty: Bool { ids.isEmpty && !rebuild }

    public mutating func merge(_ other: BoardChanges) {
        ids.formUnion(other.ids)
        rebuild = rebuild || other.rebuild
        appended = rebuild ? [] : appended + other.appended
    }
}

/// A reversible edit of a board: one or more primitive changes under one name ("Draw", "Move", "Delete").
public struct BoardCommand: EditCommand, Codable, Hashable {
    public var label: String
    public var edits: [BoardEdit]

    public init(_ label: String, _ edits: [BoardEdit]) {
        self.label = label
        self.edits = edits
    }

    public var isEmpty: Bool { edits.isEmpty }

    public func apply(to target: inout Board) throws -> (inverse: BoardCommand, changes: BoardChanges) {
        var board = target
        var inverses: [BoardEdit] = []
        var changes = BoardChanges()
        for edit in edits {
            let (inverse, changed) = try Self.apply(edit, to: &board)
            inverses.append(inverse)
            changes.merge(changed)
        }
        target = board
        return (BoardCommand(label, inverses.reversed()), changes)
    }

    public static func group(_ label: String, _ commands: [BoardCommand]) -> BoardCommand {
        BoardCommand(label, commands.flatMap(\.edits))
    }

    // A gesture that keeps replacing the same items (dragging a slider over a note's colour) keeps only its last
    // state going forward and its first going back, not every step between.
    public static func coalesced(_ first: BoardCommand, _ second: BoardCommand) -> BoardCommand {
        first.replacesSameItems(as: second) ? second : group(second.label, [first, second])
    }

    public static func coalescedInverse(earlier: BoardCommand, later: BoardCommand) -> BoardCommand {
        earlier.replacesSameItems(as: later) ? earlier : group(earlier.label, [later, earlier])
    }

    func replacesSameItems(as other: BoardCommand) -> Bool {
        guard edits.count == 1, other.edits.count == 1, case let .replace(mine) = edits[0], case let .replace(theirs) = other.edits[0] else {
            return false
        }
        return mine.map(\.id) == theirs.map(\.id)
    }

    // MARK: Primitive edits

    static func apply(_ edit: BoardEdit, to board: inout Board) throws -> (BoardEdit, BoardChanges) {
        var changes = BoardChanges()
        switch edit {
        case let .insert(placed):
            return try insert(placed, into: &board)
        case let .remove(ids):
            return try remove(ids, from: &board)
        case let .replace(items):
            var old: [BoardItem] = []
            for item in items {
                guard let index = board.index(of: item.id) else { throw BoardError.missing(item.id) }
                old.append(board.items[index])
                board.items[index] = item
            }
            changes.ids = Set(items.map(\.id))
            changes.rebuild = true
            return (.replace(old.reversed()), changes)
        case let .order(ids):
            let before = board.items.map(\.id)
            guard Set(ids) == Set(before), ids.count == before.count else { throw BoardError.badOrder }
            let byID = Dictionary(uniqueKeysWithValues: board.items.map { ($0.id, $0) })
            board.items = ids.compactMap { byID[$0] }
            changes.rebuild = true
            return (.order(before), changes)
        case let .brushes(brushes):
            var old: [String: Brush?] = [:]
            for (key, brush) in brushes {
                old[key] = .some(board.brushes[key])
                board.brushes[key] = brush
            }
            // Brushes arrive with the strokes that name them; alone they change nothing on screen.
            return (.brushes(old), changes)
        case let .paper(paper):
            let before = board.paper
            board.paper = paper
            changes.rebuild = true
            return (.paper(before), changes)
        }
    }

    private static func insert(_ placed: [BoardEdit.Placed], into board: inout Board) throws -> (BoardEdit, BoardChanges) {
        var changes = BoardChanges()
        let start = board.items.count
        for entry in placed.sorted(by: { $0.index < $1.index }) {
            guard board.index(of: entry.item.id) == nil else { throw BoardError.duplicate(entry.item.id) }
            board.items.insert(entry.item, at: min(max(entry.index, 0), board.items.count))
        }
        changes.ids = Set(placed.map(\.item.id))
        // On top of everything, in order: nothing under them needs redrawing.
        let onTop = placed.sorted(by: { $0.index < $1.index }).enumerated().allSatisfy { $0.element.index >= start + $0.offset }
        if onTop {
            changes.appended = placed.sorted(by: { $0.index < $1.index }).map(\.item.id)
        } else {
            changes.rebuild = true
        }
        return (.remove(placed.map(\.item.id)), changes)
    }

    private static func remove(_ ids: [String], from board: inout Board) throws -> (BoardEdit, BoardChanges) {
        var changes = BoardChanges()
        var taken: [BoardEdit.Placed] = []
        let wanted = Set(ids)
        for id in ids where board.index(of: id) == nil {
            throw BoardError.missing(id)
        }
        // Positions as they are in the board before anything leaves: inserting them back in ascending order puts
        // every item where it was.
        for (index, item) in board.items.enumerated() where wanted.contains(item.id) {
            taken.append(BoardEdit.Placed(item, at: index))
        }
        board.items.removeAll { wanted.contains($0.id) }
        changes.ids = wanted
        changes.rebuild = true
        return (.insert(taken), changes)
    }
}
