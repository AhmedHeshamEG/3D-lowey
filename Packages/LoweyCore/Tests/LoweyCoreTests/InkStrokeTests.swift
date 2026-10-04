import Foundation
@testable import LoweyCore
import XCTest

final class InkStrokeTests: XCTestCase {
    private let line = DrawingRecipe.Stroke(points: (0 ... 10).map { Vec3(Double($0) * 0.1, 0, 0) },
                                            widths: Array(repeating: 0.02, count: 11))

    private func recipe(_ strokes: [DrawingRecipe.Stroke]) -> DrawingRecipe {
        DrawingRecipe(style: .ink, strokes: strokes, normal: .unitZ)
    }

    func testRibbonFacesTheEye() throws {
        let eye = Vec3(0.5, 0, 5)
        let mesh = InkMesher.mesh(for: recipe([line]), eye: eye)
        XCTAssertEqual(mesh.positions.count, 22)
        XCTAssertEqual(mesh.triangleCount, 20)
        // Seen from +Z, the ribbon spreads along Y (perpendicular to the stroke and to the view).
        let bounds = try XCTUnwrap(mesh.bounds)
        XCTAssertGreaterThan(bounds.max.y - bounds.min.y, 0.03)
        XCTAssertEqual(bounds.max.z - bounds.min.z, 0, accuracy: 1e-6)
        for normal in mesh.normals {
            XCTAssertGreaterThan(normal.z, 0.9)
        }
        // Seen from above, it spreads along Z instead.
        let fromAbove = try XCTUnwrap(InkMesher.mesh(for: recipe([line]), eye: Vec3(0.5, 5, 0)).bounds)
        XCTAssertGreaterThan(fromAbove.max.z - fromAbove.min.z, 0.03)
        XCTAssertEqual(fromAbove.max.y - fromAbove.min.y, 0, accuracy: 1e-6)
    }

    func testEndsTaper() {
        let mesh = InkMesher.mesh(for: recipe([line]), eye: Vec3(0.5, 0, 5))
        func width(at point: Int) -> Float { abs(mesh.positions[point * 2].y - mesh.positions[point * 2 + 1].y) }
        XCTAssertLessThan(width(at: 0), width(at: 5) * 0.3)
        XCTAssertLessThan(width(at: 10), width(at: 5) * 0.3)
        XCTAssertEqual(width(at: 5), 0.04, accuracy: 1e-4)
    }

    func testRevealWritesTheDrawingOn() throws {
        let second = DrawingRecipe.Stroke(points: line.points.map { $0 + Vec3(0, 1, 0) }, widths: line.widths)
        let drawing = recipe([line, second])
        XCTAssertTrue(InkMesher.mesh(for: drawing, eye: .unitZ, reveal: 0).isEmpty)
        let quarter = try XCTUnwrap(InkMesher.mesh(for: drawing, eye: Vec3(0, 0, 5), reveal: 0.25).bounds)
        XCTAssertEqual(quarter.max.x, 0.5, accuracy: 1e-3)
        XCTAssertLessThan(quarter.max.y, 0.5, "the second stroke isn't drawn yet")
        let threeQuarters = try XCTUnwrap(InkMesher.mesh(for: drawing, eye: Vec3(0, 0, 5), reveal: 0.75).bounds)
        XCTAssertGreaterThan(threeQuarters.max.y, 0.9)
        XCTAssertEqual(InkMesher.mesh(for: drawing, eye: Vec3(0, 0, 5)).triangleCount, 40)
    }

    func testDotsAndPlaneFallback() {
        let dot = DrawingRecipe.Stroke(points: [.zero], widths: [0.05])
        XCTAssertEqual(InkMesher.mesh(for: recipe([dot]), eye: Vec3(0, 0, 3)).triangleCount, 2)
        // No eye: lies across the plane normal (export, picking).
        let flat = DrawingMesher.mesh(for: recipe([line]))
        XCTAssertFalse(flat.isEmpty)
        XCTAssertTrue(flat.normals.allSatisfy { $0.z > 0.99 })
    }

