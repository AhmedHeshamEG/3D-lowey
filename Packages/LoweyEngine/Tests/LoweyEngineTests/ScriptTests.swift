import LoweyCore
@testable import LoweyEngine
import XCTest

/// JavaScript scripts: the bundled examples build and animate as one exact undo step; mistakes come back with lines.
final class ScriptTests: XCTestCase {
    private func empty() -> Document {
        Document(project: ProjectInfo(id: "p", name: "p"), scene: Scene(id: "s", name: "s"))
    }

    func testExampleScriptsBuildAndAnimate() throws {
        for example in ScriptExamples.all {
            var document = empty()
            let outcome = ScriptRunner.runSynchronously(example.source, name: example.name, document: document, selection: [], time: 0)
            XCTAssertNil(outcome.error, "\(example.name): \(outcome.error ?? "")")
            let command = try XCTUnwrap(outcome.command, example.name)
            _ = try command.apply(to: &document)
            XCTAssertFalse(document.scene.timeline.isEmpty, "\(example.name) animates")
            XCTAssertFalse(outcome.log.isEmpty)
            let groups = document.scene.roots.count
            switch example.name {
            case ScriptExamples.forest.name: XCTAssertEqual(groups, 40)
            case ScriptExamples.flock.name: XCTAssertEqual(groups, 24)
            default: XCTAssertEqual(groups, 16)
            }
            // Undo is exact: the command's inverse restores the empty scene.
            var undone = empty()
            let (inverse, _) = try command.apply(to: &undone)
            _ = try inverse.apply(to: &undone)
            XCTAssertTrue(undone.scene.objects.isEmpty)
        }
    }

    func testScriptErrorsAreReportedWithLines() {
        let document = empty()
        let syntax = ScriptRunner.runSynchronously("let x = ;", name: "Bad", document: document, selection: [], time: 0)
        XCTAssertNotNil(syntax.error)
        XCTAssertNil(syntax.command)
        let api = ScriptRunner.runSynchronously("lowey.add(\"teapot\")", name: "Bad", document: document, selection: [], time: 0)
        XCTAssertTrue(api.error?.contains("teapot") == true, api.error ?? "")
        let keyed = ScriptRunner.runSynchronously("""
        const id = lowey.add("cube", { position: [0, 0, 0], color: "#ff8800" });
        lowey.key(id, "position", 1, [0, 2, 0], "easeOut");
        lowey.set(id, "emissiveIntensity", 2);
        lowey.log(scene.objects().length);
        """, name: "Key", document: document, selection: [], time: 0)
        XCTAssertNil(keyed.error)
        XCTAssertEqual(keyed.log, ["1"])
        XCTAssertEqual(keyed.created.count, 1)
    }

    /// The time limit is checked on every call into `lowey` / `scene`, so a runaway loop that uses the API stops.
    func testARunawayScriptIsStopped() async {
        let outcome = await ScriptRunner.run("for (;;) { scene.objects(); }", name: "Loop", document: empty(), selection: [], time: 0, timeLimit: 1)
        XCTAssertTrue(outcome.error?.contains("too long") == true, outcome.error ?? "no error")
        XCTAssertNil(outcome.command)
    }
}
