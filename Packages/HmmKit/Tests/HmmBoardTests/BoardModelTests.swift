import Foundation
@testable import HmmBoard
import HmmBrush
import HmmCommands
import HmmDocuments
import XCTest

func stroke(_ id: String, _ points: [(Double, Double)], width: Double = 2) -> BoardItem {
    let path = BrushPath(points: points.map { Vec2($0.0, $0.1) }, widths: Array(repeating: width, count: points.count),
                         alphas: Array(repeating: 1, count: points.count))
    return BoardItem(id: id, .stroke(BoardStroke(path: path, brush: "b-1", seed: 7)))
}

func note(_ id: String, x: Double, y: Double, text: String = "") -> BoardItem {
    BoardItem(id: id, .note(BoardNote(text: text, rect: BoardRect(x: x, y: y, width: 200, height: 140))))
}

func frame(_ id: String, _ rect: BoardRect, title: String = "Frame 1") -> BoardItem {
    BoardItem(id: id, .frame(BoardFrame(title: title, rect: rect)))
}

/// Applies a command, checks its inverse brings the board back exactly, and returns the changed board.
@discardableResult
func assertReverts(_ command: BoardCommand?, on board: Board, file: StaticString = #filePath, line: UInt = #line) throws -> Board {
    let command = try XCTUnwrap(command, file: file, line: line)
    var changed = board
    let (inverse, _) = try command.apply(to: &changed)
    var back = changed
    let (again, _) = try inverse.apply(to: &back)
    XCTAssertEqual(back, board, "the inverse doesn't restore the board", file: file, line: line)
    var forward = back
    _ = try again.apply(to: &forward)
    XCTAssertEqual(forward, changed, "redo doesn't repeat the change", file: file, line: line)
    return changed
}

final class BoardModelTests: XCTestCase {
    // MARK: Geometry

    func testRectangles() {
        let rect = BoardRect(Vec2(10, 20), Vec2(0, 0))
        XCTAssertEqual(rect, BoardRect(x: 0, y: 0, width: 10, height: 20))
        XCTAssertTrue(rect.contains(Vec2(5, 5)))
        XCTAssertFalse(rect.contains(Vec2(11, 5)))
        XCTAssertTrue(rect.contains(BoardRect(x: 1, y: 1, width: 2, height: 2)))
        XCTAssertTrue(rect.intersects(BoardRect(x: 9, y: 19, width: 5, height: 5)))
        XCTAssertFalse(rect.intersects(BoardRect(x: 11, y: 0, width: 5, height: 5)))
        XCTAssertEqual(rect.union(BoardRect(x: -5, y: 5, width: 1, height: 30)), BoardRect(x: -5, y: 0, width: 15, height: 35))
        XCTAssertEqual(rect.expanded(by: 2), BoardRect(x: -2, y: -2, width: 14, height: 24))
        XCTAssertEqual(rect.expanded(by: -100).width, 0)
        XCTAssertEqual(rect.distanceToEdge(Vec2(5, 1)), 1)
        XCTAssertEqual(rect.distanceToEdge(Vec2(13, 24)), 5)
        XCTAssertEqual(rect.corners.count, 4)
        XCTAssertEqual(rect.area, 200)
        XCTAssertNil(BoardRect.around([]))
        XCTAssertEqual(BoardRect(center: Vec2(0, 0), width: 4, height: 2).origin, Vec2(-2, -1))
    }

    func testTransformsMoveAndResize() {
        let move = BoardTransform(movingBy: Vec2(3, 4))
        XCTAssertTrue(move.isMove)
        XCTAssertEqual(move.apply(Vec2(1, 1)), Vec2(4, 5))
        let grow = BoardTransform(from: BoardRect(x: 0, y: 0, width: 10, height: 10), to: BoardRect(x: 10, y: 10, width: 20, height: 40))
        XCTAssertFalse(grow.isMove)
        XCTAssertEqual(grow.apply(Vec2(5, 5)), Vec2(20, 30))
        XCTAssertEqual(grow.widthScale, 2)
        XCTAssertEqual(grow.apply(BoardRect(x: 0, y: 0, width: 5, height: 5)), BoardRect(x: 10, y: 10, width: 10, height: 20))
        let flat = BoardTransform(from: BoardRect(x: 0, y: 0, width: 0, height: 0), to: BoardRect(x: 1, y: 1, width: 5, height: 5))
        XCTAssertEqual(flat.scaleX, 1)
    }

