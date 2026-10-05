import LoweyCore
@testable import LoweyFeatures
import XCTest

/// Brushes in the editor: a stroke keeps the brush it was drawn with (frozen in the project, one undo step with the
/// stroke), library edits never reach finished strokes, and the drawing guides straighten and mirror strokes.
@MainActor
final class BrushFlowTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Brush \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        return try XCTUnwrap(app.editor)
    }

    private func line(_ y: Double) -> [Vec3] {
        (0 ... 20).map { Vec3(Double($0) * 0.05, y, 0) }
    }

    func testAStrokeFreezesItsBrushInTheProjectAsOneStep() throws {
        let editor = try makeEditor()
        editor.tool = .ink
        editor.app.brushes.select("builtin.pencil", for: .ink)
        editor.commitInkStroke(points: line(1), pressures: Array(repeating: 0.7, count: 21))
        let key = BrushKey.key(for: BuiltInBrushes.pencil)
        let stroke = try XCTUnwrap(editor.activeInk.flatMap(editor.inkRecipe)?.strokes.first)
        XCTAssertEqual(stroke.brush, key)
        XCTAssertNotNil(stroke.seed)
        XCTAssertEqual(stroke.alphas?.count, stroke.points.count, "the pencil's pressure opacity is kept per point")
        XCTAssertEqual(editor.document.project.brushes[key]?.name, "Pencil")
        editor.undo()
        XCTAssertTrue(editor.document.project.brushes.isEmpty, "the brush's first use undoes with its stroke")
        XCTAssertTrue(editor.baseScene.objects.values.filter(\.isInk).isEmpty)
    }

    func testLibraryEditsNeverReachFinishedStrokes() throws {
        let editor = try makeEditor()
        editor.tool = .ink
        editor.app.brushes.select(BuiltInBrushes.inkPenID, for: .ink)
        editor.commitInkStroke(points: line(1), pressures: Array(repeating: 1, count: 21))
        let first = try XCTUnwrap(editor.activeInk.flatMap(editor.inkRecipe)?.strokes.first?.brush)
        var edited = BuiltInBrushes.inkPen
        edited.stroke.spacing = 0.5
        editor.app.brushes.update(edited)
        editor.commitInkStroke(points: line(1.2), pressures: Array(repeating: 1, count: 21))
        let strokes = try XCTUnwrap(editor.activeInk.flatMap(editor.inkRecipe)?.strokes)
        XCTAssertNotEqual(strokes[1].brush, first, "the edited brush is a new key")
        XCTAssertEqual(editor.document.project.brushes[first]?.stroke.spacing, BuiltInBrushes.inkPen.stroke.spacing)
        XCTAssertEqual(editor.document.project.brushes.count, 2)
        editor.app.brushes.reset(BuiltInBrushes.inkPenID)
    }

    func testSymmetryOnTheGuidePlaneMirrorsInkAsOneStep() throws {
        let editor = try makeEditor()
        editor.tool = .ink
        editor.planeGuide = DrawingGuide(kind: .symmetry, symmetry: .vertical)
        let surface = GuideSurface.plane(origin: .zero, normal: .unitZ)
        let samples = line(1).map { BrushInput(point: $0 + Vec3(0.2, 0, 0), pressure: 1, time: 0) }
        let copies = editor.guidedOnPlane(samples.map(\.point), guide: surface)
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(copies[1][0].x, -copies[0][0].x, accuracy: 1e-9, "mirrored across the plane's upright axis")
        editor.commitInkStrokes(copies.map { copy in zip(samples, copy).map { BrushInput(point: $1, pressure: $0.pressure, time: $0.time) } },
                                seed: 7)
        XCTAssertEqual(editor.activeInk.flatMap(editor.inkRecipe)?.strokes.count, 2)
        editor.undo()
        XCTAssertTrue(editor.baseScene.objects.values.filter(\.isInk).isEmpty, "both copies are one step")
    }

    func testTheLibraryDuplicatesResetsAndRemembersTheToolsBrush() throws {
        let editor = try makeEditor()
        let brushes = editor.app.brushes
        let copy = try XCTUnwrap(brushes.duplicate("builtin.charcoal"))
        XCTAssertEqual(brushes.library.brush(copy)?.name, "Charcoal copy")
        brushes.select(copy, for: .flipbook)
        XCTAssertEqual(brushes.brush(for: .flipbook).id, copy)
        brushes.delete(copy)
        XCTAssertEqual(brushes.brush(for: .flipbook).id, BuiltInBrushes.inkPenID, "a deleted brush falls back to Ink Pen")
    }
}
