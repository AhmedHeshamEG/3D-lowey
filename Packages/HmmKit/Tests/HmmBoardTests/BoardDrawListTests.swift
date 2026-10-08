import Foundation
@testable import HmmBoard
import HmmBrush
import XCTest

final class BoardDrawListTests: XCTestCase {
    func testPlacementsPutTheBoardOnScreenAndInPictures() {
        let view = BoardViewport(center: Vec2(100, 50), scale: 2)
        let screen = BoardPlacement(viewport: view, size: Vec2(800, 600), contentScale: 2)
        XCTAssertEqual(screen.scale, 4)
        XCTAssertEqual(screen.apply(Vec2(100, 50)), Vec2(800, 600), "the view's centre is the middle pixel")
        let picture = BoardPlacement(region: BoardRect(x: 10, y: 20, width: 100, height: 50), pixelsPerUnit: 3)
        XCTAssertEqual(picture.apply(Vec2(10, 20)), .zero)
        XCTAssertEqual(picture.corners(BoardRect(x: 10, y: 20, width: 100, height: 50)), [Vec2(0, 0), Vec2(300, 0), Vec2(0, 150), Vec2(300, 150)])
        XCTAssertEqual(BoardPlacement(offset: Vec2(1, 2), scale: 2).apply(Vec2(1, 1)), Vec2(3, 4))
    }

    func testEveryKindOfItemIsDrawnBackToFront() throws {
        let key = BrushKey.key(for: BuiltInBrushes.marker)
        var inked = stroke("s", [(0, 0), (10, 10)])
        inked.content = try .stroke(BoardStroke(path: XCTUnwrap(inked.stroke).path, brush: key))
        let board = Board(items: [
            frame("f", BoardRect(x: -50, y: -50, width: 600, height: 400), title: "Shots"),
            inked,
            BoardItem(id: "p", .picture(BoardPicture(asset: "a.png", rect: BoardRect(x: 0, y: 0, width: 10, height: 10)))),
            note("n", x: 100, y: 100, text: "Lamp"),
            BoardItem(id: "a", .arrow(BoardArrow(from: Vec2(0, 0), to: Vec2(100, 0)))),
            note("far", x: 9000, y: 9000, text: "Elsewhere")
        ], brushes: [key: BuiltInBrushes.marker])
        let placement = BoardPlacement(offset: .zero, scale: 2)
        let draws = BoardDrawList.items(board.items, on: board, placement: placement, clip: BoardRect(x: -100, y: -100, width: 1000, height: 1000))
        XCTAssertEqual(draws.count, 2 + 1 + 1 + 2 + 1, "a frame and a note are two draws each; the far note is clipped")
        guard case let .text(title, _) = draws[1], case let .stroke(_, brush) = draws[2], case let .picture(asset, corners) = draws[3],
              case let .text(words, box) = draws[5] else { return XCTFail("unexpected order") }
        XCTAssertEqual(title.text, "Shots")
        XCTAssertTrue(title.isTitle)
        XCTAssertEqual(brush.name, "Marker")
        XCTAssertEqual(asset, "a.png")
        XCTAssertEqual(corners[3], Vec2(20, 20))
        XCTAssertEqual(words.text, "Lamp")
        XCTAssertEqual(words.width, 200 - 24)
        XCTAssertEqual(words.resolution, 2)
        XCTAssertEqual(box[0], Vec2(224, 224))
        XCTAssertLessThan(words.color.luminance, 0.5, "dark words on the amber slip")
    }