    func testColoursAreHex() throws {
        let amber = try XCTUnwrap(BoardColor(hex: "#FFB847"))
        XCTAssertEqual(amber.hex, "#FFB847")
        XCTAssertEqual(BoardColor(hex: "0a0B0c")?.hex, "#0A0B0C")
        XCTAssertNil(BoardColor(hex: "#12"))
        XCTAssertNil(BoardColor(hex: "#GGGGGG"))
        let data = try JSONEncoder().encode([amber])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"#FFB847\"]")
        XCTAssertEqual(try JSONDecoder().decode([BoardColor].self, from: data), [amber])
        XCTAssertThrowsError(try JSONDecoder().decode([BoardColor].self, from: Data("[\"red\"]".utf8)))
        XCTAssertGreaterThan(BoardColor.paper.luminance, 0.5)
        XCTAssertEqual(BoardColor(red: 2, green: -1, blue: .nan).hex, "#FF0000")
    }

    func testSegments() {
        XCTAssertEqual(BoardMath.distance(Vec2(5, 3), toSegment: Vec2(0, 0), Vec2(10, 0)), 3)
        XCTAssertEqual(BoardMath.distance(Vec2(13, 4), toSegment: Vec2(0, 0), Vec2(10, 0)), 5)
        XCTAssertEqual(BoardMath.distance(Vec2(3, 4), toSegment: Vec2(0, 0), Vec2(0, 0)), 5)
        XCTAssertTrue(BoardMath.crosses(Vec2(0, 0), Vec2(10, 10), Vec2(0, 10), Vec2(10, 0)))
        XCTAssertFalse(BoardMath.crosses(Vec2(0, 0), Vec2(1, 1), Vec2(5, 5), Vec2(6, 7)))
        XCTAssertEqual(BoardMath.distance(segment: Vec2(0, 0), Vec2(10, 10), toSegment: Vec2(0, 10), Vec2(10, 0)), 0)
        XCTAssertEqual(BoardMath.distance(segment: Vec2(0, 0), Vec2(10, 0), toSegment: Vec2(0, 3), Vec2(10, 3)), 3)
    }

    // MARK: Items

    func testEveryItemRoundTripsThroughJSON() throws {
        let items = [
            stroke("s", [(0, 0), (10, 5)]),
            BoardItem(id: "p", .picture(BoardPicture(asset: "a.png", rect: BoardRect(x: 1, y: 2, width: 3, height: 4)))),
            note("n", x: 0, y: 0, text: "Tower first"),
            BoardItem(id: "a", .arrow(BoardArrow(from: Vec2(0, 0), to: Vec2(100, 0), fromItem: "n"))),
            frame("f", BoardRect(x: -10, y: -10, width: 500, height: 400))
        ]
        let board = Board(items: items, brushes: ["b-1": BuiltInBrushes.pencil], paper: BoardPaper(pattern: .grid, color: BoardPaper.light))
        let data = try HmmJSON.encode(board)
        XCTAssertEqual(try HmmJSON.decode(Board.self, from: data), board)
        XCTAssertEqual(items.map(\.kind), BoardItem.Kind.allCases)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"kind\" : \"stroke\""))
        XCTAssertNotNil(items[0].stroke)
        XCTAssertNotNil(items[1].picture)
        XCTAssertNotNil(items[2].note)
        XCTAssertNotNil(items[3].arrow)
        XCTAssertNotNil(items[4].frame)
        XCTAssertNil(items[0].frame)
        XCTAssertNil(items[1].stroke)
        XCTAssertNil(items[0].note)
        XCTAssertNil(items[0].arrow)
        XCTAssertNil(items[0].picture)
    }

    func testAHandWrittenBoardReads() throws {
        let json = """
        {"items":[{"id":"s","kind":"stroke","points":[0,0,10,0,20,0],"widths":[2],"color":"#000000"},
                  {"id":"x","kind":"note","text":"hi","rect":{"x":0,"y":0,"width":10,"height":10},"color":"#FFFFFF"}]}
        """
        let board = try JSONDecoder().decode(Board.self, from: Data(json.utf8))
        let stroke = try XCTUnwrap(board.items[0].stroke)
        XCTAssertEqual(stroke.path.points.count, 3)
        XCTAssertEqual(stroke.path.widths, [2, 2, 2])
        XCTAssertEqual(stroke.path.alphas, [1, 1, 1])
        XCTAssertEqual(stroke.seed, 1)
        XCTAssertEqual(board.paper, BoardPaper())
        XCTAssertTrue(board.paper.isDark)
        XCTAssertGreaterThan(board.paper.ink.luminance, 0.8)
        XCTAssertLessThan(BoardPaper(color: BoardPaper.light).ink.luminance, 0.2)
        XCTAssertGreaterThan(board.paper.faint.luminance, board.paper.color.luminance)
        XCTAssertLessThan(BoardPaper(color: BoardPaper.light).faint.luminance, BoardPaper.light.luminance)
        XCTAssertEqual(BoardStroke.fitted([1, 2, 3], to: 2, fallback: 0), [1, 2])
        XCTAssertThrowsError(try JSONDecoder().decode(Board.self, from: Data(#"{"items":[{"id":"q","kind":"video"}]}"#.utf8)))
    }

    func testBoundsAndHits() {
        let line = stroke("s", [(0, 0), (100, 0)], width: 4)
        XCTAssertEqual(line.bounds, BoardRect(x: -4, y: -4, width: 108, height: 8))
        XCTAssertTrue(line.hit(Vec2(50, 5), tolerance: 2))
        XCTAssertFalse(line.hit(Vec2(50, 9), tolerance: 2))
        XCTAssertFalse(line.hit(Vec2(500, 0), tolerance: 2))
        let dot = stroke("d", [(5, 5)], width: 3)
        XCTAssertTrue(dot.hit(Vec2(7, 5), tolerance: 0))
        XCTAssertEqual(BoardStroke(path: BrushPath()).distance(to: .zero), .infinity)

        let arrow = BoardItem(id: "a", .arrow(BoardArrow(from: Vec2(0, 0), to: Vec2(100, 0), width: 4)))
        XCTAssertTrue(arrow.hit(Vec2(50, 3), tolerance: 1))
        XCTAssertFalse(arrow.hit(Vec2(50, 30), tolerance: 1))
        XCTAssertEqual(arrow.arrow?.triangles.count, 9)
        XCTAssertEqual(BoardArrow(from: .zero, to: .zero).triangles, [])
        XCTAssertTrue(arrow.touches(BoardRect(x: 40, y: -10, width: 5, height: 20)))
        XCTAssertFalse(arrow.touches(BoardRect(x: 40, y: 5, width: 5, height: 20)))
        XCTAssertTrue(arrow.touches(BoardRect(x: -5, y: -5, width: 10, height: 10)))

        let paper = note("n", x: 0, y: 0)
        XCTAssertTrue(paper.hit(Vec2(100, 70), tolerance: 0))
        XCTAssertFalse(paper.hit(Vec2(300, 70), tolerance: 0))
        XCTAssertTrue(paper.touches(BoardRect(x: 190, y: 130, width: 50, height: 50)))

        let area = frame("f", BoardRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertFalse(area.hit(Vec2(200, 150), tolerance: 6), "the middle of a frame belongs to what's in it")
        XCTAssertTrue(area.hit(Vec2(2, 150), tolerance: 6))
        XCTAssertTrue(area.hit(Vec2(50, -10), tolerance: 6), "its title picks it")
        XCTAssertTrue(line.touches(BoardRect(x: 90, y: -1, width: 30, height: 2)))
        XCTAssertFalse(line.touches(BoardRect(x: 200, y: -1, width: 30, height: 2)))
    }

    func testQueries() {
        let board = Board(items: [
            frame("f", BoardRect(x: 0, y: 0, width: 400, height: 300)),
            frame("inner", BoardRect(x: 10, y: 40, width: 100, height: 100), title: "Frame 2"),
            note("in", x: 20, y: 50),
            note("out", x: 600, y: 0),
            stroke("s", [(300, 200), (350, 250)])
        ])
        XCTAssertEqual(board.item(at: Vec2(30, 60), tolerance: 4)?.id, "in")
        XCTAssertNil(board.item(at: Vec2(500, 500), tolerance: 4))
        XCTAssertEqual(Set(board.contents(ofFrame: "f").map(\.id)), ["inner", "in", "s"])
        XCTAssertEqual(board.contents(ofFrame: "in"), [])
        XCTAssertEqual(board.carried(by: ["f"]), ["f", "inner", "in", "s"])
        XCTAssertEqual(board.carried(by: ["out"]), ["out"])
        XCTAssertEqual(board.frame(containing: Vec2(50, 80))?.id, "inner")
        XCTAssertEqual(board.frame(containing: Vec2(300, 280))?.id, "f")
        XCTAssertNil(board.frame(containing: Vec2(900, 900)))
        XCTAssertEqual(board.nextFrameTitle, "Frame 3")
        XCTAssertEqual(Set(board.items(in: BoardRect(x: 15, y: 45, width: 400, height: 400)).map(\.id)), ["in", "s"])
        XCTAssertEqual(Set(board.items(in: BoardRect(x: -50, y: -50, width: 500, height: 400)).map(\.id)), ["f", "inner", "in", "s"])
        XCTAssertEqual(board.bounds(of: ["out"]), BoardRect(x: 600, y: 0, width: 200, height: 140))
        XCTAssertNil(Board().bounds())
        XCTAssertTrue(Board().isEmpty)
        XCTAssertEqual(board.bounds()?.maxX, 800)
        XCTAssertEqual(board.index(of: "in"), 2)
    }

    // MARK: The view

    func testTheViewPansAndZoomsAboutTheFingers() {
        let size = Vec2(1000, 800)
        var view = BoardViewport()
        XCTAssertEqual(view.toScreen(.zero, size: size), Vec2(500, 400))
        XCTAssertEqual(view.toBoard(Vec2(600, 400), size: size), Vec2(100, 0))
        view = view.panned(byScreen: Vec2(100, 0))
        XCTAssertEqual(view.toScreen(.zero, size: size), Vec2(600, 400))
        let finger = Vec2(250, 300)
        let under = view.toBoard(finger, size: size)
        let closer = view.zoomed(by: 2, around: finger, size: size)
        XCTAssertEqual(closer.scale, 2)
        XCTAssertEqual(closer.toScreen(under, size: size).x, finger.x, accuracy: 1e-9)
        XCTAssertEqual(closer.toScreen(under, size: size).y, finger.y, accuracy: 1e-9)
        XCTAssertEqual(view.zoomed(by: 1e9, around: finger, size: size).scale, 32)
        XCTAssertEqual(view.zoomed(by: 1e-9, around: finger, size: size).scale, 0.05)
        XCTAssertEqual(closer.visibleRect(size: size).width, 500)
        XCTAssertEqual(closer.percentText, "200 %")
        let fitted = BoardViewport.fitting(BoardRect(x: 0, y: 0, width: 4000, height: 1000), size: size, padding: 100)
        XCTAssertEqual(fitted.scale, 0.2)
        XCTAssertEqual(fitted.center, Vec2(2000, 500))
        XCTAssertEqual(BoardViewport.fitting(BoardRect(x: 0, y: 0, width: 10, height: 10), size: size).scale, 1)
    }
}
