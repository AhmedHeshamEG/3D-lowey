import Foundation
@testable import HmmBoard
import HmmBrush
import HmmCommands
import XCTest

final class BoardSessionTests: XCTestCase {
    private func session(_ items: [BoardItem] = []) -> BoardSession {
        var session = BoardSession(board: Board(items: items))
        session.ids = BoardIDs(counted: true)
        return session
    }

    private func touch(_ x: Double, _ y: Double, pressure: Double = 1, time: Double = 0) -> BrushInput<Vec2> {
        BrushInput(point: Vec2(x, y), pressure: pressure, time: time)
    }

    /// A whole gesture: down at the first point, through the rest, up at the last.
    private func drag(_ session: inout BoardSession, _ points: [(Double, Double)], slack: Double = 6) {
        session.begin(touch(points[0].0, points[0].1), slack: slack)
        for (index, point) in points.dropFirst().enumerated() {
            session.move(touch(point.0, point.1, time: Double(index + 1) / 120))
        }
        let last = points[points.count - 1]
        session.end(touch(last.0, last.1, time: Double(points.count) / 120), slack: slack)
    }

    // MARK: Drawing

    func testAStrokeIsOneUndoStepAndIsWhatWasShown() {
        var session = session()
        XCTAssertEqual(session.color, session.board.paper.ink)
        session.begin(touch(0, 0), slack: 6)
        XCTAssertTrue(session.isBusy)
        session.move(touch(50, 0, time: 0.1))
        session.move(touch(100, 0, time: 0.2))
        let shown = session.liveStroke()
        XCTAssertNotNil(session.liveStroke(predicted: [touch(120, 0, time: 0.25)]))
        session.end(touch(100, 0, time: 0.2), slack: 6)
        XCTAssertFalse(session.isBusy)
        XCTAssertNil(session.liveStroke())
        let kept = session.board.items[0].stroke
        XCTAssertEqual(kept?.path, shown?.path, "what was drawn is what is kept")
        XCTAssertEqual(kept?.seed, shown?.seed)
        XCTAssertEqual(session.board.items[0].id, "item-1")
        let changes = session.takeChanges()
        XCTAssertEqual(changes.appended, ["item-1"])
        XCTAssertFalse(changes.rebuild)
        XCTAssertTrue(session.takeChanges().isEmpty)
        XCTAssertEqual(session.revision, 1)
        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.board.isEmpty)
        XCTAssertTrue(session.takeChanges().rebuild)
        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.board.items.count, 1)
        XCTAssertFalse(session.redo())
        XCTAssertTrue(session.canUndo)
        XCTAssertFalse(session.canRedo)
    }

    func testATapIsADotAndEveryStrokeScattersDifferently() {
        var session = session()
        drag(&session, [(10, 10)])
        drag(&session, [(30, 10)])
        XCTAssertEqual(session.board.items.count, 2)
        XCTAssertNotEqual(session.board.items[0].stroke?.seed, session.board.items[1].stroke?.seed)
        // A touch that turns into a pinch leaves nothing.
        session.begin(touch(0, 0), slack: 6)
        session.move(touch(5, 5))
        session.cancel()
        XCTAssertEqual(session.board.items.count, 2)
        session.move(touch(9, 9))
        XCTAssertNil(session.liveStroke())
    }

    func testErasingIsOneStep() {
        var session = session([stroke("a", (0 ... 20).map { (Double($0) * 10, 0.0) }, width: 1), stroke("b", [(0, 80), (200, 80)])])
        session.tool = .erase
        session.size = 2
        XCTAssertEqual(session.eraserRadius, 5)
        drag(&session, [(60, -20), (60, 20), (140, 20), (140, -20)])
        XCTAssertEqual(session.board.items.count, 4, "a is cut twice into three pieces; b is untouched")
        XCTAssertEqual(session.board.items.last?.id, "b")
        XCTAssertEqual(session.history.undoStack.count, 1)
        session.undo()
        XCTAssertEqual(session.board.items.map(\.id), ["a", "b"])
        session.begin(touch(60, 0), slack: 6)
        session.cancel()
        XCTAssertFalse(session.isBusy)
    }

    // MARK: Selecting

    func testTapPicksDragMovesAndABoxPicksSeveral() {
        var session = session([note("a", x: 0, y: 0), note("b", x: 300, y: 0), stroke("s", [(0, 300), (100, 300)])])
        session.tool = .select
        drag(&session, [(50, 50)])
        XCTAssertEqual(session.selection, ["a"])
        XCTAssertEqual(session.history.undoStack.count, 0, "a tap moves nothing")
        // Dragging it shows it lifted, then moves it in one step.
        session.begin(touch(50, 50), slack: 6)
        session.move(touch(150, 90))
        XCTAssertEqual(session.lifted.first?.note?.rect.origin, Vec2(100, 40))
        XCTAssertEqual(session.hidden, ["a"])
        XCTAssertEqual(session.selectionBounds?.origin, Vec2(100, 40))
        session.end(touch(150, 90), slack: 6)
        XCTAssertEqual(session.board.item("a")?.note?.rect.origin, Vec2(100, 40))
        XCTAssertEqual(session.hidden, [])
        XCTAssertEqual(session.lifted, [])
        // A box from empty space picks what it touches.
        session.begin(touch(320, -50), slack: 6)
        session.move(touch(600, 400))
        XCTAssertEqual(session.marquee, BoardRect(x: 320, y: -50, width: 280, height: 450))
        session.end(touch(600, 400), slack: 6)
        XCTAssertEqual(session.selection, ["b"])
        XCTAssertNil(session.marquee)
        // A tap on nothing lets go.
        drag(&session, [(900, 900)])
        XCTAssertEqual(session.selection, [])
        XCTAssertNil(session.selectionBounds)
        session.selectAll()
        XCTAssertEqual(session.selection.count, 3)
        // Inside the pick's box but between its items: the whole pick moves.
        drag(&session, [(250, 200), (260, 200)])
        XCTAssertEqual(session.board.item("b")?.note?.rect.x, 310)
        XCTAssertEqual(session.board.item("s")?.stroke?.path.points.first, Vec2(10, 300))
    }

    func testHandlesResize() throws {
        var session = session([note("a", x: 0, y: 0)])
        session.tool = .select
        session.selection = ["a"]
        XCTAssertEqual(session.handle(at: Vec2(202, 141), slack: 6), 4)
        XCTAssertNil(session.handle(at: Vec2(100, 70), slack: 6))
        session.begin(touch(200, 140), slack: 6)
        session.move(touch(400, 200))
        XCTAssertEqual(session.selectionBounds, BoardRect(x: 0, y: 0, width: 400, height: 280))
        XCTAssertEqual(session.lifted.first?.note?.rect.width, 400)
        session.end(touch(400, 200), slack: 6)
        XCTAssertEqual(session.board.item("a")?.note?.rect, BoardRect(x: 0, y: 0, width: 400, height: 280))
        XCTAssertEqual(session.history.undoLabel, "Resize")
    }

    // MARK: Notes, arrows, frames

    func testANoteIsPlacedAndTypedAndAnEmptyOneIsNotKept() {
        var session = session()
        session.tool = .note
        drag(&session, [(100, 100)])
        XCTAssertEqual(session.editingNote, "item-1")
        XCTAssertEqual(session.tool, .select)
        XCTAssertEqual(session.board.item("item-1")?.note?.rect.center, Vec2(100, 100))
        session.setText("T", ofNote: "item-1")
        session.setText("Tower", ofNote: "item-1")
        session.finishEditing()
        XCTAssertNil(session.editingNote)
        XCTAssertEqual(session.history.undoStack.count, 2, "placing, then typing as one step")
        session.undo()
        XCTAssertEqual(session.board.item("item-1")?.note?.text, "")
        session.redo()
        // Tapping the picked note again opens it; a touch anywhere else is done typing.
        drag(&session, [(100, 100)])
        XCTAssertEqual(session.editingNote, "item-1")
        drag(&session, [(900, 900)])
        XCTAssertNil(session.editingNote)
        XCTAssertEqual(session.selection, [])
        drag(&session, [(100, 100)])
        XCTAssertNil(session.editingNote, "the first tap only picks it")
        // A note nobody wrote on goes away.
        session.tool = .note
        drag(&session, [(500, 500)])
        session.finishEditing()
        XCTAssertEqual(session.board.items.count, 1)
        session.finishEditing()
        // Deleting the note being typed ends the typing.
        session.editingNote = "item-1"
        session.selection = ["item-1"]
        XCTAssertTrue(session.deleteSelection())
        XCTAssertNil(session.editingNote)
        XCTAssertFalse(session.deleteSelection())
    }

    func testArrowsTieToWhatTheyPointAtAndFramesNameThemselves() {
        var session = session([note("a", x: 0, y: 0), note("b", x: 400, y: 0)])
        session.tool = .arrow
        session.begin(touch(100, 70), slack: 6)
        session.move(touch(450, 70))
        XCTAssertEqual(session.lifted.first?.id, "pulling")
        session.end(touch(450, 70), slack: 6)
        let arrow = session.board.items.last?.arrow
        XCTAssertEqual(arrow?.fromItem, "a")
        XCTAssertEqual(arrow?.toItem, "b")
        XCTAssertEqual(session.tool, .arrow, "more arrows can follow")
        drag(&session, [(0, 500), (2, 500)])
        XCTAssertEqual(session.board.items.count, 3, "too short to be an arrow")

        session.tool = .frame
        drag(&session, [(-20, -40), (700, 300)])
        XCTAssertEqual(session.board.items.first?.frame?.title, "Frame 1")
        XCTAssertEqual(session.selection, ["item-3"])
        XCTAssertEqual(session.tool, .select)
        session.tool = .frame
        drag(&session, [(0, 0), (10, 10)])
        XCTAssertEqual(session.board.items.count, 4, "too small to be a frame")
        XCTAssertTrue(session.rename(frame: "item-3", to: "Shots"))
        XCTAssertEqual(session.excerpt(of: "item-3")?.title, "Shots")
        XCTAssertEqual(session.excerpt(of: "item-3")?.items.count, 4)
        session.tool = .note
        session.begin(touch(0, 0), slack: 6)
        session.move(touch(5, 5))
        XCTAssertEqual(session.lifted, [])
    }

    // MARK: Menus

    func testDuplicateCopyPasteAndOrder() throws {
        var session = session([note("a", x: 0, y: 0, text: "Lamp"), stroke("s", [(0, 300), (100, 300)])])
        XCTAssertNil(session.copySelection())
        XCTAssertFalse(session.duplicateSelection())
        session.selection = ["a", "s"]
        XCTAssertTrue(session.duplicateSelection())
        XCTAssertEqual(session.selection, ["item-1", "item-2"])
        XCTAssertEqual(session.board.item("item-1")?.note?.rect.origin, Vec2(24, 24))
        let clipboard = try XCTUnwrap(session.copySelection())
        XCTAssertEqual(clipboard.items.count, 2)
        XCTAssertEqual(clipboard.brushes.count, 0, "these strokes name a brush the board never had")

        var other = BoardSession()
        other.ids = BoardIDs(counted: true)
        XCTAssertTrue(other.paste(clipboard, at: Vec2(1000, 1000)))
        XCTAssertEqual(other.board.bounds()?.center.x ?? 0, 1000, accuracy: 1e-9)
        XCTAssertEqual(other.tool, .select)
        XCTAssertTrue(other.paste(clipboard))
        XCTAssertEqual(other.board.items.count, 4)
        XCTAssertFalse(other.paste(BoardClipboard(items: [], brushes: [:])))

        session.selection = ["a"]
        XCTAssertTrue(session.bringSelectionToFront())
        XCTAssertEqual(session.board.items.last?.id, "a")
        XCTAssertTrue(session.sendSelectionToBack())
        XCTAssertEqual(session.board.items.first?.id, "a")
        XCTAssertFalse(session.sendSelectionToBack())
        XCTAssertEqual(session.excerpt(of: "a")?.title, "Lamp")
        XCTAssertEqual(session.excerpt(of: nil)?.items.count, 4)
        XCTAssertNil(BoardSession().excerpt(of: nil))
        var random = BoardIDs()
        XCTAssertEqual(random.next().count, 36)
    }

    func testColourPaperPicturesAndTheView() throws {
        var session = session([note("a", x: 0, y: 0), frame("f", BoardRect(x: 1000, y: 1000, width: 400, height: 300))])
        let red = try XCTUnwrap(BoardColor(hex: "#FF0000"))
        session.setColor(red)
        XCTAssertEqual(session.board.item("a")?.note?.color, .paper, "the Draw tool only changes the colour in the hand")
        session.tool = .select
        session.selection = ["a"]
        session.setColor(red)
        XCTAssertEqual(session.board.item("a")?.note?.color, red)

        var fresh = BoardSession()
        let light = BoardPaper(pattern: .grid, color: BoardPaper.light)
        fresh.setPaper(light)
        XCTAssertEqual(fresh.color, light.ink, "ink that was the paper's own follows the paper")
        fresh.setColor(red)
        fresh.setPaper(BoardPaper())
        XCTAssertEqual(fresh.color, red)
        fresh.setPaper(BoardPaper())

        XCTAssertTrue(session.addPicture(asset: "x.png", pixelSize: Vec2(4000, 2000), at: Vec2(0, -500)))
        XCTAssertEqual(session.board.items.last?.picture?.rect, BoardRect(x: -240, y: -620, width: 480, height: 240))
        XCTAssertEqual(session.selection, ["item-1"])

        let size = Vec2(1000, 800)
        session.frame(at: Vec2(1100, 1100), size: size)
        XCTAssertEqual(session.viewport.center.x, 1200)
        session.frame(at: Vec2(-5000, 0), size: size)
        XCTAssertLessThan(session.viewport.scale, 1)
        var empty = BoardSession()
        empty.viewport = BoardViewport(center: Vec2(9, 9), scale: 3)
        empty.zoomToFit(size: size)
        XCTAssertEqual(empty.viewport, BoardViewport())
        XCTAssertFalse(empty.undo())
        XCTAssertFalse(empty.perform(nil))
        _ = session.takePendingOps()
    }
}
