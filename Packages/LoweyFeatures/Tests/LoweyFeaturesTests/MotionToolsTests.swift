import LoweyCore
@testable import LoweyFeatures
import XCTest

@MainActor
final class MotionToolsTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Motion \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        return try XCTUnwrap(app.editor)
    }

    /// A cube keyed at 0 s, 1 s and 2 s, the playhead at 1.5 s.
    private func keyedCube(_ editor: EditorModel) throws -> ObjectID {
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection?.id)
        editor.timelineMode = .keyframe
        for second in 0 ... 2 {
            editor.setTime(Double(second))
            editor.translateSelection(by: Vec3(1, 0, 0), gesture: "key-\(second)")
            editor.endGesture()
        }
        editor.timelineMode = .compose
        editor.setTime(1.5)
        return cube
    }

    func testMotionPathAndOnionSkin() throws {
        let editor = try makeEditor()
        _ = try keyedCube(editor)
        let path = try XCTUnwrap(editor.selectionMotionPath())
        XCTAssertEqual(path.keys.count, 3)
        XCTAssertTrue(editor.onionGhosts().isEmpty, "off by default")
        editor.animationView.onionSkin = true
        editor.animationView.onionBefore = 2
        editor.animationView.onionAfter = 1
        let ghosts = editor.onionGhosts()
        XCTAssertEqual(ghosts.count, 3, "two keys before the playhead, one after")
        XCTAssertGreaterThan(ghosts[0].opacity, ghosts[1].opacity, "nearer is stronger")
        editor.tool = .ink
        XCTAssertTrue(editor.onionGhosts().isEmpty, "only with the select tool")
    }

    func testSmearIsOneStep() throws {
        let editor = try makeEditor()
        let cube = try keyedCube(editor)
        editor.setSmear(0.4)
        editor.setSmear(0.7)
        editor.endGesture()
        XCTAssertEqual(editor.baseScene.objects[cube]?[.smear]?.floatValue ?? 0, 0.7, accuracy: 1e-9)
        editor.undo()
        XCTAssertNil(editor.baseScene.objects[cube]?[.smear])
    }
}
