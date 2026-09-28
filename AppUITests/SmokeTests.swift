import XCTest

/// Critical flow: create a project, build, undo/redo, switch modes, go home, reopen.
final class SmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Matches by accessibility identifier only (hidden keyboard-shortcut buttons share labels).
    private func button(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.buttons.matching(identifier: identifier).firstMatch
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Phase 3: build a character, see its voice & face tools, add an effect and captions, open the AI bridge.
    @MainActor
    func testCharacterEffectsAndBridge() throws {
        executionTimeAllowance = 470
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let newProject = button(app, "new-project")
        XCTAssertTrue(newProject.waitForExistence(timeout: 20))
        newProject.tap()
        let name = app.textFields["project-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Phase three")
        button(app, "preset-goldenHour").tap()
        button(app, "Create").tap()
        XCTAssertTrue(app.otherElements["stage"].waitForExistence(timeout: 20))

        // A character from the builder.
        button(app, "Add").tap()
        let character = button(app, "add-character")
        XCTAssertTrue(character.waitForExistence(timeout: 5))
        character.tap()
        let done = button(app, "character-done")
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the character builder opens")
        sleep(2)
        screenshot(app, "p3-01-character-builder")
        done.tap()
        let inspectorName = app.textFields["inspector-name"]
        XCTAssertTrue(inspectorName.waitForExistence(timeout: 10))
        XCTAssertEqual(inspectorName.value as? String, "Me")
        screenshot(app, "p3-02-character-in-scene")

        // Animate: voice & face tools, a flash, captions.
        button(app, "mode-animate").tap()
        XCTAssertTrue(button(app, "lip-sync").waitForExistence(timeout: 10), "lip sync is offered for the character")
        XCTAssertTrue(button(app, "face-camera").exists)
        let flash = button(app, "effect-flash")
        if !flash.isHittable { app.swipeUp() }
        if flash.waitForExistence(timeout: 5), flash.isHittable { flash.tap() }
        screenshot(app, "p3-03-animate-character")

        // The AI & laptop bridge.
        button(app, "scene-menu").tap()
        let bridgeItem = app.buttons["AI & laptop bridge…"].firstMatch
        XCTAssertTrue(bridgeItem.waitForExistence(timeout: 5))
        bridgeItem.tap()
        let toggle = app.switches["bridge-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        // Tap the switch knob until it reads on; never tap again once it is on (a second tap turns it back off).
        for _ in 0 ..< 3 where toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            let isOn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
            _ = XCTWaiter.wait(for: [isOn], timeout: 3)
        }
        let pairLine = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'lowey-link pair'")).firstMatch
        let code = app.staticTexts["bridge-code"].waitForExistence(timeout: 8) || pairLine.waitForExistence(timeout: 2)
        screenshot(app, "p3-04-bridge")
        XCTAssertTrue(code, "the pairing code shows")
    }

    @MainActor
    func testCreateBuildUndoReopen() throws {
        executionTimeAllowance = 470
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let newProject = button(app, "new-project")
        XCTAssertTrue(newProject.waitForExistence(timeout: 20))
        screenshot(app, "01-home-empty")
        newProject.tap()

        let name = app.textFields["project-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Smoke test")
        button(app, "preset-night").tap()
        button(app, "Create").tap()

        let stage = app.otherElements["stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        screenshot(app, "02-empty-stage")

        // Add a cube.
        button(app, "Add").tap()
        let addCube = button(app, "add-cube")
        XCTAssertTrue(addCube.waitForExistence(timeout: 5))
        addCube.tap()
        let inspectorName = app.textFields["inspector-name"]
        XCTAssertTrue(inspectorName.waitForExistence(timeout: 5), "inspector shows the new cube")
        XCTAssertEqual(inspectorName.value as? String, "Cube")
        screenshot(app, "03-cube-added")

        // Duplicate, then undo and redo it.
        button(app, "Duplicate").tap()
        XCTAssertEqual(inspectorName.value as? String, "Cube 2", app.staticTexts["debug-trail"].label)
        button(app, "Undo").tap()
        button(app, "Redo").tap()
        button(app, "Undo").tap()

        // Add a sphere, delete it, undo the delete.
        button(app, "Add").tap()
        XCTAssertTrue(button(app, "add-sphere").waitForExistence(timeout: 5))
        button(app, "add-sphere").tap()
        XCTAssertTrue(inspectorName.waitForExistence(timeout: 5))
        XCTAssertEqual(inspectorName.value as? String, "Sphere")
        button(app, "Delete").tap()
        let stillSelected = inspectorName.waitForExistence(timeout: 1)
        XCTAssertFalse(stillSelected, "after delete: \(app.staticTexts["debug-trail"].label)")
        button(app, "Undo").tap()

        // Modes.
        button(app, "mode-look").tap()
        XCTAssertTrue(app.staticTexts["Look"].waitForExistence(timeout: 5))
        button(app, "preset-goldenHour").tap()
        screenshot(app, "04-look-golden-hour")
        button(app, "mode-export").tap()
        XCTAssertTrue(button(app, "take-snapshot").waitForExistence(timeout: 5))
        screenshot(app, "05-export-framing")
        // Animate: a one-tap preset on a new cone, play and pause.
        button(app, "mode-build").tap()
        button(app, "Add").tap()
        XCTAssertTrue(button(app, "add-cone").waitForExistence(timeout: 5))
        button(app, "add-cone").tap()
        button(app, "mode-animate").tap()
        let bounce = button(app, "preset-bounce")
        XCTAssertTrue(bounce.waitForExistence(timeout: 5), "the Animate panel shows presets")
        bounce.tap()
        XCTAssertTrue(app.otherElements["timeline-ruler"].waitForExistence(timeout: 5) || app.staticTexts["timeline-time"].exists)
        button(app, "Play").tap()
        sleep(1)
        button(app, "Pause").tap()
        screenshot(app, "08-animate-timeline")
        // Camera: save a camera, look through it.
        button(app, "mode-camera").tap()
        let saveCamera = button(app, "Save camera from view")
        XCTAssertTrue(saveCamera.waitForExistence(timeout: 5))
        saveCamera.tap()
        sleep(1)
        screenshot(app, "09-camera-look-through")
        button(app, "mode-export").tap()
        XCTAssertTrue(button(app, "export-video").waitForExistence(timeout: 5))
        screenshot(app, "10-export-video")
        button(app, "mode-build").tap()

        // Home and back: the project is there and reopens.
        button(app, "Home").tap()
        let card = app.otherElements["project-Smoke test"].firstMatch
        let cardExists = card.waitForExistence(timeout: 10) || app.staticTexts["Smoke test"].waitForExistence(timeout: 5)
        XCTAssertTrue(cardExists)
        screenshot(app, "06-home-with-project")
        app.staticTexts["Smoke test"].firstMatch.tap()
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        screenshot(app, "07-reopened")
    }

    /// The first-launch tour, every card, including the one that plays the island's camera shot.
    @MainActor
    func testTourRunsToTheEnd() throws {
        executionTimeAllowance = 470
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-sample", "-ui-testing-tour"]
        app.launch()
        let next = button(app, "tour-next")
        XCTAssertTrue(next.waitForExistence(timeout: 90), "the tour opens on the welcome island")
        for step in 1 ... 8 {
            XCTAssertTrue(next.waitForExistence(timeout: 15), "card \(step) shows")
            sleep(2)
            screenshot(app, "tour-\(step)")
            next.tap()
        }
        XCTAssertTrue(app.otherElements["stage"].waitForExistence(timeout: 15), "the editor is there after the tour")
        XCTAssertFalse(next.waitForExistence(timeout: 3), "the tour closed")
        XCTAssertEqual(app.state, .runningForeground, "no crash")
        screenshot(app, "tour-done")
    }

    @MainActor
    func testSampleProjectOpensAllScenes() throws {
        executionTimeAllowance = 470
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
        for index in 2 ... 5 {
            button(app, "scene-menu").tap()
            let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(index) ·")).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.tap()
            sleep(3)
            screenshot(app, "sample-scene-\(index)")
        }
        // The animated opening, seen through its cameras.
        button(app, "mode-camera").tap()
        sleep(2)
        screenshot(app, "sample-opening-camera")
        button(app, "Play").tap()
        sleep(4)
        button(app, "Pause").tap()
        screenshot(app, "sample-opening-playing")
    }
}
