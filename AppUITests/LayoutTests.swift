import XCTest

/// The layout of docs/LAYOUT.md on the iPad simulator: every 2.0 feature is reachable from its home, and the stage
/// owns the screen at rest.
@MainActor
final class LayoutTests: XCTestCase {
    private var app: XCUIApplication!
    private let panels: Set<String> = ["Model", "Draw", "Paint", "Cast", "Actions", "Look", "Select"]

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    /// A plain wait: panels that render pictures (Look's swatches, the Kit's tiles) keep the app busy for a moment,
    /// and querying the UI tree then can time out.
    private func settle(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
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

    private func newProject(_ name: String) {
        XCTAssertTrue(tap("new-project", timeout: 15))
        let field = app.textFields["project-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        tap("create-project")
        XCTAssertTrue(app.otherElements["stage"].waitForExistence(timeout: 15))
    }

    // MARK: Every control has a home

    func testEveryControlInTheLayoutIsReachable() {
        XCTAssertGreaterThan(LayoutWalk.rows.count, 60)
        for row in LayoutWalk.rows where row.precondition == "home" {
            walk(row)
        }
        newProject("Walk")
        for precondition in ["", "cube", "blob", "timeline", "transport"] {
            prepare(precondition)
            for row in LayoutWalk.rows where row.precondition == precondition {
                walk(row)
            }
            shot("Walked [\(precondition.isEmpty ? "start" : precondition)]")
        }
    }

    private func prepare(_ precondition: String) {
        switch precondition {
        case "cube":
            resetTool()
            tap("Model")
            tap("model-add")
            tap("add-cube")
            XCTAssertTrue(element("inspector").waitForExistence(timeout: 5), "a cube to inspect")
        case "blob":
            tap("Cast")
            tap("add-me")
            tap("Cast")
        case "timeline":
            if !element("timeline").exists { tap("Animate") }
        case "transport":
            if element("timeline").exists { tap("Collapse the timeline") }
            if !element("hide-timeline").waitForExistence(timeout: 2) { tap("timeline-toggle") }
        default:
            break
        }
    }

    /// Taps every step but the last; the last must be there.
    private func walk(_ row: LayoutWalk.Row) {
        for step in row.steps.dropLast() {
            XCTAssertTrue(tap(step), "\(row.home) › \(row.control): \(step) isn't there")
            if panels.contains(step) || step.hasPrefix("model-") { settle(step == "Look" ? 3 : 1) }
        }
        if let last = row.steps.last {
            XCTAssertTrue(element(last).waitForExistence(timeout: 5), "\(row.home) › \(row.control): \(last) isn't reachable")
        }
        guard row.steps.count > 1, let first = row.steps.first, panels.contains(first) else { return }
        tap(first)
        if first == "Draw" || first == "Paint" { resetTool() }
    }

    /// Back to tapping (painting tools change the sidebar and hide the joystick).
    private func resetTool() {
        tap("Select")
        tap("Tap")
        tap("Select")
    }

    // MARK: The canvas owns the screen

    func testTheIdleStageHoldsAtLeast85PercentOfTheScreen() throws {
        newProject("Idle")
        let window = app.windows.firstMatch.frame
        let stage = app.otherElements["stage"].frame
        XCTAssertGreaterThan(stage.height, window.height * 0.97, "no timeline under the stage until it's called")
        let leading = ["Home", "Actions", "Look", "Select"].map { element($0).frame }
        let trailing = ["Model", "Draw", "Paint", "Animate", "Cast"].map { element($0).frame }
        var chrome = [union(leading), union(trailing), element("sidebar").frame, element("view-controls").frame]
        if element("scene-name").exists { chrome.append(element("scene-name").frame) }
        // The glass around each cluster reaches a little past its buttons.
        let covered = chrome.map { $0.insetBy(dx: -4, dy: -4).intersection(window) }.reduce(0) { $0 + $1.width * $1.height }
        let share = 1 - covered / (window.width * window.height)
        let attachment = XCTAttachment(string: String(format: "The stage holds %.1f%% of the screen at rest", share * 100))
        attachment.lifetime = .keepAlways
        add(attachment)
        shot("Idle stage")
        XCTAssertGreaterThanOrEqual(share, 0.85, "the canvas owns the screen")
    }

    private func union(_ frames: [CGRect]) -> CGRect {
        frames.dropFirst().reduce(frames.first ?? .zero) { $0.union($1) }
    }

    // MARK: Home with a hundred projects

    func testTheHomeBenchmarkRunsAndReports() {
        newProject("Bench")
        tap("Actions")
        XCTAssertTrue(tap("Diagnostics"))
        XCTAssertTrue(tap("run-home-benchmark", timeout: 10))
        let frames = element("home-benchmark-frames")
        XCTAssertTrue(frames.waitForExistence(timeout: 240), "the benchmark finishes and reports")
        shot("Home benchmark")
        XCTAssertTrue(frames.label.contains("frames"))
        let attachment = XCTAttachment(string: frames.label)
        attachment.name = "Home benchmark (simulator: the device report is the gate)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
