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

    /// Taps a floating number and types a length into it.
    private func type(_ text: String, into dimension: String) {
        XCTAssertTrue(tap("dimension-\(dimension)"), "the \(dimension) number floats on the stage")
        let field = app.textFields["dimension-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3), "tapping \(dimension) opens a field")
        field.tap()
        field.typeText(text + "\n")
    }

    private func centre(of identifier: String) -> CGPoint {
        let frame = element(identifier).frame
        let origin = stage.frame.origin
        return CGPoint(x: frame.midX - origin.x, y: frame.midY - origin.y)
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

        let start = Date()
        XCTAssertTrue(tap("model-shape"))
        XCTAssertTrue(tap("sketch-rectangle"))
        let size = stage.frame.size
        let middle = CGPoint(x: size.width / 2, y: size.height * 0.55)
        tapStage(CGPoint(x: middle.x - 70, y: middle.y - 30))
        tapStage(CGPoint(x: middle.x + 70, y: middle.y + 40))
        type("40", into: "width")
        type("20", into: "depth")
        shot("A 40 × 20 mm rectangle")

        // Inside the rectangle: across from its two sizes (the middle of its bottom side and of its right side).
        let inside = CGPoint(x: centre(of: "dimension-width").x, y: centre(of: "dimension-depth").y)
        tapStage(inside)
        type("10", into: "pull")
        XCTAssertTrue(element("debug-trail").label.contains("cmd=Pull"), "the region became a solid")
        let sizeLabel = element("selection-size")
        XCTAssertTrue(sizeLabel.waitForExistence(timeout: 3))
        XCTAssertEqual(sizeLabel.label, "40 × 10 × 20 mm")
        shot("A 40 × 20 × 10 mm block")

        // A circle on the block's top (a little above the region's middle: the top face, not the front).
        XCTAssertTrue(tap("Circle"))
        let top = CGPoint(x: inside.x, y: inside.y - 24)
        tapStage(top)
        tapStage(CGPoint(x: top.x + 60, y: top.y))
        type("6", into: "diameter")
        tapStage(top)
        type("-10", into: "pull")
        let elapsed = Date().timeIntervalSince(start)
        shot("A 6 mm hole through it")

        let trail = element("debug-trail").label
        XCTAssertTrue(trail.contains("cmd=Cut"), "the circle cut through the block: \(trail)")
        XCTAssertEqual(element("selection-size").label, "40 × 10 × 20 mm", "the block keeps its size")
        let report = XCTAttachment(string: String(format: "Built in %.1f s of taps", elapsed))
        report.lifetime = .keepAlways
        add(report)
        XCTAssertLessThan(elapsed, 30)
    }
}
