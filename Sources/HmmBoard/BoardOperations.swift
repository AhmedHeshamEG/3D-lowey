import Foundation
import HmmBrush

/// Everything a person does to a board, as commands. Nothing here changes a board: each function reads it and
/// returns the command to perform (nil when there is nothing to do), so every change is one undo step.
public enum BoardOperations {
    // MARK: Making

    /// A new stroke on top, with its brush frozen into the board the first time it's used.
    public static func addStroke(_ path: BrushPath<Vec2>, brush: Brush, color: BoardColor, seed: UInt64, id: String,
                                 on board: Board) -> BoardCommand? {
        guard !path.points.isEmpty else { return nil }
        let key = BrushKey.key(for: brush)
        var edits: [BoardEdit] = []
        if board.brushes[key] == nil {
            var frozen = brush.clamped
            frozen.id = key
            edits.append(.brushes([key: frozen]))
        }
        let stroke = BoardStroke(path: path, color: color, brush: key, seed: seed)
        edits.append(.insert([.init(BoardItem(id: id, .stroke(stroke)), at: board.items.count)]))
        return BoardCommand("Draw", edits)
    }

    /// Any other new item, on top (frames go to the back: they sit behind what they hold).
    public static func add(_ item: BoardItem, to board: Board) -> BoardCommand {
        let index = item.frame == nil ? board.items.count : 0
        return BoardCommand("Add \(name(of: item.kind))", [.insert([.init(item, at: index)])])
    }

    /// Items from the clipboard or a duplicate, on top, with any brushes they bring.
    public static func add(_ items: [BoardItem], brushes: [String: Brush] = [:], label: String, to board: Board) -> BoardCommand? {
        guard !items.isEmpty else { return nil }
        var edits: [BoardEdit] = []
        let missing = brushes.filter { board.brushes[$0.key] == nil }
        if !missing.isEmpty { edits.append(.brushes(missing.mapValues { Optional($0) })) }
        edits.append(.insert(items.enumerated().map { .init($0.element, at: board.items.count + $0.offset) }))
        return BoardCommand(label, edits)
    }

    static func name(of kind: BoardItem.Kind) -> String {
        switch kind {
        case .stroke: "Stroke"
        case .picture: "Picture"
        case .note: "Note"
        case .arrow: "Arrow"
        case .frame: "Frame"
        }
    }

    // MARK: Changing

    public static func delete(_ ids: Set<String>, from board: Board) -> BoardCommand? {
        let all = board.carried(by: ids)
        let present = board.items.map(\.id).filter(all.contains)
        guard !present.isEmpty else { return nil }
        var edits: [BoardEdit] = []
        // Arrows tied to something that goes stay where they point, untied.
        let untied = board.items.compactMap { item -> BoardItem? in
            guard !all.contains(item.id), var arrow = item.arrow else { return nil }
            let before = arrow
            if let from = arrow.fromItem, all.contains(from) { arrow.fromItem = nil }
            if let to = arrow.toItem, all.contains(to) { arrow.toItem = nil }
            return arrow == before ? nil : BoardItem(id: item.id, .arrow(arrow))
        }
        if !untied.isEmpty { edits.append(.replace(untied)) }
        edits.append(.remove(present))
        return BoardCommand("Delete", edits)
    }

    /// Copies of `ids` (and what their frames carry), moved by `offset`. `newID` names each copy; arrows between
    /// copies point at the copies.
    public static func duplicate(_ ids: Set<String>, offset: Vec2, on board: Board,
                                 newID: (String) -> String) -> (command: BoardCommand, ids: [String])? {
        let copies = copies(of: ids, offset: offset, on: board, newID: newID)
        guard let command = add(copies, label: "Duplicate", to: board) else { return nil }
        return (command, copies.map(\.id))
    }

    /// The items a copy takes (frames with their contents), renamed and moved, arrows re-tied among themselves.
    public static func copies(of ids: Set<String>, offset: Vec2, on board: Board, newID: (String) -> String) -> [BoardItem] {
        let all = board.carried(by: ids)
        let originals = board.items.filter { all.contains($0.id) }
        var names: [String: String] = [:]
        for item in originals {
            names[item.id] = newID(item.id)
        }
        let move = BoardTransform(movingBy: offset)
        return originals.map { item in
            var copy = item.transformed(by: move)
            copy.id = names[item.id] ?? item.id
            if var arrow = copy.arrow {
                arrow.fromItem = arrow.fromItem.flatMap { names[$0] }
                arrow.toItem = arrow.toItem.flatMap { names[$0] }
                copy.content = .arrow(arrow)
            }
            return copy
        }
    }

