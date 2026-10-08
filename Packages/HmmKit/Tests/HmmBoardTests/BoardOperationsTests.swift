import Foundation
@testable import HmmBoard
import HmmBrush
import HmmCommands
import HmmDocuments
import XCTest

final class BoardOperationsTests: XCTestCase {
    private func path(_ points: [(Double, Double)]) -> BrushPath<Vec2> {
        BrushPath(points: points.map { Vec2($0.0, $0.1) }, widths: Array(repeating: 2, count: points.count),
                  alphas: Array(repeating: 1, count: points.count))
    }

    // MARK: Making

    func testAStrokeBringsItsBrushOnce() throws {
        let first = BoardOperations.addStroke(path([(0, 0), (10, 0)]), brush: BuiltInBrushes.pencil, color: .ink, seed: 3, id: "a", on: Board())
        var board = try assertReverts(first, on: Board())
        let key = BrushKey.key(for: BuiltInBrushes.pencil)
        XCTAssertEqual(board.brushes[key]?.name, "Pencil")
        XCTAssertEqual(board.items[0].stroke?.brush, key)
        XCTAssertEqual(first?.label, "Draw")
        let second = try XCTUnwrap(BoardOperations.addStroke(path([(0, 5), (10, 5)]), brush: BuiltInBrushes.pencil, color: .ink, seed: 4, id: "b",
                                                             on: board))
        XCTAssertEqual(second.edits.count, 1, "the brush is already on the board")
        let (_, changes) = try second.apply(to: &board)
        XCTAssertEqual(changes.appended, ["b"])
        XCTAssertFalse(changes.rebuild)
        XCTAssertNil(BoardOperations.addStroke(BrushPath(), brush: BuiltInBrushes.pencil, color: .ink, seed: 1, id: "c", on: board))
    }

    func testFramesGoBehindEverythingElseOnTop() throws {
        var board = Board(items: [note("n", x: 0, y: 0)])
        let area = BoardOperations.add(frame("f", BoardRect(x: -10, y: -10, width: 300, height: 300)), to: board)
        let (_, changes) = try area.apply(to: &board)
        XCTAssertEqual(board.items.map(\.id), ["f", "n"])
        XCTAssertTrue(changes.rebuild)
        XCTAssertEqual(area.label, "Add Frame")
        board = try assertReverts(BoardOperations.add(note("m", x: 50, y: 50), to: board), on: board)
        XCTAssertEqual(board.items.map(\.id), ["f", "n", "m"])
        XCTAssertEqual(BoardItem.Kind.allCases.map(BoardOperations.name), ["Stroke", "Picture", "Note", "Arrow", "Frame"])
    }

    func testCommandsRefuseWhatIsNotThere() {
        var board = Board(items: [note("n", x: 0, y: 0)])
        XCTAssertThrowsError(try BoardCommand("x", [.remove(["ghost"])]).apply(to: &board)) { XCTAssertEqual($0 as? BoardError, .missing("ghost")) }
        XCTAssertThrowsError(try BoardCommand("x", [.insert([.init(note("n", x: 1, y: 1), at: 0)])]).apply(to: &board)) {
            XCTAssertEqual($0 as? BoardError, .duplicate("n"))
        }
        XCTAssertThrowsError(try BoardCommand("x", [.replace([note("ghost", x: 0, y: 0)])]).apply(to: &board))
        XCTAssertThrowsError(try BoardCommand("x", [.order(["n", "n"])]).apply(to: &board)) { XCTAssertEqual($0 as? BoardError, .badOrder) }
        // A command that fails half way leaves the board as it was.
        XCTAssertThrowsError(try BoardCommand("x", [.remove(["n"]), .remove(["n"])]).apply(to: &board))
        XCTAssertEqual(board.items.count, 1)
        XCTAssertFalse(BoardError.missing("a").description.isEmpty)
        XCTAssertFalse(BoardError.duplicate("a").description.isEmpty)
        XCTAssertFalse(BoardError.badOrder.description.isEmpty)
        XCTAssertTrue(BoardCommand("x", []).isEmpty)
    }

