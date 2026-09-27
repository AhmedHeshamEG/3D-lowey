import XCTest

/// Critical flow: create a project, build, undo/redo, switch modes, go home, reopen.
final class SmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCreateBuildUndoReopen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let newProject = app.buttons["new-project"]
        XCTAssertTrue(newProject.waitForExistence(timeout: 20))
        screenshot(app, "01-home-empty")
        newProject.tap()

        let name = app.textFields["project-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Smoke test")
        app.buttons["preset-night"].tap()
        app.buttons["Create"].tap()

        let stage = app.otherElements["stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        screenshot(app, "02-empty-stage")

        // Add a cube.
        app.buttons["Add"].tap()
        let addCube = app.buttons["add-cube"]
        XCTAssertTrue(addCube.waitForExistence(timeout: 5))
        addCube.tap()
        let inspectorName = app.textFields["inspector-name"]
        XCTAssertTrue(inspectorName.waitForExistence(timeout: 5), "inspector shows the new cube")
        XCTAssertEqual(inspectorName.value as? String, "Cube")
        screenshot(app, "03-cube-added")

        // Duplicate, then undo and redo it.
        app.buttons["Duplicate"].tap()
        app.buttons["Undo"].tap()
        app.buttons["Redo"].tap()
        app.buttons["Undo"].tap()

        // Add a sphere, delete it, undo the delete.
        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["add-sphere"].waitForExistence(timeout: 5))
        app.buttons["add-sphere"].tap()
        XCTAssertTrue(inspectorName.waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        XCTAssertFalse(inspectorName.waitForExistence(timeout: 1))
        app.buttons["Undo"].tap()

        // Modes.
        app.buttons["mode-look"].tap()
        XCTAssertTrue(app.staticTexts["Look"].waitForExistence(timeout: 5))
        app.buttons["preset-goldenHour"].tap()
        screenshot(app, "04-look-golden-hour")
        app.buttons["mode-export"].tap()
        XCTAssertTrue(app.buttons["take-snapshot"].waitForExistence(timeout: 5))
        screenshot(app, "05-export-framing")
        app.buttons["mode-animate"].tap()
        app.buttons["mode-build"].tap()

        // Home and back: the project is there and reopens.
        app.buttons["Home"].tap()
        let card = app.otherElements["project-Smoke test"].firstMatch
        let cardExists = card.waitForExistence(timeout: 10) || app.staticTexts["Smoke test"].waitForExistence(timeout: 5)
        XCTAssertTrue(cardExists)
        screenshot(app, "06-home-with-project")
        app.staticTexts["Smoke test"].firstMatch.tap()
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        screenshot(app, "07-reopened")
    }

    @MainActor
    func testSampleProjectOpensAllScenes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-sample"]
        app.launch()
        let sample = app.staticTexts["Enigma — sets"].firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 20))
        sample.tap()
        let stage = app.otherElements["stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        sleep(3)
        screenshot(app, "sample-scene-1")
        for index in 2 ... 3 {
            app.buttons["scene-menu"].tap()
            let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(index) ·")).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.tap()
            sleep(3)
            screenshot(app, "sample-scene-\(index)")
        }
    }
}
