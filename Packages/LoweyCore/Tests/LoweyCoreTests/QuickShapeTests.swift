import Foundation
@testable import LoweyCore
import XCTest

/// Hand-drawn strokes (with a wobble, as a finger or Pencil draws them) snap to the right clean shape.
final class QuickShapeTests: XCTestCase {
    /// A deterministic wobble so the strokes look hand-drawn.
    private func wobble(_ index: Int, _ amount: Double) -> Vec2 {
        Vec2(sin(Double(index) * 1.7) * amount, cos(Double(index) * 2.3) * amount)
    }

    private func ellipseStroke(center: Vec2, a: Double, b: Double, turn: Double = 0, sweep: Double = 2 * .pi, count: Int = 90) -> [Vec2] {
        (0 ... count).map { index in
            let t = sweep * Double(index) / Double(count)
            let u = cos(t) * a
            let v = sin(t) * b
            return center + Vec2(u * cos(turn) - v * sin(turn), u * sin(turn) + v * cos(turn)) + wobble(index, 2)
        }
    }

    private func polylineStroke(_ corners: [Vec2], perSide: Int = 25) -> [Vec2] {
        var out: [Vec2] = []
        for index in 0 ..< corners.count - 1 {
            for step in 0 ..< perSide {
                let t = Double(step) / Double(perSide)
                out.append(corners[index] + (corners[index + 1] - corners[index]) * t + wobble(out.count, 1.5))
            }
        }
        out.append(corners[corners.count - 1])
        return out
    }

    func testAShakyStraightStrokeBecomesALine() throws {
        let stroke = (0 ... 60).map { Vec2(Double($0) * 5, 100 + Double($0) * 1.2) + wobble($0, 2) }
        let result = try XCTUnwrap(QuickShape.fit(stroke))
        XCTAssertEqual(result.kind, .line)
        XCTAssertEqual(result.points.first, stroke.first)
        XCTAssertEqual(result.points.last, stroke.last)
    }

    func testARoundLoopBecomesACircle() throws {
        let result = try XCTUnwrap(QuickShape.fit(ellipseStroke(center: Vec2(300, 300), a: 120, b: 115)))
        XCTAssertEqual(result.kind, .circle)
        XCTAssertEqual(result.pivot.x, 300, accuracy: 6)
        XCTAssertEqual(result.pivot.y, 300, accuracy: 6)
        for point in result.points {
            XCTAssertEqual((point - result.pivot).length, 117.5, accuracy: 6, "on one radius")
        }
        let ends = try XCTUnwrap(result.points.first) - XCTUnwrap(result.points.last)
        XCTAssertEqual(ends.length, 0, accuracy: 1e-6, "closed")
    }

    func testAnOvalLoopBecomesAnEllipse() throws {
        let result = try XCTUnwrap(QuickShape.fit(ellipseStroke(center: Vec2(0, 0), a: 200, b: 90, turn: 0.4)))
        XCTAssertEqual(result.kind, .ellipse)
    }

    func testFourCornersBecomeARectangleWithSquareCorners() throws {
        let corners = [Vec2(100, 100), Vec2(400, 110), Vec2(395, 300), Vec2(95, 290), Vec2(102, 104)]
        let result = try XCTUnwrap(QuickShape.fit(polylineStroke(corners)))
        XCTAssertEqual(result.kind, .rectangle)
        // Corners every 12 samples; check the angles are right angles.
        let sides = stride(from: 0, to: 48, by: 12).map { result.points[$0] }
        for index in 0 ..< 4 {
            let a = sides[(index + 3) % 4] - sides[index]
            let b = sides[(index + 1) % 4] - sides[index]
            XCTAssertEqual((a.x * b.x + a.y * b.y) / (a.length * b.length), 0, accuracy: 1e-6)
        }
    }

    func testThreeCornersBecomeATriangle() throws {
        let corners = [Vec2(0, 0), Vec2(300, 20), Vec2(140, 260), Vec2(4, 6)]
        XCTAssertEqual(QuickShape.fit(polylineStroke(corners))?.kind, .triangle)
    }

    func testAnOpenBendBecomesAnArc() throws {
        let result = try XCTUnwrap(QuickShape.fit(ellipseStroke(center: Vec2(0, 0), a: 150, b: 150, sweep: 2.2)))
        XCTAssertEqual(result.kind, .arc)
    }

    func testAnLShapeBecomesAPolyline() throws {
        let result = try XCTUnwrap(QuickShape.fit(polylineStroke([Vec2(0, 0), Vec2(0, 300), Vec2(250, 300)])))
        XCTAssertEqual(result.kind, .polyline)
    }

    func testAScribbleStaysAsDrawn() {
        let scribble = (0 ... 120).map { index -> Vec2 in
            let t = Double(index) * 0.21
            return Vec2(t * 20 + sin(t * 3.1) * 60, cos(t * 1.7) * 80 + sin(t * 4.3) * 40)
        }
        XCTAssertNil(QuickShape.fit(scribble))
        XCTAssertNil(QuickShape.fit([Vec2(0, 0), Vec2(3, 3)]), "a dot is not a shape")
    }

    func testHoldingAndDraggingAdjustsTheShape() throws {
        let line = try XCTUnwrap(QuickShape.fit((0 ... 40).map { Vec2(Double($0) * 5, 0) }))
        let moved = QuickShape.adjusted(line, anchor: Vec2(200, 0), current: Vec2(0, 200))
        XCTAssertEqual(moved.points.first, Vec2(0, 0), "a line keeps its start")
        XCTAssertEqual(moved.points.last, Vec2(0, 200), "and its end follows the finger")

        let circle = try XCTUnwrap(QuickShape.fit(ellipseStroke(center: Vec2(0, 0), a: 100, b: 100)))
        let bigger = QuickShape.adjusted(circle, anchor: circle.pivot + Vec2(100, 0), current: circle.pivot + Vec2(0, 200))
        XCTAssertEqual(bigger.kind, .circle)
        let radius = (bigger.points[10] - bigger.pivot).length
        XCTAssertEqual(radius, 2 * (circle.points[10] - circle.pivot).length, accuracy: 1e-6, "twice as far: twice as big")
    }
}
