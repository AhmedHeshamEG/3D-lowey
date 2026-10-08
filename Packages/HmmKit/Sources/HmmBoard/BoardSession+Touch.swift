import Foundation
import HmmBrush

/// The making touch (the Pencil, or a finger when fingers make): what it does depends on the tool in the hand.
/// Points are board points; `slack` is how far off a tap may land, in board units (a finger's is larger).
public extension BoardSession {
    mutating func begin(_ sample: BrushInput<Vec2>, slack: Double) {
        cancel()
        finishEditing()
        gesture += 1
        let point = sample.point
        switch tool {
        case .draw:
            samples = [sample]
            // Odd and different for every stroke: the brush's scatter never repeats from one stroke to the next.
            strokeSeed = (UInt64(truncatingIfNeeded: board.items.count &+ revision &* 31 &+ gesture) &* 0x9E37_79B9_7F4A_7C15) | 1
        case .erase:
            erase(to: point)
        case .select:
            beginSelecting(at: point, slack: slack)
        case .arrow, .frame:
            drag = .shape(from: point, to: point)
        case .note:
            break
        }
    }

    mutating func move(_ sample: BrushInput<Vec2>) {
        let point = sample.point
        switch tool {
        case .draw:
            if !samples.isEmpty { samples.append(sample) }
        case .erase:
            if lastErase != nil { erase(to: point) }
        case .select, .arrow, .frame:
            drag = drag.map { $0.moved(to: point) }
        case .note:
            break
        }
    }

    mutating func end(_ sample: BrushInput<Vec2>, slack: Double) {
        let point = sample.point
        switch tool {
        case .draw:
            endStroke(sample)
        case .erase:
            lastErase = nil
            history.endCoalescing()
        case .select:
            endSelecting(at: point, slack: slack)
        case .arrow, .frame:
            endShape(at: point, slack: slack)
        case .note:
            addNote(at: point)
        }
        samples = []
        drag = nil
    }

    /// Drops whatever is in progress without keeping it (the touch turned into a pinch, a menu opened).
    mutating func cancel() {
        samples = []
        drag = nil
        tappedAgain = nil
        if lastErase != nil {
            lastErase = nil
            history.endCoalescing()
        }
    }

    /// How far the eraser reaches around its middle, in board units.
    var eraserRadius: Double { max(size * 2.5, 4) }

    // MARK: Drawing and erasing

    private mutating func endStroke(_ last: BrushInput<Vec2>) {
        guard !samples.isEmpty else { return }
        if samples.count == 1 || samples.last?.point != last.point { samples.append(last) }
        let path = BrushStroker.path(samples, brush: brush, size: size, opacity: opacity)
        let id = ids.next()
        perform(BoardOperations.addStroke(path, brush: brush, color: color, seed: strokeSeed, id: id, on: board))
    }

    private mutating func erase(to point: Vec2) {
        let from = lastErase ?? point
        var names = ids
        let command = BoardOperations.erase(from: from, to: point, radius: eraserRadius, on: board) { names.next() }
        ids = names
        perform(command, coalesceKey: "erase-\(gesture)")
        lastErase = point
    }

    // MARK: Selecting, moving, resizing

    /// The selection's handle under a point (nil: none), as an index into `BoardShapes.handles`.
    func handle(at point: Vec2, slack: Double) -> Int? {
        guard drag == nil, let bounds = selectionBounds else { return nil }
        let handles = BoardShapes.handles(of: bounds)
        let nearest = handles.indices.min { handles[$0].distance(to: point) < handles[$1].distance(to: point) }
        guard let nearest, handles[nearest].distance(to: point) <= slack * 1.5 else { return nil }
        return nearest
    }

    private mutating func beginSelecting(at point: Vec2, slack: Double) {
        if let handle = handle(at: point, slack: slack), let bounds = selectionBounds {
            drag = .resize(handle: handle, start: bounds, to: point)
        } else if let item = board.item(at: point, tolerance: slack) {
            tappedAgain = item.note != nil && selection == [item.id] ? item.id : nil
            if !board.carried(by: selection).contains(item.id) { selection = [item.id] }
            drag = .move(from: point, to: point)
        } else if let bounds = selectionBounds, bounds.contains(point) {
            // Inside the selection's box: the whole pick moves, even from a gap between its strokes.
            drag = .move(from: point, to: point)
        } else {
            drag = .marquee(from: point, to: point)
        }
    }

    private mutating func endSelecting(at point: Vec2, slack: Double) {
        switch drag?.moved(to: point) {
        case let .move(from, to):
            guard from.distance(to: to) > slack * 0.25 else {
                // A second tap on a note opens it for typing.
                if let tappedAgain { editingNote = tappedAgain }
                return
            }
            perform(BoardOperations.transform(selection, by: BoardTransform(movingBy: to - from), on: board))
        case let .resize(handle, start, to):
            let target = BoardShapes.resized(start, handle: handle, to: to, minimum: Self.minimumSide)
            perform(BoardOperations.transform(selection, by: BoardTransform(from: start, to: target), on: board))
        case let .marquee(from, to):
            // A tap on nothing lets go of the selection; a dragged box picks what it touches.
            selection = from.distance(to: to) > slack * 0.25 ? Set(board.items(in: BoardRect(from, to)).map(\.id)) : []
        case .shape, nil:
            break
        }
    }

    // MARK: Notes, arrows, frames

    private mutating func addNote(at point: Vec2) {
        let size = BoardNote.defaultSize
        let id = ids.next()
        let note = BoardNote(rect: BoardRect(center: point, width: size.x, height: size.y))
        guard perform(BoardOperations.add(BoardItem(id: id, .note(note)), to: board)) else { return }
        selection = [id]
        editingNote = id
        tool = .select
    }

    /// The arrow or frame a drag from `from` to `to` makes (nil while it is too small to mean anything).
    internal func pulledShape(from: Vec2, to: Vec2, id: String) -> BoardItem? {
        switch tool {
        case .arrow:
            guard from.distance(to: to) > 6 else { return nil }
            let arrow = BoardArrow(from: from, to: to, color: color, width: max(size, 2), fromItem: tieable(at: from), toItem: tieable(at: to))
            return BoardItem(id: id, .arrow(arrow))
        case .frame:
            let rect = BoardRect(from, to)
            guard rect.width > 24, rect.height > 24 else { return nil }
            return BoardItem(id: id, .frame(BoardFrame(title: board.nextFrameTitle, rect: rect)))
        default:
            return nil
        }
    }

    /// What an arrow's end ties itself to: a note or a picture under it.
    private func tieable(at point: Vec2) -> String? {
        board.items.last { ($0.note != nil || $0.picture != nil) && $0.bounds.contains(point) }?.id
    }

    private mutating func endShape(at point: Vec2, slack _: Double) {
        guard case let .shape(from, _) = drag else { return }
        let id = ids.next()
        guard let item = pulledShape(from: from, to: point, id: id), perform(BoardOperations.add(item, to: board)) else { return }
        if item.frame != nil {
            selection = [id]
            tool = .select
        }
    }
}

extension BoardSession.Drag {
    func moved(to point: Vec2) -> BoardSession.Drag {
        switch self {
        case let .move(from, _): .move(from: from, to: point)
        case let .resize(handle, start, _): .resize(handle: handle, start: start, to: point)
        case let .marquee(from, _): .marquee(from: from, to: point)
        case let .shape(from, _): .shape(from: from, to: point)
        }
    }
}