    func testEditsRoundTripThroughJSON() throws {
        let edits: [BoardEdit] = [
            .insert([.init(note("n", x: 0, y: 0), at: 2)]), .remove(["a", "b"]), .replace([stroke("s", [(0, 0), (1, 1)])]), .order(["b", "a"]),
            .brushes(["k": BuiltInBrushes.marker, "gone": nil]), .paper(BoardPaper(pattern: .plain))
        ]
        let command = BoardCommand("Everything", edits)
        let data = try HmmJSON.encode(HistoryOp.perform(command, coalesceKey: "k"))
        guard case let .perform(decoded, key) = try HmmJSON.decode(HistoryOp<BoardCommand>.self, from: data) else { return XCTFail("not a perform") }
        XCTAssertEqual(decoded, command)
        XCTAssertEqual(key, "k")
        XCTAssertThrowsError(try JSONDecoder().decode(BoardEdit.self, from: Data(#"{"edit":"explode"}"#.utf8)))
    }

    // MARK: Changing

    func testDeleteTakesAFramesContentsAndUntiesArrows() throws {
        let board = Board(items: [
            frame("f", BoardRect(x: 0, y: 0, width: 400, height: 300)),
            note("in", x: 20, y: 50),
            note("out", x: 600, y: 0),
            BoardItem(id: "arrow", .arrow(BoardArrow(from: Vec2(220, 100), to: Vec2(600, 70), fromItem: "in", toItem: "out")))
        ])
        let after = try assertReverts(BoardOperations.delete(["f"], from: board), on: board)
        XCTAssertEqual(after.items.map(\.id), ["out", "arrow"])
        XCTAssertNil(after.item("arrow")?.arrow?.fromItem)
        XCTAssertEqual(after.item("arrow")?.arrow?.toItem, "out")
        XCTAssertNil(BoardOperations.delete(["ghost"], from: board))
    }

    func testDuplicateCopiesFramesWholeAndReTiesArrows() throws {
        let board = Board(items: [
            frame("f", BoardRect(x: 0, y: 0, width: 400, height: 300)),
            note("a", x: 20, y: 50),
            note("b", x: 180, y: 150),
            BoardItem(id: "arrow", .arrow(BoardArrow(from: Vec2(120, 120), to: Vec2(280, 220), fromItem: "a", toItem: "b"))),
            note("far", x: 900, y: 900)
        ])
        let result = try XCTUnwrap(BoardOperations.duplicate(["f"], offset: Vec2(500, 0), on: board) { $0 + "2" })
        XCTAssertEqual(result.ids, ["f2", "a2", "b2", "arrow2"])
        let after = try assertReverts(result.command, on: board)
        XCTAssertEqual(after.item("arrow2")?.arrow?.fromItem, "a2")
        XCTAssertEqual(after.item("arrow2")?.arrow?.to, Vec2(780, 220))
        XCTAssertEqual(after.item("f2")?.frame?.rect.x, 500)
        // An arrow copied without what it points at lets go.
        let alone = BoardOperations.copies(of: ["arrow"], offset: .zero, on: board) { $0 + "3" }
        XCTAssertNil(alone[0].arrow?.fromItem)
        XCTAssertNil(BoardOperations.duplicate([], offset: .zero, on: board) { $0 })
    }

    func testPasteBringsItsBrushes() throws {
        let key = BrushKey.key(for: BuiltInBrushes.marker)
        var item = stroke("s", [(0, 0), (5, 5)])
        item.content = try .stroke(BoardStroke(path: XCTUnwrap(item.stroke).path, brush: key))
        let command = BoardOperations.add([item], brushes: [key: BuiltInBrushes.marker], label: "Paste", to: Board())
        let board = try assertReverts(command, on: Board())
        XCTAssertNotNil(board.brushes[key])
        XCTAssertEqual(BoardOperations.add([note("n", x: 0, y: 0)], brushes: [key: BuiltInBrushes.marker], label: "Paste", to: board)?.edits.count, 1)
    }

    func testTextTitlesColoursAndPaper() throws {
        let board = Board(items: [note("n", x: 0, y: 0), frame("f", BoardRect(x: 0, y: 0, width: 9, height: 9)), stroke("s", [(0, 0), (1, 1)]),
                                  BoardItem(id: "a", .arrow(BoardArrow(from: .zero, to: Vec2(9, 9))))])
        XCTAssertEqual(try assertReverts(BoardOperations.setText("Lamp", ofNote: "n", on: board), on: board).item("n")?.note?.text, "Lamp")
        XCTAssertNil(BoardOperations.setText("", ofNote: "n", on: board))
        XCTAssertNil(BoardOperations.setText("x", ofNote: "f", on: board))
        XCTAssertEqual(try assertReverts(BoardOperations.rename(frame: "f", to: " Shots ", on: board), on: board).item("f")?.frame?.title, "Shots")
        XCTAssertNil(BoardOperations.rename(frame: "f", to: "  ", on: board))
        let red = try XCTUnwrap(BoardColor(hex: "#FF0000"))
        let painted = try assertReverts(BoardOperations.setColor(red, of: ["n", "f", "s", "a"], on: board), on: board)
        XCTAssertEqual(painted.item("s")?.stroke?.color, red)
        XCTAssertEqual(painted.item("a")?.arrow?.color, red)
        XCTAssertEqual(painted.item("n")?.note?.color, red)
        XCTAssertNil(BoardOperations.setColor(red, of: ["f"], on: board))
        let plain = BoardPaper(pattern: .plain, color: BoardPaper.light)
        XCTAssertEqual(try assertReverts(BoardOperations.setPaper(plain, on: board), on: board).paper, plain)
        XCTAssertNil(BoardOperations.setPaper(BoardPaper(), on: board))
    }

    func testOrder() throws {
        let board = Board(items: [note("a", x: 0, y: 0), note("b", x: 0, y: 0), note("c", x: 0, y: 0)])
        XCTAssertEqual(try assertReverts(BoardOperations.bringToFront(["a"], on: board), on: board).items.map(\.id), ["b", "c", "a"])
        XCTAssertEqual(try assertReverts(BoardOperations.sendToBack(["c"], on: board), on: board).items.map(\.id), ["c", "a", "b"])
        XCTAssertNil(BoardOperations.bringToFront(["c"], on: board))
        XCTAssertNil(BoardOperations.sendToBack(["a"], on: board))
    }

    // MARK: Moving and erasing

    func testMovingAFrameCarriesItsContentsAndTiedArrowEnds() throws {
        let board = Board(items: [
            frame("f", BoardRect(x: 0, y: 0, width: 400, height: 300)),
            note("in", x: 20, y: 50),
            note("out", x: 600, y: 0),
            BoardItem(id: "arrow", .arrow(BoardArrow(from: Vec2(220, 100), to: Vec2(600, 70), fromItem: "in", toItem: "out")))
        ])
        let move = BoardTransform(movingBy: Vec2(0, 1000))
        let after = try assertReverts(BoardOperations.transform(["f"], by: move, on: board), on: board)
        XCTAssertEqual(after.item("in")?.note?.rect.y, 1050)
        XCTAssertEqual(after.item("out")?.note?.rect.y, 0)
        XCTAssertEqual(after.item("arrow")?.arrow?.from, Vec2(220, 1100))
        XCTAssertEqual(after.item("arrow")?.arrow?.to, Vec2(600, 70))
        XCTAssertEqual(BoardOperations.transform(["f"], by: move, on: board)?.label, "Move")
        XCTAssertEqual(BoardOperations.preview(["in"], by: move, on: board).map(\.id), ["in", "arrow"])
        XCTAssertEqual(BoardOperations.preview([], by: move, on: board), [])
        XCTAssertNil(BoardOperations.transform(["in"], by: BoardTransform(movingBy: .zero), on: board))
    }

    func testResizingScalesStrokesWithTheirWidth() throws {
        let arrow = BoardItem(id: "a", .arrow(BoardArrow(from: .zero, to: Vec2(10, 0), width: 4)))
        let board = Board(items: [stroke("s", [(0, 0), (10, 10)], width: 2), arrow,
                                  BoardItem(id: "p", .picture(BoardPicture(asset: "x.png", rect: BoardRect(x: 0, y: 0, width: 10, height: 10))))])
        let grow = BoardTransform(from: BoardRect(x: 0, y: 0, width: 10, height: 10), to: BoardRect(x: 0, y: 0, width: 30, height: 30))
        let command = BoardOperations.transform(["s", "a", "p"], by: grow, on: board)
        XCTAssertEqual(command?.label, "Resize")
        let after = try assertReverts(command, on: board)
        XCTAssertEqual(after.item("s")?.stroke?.path.points.last, Vec2(30, 30))
        XCTAssertEqual(after.item("s")?.stroke?.path.widths, [6, 6])
        XCTAssertEqual(after.item("a")?.arrow?.width, 12)
        XCTAssertEqual(after.item("p")?.picture?.rect.width, 30)
    }

    func testTheEraserCutsStrokesWhereItTouched() throws {
        let points = (0 ... 20).map { (Double($0) * 10, 0.0) }
        let board = Board(items: [stroke("under", [(0, 50), (200, 50)]), stroke("s", points, width: 1), note("n", x: 80, y: -20)])
        var next = 0
        let command = BoardOperations.erase(from: Vec2(100, -30), to: Vec2(100, 30), radius: 8, on: board) {
            next += 1
            return "piece\(next)"
        }
        XCTAssertEqual(command?.label, "Erase")
        let after = try assertReverts(command, on: board)
        XCTAssertEqual(after.items.map(\.id), ["under", "piece1", "piece2", "n"], "the pieces stay where the stroke was; the note isn't ink")
        XCTAssertEqual(after.item("piece1")?.stroke?.path.points.last, Vec2(90, 0))
        XCTAssertEqual(after.item("piece2")?.stroke?.path.points.first, Vec2(110, 0))
        XCTAssertEqual(after.item("piece2")?.stroke?.seed, 7)
        XCTAssertNil(BoardOperations.erase(from: Vec2(0, 500), to: Vec2(10, 500), radius: 8, on: board) { "x" })
        // Rubbing a whole short stroke out leaves nothing of it.
        let small = Board(items: [stroke("dot", [(0, 0), (2, 0)])])
        let gone = try assertReverts(BoardOperations.erase(from: Vec2(-5, 0), to: Vec2(5, 0), radius: 10, on: small) { "y" }, on: small)
        XCTAssertTrue(gone.isEmpty)
        XCTAssertNil(stroke("s", points).stroke?.erased(from: Vec2(0, 900), to: Vec2(9, 900), radius: 1))
    }

    // MARK: Undo and the journal

    func testADragIsOneUndoStepThatKeepsOnlyItsEnds() throws {
        var board = Board(items: [note("n", x: 0, y: 0)])
        var stack = CommandStack<BoardCommand>()
        for step in 1 ... 5 {
            var moved = note("n", x: Double(step) * 10, y: 0)
            moved.content = .note(BoardNote(text: "", rect: BoardRect(x: Double(step) * 10, y: 0, width: 200, height: 140)))
            try stack.perform(BoardCommand("Move", [.replace([moved])]), on: &board, coalesceKey: "drag")
        }
        XCTAssertEqual(stack.undoStack.count, 1)
        XCTAssertEqual(stack.undoStack[0].command.edits.count, 1, "the steps between aren't kept")
        try stack.undo(on: &board)
        XCTAssertEqual(board.item("n")?.note?.rect.x, 0)
        try stack.redo(on: &board)
        XCTAssertEqual(board.item("n")?.note?.rect.x, 50)
        // Different things under one key still undo together, in order.
        stack.endCoalescing()
        try stack.perform(BoardOperations.add(note("a", x: 0, y: 0), to: board), on: &board, coalesceKey: "k")
        try stack.perform(BoardOperations.add(note("b", x: 0, y: 0), to: board), on: &board, coalesceKey: "k")
        try stack.undo(on: &board)
        XCTAssertEqual(board.items.map(\.id), ["n"])
    }

    func testTheBoardSurvivesBeingClosedWithItsUndo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("board-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BoardStore(folder: folder, appName: "Tests")
        XCTAssertFalse(store.exists)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertNil(store.loadView())

        var (journal, opened) = try store.open()
        XCTAssertEqual(opened.source, .fresh)
        var board = opened.document
        var stack = opened.history
        try stack.perform(BoardOperations.add(note("n", x: 0, y: 0, text: "one"), to: board), on: &board)
        try stack.perform(XCTUnwrap(BoardOperations.setText("two", ofNote: "n", on: board)), on: &board)
        journal.record(stack.takePendingOps())
        journal.flush()
        try store.save(board)
        store.saveView(BoardViewport(center: Vec2(40, 50), scale: 2))
        XCTAssertTrue(store.exists)

        // Reopened (the app was killed: no checkpoint was written): the journal replays, undo still works.
        (journal, opened) = try store.open()
        board = opened.document
        stack = opened.history
        XCTAssertEqual(board.item("n")?.note?.text, "two")
        XCTAssertEqual(stack.undoLabel, "Edit Note")
        try stack.undo(on: &board)
        XCTAssertEqual(board.item("n")?.note?.text, "one")
        XCTAssertEqual(store.loadView(), BoardViewport(center: Vec2(40, 50), scale: 2))
        XCTAssertEqual(try store.load().item("n")?.note?.text, "two")
        _ = journal
    }

    func testPicturesAreStoredOnceByContent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("board-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BoardStore(folder: folder, appName: "Tests")
        let name = try store.storeAsset(Data([1, 2, 3]), fileExtension: ".PNG")
        XCTAssertTrue(name.hasSuffix(".png"))
        XCTAssertEqual(try store.storeAsset(Data([1, 2, 3]), fileExtension: "png"), name)
        XCTAssertNotEqual(try store.storeAsset(Data([9]), fileExtension: ""), name)
        XCTAssertEqual(try Data(contentsOf: store.assetURL(name)), Data([1, 2, 3]))
        XCTAssertEqual(store.assetURL("../../secret.png").deletingLastPathComponent().lastPathComponent, "assets")
    }

    func testANewerBoardIsRefused() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("board-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BoardStore(folder: folder, appName: "Tests")
        try Data(#"{"schemaVersion":99,"kind":"board","payload":{}}"#.utf8).write(to: store.boardURL)
        XCTAssertThrowsError(try store.load())
    }
}
