import XCTest

/// The atlas: a picture of every screen, panel and page in landscape, to review the layout as a whole.
/// It asserts nothing: a control that can't be reached is listed in the "Missing" attachment. It runs only with
/// `ATLAS=1` (the Atlas workflow), never in the smoke run.
@MainActor
final class AtlasTests: XCTestCase {
    private enum Side: CGFloat {
        case leading = 0.14
        case centre = 0.5
        case trailing = 0.86
    }

    private enum Start {
        case home, blank, cube, blob, sample
    }

    private struct Page {
        let name: String
        let steps: [String]
        var scrolls = 0
        var side = Side.trailing
    }

    private var app: XCUIApplication!
    private var area = ""
    private var count = 0
    private var missing: [String] = []

    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ATLAS"] == "1", "the atlas runs in its own workflow")
        continueAfterFailure = true
        executionTimeAllowance = 1200
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-sample", "-ui-testing-screenshots"]
    }

    override func tearDown() async throws {
        guard !missing.isEmpty else { return }
        let attachment = XCTAttachment(string: missing.joined(separator: "\n"))
        attachment.name = "Atlas \(area) Missing"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Moving around

    private func settle(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @discardableResult
    private func tap(_ identifier: String, timeout: TimeInterval = 8) -> Bool {
        let target = element(identifier)
        guard target.waitForExistence(timeout: timeout) else {
            missing.append(identifier)
            return false
        }
        target.tap()
        return true
    }

    private func shot(_ name: String) {
        count += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "Atlas %@ %02d %@", area, count, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scroll(_ side: Side) {
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: side.rawValue, dy: 0.72))
        from.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: side.rawValue, dy: 0.28)))
    }

    /// A new launch, so whatever the last page left open can't leak into the next picture.
    private func fresh(_ start: Start) {
        app.terminate()
        app.launch()
        switch start {
        case .home:
            _ = element("new-project").waitForExistence(timeout: 30)
        case .sample:
            tap("project-Enigma — the story", timeout: 60)
            _ = app.otherElements["stage"].waitForExistence(timeout: 30)
            settle(4)
        case .blank, .cube, .blob:
            newProject()
            if start == .cube { addCube() }
            if start == .blob { addBlob() }
        }
    }

    private func newProject() {
        tap("new-project", timeout: 30)
        let field = app.textFields["project-name"]
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("Atlas")
        }
        tap("create-project")
        _ = app.otherElements["stage"].waitForExistence(timeout: 15)
    }

    private func addCube() {
        tap("Model")
        tap("model-add")
        tap("add-cube")
        _ = element("inspector").waitForExistence(timeout: 5)
    }

    private func addBlob() {
        tap("Cast")
        tap("add-me")
        tap("Cast")
    }

    private func open(_ page: Page) {
        for step in page.steps {
            tap(step)
            settle(1)
        }
        settle(page.steps.first == "Look" ? 3 : 1.5)
        shot(page.name)
        for index in 0 ..< page.scrolls {
            scroll(page.side)
            settle(1)
            shot("\(page.name), further \(index + 1)")
        }
    }

    /// Panels that close when their button is tapped again: one launch for all of them.
    private func walk(_ pages: [Page], from start: Start) {
        fresh(start)
        for page in pages {
            open(page)
            guard let first = page.steps.first else { continue }
            tap(first)
            if first == "Draw" || first == "Paint" {
                tap("Select")
                tap("Tap")
                tap("Select")
            }
        }
    }

    /// Pages that open something of their own (a sheet, a menu, a library): a launch each.
    private func each(_ pages: [Page], from start: Start) {
        for page in pages {
            fresh(start)
            open(page)
        }
    }

    // MARK: The pictures

    func test01Home() {
        area = "1 Home"
        fresh(.home)
        shot("Home")
        each([
            Page(name: "New project", steps: ["new-project"], scrolls: 2, side: .centre),
            Page(name: "Sort", steps: ["gallery-sort"]),
            Page(name: "Select several", steps: ["gallery-select"]),
            Page(name: "Home menu", steps: ["theater-menu"]),
            Page(name: "Settings", steps: ["Settings"], scrolls: 3, side: .centre),
            Page(name: "Search", steps: ["gallery-search"])
        ], from: .home)
    }

    func test02Panels() {
        area = "2 Panels"
        fresh(.blank)
        shot("Empty stage")
        walk([
            Page(name: "Actions", steps: ["Actions"], scrolls: 1, side: .leading),
            Page(name: "Look", steps: ["Look"], scrolls: 2, side: .leading),
            Page(name: "Select", steps: ["Select"], side: .leading),
            Page(name: "Model, Add", steps: ["Model", "model-add"], scrolls: 3),
            Page(name: "Model, Edit", steps: ["Model", "model-shape"], scrolls: 2),
            Page(name: "Model, Library", steps: ["Model", "model-library"], scrolls: 1),
            Page(name: "Model, Precision", steps: ["Model", "model-precision"], scrolls: 2),
            Page(name: "Draw, Ink", steps: ["Draw", "tool-ink"], scrolls: 1),
            Page(name: "Draw, Solid shape", steps: ["Draw", "tool-draw"], scrolls: 1),
            Page(name: "Draw, Flipbook", steps: ["Draw", "tool-flipbook"], scrolls: 1),
            Page(name: "Paint, Colour", steps: ["Paint", "tool-paint"], scrolls: 1),
            Page(name: "Paint, Shadow Brush", steps: ["Paint", "tool-shadow-brush"], scrolls: 1),
            Page(name: "Paint, Scatter", steps: ["Paint", "tool-scatter"]),
            Page(name: "Cast", steps: ["Cast"], scrolls: 1)
        ], from: .blank)
    }

    func test03Deeper() {
        area = "3 Deeper"
        each([
            Page(name: "Brush library", steps: ["Draw", "tool-ink", "brush-ink"], scrolls: 1, side: .centre),
            Page(name: "Drawing guide", steps: ["Draw", "tool-ink", "drawing-guide"]),
            Page(name: "Colour well", steps: ["Draw", "tool-ink", "colour-well"]),
            Page(name: "Flipbook tracks", steps: ["Draw", "tool-flipbook", "flipbook-tracks"]),
            Page(name: "My Look editor", steps: ["Look", "look-clay", "duplicate-look"], scrolls: 1, side: .leading),
            Page(name: "Fine tune the world", steps: ["Look", "Fine tune the world"], scrolls: 1, side: .leading),
            Page(name: "Outliner", steps: ["Select", "outliner"], side: .leading),
            Page(name: "Print check", steps: ["Model", "model-shape", "print-check"]),
            Page(name: "Views", steps: ["views-menu"]),
            Page(name: "Director view", steps: ["director-view"])
        ], from: .blank)
    }

    func test04Sheets() {
        area = "4 Sheets"
        each([
            Page(name: "Export", steps: ["Actions", "open-export"], scrolls: 2, side: .centre),
            Page(name: "History", steps: ["Actions", "open-history"]),
            Page(name: "Board", steps: ["Actions", "open-board"]),
            Page(name: "Scripts", steps: ["Actions", "open-scripts"]),
            Page(name: "Bridge", steps: ["Actions", "open-bridge"], scrolls: 1, side: .centre),
            Page(name: "Gestures", steps: ["Actions", "Gestures"], scrolls: 2, side: .centre),
            Page(name: "Diagnostics", steps: ["Actions", "Diagnostics"], scrolls: 2, side: .centre),
            Page(name: "Settings", steps: ["Actions", "Settings"], scrolls: 3, side: .centre)
        ], from: .blank)
    }

    func test05Selection() {
        area = "5 Selection"
        fresh(.cube)
        shot("Inspector")
        for index in 1 ... 3 {
            element("inspector").swipeUp()
            settle(1)
            shot("Inspector, further \(index)")
        }
        fresh(.cube)
        app.otherElements["stage"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
        settle(1)
        shot("Hold menu on an object")
        each([
            Page(name: "Turn gizmo", steps: ["gizmo-rotate"]),
            Page(name: "Transform as numbers", steps: ["transform-toggle"]),
            Page(name: "More actions", steps: ["more-actions"]),
            Page(name: "Motion row, Bounce", steps: ["motion-bounce"]),
            Page(name: "Model, Edit on an object", steps: ["Model", "model-shape"], scrolls: 2),
            Page(name: "Paint layers", steps: ["Paint", "tool-paint", "paint-start"], scrolls: 1),
            Page(name: "Rig, Bones", steps: ["Cast", "rig-step-bones"], scrolls: 1),
            Page(name: "Rig as a person", steps: ["Cast", "rig-person"])
        ], from: .cube)
        fresh(.blob)
        open(Page(name: "Cast with a character", steps: ["Cast"], scrolls: 3))
    }

    func test06Timeline() {
        area = "6 Timeline"
        fresh(.cube)
        tap("Animate")
        settle(2)
        shot("Timeline, Compose")
        tap("timeline-mode-keyframe")
        settle(1)
        shot("Timeline, Keyframe")
        tap("timeline-mode-perform")
        settle(1)
        shot("Timeline, Perform")
        tap("Collapse the timeline")
        settle(1)
        shot("Slim transport")
        each([
            Page(name: "Sound and words", steps: ["Animate", "Sound and words"]),
            Page(name: "Timeline menu", steps: ["Animate", "timeline-menu"]),
            Page(name: "Graph editor", steps: ["Animate", "timeline-mode-keyframe", "auto-key"])
        ], from: .cube)
    }

    func test07Sample() {
        area = "7 Sample"
        fresh(.sample)
        shot("A finished scene")
        walk([
            Page(name: "Look on a scene", steps: ["Look"], side: .leading),
            Page(name: "Outliner on a scene", steps: ["Select", "outliner"], side: .leading),
            Page(name: "Model over a scene", steps: ["Model", "model-add"])
        ], from: .sample)
        tap("Animate")
        settle(2)
        shot("Timeline on a scene")
        fresh(.home)
        shot("Home with projects")
    }
}