    func testEraseSplitsStrokes() {
        let erased = InkEditing.erasing(recipe([line])) { _, point in point == 4 || point == 5 }
        XCTAssertEqual(erased.strokes.count, 2)
        XCTAssertEqual(erased.strokes[0].points.count, 4)
        XCTAssertEqual(erased.strokes[1].points.count, 5)
        // Erasing all but one point of a piece drops it.
        let mostly = InkEditing.erasing(recipe([line])) { _, point in point != 3 }
        XCTAssertTrue(mostly.strokes.isEmpty)
    }

    func testStrokeEditing() throws {
        let other = DrawingRecipe.Stroke(points: [Vec3(0, 1, 0), Vec3(0, 2, 0)], widths: [0.01, 0.03])
        var drawing = InkEditing.appending(other, to: recipe([line]))
        XCTAssertEqual(drawing.strokes.count, 2)
        XCTAssertEqual(InkEditing.strokes(of: drawing) { $0.y > 1.5 }, [1])
        drawing = InkEditing.moving([1], by: Vec3(1, 0, 0), in: drawing)
        XCTAssertEqual(drawing.strokes[1].points[0], Vec3(1, 1, 0))
        XCTAssertEqual(drawing.strokes[0].points[0], .zero, "other strokes stay")
        drawing = InkEditing.scalingWidths([1], by: 2, in: drawing)
        XCTAssertEqual(drawing.strokes[1].widths, [0.02, 0.06])
        let wobbly = DrawingRecipe.Stroke(points: (0 ... 40).map { Vec3(Double($0) * 0.02, $0 % 2 == 0 ? 0.01 : -0.01, 0) },
                                          widths: Array(repeating: 0.02, count: 41))
        let smoothed = InkEditing.smoothing([0], by: 1, in: recipe([wobbly]))
        let maxOffset = smoothed.strokes[0].points.dropFirst().dropLast().map { abs($0.y) }.max() ?? 1
        XCTAssertLessThan(maxOffset, 0.006)
        XCTAssertEqual(smoothed.strokes[0].points.first, wobbly.points.first)
        XCTAssertEqual(InkEditing.removing([0], from: drawing).strokes.count, 1)
    }

    func testInkObjectsAreLineArt() throws {
        var factory = ObjectFactory(ids: .sequential("ink"))
        let object = factory.drawing(recipe([line]), transform: .identity, color: .rgba(RGBA(0.1, 0.1, 0.12)))
        XCTAssertEqual(object.name, "Ink")
        XCTAssertTrue(object.isInk)
        XCTAssertEqual(object[.castsShadow]?.boolValue, false)
        // Round-trips like every drawing.
        let data = try JSONEncoder().encode(object)
        XCTAssertEqual(try JSONDecoder().decode(SceneObject.self, from: data), object)
        // Editing a stroke is one undoable command.
        var document = makeDocument()
        _ = try EditCommand.insert(SceneFragment(object: object), parent: nil, index: nil).apply(to: &document)
        let edited = InkEditing.removing([0], from: recipe([line]))
        _ = try assertReverts(.setKind(object.id, .drawing(edited)), on: document)
    }

    func testAnEraserGestureIsOneUndoStep() throws {
        var factory = ObjectFactory(ids: .sequential("ink"))
        let object = factory.drawing(recipe([line]), transform: .identity, color: .palette(0))
        var session = EditSession(document: makeDocument())
        try session.perform(.insert(SceneFragment(object: object), parent: nil, index: nil))
        var current = recipe([line])
        for point in 2 ... 6 {
            current = InkEditing.erasing(current) { _, index in index == point }
            try session.perform(.setKind(object.id, .drawing(current)), coalesceKey: "eraser")
        }
        session.endCoalescing()
        XCTAssertEqual(session.undoStack.count, 2, "insert + one erase")
        try session.undo()
        XCTAssertEqual(session.document.scene.objects[object.id]?.kind, .drawing(recipe([line])))
    }

    func testWriteOnPreset() {
        var factory = ObjectFactory(ids: .sequential("ink"))
        let object = factory.drawing(recipe([line]), transform: .identity, color: .palette(0))
        let keys = PresetBuilder.keys(.typewriter, for: object, at: 1, options: PresetOptions(duration: 2, amplitude: 1))
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].1, .reveal)
        XCTAssertEqual(keys[0].2.map(\.time), [1, 3])
        XCTAssertEqual(keys[0].2.last?.value, .float(1))
    }
}
