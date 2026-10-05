import Foundation
@testable import LoweyCore
import XCTest

final class DrawingGuideTests: XCTestCase {
    private func wobbly(from start: Vec2, toward end: Vec2) -> [Vec2] {
        (0 ... 20).map { index in
            let t = Double(index) / 20
            return start + (end - start) * t + Vec2(0.01 * sin(Double(index)), 0.01 * cos(Double(index)))
        }
    }

    private func assertOnLine(_ points: [Vec2], direction: Vec2, file: StaticString = #filePath, line: UInt = #line) {
        guard let first = points.first else { return XCTFail("no points", file: file, line: line) }
        for point in points.dropFirst() {
            let offset = point - first
            XCTAssertEqual(offset.cross(direction), 0, accuracy: 1e-9, file: file, line: line)
        }
    }

    func testAGridStraightensToItsAxes() {
        let guide = DrawingGuide(kind: .grid)
        assertOnLine(GuideAssist.constrained(wobbly(from: Vec2(0, 0), toward: Vec2(1, 0.15)), guide: guide), direction: Vec2(1, 0))
        assertOnLine(GuideAssist.constrained(wobbly(from: Vec2(0, 0), toward: Vec2(-0.1, 1)), guide: guide), direction: Vec2(0, 1))
        var turned = guide
        turned.angle = 45
        assertOnLine(GuideAssist.constrained(wobbly(from: Vec2(0, 0), toward: Vec2(1, 0.9)), guide: turned), direction: Vec2(1, 1))
    }

    func testIsometricHasThreeDirections() {
        let guide = DrawingGuide(kind: .isometric)
        let thirty = Vec2(cos(.pi / 6), sin(.pi / 6))
        assertOnLine(GuideAssist.constrained(wobbly(from: Vec2(0, 0), toward: thirty * 2), guide: guide), direction: thirty)
        assertOnLine(GuideAssist.constrained(wobbly(from: Vec2(0, 0), toward: Vec2(-1.7, 1)), guide: guide), direction: Vec2(-thirty.x, thirty.y))
    }

    func testPerspectiveLinesRunToTheVanishingPoints() {
        let guide = DrawingGuide.perspective(points: 2)
        let start = Vec2(0.2, -0.3)
        let left = guide.vanishingPoints[0]
        let pulled = GuideAssist.constrained(wobbly(from: start, toward: start + (left - start) * 0.3), guide: guide)
        // The line starts where the Pencil touched down (the wobble's first point).
        assertOnLine(pulled, direction: left - pulled[0])
        // Two-point perspective keeps upright lines upright.
        assertOnLine(GuideAssist.constrained(wobbly(from: start, toward: start + Vec2(0.02, 0.5)), guide: guide), direction: Vec2(0, 1))
        // Three points: the third replaces the upright.
        let three = DrawingGuide.perspective(points: 3)
        let toward = three.vanishingPoints[2] - start
        let falling = GuideAssist.constrained(wobbly(from: start, toward: start + toward * 0.2), guide: three)
        assertOnLine(falling, direction: three.vanishingPoints[2] - falling[0])
    }

    func testUnassistedGuidesLeaveTheStrokeAlone() {
        var guide = DrawingGuide(kind: .grid)
        guide.assisted = false
        let stroke = wobbly(from: Vec2(0, 0), toward: Vec2(1, 0.3))
        XCTAssertEqual(GuideAssist.constrained(stroke, guide: guide), stroke)
        XCTAssertEqual(GuideAssist.copies(stroke, guide: guide), [stroke])
        XCTAssertEqual(GuideAssist.constrained([Vec2(1, 1)], guide: DrawingGuide()), [Vec2(1, 1)])
    }

    func testSymmetryDrawsTheMirroredCopies() {
        let stroke = [Vec2(0.2, 0.1), Vec2(0.4, 0.3)]
        let vertical = GuideAssist.copies(stroke, guide: DrawingGuide(kind: .symmetry, symmetry: .vertical))
        XCTAssertEqual(vertical.count, 2)
        XCTAssertEqual(vertical[1][0].x, -0.2, accuracy: 1e-12)
        XCTAssertEqual(vertical[1][0].y, 0.1, accuracy: 1e-12)
        let quadrant = GuideAssist.copies(stroke, guide: DrawingGuide(kind: .symmetry, symmetry: .quadrant))
        XCTAssertEqual(quadrant.count, 4)
        XCTAssertEqual(quadrant[3][1].x, -0.4, accuracy: 1e-12)
        XCTAssertEqual(quadrant[3][1].y, -0.3, accuracy: 1e-12)
        let radial = GuideAssist.copies(stroke, guide: DrawingGuide(kind: .symmetry, symmetry: .radial, segments: 4))
        XCTAssertEqual(radial.count, 4)
        XCTAssertEqual(radial[1][0].x, -0.1, accuracy: 1e-12)
        XCTAssertEqual(radial[1][0].y, 0.2, accuracy: 1e-12)
        XCTAssertEqual(GuideAssist.copies(stroke, guide: DrawingGuide(kind: .symmetry, symmetry: .radial, segments: 4, mirrorRadial: true)).count, 8)
        // A moved centre mirrors around it.
        let moved = GuideAssist.copies(stroke, guide: DrawingGuide(kind: .symmetry, origin: Vec2(1, 0), symmetry: .vertical))
        XCTAssertEqual(moved[1][0].x, 1.8, accuracy: 1e-12)
    }

    func testGuideLinesCoverTheRectAndStayFew() {
        let rect = (min: Vec2(-0.9, -0.5), max: Vec2(0.9, 0.5))
        let grid = GuideLines.lines(DrawingGuide(kind: .grid, spacing: 0.1), in: rect)
        XCTAssertGreaterThan(grid.count, 20)
        XCTAssertTrue(grid.contains { $0.major })
        let tiny = GuideLines.lines(DrawingGuide(kind: .grid, spacing: 1e-6), in: rect)
        XCTAssertLessThanOrEqual(tiny.count, GuideLines.maximum + 10)
        XCTAssertEqual(GuideLines.lines(DrawingGuide(kind: .symmetry, symmetry: .quadrant), in: rect).count, 2)
        XCTAssertEqual(GuideLines.lines(DrawingGuide(kind: .symmetry, symmetry: .radial, segments: 5), in: rect).count, 5)
        let perspective = GuideLines.lines(.perspective(points: 2), in: rect)
        XCTAssertEqual(perspective.filter(\.major).count, 1, "one horizon")
    }

    func testGuidesRoundTripThroughJSON() throws {
        let guide = DrawingGuide(kind: .symmetry, spacing: 0.2, angle: 15, symmetry: .radial, segments: 7, mirrorRadial: true)
        XCTAssertEqual(try JSONDecoder().decode(DrawingGuide.self, from: JSONEncoder().encode(guide)), guide)
    }

    func testGuidesLiveInTheWorkspace() throws {
        var workspace = ProjectWorkspace()
        workspace.frameGuide = .perspective(points: 3)
        workspace.planeGuide = DrawingGuide(kind: .symmetry, symmetry: .radial)
        let back = try JSONDecoder().decode(ProjectWorkspace.self, from: JSONEncoder().encode(workspace))
        XCTAssertEqual(back.frameGuide, workspace.frameGuide)
        XCTAssertEqual(back.planeGuide, workspace.planeGuide)
        XCTAssertNil(try JSONDecoder().decode(ProjectWorkspace.self, from: Data(#"{"frameGuide": 3}"#.utf8)).frameGuide)
    }
}
