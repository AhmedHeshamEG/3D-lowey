import LoweyCore
@testable import LoweyFeatures
import XCTest

@MainActor
final class InkFlowTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Ink \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        return try XCTUnwrap(app.editor)
    }

    private func line(_ y: Double) -> [Vec3] {
        (0 ... 20).map { Vec3(Double($0) * 0.05, y, 0) }
    }

    func testStrokesJoinTheSelectedInkDrawing() throws {
        let editor = try makeEditor()
        editor.tool = .ink
        editor.commitInkStroke(points: line(1), pressures: Array(repeating: 1, count: 21))
        let drawing = try XCTUnwrap(editor.activeInk, "the first stroke starts a drawing and selects it")
        XCTAssertEqual(drawing[.castsShadow]?.boolValue, false)
        editor.commitInkStroke(points: line(1.5), pressures: Array(repeating: 0.5, count: 21))
        let recipe = try XCTUnwrap(editor.activeInk.flatMap(editor.inkRecipe))
        XCTAssertEqual(recipe.strokes.count, 2, "the second stroke joins it")
        XCTAssertEqual(editor.baseScene.objects.values.filter(\.isInk).count, 1)
        // Strokes are stored in the drawing's own space.
        XCTAssertEqual(recipe.strokes[1].points[0].y, 0.5, accuracy: 1e-6)
        // Deselecting starts a new drawing.
        editor.select(nil)
        editor.commitInkStroke(points: line(3), pressures: Array(repeating: 1, count: 21))
        XCTAssertEqual(editor.baseScene.objects.values.filter(\.isInk).count, 2)
        editor.undo()
        XCTAssertEqual(editor.baseScene.objects.values.filter(\.isInk).count, 1)
    }

    func testPickedStrokesAreEditedAsOneStepEach() throws {
        let editor = try makeEditor()
        editor.tool = .ink
        editor.commitInkStroke(points: line(1), pressures: Array(repeating: 1, count: 21))
        editor.commitInkStroke(points: line(2), pressures: Array(repeating: 1, count: 21))
        let id = try XCTUnwrap(editor.activeInk?.id)
        editor.inkStrokes = [1]
        let before = try XCTUnwrap(editor.activeInk.flatMap(editor.inkRecipe))
        editor.scaleInkStrokes(by: 2)
        let thicker = try XCTUnwrap(editor.activeInk.flatMap(editor.inkRecipe))
        XCTAssertEqual(thicker.strokes[1].widths[5], before.strokes[1].widths[5] * 2, accuracy: 1e-9)
        XCTAssertEqual(thicker.strokes[0], before.strokes[0])
        editor.moveInkStrokes(byWorld: Vec3(0, 0, 1), gesture: "drag")
        editor.moveInkStrokes(byWorld: Vec3(0, 0, 1), gesture: "drag")
        editor.endGesture()
        let moved = try XCTUnwrap(editor.activeInk.flatMap(editor.inkRecipe))
        XCTAssertEqual(moved.strokes[1].points[0].z, 2, accuracy: 1e-6)
        editor.undo()
        XCTAssertEqual(editor.activeInk.flatMap(editor.inkRecipe), thicker, "a drag is one undo step")
        editor.deleteInkStrokes()
        XCTAssertEqual(editor.baseScene.objects[id].flatMap(editor.inkRecipe)?.strokes.count, 1)
        editor.setSelection([id])
        editor.inkStrokes = [0]
        editor.deleteInkStrokes()
        XCTAssertNil(editor.baseScene.objects[id], "deleting the last stroke deletes the drawing")
    }

    func testOpacityAndWriteOn() throws {
        let editor = try makeEditor()
        editor.tool = .ink
        editor.commitInkStroke(points: line(1), pressures: Array(repeating: 1, count: 21))
        let id = try XCTUnwrap(editor.activeInk?.id)
        editor.setInkOpacity(0.5)
        editor.setInkOpacity(0.4)
        editor.endGesture()
        XCTAssertEqual(editor.baseScene.objects[id]?.opacity ?? 1, 0.4, accuracy: 1e-9)
        editor.writeOnInk()
        XCTAssertNotNil(editor.timeline.track(for: id, .reveal), "the drawing writes itself on")
    }
}
