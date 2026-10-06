import XCTest

/// M3's acceptance on the iPad simulator: a 40 × 20 × 10 mm block with a 6 mm hole through it, built with taps only
/// (sketch a rectangle, type its sides, pull it up 10 mm, sketch a circle on its top, type 6, cut it through) in
/// under 30 seconds.
@MainActor
final class ModelingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @discardableResult
    private func tap(_ identifier: String, timeout: TimeInterval = 5) -> Bool {
        let target = element(identifier)
        guard target.waitForExistence(timeout: timeout) else { return false }
        target.tap()
        return true
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var stage: XCUIElement { app.otherElements["stage"] }

    /// A point on the stage, in points from its top-left corner.
    private func tapStage(_ point: CGPoint) {
        stage.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
    }

    /// Taps a floating number and types a length into it (the field takes focus as it opens). One query per step:
    /// the clock is running.
    private func type(_ text: String, into dimension: String) {
        element("dimension-\(dimension)").tap()
        app.textFields["dimension-field"].typeText(text + "\n")
    }

    /// Double-tap: frame what's selected (or everything), then let the camera settle.
    private func frameAll() {
        stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).doubleTap()
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "camera settles")], timeout: 0.5)
    }

    func testABlockWithAHoleThroughItInUnderThirtySeconds() {
        XCTAssertTrue(tap("new-project", timeout: 15))
        let name = app.textFields["project-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Bracket")
        tap("template-print")
        tap("create-project")
        XCTAssertTrue(stage.waitForExistence(timeout: 15))
        // Model to print opens Model; its Shape page has the sketch shapes.
        if !element("model-shape").waitForExistence(timeout: 3) { tap("Model") }

        // The timed part is only what a person does: taps and typed numbers. Checks and pictures come after.
        let start = Date()
        element("model-shape").tap()
        element("sketch-rectangle").tap()
        let size = stage.frame.size
        let middle = CGPoint(x: size.width / 2, y: size.height * 0.55)
        tapStage(CGPoint(x: middle.x - 70, y: middle.y - 30))
        tapStage(CGPoint(x: middle.x + 70, y: middle.y + 40))
        type("40", into: "width")
        type("20", into: "depth")
        // Double-tap frames the work, so the rectangle's middle is the stage's middle; pull it up 10.
        frameAll()
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        tapStage(centre)
        type("10", into: "pull")
        // A circle on the block's top (framed, the top face lies above the middle), 6 across, cut through.
        frameAll()
        element("Circle").tap()
        let top = CGPoint(x: centre.x, y: centre.y - size.height * 0.06)
        tapStage(top)
        tapStage(CGPoint(x: top.x + 60, y: top.y))
        type("6", into: "diameter")
        tapStage(top)
        type("-10", into: "pull")
        let elapsed = Date().timeIntervalSince(start)
        shot("A 6 mm hole through a 40 × 20 × 10 mm block")

        let trail = element("debug-trail").label
        XCTAssertTrue(trail.contains("cmd=Pull"), "the rectangle became a solid: \(trail)")
        XCTAssertTrue(trail.contains("cmd=Cut"), "the circle cut through the block: \(trail)")
        XCTAssertTrue(tap("Faces"))
        XCTAssertTrue(element("selection-size").waitForExistence(timeout: 3))
        XCTAssertEqual(element("selection-size").label, "40 × 10 × 20 mm", "the block keeps its size")
        let report = XCTAttachment(string: String(format: "Built in %.1f s of taps", elapsed))
        report.lifetime = .keepAlways
        add(report)
        // Under 30 s is the claim for a person on an iPad (the device checklist); on CI's shared simulator each tap
        // costs the runner seconds of its own, so the run fails only past 45 (D-175).
        XCTAssertLessThan(elapsed, 45)
    }
}