    func testNotesBeingTypedAndLostBrushes() {
        let placement = BoardPlacement(offset: .zero, scale: 2)
        let board = Board(items: [note("n", x: 100, y: 100, text: "Lamp")])
        // The note being typed keeps its slip, not its words; an empty note has none either.
        XCTAssertEqual(BoardDrawList.items(board.items, on: board, placement: placement).count, 2)
        XCTAssertEqual(BoardDrawList.items(board.items, on: board, placement: placement, editingNote: "n").count, 1)
        let blank = BoardNote(rect: BoardRect(x: 0, y: 0, width: 99, height: 99))
        XCTAssertEqual(BoardDrawList.note(blank, placement: placement, showsText: true).count, 1)
        var dark = BoardNote(text: "x", rect: BoardRect(x: 0, y: 0, width: 200, height: 100))
        dark.color = BoardPaper.dark
        guard case let .text(light, _) = BoardDrawList.note(dark, placement: placement, showsText: true)[1] else { return XCTFail("no words") }
        XCTAssertGreaterThan(light.color.luminance, 0.5)
        // A stroke whose brush the board lost still draws, with Ink Pen.
        let lost = BoardDrawList.items([stroke("x", [(0, 0), (1, 1)])], on: Board(), placement: placement)
        guard case let .stroke(_, fallback) = lost[0] else { return XCTFail("no stroke") }
        XCTAssertEqual(fallback.id, BuiltInBrushes.inkPenID)
        let untitled = BoardFrame(title: "", rect: BoardRect(x: 0, y: 0, width: 99, height: 99))
        XCTAssertEqual(BoardDrawList.frame(untitled, paper: BoardPaper(), placement: placement, contentScale: 1).count, 1)
    }

    func testWordsStaySharpInSteps() {
        XCTAssertEqual(BoardTextSpec.resolution(for: 0.2), 1)
        XCTAssertEqual(BoardTextSpec.resolution(for: 1), 1)
        XCTAssertEqual(BoardTextSpec.resolution(for: 1.1), 2)
        XCTAssertEqual(BoardTextSpec.resolution(for: 3), 4)
        XCTAssertEqual(BoardTextSpec.resolution(for: 500), 8)
    }

    func testPaperAndOverlay() {
        let placement = BoardPlacement(offset: .zero, scale: 2)
        let rect = BoardRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(BoardDrawList.paper(BoardPaper(pattern: .plain), over: rect, placement: placement, viewScale: 1, contentScale: 2), [])
        XCTAssertEqual(BoardDrawList.paper(BoardPaper(), over: rect, placement: placement, viewScale: 1, contentScale: 2).count, 1)
        var overlay = BoardDrawList.Overlay(accent: .paper, ink: .ink)
        XCTAssertEqual(BoardDrawList.overlay(overlay, placement: placement, contentScale: 2), [])
        overlay.selection = rect
        overlay.marquee = rect
        overlay.eraser = Vec2(5, 5)
        overlay.eraserRadius = 10
        overlay.hover = Vec2(1, 1)
        XCTAssertEqual(BoardDrawList.overlay(overlay, placement: placement, contentScale: 2).count, 2 + 3 + 1 + 1)
        overlay.showsHandles = false
        XCTAssertEqual(BoardDrawList.overlay(overlay, placement: placement, contentScale: 2).count, 2 + 1 + 1 + 1)
    }

    func testTheLayerServesWhileFingersMoveAndIsRedrawnSharpAtRest() {
        let visible = BoardRect(x: 0, y: 0, width: 1000, height: 800)
        let layer = BoardLayerPlan(visible: visible, pixelsPerUnit: 2)
        XCTAssertEqual(layer.region, BoardRect(x: -250, y: -200, width: 1500, height: 1200))
        XCTAssertEqual(layer.pixelWidth, 3000)
        XCTAssertEqual(layer.pixelHeight, 2400)
        XCTAssertTrue(layer.serves(visible: visible, pixelsPerUnit: 2, interacting: false))
        XCTAssertTrue(layer.serves(visible: visible.moved(by: Vec2(200, 0)), pixelsPerUnit: 2, interacting: false), "a pan inside the margin")
        XCTAssertFalse(layer.serves(visible: visible.moved(by: Vec2(300, 0)), pixelsPerUnit: 2, interacting: true), "past the margin")
        XCTAssertTrue(layer.serves(visible: visible, pixelsPerUnit: 3.5, interacting: true), "stretched during a pinch")
        XCTAssertFalse(layer.serves(visible: visible, pixelsPerUnit: 3.5, interacting: false), "sharp again at rest")
        XCTAssertFalse(layer.serves(visible: visible, pixelsPerUnit: 4.5, interacting: true))
        XCTAssertFalse(BoardLayerPlan(region: visible, pixelsPerUnit: 0).serves(visible: visible, pixelsPerUnit: 1, interacting: true))
    }
}