    public static func setText(_ text: String, ofNote id: String, on board: Board) -> BoardCommand? {
        guard var note = board.item(id)?.note, note.text != text else { return nil }
        note.text = text
        return BoardCommand("Edit Note", [.replace([BoardItem(id: id, .note(note))])])
    }

    public static func rename(frame id: String, to title: String, on board: Board) -> BoardCommand? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var frame = board.item(id)?.frame, !trimmed.isEmpty, frame.title != trimmed else { return nil }
        frame.title = trimmed
        return BoardCommand("Rename Frame", [.replace([BoardItem(id: id, .frame(frame))])])
    }

    /// Strokes, arrows and notes take the colour; pictures and frames have none.
    public static func setColor(_ color: BoardColor, of ids: Set<String>, on board: Board) -> BoardCommand? {
        let changed = board.items.compactMap { item -> BoardItem? in
            guard ids.contains(item.id) else { return nil }
            var copy = item
            switch item.content {
            case var .stroke(stroke):
                stroke.color = color
                copy.content = .stroke(stroke)
            case var .arrow(arrow):
                arrow.color = color
                copy.content = .arrow(arrow)
            case var .note(note):
                note.color = color
                copy.content = .note(note)
            case .picture, .frame:
                return nil
            }
            return copy == item ? nil : copy
        }
        return changed.isEmpty ? nil : BoardCommand("Colour", [.replace(changed)])
    }

    public static func setPaper(_ paper: BoardPaper, on board: Board) -> BoardCommand? {
        board.paper == paper ? nil : BoardCommand("Paper", [.paper(paper)])
    }

    // MARK: Order

    public static func bringToFront(_ ids: Set<String>, on board: Board) -> BoardCommand? {
        reorder(board, label: "Bring to Front") { order in order.filter { !ids.contains($0) } + order.filter(ids.contains) }
    }

    public static func sendToBack(_ ids: Set<String>, on board: Board) -> BoardCommand? {
        reorder(board, label: "Send to Back") { order in order.filter(ids.contains) + order.filter { !ids.contains($0) } }
    }

    private static func reorder(_ board: Board, label: String, _ change: ([String]) -> [String]) -> BoardCommand? {
        let before = board.items.map(\.id)
        let after = change(before)
        return after == before ? nil : BoardCommand(label, [.order(after)])
    }

    // MARK: Moving, resizing, erasing

    /// Moves or resizes `ids` and what their frames carry. Arrows tied to something that moves follow with that
    /// end, even when they aren't picked themselves.
    public static func transform(_ ids: Set<String>, by transform: BoardTransform, on board: Board) -> BoardCommand? {
        let all = board.carried(by: ids)
        guard !all.isEmpty, transform.from != transform.to else { return nil }
        let changed = board.items.compactMap { item -> BoardItem? in
            if all.contains(item.id) { return item.transformed(by: transform) }
            guard var arrow = item.arrow else { return nil }
            let before = arrow
            if let from = arrow.fromItem, all.contains(from) { arrow.from = transform.apply(arrow.from) }
            if let to = arrow.toItem, all.contains(to) { arrow.to = transform.apply(arrow.to) }
            return arrow == before ? nil : BoardItem(id: item.id, .arrow(arrow))
        }
        guard !changed.isEmpty else { return nil }
        return BoardCommand(transform.isMove ? "Move" : "Resize", [.replace(changed)])
    }

    /// What `transform` shows while a drag is still going: the items as they would land, without a command.
    public static func preview(_ ids: Set<String>, by transform: BoardTransform, on board: Board) -> [BoardItem] {
        guard let command = BoardOperations.transform(ids, by: transform, on: board), case let .replace(items)? = command.edits.first else {
            return []
        }
        return items
    }

    /// An eraser of `radius` passing from `a` to `b`: strokes it crosses are cut where it touched (the pieces stay
    /// where the stroke was in the order). Only ink is erased; pictures, notes, arrows and frames are deleted whole,
    /// by choice.
    public static func erase(from a: Vec2, to b: Vec2, radius: Double, on board: Board, newID: () -> String) -> BoardCommand? {
        let swept = BoardRect(a, b).expanded(by: radius)
        var removed: [String] = []
        var inserted: [BoardEdit.Placed] = []
        var index = 0
        for item in board.items {
            guard let stroke = item.stroke, item.bounds.intersects(swept), let pieces = stroke.erased(from: a, to: b, radius: radius) else {
                index += 1
                continue
            }
            removed.append(item.id)
            for piece in pieces {
                inserted.append(.init(BoardItem(id: newID(), .stroke(piece)), at: index))
                index += 1
            }
        }
        guard !removed.isEmpty else { return nil }
        return BoardCommand("Erase", inserted.isEmpty ? [.remove(removed)] : [.remove(removed), .insert(inserted)])
    }
}
