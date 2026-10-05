import XCTest

/// The main flows on the iPad simulator, with screenshots of each step (CI uploads them).
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String] = []) {
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(identifier) is missing", file: file, line: line)
        element.tap()
    }

    private func newProject(_ name: String) {
        tap("new-project")
        let field = app.textFields["project-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        tap("look-comic")
        shot("New project")
        tap("create-project")
        XCTAssertTrue(app.otherElements["stage"].waitForExistence(timeout: 15))
    }

    func testCreateBuildUndoAndReopen() {
        launch()
        shot("Home")
        newProject("Smoke")
        shot("Empty stage")
        tap("Model")
        tap("add-cube")
        XCTAssertTrue(app.otherElements["inspector"].waitForExistence(timeout: 5), "the inspector floats in beside the new cube")
        shot("A cube")
        tap("Model")
        tap("add-sphere")
        tap("gizmo-rotate")
        shot("Turn gizmo")
        tap("Undo")
        tap("Redo")
        tap("Home")
        let card = app.descendants(matching: .any)["project-Smoke"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.otherElements["stage"].waitForExistence(timeout: 15))
        shot("Reopened")
    }

    func testLookCameraDirectorViewAndExportSheet() {
        launch()
        newProject("Director")
        tap("Look")
        tap("look-clay")
        tap("duplicate-look")
        shot("My Look")
        tap("Model")
        tap("add-camera")
        tap("director-view")
        shot("Director view")
        tap("director-view")
        tap("Actions")
        tap("open-export")
        XCTAssertTrue(app.descendants(matching: .any)["export-hd1080"].firstMatch.waitForExistence(timeout: 5))
        shot("Export")
    }

    func testCastTimelineAndDiagnostics() {
        launch()
        newProject("Cast")
        tap("Cast")
        tap("add-me")
        tap("Cast")
        shot("A Blob")
        tap("Animate")
        tap("timeline-mode-keyframe")
        tap("timeline-mode-perform")
        shot("Perform")
        tap("Actions")
        tap("Diagnostics")
        XCTAssertTrue(app.descendants(matching: .any)["run-benchmark"].firstMatch.waitForExistence(timeout: 5))
        shot("Diagnostics")
    }

    func testTourRunsToTheEnd() {
        launch(["-ui-testing-tour", "-ui-testing-sample"])
        XCTAssertTrue(app.descendants(matching: .any)["tour"].firstMatch.waitForExistence(timeout: 30))
        for index in 0 ..< 7 {
            shot("Tour \(index + 1)")
            tap("tour-next")
        }
        XCTAssertFalse(app.descendants(matching: .any)["tour"].firstMatch.exists)
    }

    /// Arabic: the chrome mirrors (the making tools move to the left, the document cluster to the right), the labels are
    /// Arabic, and the timeline keeps time running left to right.
    func testArabicIsRightToLeft() {
        launch(["-AppleLanguages", "(ar)", "-AppleLocale", "ar_EG"])
        shot("Theater (ar)")
        newProject("RTL")
        let model = app.descendants(matching: .any)["Model"].firstMatch
        let look = app.descendants(matching: .any)["Look"].firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 10))
        XCTAssertTrue(look.exists)
        XCTAssertLessThan(model.frame.midX, look.frame.midX, "Model (top right in English) sits on the left in Arabic")
        XCTAssertNotEqual(model.label, "Model", "the label is translated")
        tap("Model")
        shot("Model panel (ar)")
    }

    func testItalianLabels() {
        launch(["-AppleLanguages", "(it)", "-AppleLocale", "it_IT"])
        newProject("Italiano")
        let undo = app.descendants(matching: .any)["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        XCTAssertEqual(undo.label, "Annulla")
        shot("Stage (it)")
    }
}
