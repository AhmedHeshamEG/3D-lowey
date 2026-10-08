import Foundation
import HmmBrush

/// What the menus and buttons of a board do. Each is one undo step.
public extension BoardSession {
    // MARK: The selection

    mutating func selectAll() {
        selection = Set(board.items.map(\.id))
    }

    @discardableResult
    mutating func deleteSelection() -> Bool {
        let done = perform(BoardOperations.delete(selection, from: board))
        if done { selection = [] }
        return done
    }

    /// Copies of the selection, a little down and to the right, picked instead of the originals.
    @discardableResult
    mutating func duplicateSelection() -> Bool {
        var names = ids
        let result = BoardOperations.duplicate(selection, offset: Vec2(24, 24), on: board) { _ in names.next() }
        ids = names
        guard let result, perform(result.command) else { return false }
        selection = Set(result.ids)
        return true
    }

    /// The selection as something to paste (here or on another board), nil when nothing is picked.
    func copySelection() -> BoardClipboard? {
        let items = BoardOperations.copies(of: selection, offset: .zero, on: board) { $0 }
        guard !items.isEmpty else { return nil }
        let keys = Set(items.compactMap { $0.stroke?.brush })
        return BoardClipboard(items: items, brushes: board.brushes.filter { keys.contains($0.key) })
    }

    /// Pastes with the copy's middle at `point` (the finger), or a little off where it was copied from.
    @discardableResult
    mutating func paste(_ clipboard: BoardClipboard, at point: Vec2? = nil) -> Bool {
        guard let bounds = clipboard.bounds else { return false }
        let offset = point.map { $0 - bounds.center } ?? Vec2(24, 24)
        // The copies live on a board of their own for a moment, to be renamed and moved like any duplicate.
        let source = Board(items: clipboard.items)
        var names = ids
        let copies = BoardOperations.copies(of: Set(clipboard.items.map(\.id)), offset: offset, on: source) { _ in names.next() }
        ids = names
        guard perform(BoardOperations.add(copies, brushes: clipboard.brushes, label: "Paste", to: board)) else { return false }
        selection = Set(copies.map(\.id))
        tool = .select
        return true
    }

    @discardableResult
    mutating func bringSelectionToFront() -> Bool {
        perform(BoardOperations.bringToFront(board.carried(by: selection), on: board))
    }

    @discardableResult
    mutating func sendSelectionToBack() -> Bool {
        perform(BoardOperations.sendToBack(board.carried(by: selection), on: board))
    }

    /// The colour in the hand; with the Select tool it also recolours what is picked.
    mutating func setColor(_ color: BoardColor) {
        self.color = color
        if tool == .select, !selection.isEmpty {
            perform(BoardOperations.setColor(color, of: selection, on: board), coalesceKey: "colour-\(selection.sorted().joined())")
        }
    }

    // MARK: Words

    /// Sets a note's words while they are typed (one undo step for the whole edit).
    mutating func setText(_ text: String, ofNote id: String) {
        perform(BoardOperations.setText(text, ofNote: id, on: board), coalesceKey: "text-\(id)")
    }

    /// Done typing. A note left empty isn't kept.
    mutating func finishEditing() {
        guard let id = editingNote else { return }
        editingNote = nil
        history.endCoalescing()
        if board.item(id)?.note?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            perform(BoardOperations.delete([id], from: board))
        }
    }

    @discardableResult
    mutating func rename(frame id: String, to title: String) -> Bool {
        perform(BoardOperations.rename(frame: id, to: title, on: board))
    }

    // MARK: Pictures and paper

    /// Puts a stored picture on the board, its middle at `point`, no larger than 480 units on its long side.
    @discardableResult
    mutating func addPicture(asset: String, pixelSize: Vec2, at point: Vec2) -> Bool {
        let longest = max(pixelSize.x, pixelSize.y, 1)
        let scale = min(480 / longest, 1)
        let rect = BoardRect(center: point, width: max(pixelSize.x * scale, 8), height: max(pixelSize.y * scale, 8))
        let id = ids.next()
        guard perform(BoardOperations.add(BoardItem(id: id, .picture(BoardPicture(asset: asset, rect: rect))), to: board)) else { return false }
        selection = [id]
        tool = .select
        return true
    }

    mutating func setPaper(_ paper: BoardPaper) {
        let wasDefaultInk = color == board.paper.ink
        guard perform(BoardOperations.setPaper(paper, on: board)) else { return }
        // Ink that was the old paper's own follows the new paper, so the next stroke still shows.
        if wasDefaultInk { color = paper.ink }
    }

    // MARK: The view

    /// Shows everything (or 100 % around the origin on an empty board). `size` is the view's, in points.
    mutating func zoomToFit(size: Vec2) {
        viewport = board.bounds().map { BoardViewport.fitting($0, size: size) } ?? BoardViewport()
    }

    /// Double-tap: the frame under the finger fills the view; anywhere else, everything does.
    mutating func frame(at point: Vec2, size: Vec2) {
        if let frame = board.frame(containing: point) {
            viewport = BoardViewport.fitting(frame.bounds, size: size)
        } else {
            zoomToFit(size: size)
        }
    }

    // MARK: Pinning and sharing

    /// What a pin or a shared picture of `id` shows: a frame is its own area and title; anything else is the
    /// selection it belongs to (or itself) with a little room; nil means the whole board.
    func excerpt(of id: String?) -> BoardExcerpt? {
        if let id, let frame = board.item(id)?.frame {
            return BoardExcerpt(rect: frame.rect, title: frame.title, items: board.carried(by: [id]))
        }
        let ids: Set<String> = id.map { selection.contains($0) ? selection : [$0] } ?? Set(board.items.map(\.id))
        let all = board.carried(by: ids)
        guard let bounds = board.bounds(of: all) else { return nil }
        let name = board.items.filter { all.contains($0.id) }.compactMap { $0.note?.text }.first { !$0.isEmpty } ?? ""
        return BoardExcerpt(rect: bounds.expanded(by: 16), title: String(name.prefix(40)), items: all)
    }
}

/// A part of the board to picture: the area, a name for it, and the items it holds.
public struct BoardExcerpt: Hashable, Sendable {
    public var rect: BoardRect
    public var title: String
    public var items: Set<String>

    public init(rect: BoardRect, title: String, items: Set<String>) {
        self.rect = rect
        self.title = title
        self.items = items
    }
}
