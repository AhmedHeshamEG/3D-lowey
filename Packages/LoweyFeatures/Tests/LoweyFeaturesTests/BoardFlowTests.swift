import HmmBoard
import HmmBoardUI
import LoweyCore
@testable import LoweyFeatures
import XCTest

/// The Schizzo board in a project: where it lives, what a pin becomes, and that it comes back.
@MainActor
final class BoardFlowTests: XCTestCase {
    private var app: AppModel?

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: AppSettings.boardEnabled)
    }

    private func makeEditor(_ template: StarterTemplate = .blank) throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Board \(UUID().uuidString.prefix(6))", template: template, mood: template.mood, look: template.lookPresetID)
        return try XCTUnwrap(app.editor)
    }

    private func drawLine(on board: BoardModel, y: Double) {
        board.mutate { session in
            session.tool = .draw
            session.begin(BrushInput(point: Vec2(0, y), pressure: 1, time: 0), slack: 6)
            session.move(BrushInput(point: Vec2(120, y), pressure: 1, time: 0.2))
            session.end(BrushInput(point: Vec2(120, y), pressure: 1, time: 0.2), slack: 6)
        }
    }

    func testTheBoardLivesInTheProjectAndComesBack() async throws {
        let editor = try makeEditor()
        XCTAssertNil(editor.board, "a project that never opens its board carries none")
        XCTAssertFalse(FileManager.default.fileExists(atPath: editor.projectURL.appendingPathComponent(ProjectLayout.boardFolder).path))
        editor.openBoard()
        XCTAssertTrue(editor.boardShown)
        let board = try XCTUnwrap(editor.board)
        await board.load()
        drawLine(on: board, y: 20)
        board.mutate { session in
            session.tool = .note
            session.begin(BrushInput(point: Vec2(300, 300), pressure: 1), slack: 6)
            session.end(BrushInput(point: Vec2(300, 300), pressure: 1), slack: 6)
            session.setText("Tower first", ofNote: session.editingNote ?? "")
        }
        editor.closeBoard()
        XCTAssertFalse(editor.boardShown)
        XCTAssertTrue(FileManager.default.fileExists(atPath: editor.projectURL.appendingPathComponent("board/board.json").path))

        await editor.saveNow(thumbnail: false)
        editor.tearDown()
        let app = try XCTUnwrap(app)
        app.open(url: editor.projectURL)
        let reopened = try XCTUnwrap(app.editor)
        let again = reopened.projectBoard()
        await again.load()
        XCTAssertEqual(again.session.board.items.count, 2)
        XCTAssertEqual(again.session.board.items.last?.note?.text, "Tower first")
        XCTAssertTrue(again.session.canUndo, "the board's undo survives closing the project")
    }

    func testAPinFloatsOverTheStageAndCanStandInTheScene() async throws {
        let editor = try makeEditor()
        let board = editor.projectBoard()
        await board.load()
        drawLine(on: board, y: 20)
        XCTAssertTrue(board.canPin)
        board.pinExcerpt(of: nil)
        let card = try XCTUnwrap(editor.references.first, "the pin is a card over the stage")
        XCTAssertTrue(card.image.hasPrefix("references/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: editor.referenceURL(card).path))
        XCTAssertGreaterThan(card.aspect, 0)
        XCTAssertTrue(editor.baseScene.objects.isEmpty, "a card isn't in the scene")

        // Moved and sized, it stays where it was put when the project opens again.
        var moved = card
        moved.x = 0.2
        moved.width = 5000
        editor.updateReference(moved)
        XCTAssertEqual(editor.references.first?.width, ReferenceCard.widthRange.upperBound)
        editor.saveWorkspace()
        XCTAssertEqual(editor.store.loadWorkspace(at: editor.projectURL).references.first?.x, 0.2)

        // The same picture as a plane in the scene: one undoable object.
        editor.standReferenceInScene(card)
        let plane = try XCTUnwrap(editor.singleSelection)
        guard case let .card(recipe) = plane.kind else { return XCTFail("a pinned picture stands in the scene as a card") }
        XCTAssertEqual(recipe.image, card.image)
        XCTAssertEqual(plane.name, "Reference")
        editor.undo()
        XCTAssertTrue(editor.baseScene.objects.isEmpty)
        XCTAssertEqual(editor.references.count, 1, "the card stays")

        editor.removeReference(card.id)
        XCTAssertTrue(editor.references.isEmpty)
    }

    func testSketchOpensOnTheBoardOnceAndTheSwitchPutsItAway() throws {
        let sketch = try makeEditor(.sketch)
        XCTAssertTrue(sketch.boardShown, "a Sketch project opens on its board")
        XCTAssertNil(sketch.store.loadWorkspace(at: sketch.projectURL).firstPanel, "once")
        sketch.closeBoard()

        UserDefaults.standard.set(false, forKey: AppSettings.boardEnabled)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.boardEnabled) }
        let plain = try makeEditor()
        plain.openBoard()
        XCTAssertFalse(plain.boardShown, "switched off in Settings")
    }
}
