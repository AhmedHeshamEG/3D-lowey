import XCTest

/// The Schizzo board on the iPad simulator: plan on it, pin a note to the project, find it over the stage.
final class BoardTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let element = element(identifier)
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(identifier) is missing", file: file, line: line)
        element.tap()
    }

    private func newProject(_ name: String) {
        tap("new-project")
        let field = app.textFields["project-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        tap("create-project")
        XCTAssertTrue(app.otherElements["stage"].waitForExistence(timeout: 15))
    }

    private func point(_ canvas: XCUIElement, _ x: Double, _ y: Double) -> XCUICoordinate {
        canvas.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    func testPlanOnTheBoardAndPinItToTheProject() {
        newProject("Planned")
        tap("Actions")
        tap("open-board")
        let canvas = element("board-canvas")
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "the board covers the stage")
        XCTAssertFalse(element("Undo").isEnabled, "nothing to undo on a new board")
        shot("Empty board")

        // A stroke with a finger (no Pencil has touched this iPad, so one finger draws).
        point(canvas, 0.3, 0.45).press(forDuration: 0.05, thenDragTo: point(canvas, 0.55, 0.6))
        XCTAssertTrue(element("Undo").isEnabled, "the stroke is on the board")

        // A note, written on.
        tap("Note")
        point(canvas, 0.7, 0.35).tap()
        let words = element("board-note-text")
        XCTAssertTrue(words.waitForExistence(timeout: 5), "a new note opens for typing")
        words.typeText("Lamp")
        shot("A stroke and a note")

        // Picked, it can be pinned to the project.
        tap("Select")
        point(canvas, 0.7, 0.35).tap()
        tap("board-pin")
        shot("Pinned")
        tap("board-close")
        XCTAssertTrue(app.otherElements["stage"].waitForExistence(timeout: 10), "back on the stage")
        XCTAssertTrue(element("reference-card").waitForExistence(timeout: 10), "the pinned note floats over the stage")
        shot("Reference card over the stage")

        // The board is the project's: it's all there when it opens again, undo included.
        tap("Actions")
        tap("open-board")
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertTrue(element("Undo").isEnabled, "the board came back with its history")
        tap("board-close")
    }
}
