import XCTest

/// The layout of docs/LAYOUT.md on the iPad simulator: every 2.0 feature is reachable from its home, and the stage
/// owns the screen at rest.
@MainActor
final class LayoutTests: XCTestCase {
    private var app: XCUIApplication!
    private let panels: Set<String> = ["Model", "Draw", "Paint", "Cast", "Actions", "Look", "Select"]

    override func setUp() async throws {
        continueAfterFailure = true
        // The walk taps a hundred controls, letting picture-heavy panels settle; CI's default is five minutes.
        executionTimeAllowance = 600
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

    /// Model ▸ Add ▸ Shapes shows all seven shapes, each one whole inside the panel and tappable (device note: the
    /// sphere couldn't be found).
    func testAllSevenShapesAreVisible() throws {
        newProject("Shapes")
        XCTAssertTrue(tap("Model"))
        settle(2)
        XCTAssertTrue(tap("model-add"))
        settle(1)
        // One snapshot of the screen instead of a query per tile: the Model panel is slow to query on CI's simulator.
        let screen = try app.snapshot()
        var tiles: [String: XCUIElementSnapshot] = [:]
        func collect(_ element: XCUIElementSnapshot) {
            if element.identifier.hasPrefix("add-") { tiles[element.identifier] = element }
            element.children.forEach(collect)
        }
        collect(screen)
        for shape in ["cube", "sphere", "cylinder", "cone", "plane", "torus", "ramp"] {
            let tile = try XCTUnwrap(tiles["add-\(shape)"], "\(shape) is missing from Model ▸ Add")
            XCTAssertTrue(screen.frame.contains(tile.frame), "\(shape) is cut off")
            XCTAssertGreaterThan(tile.frame.width, 60, "\(shape) is squeezed")
            XCTAssertGreaterThan(tile.frame.height, 40, "\(shape) is squeezed")
        }
        XCTAssertEqual(tiles["add-sphere"]?.label, "Sphere")
        shot("Shapes")
        XCTAssertTrue(tap("add-sphere"))
        XCTAssertTrue(app.otherElements["inspector"].waitForExistence(timeout: 5), "a sphere landed on the stage")
    }

    // MARK: One hold menu everywhere

    /// The rows of the menu that's open, top to bottom.
    private func openMenuRows() -> [String] {
        let names = ["Duplicate", "Rename", "Copy", "Paste", "Delete"]
        // Paste is only ever in the menu; the others are also buttons elsewhere (the inspector's Duplicate), so take
        // the ones in Paste's column.
        let paste = app.buttons["Paste"].firstMatch
        guard paste.waitForExistence(timeout: 5) else { return [] }
        let column = paste.frame.minX
        let rows = names.flatMap { app.buttons.matching(identifier: $0).allElementsBoundByIndex }.filter { abs($0.frame.minX - column) < 2 }
        return rows.sorted { $0.frame.minY < $1.frame.minY }.map(\.label)
    }

    private func closeMenu() {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).tap()
        settle(1)
    }

    /// Touch and hold opens the same menu on every kind of thing: Duplicate, Rename, Copy, Paste first, Delete last
    /// (CONTEXT §4.1). Walks an object on the stage, a Look and a project's card; keys, clips, drawings: `HoldMenuFlowTests`.
    func testTheHoldMenuStartsTheSameOnEveryKindOfThing() {
        let expected = ["Duplicate", "Rename", "Copy", "Paste", "Delete"]
        newProject("Holding")
        XCTAssertTrue(tap("Model"))
        XCTAssertTrue(tap("add-cube"))
        XCTAssertTrue(app.otherElements["inspector"].waitForExistence(timeout: 5))
        settle(1)

        let stage = app.otherElements["stage"]
        stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
        XCTAssertEqual(openMenuRows(), expected, "an object on the stage")
        shot("Hold menu on the stage")
        closeMenu()

        XCTAssertTrue(tap("Look"))
        let look = element("look-clay")
        XCTAssertTrue(look.waitForExistence(timeout: 5))
        look.press(forDuration: 1.2)
        XCTAssertEqual(openMenuRows(), expected, "a Look")
        closeMenu()
        tap("Look")

        XCTAssertTrue(tap("Home"))
        let card = element("project-Holding")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.press(forDuration: 1.2)
        XCTAssertEqual(openMenuRows(), expected, "a project's card")
        shot("Hold menu on a card")
        closeMenu()
    }

    // MARK: Every control has a home

    func testHomeControlsAreReachable() {
        XCTAssertGreaterThan(LayoutWalk.rows.count, 60)
        for row in LayoutWalk.rows where row.precondition == "home" {
            walk(row)
        }
    }

    /// Everything but Model (the walk outgrew ten minutes in one test at M4).
    func testPanelAndChromeControlsAreReachable() {
        walkInAProject(["", "blob"]) { $0.home != "Model" }
    }

    /// Model's rows in two halves (the walk outgrew the per-test time on the simulator at M5).
    func testModelControlsAreReachable() {
        let first = Set(Self.modelRows.prefix(Self.modelRows.count / 2))
        walkInAProject([""]) { first.contains($0.control) }
    }

    func testMoreModelControlsAreReachable() {
        let second = Set(Self.modelRows.dropFirst(Self.modelRows.count / 2))
        walkInAProject([""]) { second.contains($0.control) }
    }

    private static let modelRows = LayoutWalk.rows.filter { $0.home == "Model" && $0.precondition.isEmpty }.map(\.control)

    func testSelectionControlsAreReachable() {
        walkInAProject(["cube"])
    }

    func testTimelineControlsAreReachable() {
        walkInAProject(["timeline", "transport"])
    }

    /// Every row with these preconditions (that `include` keeps), from a new project.
    private func walkInAProject(_ preconditions: [String], include: (LayoutWalk.Row) -> Bool = { _ in true }) {
        newProject("Walk")
        for precondition in preconditions {
            prepare(precondition)
            for row in LayoutWalk.rows where row.precondition == precondition && include(row) {
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
