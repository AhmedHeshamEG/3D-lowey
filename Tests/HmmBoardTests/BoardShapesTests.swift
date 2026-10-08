import Foundation
@testable import HmmBoard
import HmmBrush
import XCTest

final class BoardShapesTests: XCTestCase {
    /// The area triangles cover (they don't overlap in these shapes).
    private func area(_ triangles: [Vec2]) -> Double {
        var total = 0.0
        for index in stride(from: 0, to: triangles.count - 2, by: 3) {
            let ab = triangles[index + 1] - triangles[index]
            let ac = triangles[index + 2] - triangles[index]
            total += abs(ab.cross(ac)) / 2
        }
        return total
    }

    func testQuadsLinesAndOutlines() {
        let rect = BoardRect(x: 0, y: 0, width: 10, height: 4)
        XCTAssertEqual(area(BoardShapes.quad(rect)), 40, accuracy: 1e-9)
        XCTAssertEqual(area(BoardShapes.line(from: Vec2(0, 0), to: Vec2(10, 0), thickness: 2)), 20, accuracy: 1e-9)
        XCTAssertEqual(BoardShapes.line(from: .zero, to: .zero, thickness: 2), [])
        // The edge of a 10 × 4 box, 1 thick, centred on it: 11 × 5 outside minus 9 × 3 inside.
        XCTAssertEqual(area(BoardShapes.outline(rect, thickness: 1)), 55 - 27, accuracy: 1e-9)
    }

    func testRoundShapes() {
        let rect = BoardRect(x: 0, y: 0, width: 100, height: 60)
        let rounded = area(BoardShapes.roundedRect(rect, radius: 10, segments: 16))
        XCTAssertEqual(rounded, 6000 - (4 - .pi) * 100, accuracy: 2)
        XCTAssertEqual(area(BoardShapes.roundedRect(rect, radius: 0)), 6000, accuracy: 1e-9)
        XCTAssertEqual(area(BoardShapes.roundedRect(rect, radius: 500, segments: 24)), 2400 + .pi * 900, accuracy: 20)
        XCTAssertEqual(area(BoardShapes.disc(center: Vec2(5, 5), radius: 10, segments: 64)), .pi * 100, accuracy: 1)
        XCTAssertEqual(area(BoardShapes.ring(center: .zero, radius: 10, thickness: 2, segments: 64)), .pi * (121 - 81), accuracy: 1)
        XCTAssertEqual(BoardShapes.circle(center: .zero, radius: 1, segments: 1).count, 3)
    }

    func testThePaperKeepsItsDotsApartOnScreen() {
        XCTAssertEqual(BoardShapes.paperStep(scale: 1), 32)
        for scale in [0.05, 0.3, 0.7, 1, 1.9, 6, 32] {
            let onScreen = BoardShapes.paperStep(scale: scale) * scale
            XCTAssertGreaterThanOrEqual(onScreen, 20 - 1e-9)
            XCTAssertLessThan(onScreen, 40)
        }
        let view = BoardRect(x: -10, y: -10, width: 100, height: 70)
        XCTAssertEqual(BoardShapes.paper(.plain, over: view, scale: 1, mark: 1), [])
        // Columns from −32 to 64 and rows from −32 to 32: the step before the view is drawn too, so nothing pops in.
        let dots = BoardShapes.paper(.dots, over: view, scale: 1, mark: 1)
        XCTAssertEqual(dots.count, 4 * 3 * 6)
        let grid = BoardShapes.paper(.grid, over: view, scale: 1, mark: 1)
        XCTAssertEqual(grid.count, (4 + 3) * 6)
    }

    func testHandlesResizeWithoutTurningInsideOut() {
        let rect = BoardRect(x: 0, y: 0, width: 100, height: 50)
        let handles = BoardShapes.handles(of: rect)
        XCTAssertEqual(handles.count, 8)
        XCTAssertEqual(handles[4], Vec2(100, 50))
        // A corner keeps the proportions.
        XCTAssertEqual(BoardShapes.resized(rect, handle: 4, to: Vec2(200, 60), minimum: 8), BoardRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(BoardShapes.resized(rect, handle: 0, to: Vec2(50, 40), minimum: 8), BoardRect(x: 50, y: 25, width: 50, height: 25))
        // A side stretches one way.
        XCTAssertEqual(BoardShapes.resized(rect, handle: 3, to: Vec2(150, 999), minimum: 8), BoardRect(x: 0, y: 0, width: 150, height: 50))
        XCTAssertEqual(BoardShapes.resized(rect, handle: 1, to: Vec2(999, -50), minimum: 8), BoardRect(x: 0, y: -50, width: 100, height: 100))
        XCTAssertEqual(BoardShapes.resized(rect, handle: 5, to: Vec2(0, 80), minimum: 8).height, 80)
        XCTAssertEqual(BoardShapes.resized(rect, handle: 7, to: Vec2(-20, 0), minimum: 8).width, 120)
        // Dragged past the other side: it stops at the minimum.
        XCTAssertEqual(BoardShapes.resized(rect, handle: 3, to: Vec2(-500, 0), minimum: 8).width, 8)
        XCTAssertEqual(BoardShapes.resized(rect, handle: 6, to: Vec2(500, -500), minimum: 8).minX, 84)
        XCTAssertEqual(BoardShapes.resized(rect, handle: 2, to: Vec2(120, 10), minimum: 8).maxY, 50)
    }
}
